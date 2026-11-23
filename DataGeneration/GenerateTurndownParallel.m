function GenerateTurndownParallel(n_workers, epoch_override)
% GenerateTurndownParallel - the turndown sub-family driver.
%
% 89 scenarios (Healthy + 42 single-fault + 46 balanced multi-fault combos) x
% 200 epochs each = 17,800 records, at the second FIXED duty of 10 MW, written to their own
% root DiagnosisTurndown/ (never Diagnosis/ -- see ScenarioConfig.DatasetRoot, made duty-aware
% for exactly this purpose,). Generates AFTER both main families; its folder
% can be deleted without touching anything else.
%
% Architecture: identical to GenerateDiagnosisParallel.m (parfor over records, calling the
% unmodified RunScenario.m per record) -- deliberately NOT refactored to share code with it,
% because this driver pins the epoch COUNT (200, not ScenarioConfig's per-kind production
% counts) and the duty (10, not 13) as two things that must never silently drift if the main
% driver's defaults ever change.
%
% SEED OFFSET (spec, "a distinct seed offset so no turndown record shares a seed with a
% 13 MW record"): RunScenario.m (frozen) derives every seed deterministically from
% (scenario_hash, epoch, attempt) with no duty term at all, so a turndown record at epoch e and
% a main-family record at epoch e, same fault/combo, same attempt, would draw an IDENTICAL
% environment/severity/onset/noise/bias realisation under the ONLY FIXED duty literal being
% different. Since RunScenario.m cannot be edited, the offset is applied to the
% EPOCH ARGUMENT itself before it ever reaches RunScenario/ScenarioAlreadyDone -- the one input
% every seed formula in the pipeline already treats as free. TURNDOWN_EPOCH_OFFSET = 100000 is
% a multiple of 5, chosen so it does not disturb SampleSingleFaultSeverity's 5-epoch
% stratification-block boundaries (block = floor((epoch-1)/5): offsetting epoch by a multiple
% of 5 shifts the block index by exactly offset/5 and leaves pos = mod(epoch-1,5)+1 unchanged,
% so the per-block "each severity 1..5 exactly once" balance is preserved on the turndown
% family's own epochs 1..200 exactly as it is on the main family's). The on-disk filename
% (TD_<IDs>_E%04d.h5, from the frozen GenerateScenarioInfo.m's epoch argument) is therefore
% TD_<IDs>_E100001.h5 .. TD_<IDs>_E100200.h5 inside DiagnosisTurndown/ -- intentionally distinct from
% the main family's E0001..E0200 even though the two live in different folders anyway, so a
% stray file copy cannot silently collide.
%
% Resumability: ScenarioAlreadyDone.m is called with the SAME offset epoch, so it can never
% disagree with where RunScenario actually writes.
%
% AVON_DUTY_CMD_MW must be visible inside every WORKER PROCESS, not just this client: workers
% are separate OS processes that inherit environment variables only at the moment they are
% spawned, so (a) setenv happens in THIS process before the pool is (re)built, and (b) any
% pre-existing pool is always torn down and rebuilt here, never reused across a duty change --
% unlike GenerateDiagnosisParallel.m/GenerateRTFParallel.m, which reuse a same-sized pool,
% this driver cannot, because a pool left over from a 13 MW run would carry stale environments.
%
% epoch_override - OPTIONAL, NOT in the spec's own signature -- added for exactly the
%                   same reason GenerateDiagnosisParallel.m's own epoch_override was added
%                   (judgement call, recorded here rather than invented silently)
%                   smoke pass needs "all 89 scenarios at ONE epoch", not the full 200, and
%                   building a second near-duplicate driver just to change this one number
%                   would be a bigger risk than a documented optional argument. [] or omitted
%                   -> epochs 1:200 (full production count, spec own default). A
%                   scalar N -> epochs 1:N for every scenario class.
%

    if nargin < 1 || isempty(n_workers), n_workers = AvonWorkers(); end
    if nargin < 2 || isempty(epoch_override)
        TURNDOWN_EPOCHS = 1:ScenarioConfig.TURNDOWN_EPOCHS_PER_SCENARIO;
    else
        TURNDOWN_EPOCHS = 1:epoch_override;
    end
    TURNDOWN_EPOCH_OFFSET = 100000;

    setenv('AVON_DUTY_CMD_MW', '10');
    assert(abs(ScenarioConfig.DUTY_CMD_MW() - 10) < 1e-9, ...
        'GenerateTurndownParallel: AVON_DUTY_CMD_MW did not take effect in this process.');

    cfg = ScenarioConfig.GetActiveConfig();
    retry_max = cfg.sim_retry_max;

    data_root = AvonDataRoot();
    log_dir = AvonLogDir();
    if ~isfolder(log_dir), mkdir(log_dir); end
    lock_path     = fullfile(log_dir, 'turndown_parallel.lock');
    manifest_path = fullfile(log_dir, 'turndown_parallel_manifest.csv');
    failures_path = fullfile(log_dir, 'turndown_parallel_failures.log');

    AcquireFamilyLock(lock_path);
    cleanup_lock = onCleanup(@() ReleaseFamilyLock(lock_path)); %#ok<NASGU>

    %% Build the flat dispatch list: all 89 scenario classes x 200 epochs
    dispatch = struct('kind', {}, 'arg', {}, 'epoch', {});
    for e = TURNDOWN_EPOCHS
        dispatch(end+1) = struct('kind', 'healthy', 'arg', [], 'epoch', e); %#ok<AGROW>
    end
    for fault_id = cfg.single_fault_ids
        for e = TURNDOWN_EPOCHS
            dispatch(end+1) = struct('kind', 'single', 'arg', fault_id, 'epoch', e); %#ok<AGROW>
        end
    end
    for combo_id = cfg.dual_fault_combos
        for e = TURNDOWN_EPOCHS
            dispatch(end+1) = struct('kind', 'dual', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
        end
    end
    for combo_id = cfg.triple_fault_combos
        for e = TURNDOWN_EPOCHS
            dispatch(end+1) = struct('kind', 'triple', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
        end
    end
    for combo_id = cfg.quad_fault_combos
        for e = TURNDOWN_EPOCHS
            dispatch(end+1) = struct('kind', 'quad', 'arg', combo_id, 'epoch', e); %#ok<AGROW>
        end
    end
    n_before_filter = numel(dispatch);
    n_scenario_classes = 1 + numel(cfg.single_fault_ids) + numel(cfg.dual_fault_combos) + ...
        numel(cfg.triple_fault_combos) + numel(cfg.quad_fault_combos);
    fprintf('GenerateTurndownParallel: %d scenario classes x %d epochs = %d records dispatched.\n', ...
        n_scenario_classes, numel(TURNDOWN_EPOCHS), n_before_filter);

    %% Apply the seed/filename offset to every dispatch item's epoch, then pre-filter with
    % ScenarioAlreadyDone (RunScenario.m does not call it itself).
    for i = 1:n_before_filter
        dispatch(i).epoch = dispatch(i).epoch + TURNDOWN_EPOCH_OFFSET;
    end
    keep = true(1, n_before_filter);
    for i = 1:n_before_filter
        item = dispatch(i);
        switch item.kind
            case 'healthy'
                keep(i) = ~ScenarioAlreadyDone('healthy', item.epoch);
            otherwise
                keep(i) = ~ScenarioAlreadyDone(item.kind, item.epoch, item.arg);
        end
    end
    dispatch = dispatch(keep);
    n_total = numel(dispatch);
    fprintf('GenerateTurndownParallel: %d already done (skipped), %d to generate.\n', ...
        n_before_filter - n_total, n_total);

    if n_total == 0
        fprintf('GenerateTurndownParallel: nothing to do.\n');
        return;
    end

    %% Shuffle with a fixed seed (same rationale as GenerateDiagnosisParallel.m), DISTINCT from
    % its seed so the two drivers' shuffles are independent, not that it matters for correctness.
    DISPATCH_SHUFFLE_SEED = 20261112 + 1;
    rs = RandStream('mt19937ar', 'Seed', DISPATCH_SHUFFLE_SEED);
    perm = randperm(rs, n_total);
    dispatch = dispatch(perm);

    has_pct = local_has_pct();
    if n_workers > 1 && ~has_pct
        fprintf(['GenerateTurndownParallel: Parallel Computing Toolbox is NOT available, so a ' ...
                 '%d-worker pool cannot be started. Falling back to n_workers=1.\n'], n_workers);
        n_workers = 1;
    end

    n_completed = 0;
    t_start = tic;
    results = cell(n_total, 1);

    if n_workers > 1
        pool = gcp('nocreate');
        if ~isempty(pool), delete(pool); end   % ALWAYS rebuild -- see header: env must propagate
        cl = parcluster('Processes');
        if cl.NumWorkers < n_workers
            fprintf('  cluster profile caps workers at %d; raising to %d for this session only (profile not saved)\n', ...
                    cl.NumWorkers, n_workers);
            cl.NumWorkers = n_workers;
        end
        pool = parpool(cl, n_workers);
        % Broadcast the duty override to every worker PROCESS explicitly as well -- belt and
        % braces against any pool-reuse path elsewhere in a long interactive session, since a
        % worker that happens to have serviced an EARLIER 13 MW call in this same pool lifetime
        % would otherwise keep its own stale environment.
        wait(parfevalOnAll(pool, @() setenv('AVON_DUTY_CMD_MW', '10'), 0));
        dq = parallel.pool.DataQueue;
        afterEach(dq, @local_tick);
        parfor i = 1:n_total
            results{i} = local_run_one(dispatch(i), retry_max, failures_path); %#ok<PFOUS>
            send(dq, 1);
        end
    else
        fprintf('GenerateTurndownParallel: n_workers=1 -- plain for-loop, no pool.\n');
        for i = 1:n_total
            results{i} = local_run_one(dispatch(i), retry_max, failures_path);
            local_tick(1);
        end
    end

    local_write_manifest(manifest_path, results);

    n_ok = sum(cellfun(@(r) r.success, results));
    fprintf('\n=== GenerateTurndownParallel COMPLETE: %d/%d ok, %d failed, %.1f min total, %d workers ===\n', ...
        n_ok, n_total, n_total - n_ok, toc(t_start)/60, n_workers);

    function local_tick(~)
        n_completed = n_completed + 1;
        if mod(n_completed, 200) == 0 || n_completed == n_total
            elapsed = toc(t_start);
            rate = n_completed / max(elapsed, eps);
            remaining = n_total - n_completed;
            eta_h = (remaining / max(rate, eps)) / 3600;
            fprintf('  [progress] %d/%d complete | %.3f rec/s | %d workers | ETA %.2f h\n', ...
                n_completed, n_total, rate, n_workers, eta_h);
        end
    end
end

function result = local_run_one(item, retry_max, failures_path)
% Mirrors GenerateDiagnosisParallel.m's local_run_one exactly, except it also re-asserts the
% duty override at the top of every call -- belt and braces for a worker process that somehow
% started before the setenv broadcast landed (e.g. a slow-to-join worker).
    setenv('AVON_DUTY_CMD_MW', '10');
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
        warning('GenerateTurndownParallel:ManifestWriteFailed', 'Could not open %s for append.', manifest_path);
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
