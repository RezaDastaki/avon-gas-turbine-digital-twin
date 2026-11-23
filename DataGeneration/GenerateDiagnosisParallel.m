function GenerateDiagnosisParallel(n_workers, kinds, epoch_override, shard, n_shards)
% GenerateDiagnosisParallel - the parallel diagnosis-family driver.
%
% Architecture (carried forward unmodified,): parfor
% over RECORDS, each iteration calling the unmodified RunScenario.m exactly as the serial
% drivers (GenerateHealthyDataset.m etc.) do. parsim is deliberately not used -- it would leave
% the per-record HDF5 write (2.34 s measured) serial on the client.
%
% Inputs:
%   n_workers      - number of parallel workers. [] or omitted -> AvonWorkers. 1 -> plain
%                     for-loop, no pool, no Parallel Computing Toolbox required (testable
%                     without PCT, per spec "Both drivers").
%   kinds          - cellstr subset of {'healthy','single','dual','triple','quad'}.
%                     [] or omitted -> all five. A single char row is also accepted.
%   epoch_override - OPTIONAL, NOT in the spec's own signature -- added here because
%                     acceptance rows D1/D3/D4 need a way to generate a small number of
%                     epochs rather than the full ScenarioConfig.N_EPOCHS_* count, and
%                     GenerateRTFParallel's own signature already takes an analogous
%                     unit_range third argument. Judgement call, recorded
% rather than invented silently: a scalar N means "epochs 1:N" for
%                     every requested kind (a count override, matching D1's "2-epoch
%                     override" and D3's "8 epochs"); a vector is used as the explicit epoch
%                     list for every requested kind. [] or omitted -> each kind's full
%                     ScenarioConfig epoch range, unchanged production behaviour.
%   shard, n_shards - OPTIONAL: multi-machine sharding. [] or omitted for
%                     EITHER -> AvonShard resolves it (env/config.txt/default 1-of-1), so
%                     every existing call signature (0-3 args) keeps working UNCHANGED and a
%                     1-of-1 run reproduces today's full, unsharded dispatch exactly (W6).
%                     When n_shards > 1, the dispatch list is filtered to only the scenarios
%                     AvonScenarioAssignment(shard, n_shards) assigns to THIS shard, by WHOLE
%                     SCENARIO (never by epoch range, spec) -- so this machine never
%                     writes a file belonging to another shard's folder.
%
% Resumability: ScenarioAlreadyDone.m pre-filters the dispatch list before anything is
% dispatched (RunScenario.m does not call it itself) rule 10 /.
% Re-running the same call after a partial run (or after a kill) generates only what is
% still missing; nothing already-valid is regenerated (D2/D4).
%
% One driver per family at a time: a lock file in <repo>/Logs/diag_parallel.lock refuses a
% second concurrent call for this family (D8) -- see AcquireFamilyLock.m.
%
% Progress: a line every 200 completed records (count, rate, workers, ETA). Failures are
% logged to <repo>/Logs/diag_parallel_failures.log and do NOT abort the pool -- the pool
% continues with the remaining dispatch. <repo>/Logs/diag_parallel_manifest.csv gets one row
% per dispatched record (kind, arg, epoch, success, attempts, seconds), appended across runs
% so AvonProgress.m's ETA (which reads this file) accumulates history rather than resetting.
%

    if nargin < 1 || isempty(n_workers), n_workers = AvonWorkers(); end
    if nargin < 2 || isempty(kinds), kinds = {'healthy', 'single', 'dual', 'triple', 'quad'}; end
    if ischar(kinds), kinds = {kinds}; end
    if nargin < 3, epoch_override = []; end
    if nargin < 4, shard = []; end
    if nargin < 5, n_shards = []; end
    [shard, n_shards] = local_resolve_shard(shard, n_shards);

    cfg = ScenarioConfig.GetActiveConfig();
    retry_max = cfg.sim_retry_max;

    %% startup print -- always printed, even at the default 1-of-1,
    % so an operator can see at a glance whether sharding is in effect.
    assignment = AvonScenarioAssignment(shard, n_shards);
    pct_of_release = 100 * assignment.diag_records_owned / max(assignment.diag_records_total, 1);
    fprintf('shard %d of %d -- owns %d diagnosis scenarios, %d records (%.1f%% of the diagnosis family)\n', ...
        shard, n_shards, numel(assignment.diag_owned), assignment.diag_records_owned, pct_of_release);

    data_root = AvonDataRoot();
    log_dir = AvonLogDir();
    if ~isfolder(log_dir), mkdir(log_dir); end
    lock_path      = fullfile(log_dir, 'diag_parallel.lock');
    manifest_path  = fullfile(log_dir, 'diag_parallel_manifest.csv');
    failures_path  = fullfile(log_dir, 'diag_parallel_failures.log');

    AcquireFamilyLock(lock_path);
    cleanup_lock = onCleanup(@() ReleaseFamilyLock(lock_path)); %#ok<NASGU>

    %% Build the flat dispatch list
    dispatch = local_build_dispatch(cfg, kinds, epoch_override);

    %% shard filter -- BEFORE the already-done filter, so the "N skipped" print below
    % only ever counts this shard's own work. Filters by WHOLE (kind, arg) scenario, never by
    % epoch: either every epoch of a scenario passes, or none do.
    dispatch = local_filter_by_shard(dispatch, assignment);
    n_before_filter = numel(dispatch);

    %% Pre-filter with ScenarioAlreadyDone (RunScenario.m does not call it itself)
    keep = true(1, n_before_filter);
    for i = 1:n_before_filter
        keep(i) = ~local_already_done(dispatch(i));
    end
    dispatch = dispatch(keep);
    n_total = numel(dispatch);

    fprintf('GenerateDiagnosisParallel: %d dispatched, %d already done (skipped), %d to generate.\n', ...
        n_before_filter, n_before_filter - n_total, n_total);

    if n_total == 0
        fprintf('GenerateDiagnosisParallel: nothing to do.\n');
        return;
    end

    %% Shuffle with a FIXED seed (spec: "so no worker gets a contiguous block of one
    % scenario and a crash leaves a uniform rather than a lopsided hole"). Fixed, not
    % time-based, so re-running an identical dispatch list is reproducible; the literal below
    % is an arbitrary constant chosen once and never varied.
    DISPATCH_SHUFFLE_SEED = 20261112;
    rs = RandStream('mt19937ar', 'Seed', DISPATCH_SHUFFLE_SEED);
    perm = randperm(rs, n_total);
    dispatch = dispatch(perm);

    %% Toolbox check
    has_pct = local_has_pct();
    if n_workers > 1 && ~has_pct
        fprintf(['GenerateDiagnosisParallel: Parallel Computing Toolbox is NOT available on ' ...
                 'this machine, so a %d-worker pool cannot be started.\n'], n_workers);
        fprintf('Falling back to printing %d independent-process launch commands instead of failing silently:\n\n', n_workers);
        local_print_independent_commands(n_workers, kinds);
        fprintf('\nNothing was generated by this call. Run the commands above in separate matlab -batch processes,\n');
        fprintf('or call GenerateDiagnosisParallel(1, kinds) here for a plain for-loop (no toolbox needed).\n');
        return;
    end

    %% Progress-tracking state (nested function shares this workspace)
    n_completed = 0;
    n_failed_count = 0;
    t_start = tic;

    results = cell(n_total, 1);

    if n_workers > 1
        pool = gcp('nocreate');
        if isempty(pool) || pool.NumWorkers ~= n_workers
            if ~isempty(pool), delete(pool); end
            % The saved 'Processes' cluster profile carries its own NumWorkers cap,
            % which on a fresh install is the PHYSICAL core count and can be well
            % below the requested worker count -- on the development laptop it is 6
            % against feature('numcores')=10. parpool('Processes', n) then errors
            % OUTRIGHT rather than clamping, which would kill a multi-day production
            % run at launch. Raise the IN-MEMORY cluster object's cap for this call
            % only; never saveProfile, so the user's stored profile is untouched.
            cl = parcluster('Processes');
            if cl.NumWorkers < n_workers
                fprintf('  cluster profile caps workers at %d; raising to %d for this session only (profile not saved)\n', ...
                        cl.NumWorkers, n_workers);
                cl.NumWorkers = n_workers;
            end
            pool = parpool(cl, n_workers);
        end
        dq = parallel.pool.DataQueue;
        afterEach(dq, @local_tick);
        parfor i = 1:n_total
            results{i} = local_run_one(dispatch(i), retry_max, failures_path); %#ok<PFOUS>
            send(dq, 1);
        end
    else
        fprintf('GenerateDiagnosisParallel: n_workers=1 -- plain for-loop, no pool.\n');
        for i = 1:n_total
            results{i} = local_run_one(dispatch(i), retry_max, failures_path);
            local_tick(1);
        end
    end

    %% Write the manifest (append, so repeated/partial runs accumulate history for AvonProgress)
    local_write_manifest(manifest_path, results);

    n_ok = sum(cellfun(@(r) r.success, results));
    fprintf('\n=== GenerateDiagnosisParallel COMPLETE: %d/%d ok, %d failed, %.1f min total, %d workers ===\n', ...
        n_ok, n_total, n_total - n_ok, toc(t_start)/60, n_workers);

    %% ---- nested: progress tick, shares this function's workspace ----
    function local_tick(~)
        n_completed = n_completed + 1;
        if mod(n_completed, 200) == 0 || n_completed == n_total
            elapsed = toc(t_start);
            rate = n_completed / max(elapsed, eps);  % records/sec
            remaining = n_total - n_completed;
            eta_h = (remaining / max(rate, eps)) / 3600;
            fprintf('  [progress] %d/%d complete | %.3f rec/s | %d workers | ETA %.2f h\n', ...
                n_completed, n_total, rate, n_workers, eta_h);
        end
    end
end

%% ===================== local (non-nested) helpers =====================

function dispatch = local_build_dispatch(cfg, kinds, epoch_override)
    dispatch = struct('kind', {}, 'arg', {}, 'epoch', {});
    for k = 1:numel(kinds)
        kind = lower(kinds{k});
        switch kind
            case 'healthy'
                epochs = local_resolve_epochs(cfg.epochs_healthy, epoch_override);
                for e = epochs
                    dispatch(end+1) = struct('kind', 'healthy', 'arg', [], 'epoch', e); %#ok<AGROW>
                end
            case 'single'
                epochs = local_resolve_epochs(cfg.epochs_single, epoch_override);
                for fault_id = cfg.single_fault_ids
                    for e = epochs
                        dispatch(end+1) = struct('kind', 'single', 'arg', fault_id, 'epoch', e); %#ok<AGROW>
                    end
                end
            case 'dual'
                epochs = local_resolve_epochs(cfg.epochs_dual, epoch_override);
                for combo_id = cfg.dual_fault_combos
                    for e = epochs
                        dispatch(end+1) = struct('kind', 'dual', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
                    end
                end
            case 'triple'
                epochs = local_resolve_epochs(cfg.epochs_triple, epoch_override);
                for combo_id = cfg.triple_fault_combos
                    for e = epochs
                        dispatch(end+1) = struct('kind', 'triple', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
                    end
                end
            case 'quad'
                epochs = local_resolve_epochs(cfg.epochs_quad, epoch_override);
                for combo_id = cfg.quad_fault_combos
                    for e = epochs
                        dispatch(end+1) = struct('kind', 'quad', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
                    end
                end
            otherwise
                error('GenerateDiagnosisParallel:UnknownKind', 'Unknown kind "%s".', kind);
        end
    end
end

function [shard, n_shards] = local_resolve_shard(shard, n_shards)
% [] for EITHER arg -> AvonShard resolves it. Resolving both from
% AvonShard together when both are empty avoids calling it twice; either being non-empty
% (an explicit test override) is honoured as given, the other still resolved from AvonShard.
    if isempty(shard) || isempty(n_shards)
        [resolved_shard, resolved_n_shards] = AvonShard();
        if isempty(shard), shard = resolved_shard; end
        if isempty(n_shards), n_shards = resolved_n_shards; end
    end
end

function dispatch = local_filter_by_shard(dispatch, assignment)
% Keeps only dispatch items whose (kind, arg) is owned by this shard, per
% AvonScenarioAssignment -- never filters by epoch (spec: a scenario folder is owned
% whole, by exactly one machine).
    if isempty(dispatch)
        return;
    end
    owned = assignment.diag_owned;
    keep = false(1, numel(dispatch));
    for i = 1:numel(dispatch)
        for j = 1:numel(owned)
            if strcmp(dispatch(i).kind, owned(j).kind) && isequal(dispatch(i).arg, owned(j).arg)
                keep(i) = true;
                break;
            end
        end
    end
    dispatch = dispatch(keep);
end

function epochs = local_resolve_epochs(default_epochs, epoch_override)
    if isempty(epoch_override)
        epochs = default_epochs;
    elseif isscalar(epoch_override)
        epochs = 1:epoch_override;
    else
        epochs = epoch_override;
    end
end

function done = local_already_done(item)
    switch item.kind
        case 'healthy'
            done = ScenarioAlreadyDone('healthy', item.epoch);
        otherwise
            done = ScenarioAlreadyDone(item.kind, item.epoch, item.arg);
    end
end

function result = local_run_one(item, retry_max, failures_path)
% Mirrors the serial drivers' own retry loop exactly (GenerateHealthyDataset.m etc.): attempt
% 1..retry_max, calling the unmodified RunScenario with the same arguments in the same order.
% RunScenario itself never throws when ScenarioConfig.STOP_ON_ERROR is false (the production
% default) -- it catches internally and returns success=false -- so the try/catch here is a
% belt-and-braces net for the (disallowed-by-config, but still worth not crashing a worker on)
% case where it does.
    result = struct('kind', item.kind, 'arg', item.arg, 'epoch', item.epoch, ...
        'success', false, 'attempts', 0, 'seconds', NaN);
    t_item = tic;
    done = false;
    last_err = '';
    for attempt = 1:retry_max
        try
            switch item.kind
                case 'healthy'
                    success = RunScenario('healthy', item.epoch, attempt);
                otherwise
                    success = RunScenario(item.kind, item.epoch, attempt, item.arg);
            end
        catch ME
            success = false;
            last_err = ME.message;
        end
        if success
            done = true;
            result.attempts = attempt;
            break;
        end
    end
    if ~done
        result.attempts = retry_max;
        local_log_failure(failures_path, item, last_err);
    end
    result.success = done;
    result.seconds = toc(t_item);
end

function local_log_failure(failures_path, item, err_msg)
    try
        fid = fopen(failures_path, 'a');
        if fid < 0, return; end
        if isempty(item.arg)
            arg_str = '';
        else
            arg_str = mat2str(item.arg);
        end
        fprintf(fid, '%s\tkind=%s\targ=%s\tepoch=%d\terror=%s\n', ...
            datestr(now, 'yyyy-mm-dd HH:MM:SS'), item.kind, arg_str, item.epoch, err_msg);
        fclose(fid);
    catch
        % best-effort logging only -- must never abort the pool
    end
end

function local_write_manifest(manifest_path, results)
    write_header = ~isfile(manifest_path);
    fid = fopen(manifest_path, 'a');
    if fid < 0
        warning('GenerateDiagnosisParallel:ManifestWriteFailed', 'Could not open %s for append.', manifest_path);
        return;
    end
    if write_header
        fprintf(fid, 'kind,arg,epoch,success,attempts,seconds\n');
    end
    for i = 1:numel(results)
        r = results{i};
        if isempty(r.arg)
            arg_str = '';
        else
            arg_str = mat2str(r.arg);
        end
        fprintf(fid, '%s,%s,%d,%d,%d,%.3f\n', r.kind, arg_str, r.epoch, double(r.success), r.attempts, r.seconds);
    end
    fclose(fid);
end

function has_pct = local_has_pct()
    v = ver;
    has_pct = any(strcmpi({v.Name}, 'Parallel Computing Toolbox'));
end

function local_print_independent_commands(n_workers, kinds)
% Without the Parallel Computing Toolbox there is no in-process pool, so the only safe way
% to get N-way concurrency is N separate OS processes, each running its own plain for-loop
% (n_workers=1 needs no toolbox) against a DISJOINT subset of kinds -- disjoint because two
% processes racing on the SAME kind would both try to write the same files (the family lock
% above only guards against a second call to this whole function, not a hand-partitioned
% split). kinds is partitioned round-robin across up to n_workers processes; if there are
% fewer kinds than n_workers, only numel(kinds) commands are printed (one kind cannot be
% usefully split further without per-epoch partitioning, which this driver does not expose).
    avonw_dir = fileparts(fileparts(mfilename('fullpath')));  % .../the repository root
    n_procs = min(n_workers, numel(kinds));
    buckets = cell(1, n_procs);
    for i = 1:numel(kinds)
        b = mod(i-1, n_procs) + 1;
        buckets{b} = [buckets{b}, kinds(i)];
    end
    for i = 1:n_procs
        kinds_str = ['{' strjoin(cellfun(@(k) ['''' k ''''], buckets{i}, 'UniformOutput', false), ',') '}'];
        fprintf('  matlab -batch "cd(''%s''); run(''setup_paths.m''); GenerateDiagnosisParallel(1, %s)"\n', ...
            avonw_dir, kinds_str);
    end
    if n_procs < n_workers
        fprintf('\n  (Only %d independent processes printed -- there are only %d kinds to partition;\n', ...
            n_procs, numel(kinds));
        fprintf('   requesting more than %d-way concurrency without the toolbox needs per-epoch\n', numel(kinds));
        fprintf('   partitioning, which this driver does not provide.)\n');
    end
end
