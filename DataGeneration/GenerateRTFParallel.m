function GenerateRTFParallel(n_workers, mechanisms, unit_range, shard, n_shards)
% GenerateRTFParallel - the parallel run-to-failure driver.
%
% Same architecture as GenerateDiagnosisParallel.m: parfor
% over UNITS, each iteration calling the unmodified RunRTFUnit.m exactly as the serial driver
% GenerateRTFFamily.m does. Resumability is per UNIT, never mid-unit
% -- RTFAlreadyDone.m decides, and a partial unit is regenerated whole; units are long (~15
% min at ~230 cycles), so parfor granularity is naturally safe (one unit per
% iteration, never a fraction of one).
%
% Inputs:
%   n_workers  - number of parallel workers. [] or omitted -> AvonWorkers. 1 -> plain
%                for-loop, no pool, no Parallel Computing Toolbox required.
%   mechanisms - [] or omitted -> all 13 (GetRTFMechanisms.FaultID). Otherwise either a
%                cellstr of folder names (e.g. {'RTF_F02_CompressorFouling'}, matching the
%                spec's own D6 acceptance-row call) or a numeric array of fault_ids (e.g.
%                [2 3]). Both forms are accepted; resolved via GetRTFMechanisms.
%   unit_range - [lo hi] inclusive 1-based unit_id range. [] or omitted ->
%                [1, ScenarioConfig.UNITS_PER_MECHANISM].
%   shard, n_shards - OPTIONAL: multi-machine sharding, same contract as
%                     GenerateDiagnosisParallel's trailing args. [] or omitted for EITHER ->
%                     AvonShard resolves it, so every existing call signature keeps working
%                     unchanged (W6). The shard filter intersects with `mechanisms` -- an
%                     explicitly-requested mechanism not owned by this shard dispatches
%                     nothing, by WHOLE MECHANISM FOLDER, never a unit-range split.
%
% Belt and braces alongside startup.m's SDI archive-run-limit-0 cap (rule 3 /
%): Simulink.sdi.clear is called after every unit (RunRTFUnit.m does NOT do this --
% freezes that file, so the call lives here in the driver, never inside it).
%
% One driver per family at a time: <repo>/Logs/rtf_parallel.lock (same mechanism as the
% diagnosis driver, AcquireFamilyLock.m/ReleaseFamilyLock.m) -- a diagnosis run and an RTF run
% CAN proceed concurrently (different families, different files); two RTF drivers cannot.
%
% CENSORED-UNIT CONTINUATION (P6R, 2026-11-21). A unit stored as aborted at the cycle cap
% (RTFAlreadyDone status 'capped_pending') is dispatched exactly like a missing one; RunRTFUnit.m
% sees the stored file and continues it to genuine failure, bit-identical to a fresh run. So the
% same command both generates what is missing and finishes the capped units, and re-running it
% after any interruption resumes per unit. Because continuations differ in length by two orders
% of magnitude (a few cycles to ~5,000), the dispatch list is ordered longest-expected-first
% (expected extra cycles, extrapolated from the stored health trajectory) so the pool is not left
% waiting on one long unit at the end, and progress is reported per unit as it finishes, with an
% ETA weighted by that expected work and a heartbeat every ~10 minutes listing the units in
% flight. Everything printed is mirrored to DataGeneration/rtf_extend_progress.log.
%
% Test-only settings (environment variable or config.txt, like AVON_WORKERS; all unset in
% production): AVON_RTF_MAX_UNITS=N dispatches only the N pending units with the least expected
% work -- a smoke test of the real command on the real tree; AVON_RTF_HEARTBEAT_S=<seconds>
% shortens the 10-minute heartbeat; AVON_RTF_CAP_CYCLES lowers or raises the cycle cap
% (ScenarioConfig.RTFCapCycles).
%

    if nargin < 1 || isempty(n_workers), n_workers = AvonWorkers(); end
    if nargin < 4, shard = []; end
    if nargin < 5, n_shards = []; end
    [shard, n_shards] = local_resolve_shard(shard, n_shards);

    rtf = GetRTFMechanisms();
    if nargin < 2 || isempty(mechanisms)
        fault_ids = rtf.FaultID;
    else
        fault_ids = local_resolve_mechanisms(mechanisms, rtf);
    end
    if nargin < 3 || isempty(unit_range)
        unit_range = [1, ScenarioConfig.UNITS_PER_MECHANISM];
    end

    %% startup print + shard filter on fault_ids (whole mechanism,
    % never a unit-range split, spec).
    assignment = AvonScenarioAssignment(shard, n_shards);
    owned_fault_ids = [assignment.rtf_owned.fault_id];
    pct_of_release = 100 * assignment.rtf_units_owned / max(assignment.rtf_units_total, 1);
    fprintf('shard %d of %d -- owns %d RTF mechanisms, %d units (%.1f%% of the run-to-failure family)\n', ...
        shard, n_shards, numel(assignment.rtf_owned), assignment.rtf_units_owned, pct_of_release);
    fault_ids = fault_ids(ismember(fault_ids, owned_fault_ids));

    data_root = AvonDataRoot();
    log_dir = AvonLogDir();
    if ~isfolder(log_dir), mkdir(log_dir); end
    lock_path      = fullfile(log_dir, 'rtf_parallel.lock');
    manifest_path  = fullfile(log_dir, 'rtf_parallel_manifest.csv');
    failures_path  = fullfile(log_dir, 'rtf_parallel_failures.log');

    AcquireFamilyLock(lock_path);
    cleanup_lock = onCleanup(@() ReleaseFamilyLock(lock_path)); %#ok<NASGU>

    %% Build the flat (fault_id, unit_id) dispatch list
    dispatch = struct('fault_id', {}, 'unit_id', {}, 'folder', {}, 'mode', {}, 'weight', {});
    for fi = 1:numel(fault_ids)
        fault_id = fault_ids(fi);
        mech_idx = find(rtf.FaultID == fault_id, 1);
        folder_name = rtf.Folder{mech_idx};
        for unit_id = unit_range(1):unit_range(2)
            dispatch(end+1) = struct('fault_id', fault_id, 'unit_id', unit_id, 'folder', folder_name, ...
                'mode', 'fresh', 'weight', 0); %#ok<AGROW>
        end
    end
    n_before_filter = numel(dispatch);
    FRESH_UNIT_EXPECTED_CYCLES = 250;   % a unit not yet started: fleet mean life is 189-274 cycles

    %% Pre-filter with RTFAlreadyDone (per unit, never mid-unit). A 'capped_pending' unit is
    % not done: it is dispatched for continuation, with its expected extra cycles as its weight.
    keep = true(1, n_before_filter);
    n_continue = 0;
    for i = 1:n_before_filter
        [done, unit_file, status] = RTFAlreadyDone(dispatch(i).fault_id, dispatch(i).unit_id);
        keep(i) = ~done;
        dispatch(i).mode = 'fresh';
        dispatch(i).weight = FRESH_UNIT_EXPECTED_CYCLES;
        if strcmp(status, 'capped_pending')
            n_continue = n_continue + 1;
            dispatch(i).mode = 'continue';
            dispatch(i).weight = local_expected_new_cycles(unit_file);
        end
    end
    dispatch = dispatch(keep);
    n_total = numel(dispatch);
    n_already_done = n_before_filter - n_total;

    %% Test-only cap on the number of units: keep the cheapest N
    max_units = AvonSetting('AVON_RTF_MAX_UNITS', 0);
    if max_units > 0 && n_total > max_units
        [~, cheapest] = sort([dispatch.weight], 'ascend');
        dispatch = dispatch(sort(cheapest(1:max_units)));
        n_total = numel(dispatch);
        fprintf('GenerateRTFParallel: AVON_RTF_MAX_UNITS=%d (test setting) -- dispatching only the %d cheapest pending units.\n', ...
            max_units, n_total);
    end

    log_path = fullfile(fileparts(mfilename('fullpath')), 'rtf_extend_progress.log');
    log_fid = fopen(log_path, 'a');
    cleanup_log = onCleanup(@() local_close_log(log_fid)); %#ok<NASGU>
    local_say(log_fid, '%s  GenerateRTFParallel start: %d dispatched, %d already done (skipped), %d to generate (%d continuations of capped units, %d fresh).\n', ...
        datestr(now, 'yyyy-mm-dd HH:MM:SS'), n_before_filter, n_already_done, n_total, ...
        sum(strcmp({dispatch.mode}, 'continue')), sum(strcmp({dispatch.mode}, 'fresh')));

    if n_total == 0
        local_say(log_fid, 'GenerateRTFParallel: nothing to do.\n');
        return;
    end

    %% Order: seeded shuffle (as before), then stable longest-expected-work first (LPT) so a
    % single very long continuation does not start last and hold the pool open for hours.
    DISPATCH_SHUFFLE_SEED = 20261113;
    rs = RandStream('mt19937ar', 'Seed', DISPATCH_SHUFFLE_SEED);
    perm = randperm(rs, n_total);
    dispatch = dispatch(perm);
    [~, by_work] = sort([dispatch.weight], 'descend');   % sort is stable: ties keep the shuffled order
    dispatch = dispatch(by_work);
    local_say(log_fid, '  expected new cycles: %d in total, longest unit ~%d cycles (~%.1f h of one worker at 3.2 s/cycle).\n', ...
        round(sum([dispatch.weight])), round(max([dispatch.weight])), max([dispatch.weight]) * 3.2 / 3600);

    has_pct = local_has_pct();
    if n_workers > 1 && ~has_pct
        fprintf(['GenerateRTFParallel: Parallel Computing Toolbox is NOT available on this ' ...
                 'machine, so a %d-worker pool cannot be started.\n'], n_workers);
        fprintf('Falling back to printing %d independent-process launch commands instead of failing silently:\n\n', n_workers);
        local_print_independent_commands(n_workers, fault_ids, rtf);
        fprintf('\nNothing was generated by this call.\n');
        return;
    end

    % Progress state, updated by local_message as messages arrive (nested, so it shares these).
    n_completed = 0;
    t_start = tic;
    last_beat = 0;               % elapsed seconds at the last heartbeat
    BEAT_EVERY_S = AvonSetting('AVON_RTF_HEARTBEAT_S', 600);   % heartbeat interval (test-only override)
    total_work = sum([dispatch.weight]);
    done_work = 0;               % expected-cycle weight of finished units
    inflight = struct('name', {}, 'cycle', {}, 'first', {}, 'h', {}, 'weight', {});
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
        afterEach(dq, @local_message);
        parfor i = 1:n_total
            results{i} = local_run_one_rtf(dispatch(i), failures_path, dq); %#ok<PFOUS>
        end
    else
        fprintf('GenerateRTFParallel: n_workers=1 -- plain for-loop, no pool.\n');
        for i = 1:n_total
            results{i} = local_run_one_rtf(dispatch(i), failures_path, @local_message);
        end
    end

    local_write_manifest(manifest_path, results);

    n_ok = sum(cellfun(@(r) r.success, results));
    local_say(log_fid, '\n=== GenerateRTFParallel COMPLETE: %d/%d ok, %d failed, %.1f min total, %d workers ===\n', ...
        n_ok, n_total, n_total - n_ok, toc(t_start)/60, n_workers);

    function local_message(msg)
        % One message from a worker (or, with one worker, from the loop itself): 'start' when a
        % unit begins, 'progress' every few cycles, 'done' when it finishes. Runs on the client.
        key = sprintf('RTF_F%02d_U%04d', msg.fault_id, msg.unit_id);
        idx = find(strcmp({inflight.name}, key), 1);
        switch msg.type
            case 'start'
                if isempty(idx)
                    inflight(end+1) = struct('name', key, 'cycle', msg.c0, 'first', msg.c0 + 1, 'h', NaN, 'weight', msg.weight); %#ok<AGROW>
                end
            case 'progress'
                if ~isempty(idx)
                    inflight(idx).cycle = msg.cycle;
                    inflight(idx).h = msg.h;
                end
            case 'done'
                if ~isempty(idx), inflight(idx) = []; end
                n_completed = n_completed + 1;
                done_work = done_work + msg.weight;
                elapsed = toc(t_start);
                local_say(log_fid, '[%d/%d] %s %s | elapsed %s | ETA %s\n', n_completed, n_total, key, ...
                    local_describe_result(msg), local_fmt_duration(elapsed), ...
                    local_fmt_eta(elapsed, total_work, done_work + local_inflight_work(inflight)));
        end
        elapsed = toc(t_start);
        if elapsed - last_beat >= BEAT_EVERY_S
            last_beat = elapsed;
            local_say(log_fid, '[heartbeat] elapsed %s | %d/%d units done | ETA %s | in flight (%d): %s\n', ...
                local_fmt_duration(elapsed), n_completed, n_total, ...
                local_fmt_eta(elapsed, total_work, done_work + local_inflight_work(inflight)), ...
                numel(inflight), local_describe_inflight(inflight));
        end
    end
end

%% ===================== local (non-nested) helpers =====================

function [shard, n_shards] = local_resolve_shard(shard, n_shards)
% [] for EITHER arg -> AvonShard resolves it.
    if isempty(shard) || isempty(n_shards)
        [resolved_shard, resolved_n_shards] = AvonShard();
        if isempty(shard), shard = resolved_shard; end
        if isempty(n_shards), n_shards = resolved_n_shards; end
    end
end

function fault_ids = local_resolve_mechanisms(mechanisms, rtf)
    if iscell(mechanisms)
        fault_ids = zeros(1, numel(mechanisms));
        for i = 1:numel(mechanisms)
            idx = find(strcmp(rtf.Folder, mechanisms{i}), 1);
            if isempty(idx)
                error('GenerateRTFParallel:UnknownMechanism', ...
                    'Mechanism folder name "%s" is not one of GetRTFMechanisms().Folder.', mechanisms{i});
            end
            fault_ids(i) = rtf.FaultID(idx);
        end
    else
        fault_ids = mechanisms(:)';
        if ~all(ismember(fault_ids, rtf.FaultID))
            bad = setdiff(fault_ids, rtf.FaultID);
            error('GenerateRTFParallel:UnknownMechanism', ...
                'fault_id(s) %s are not run-to-failure mechanisms (see GetRTFMechanisms).', mat2str(bad));
        end
    end
end

function result = local_run_one_rtf(item, failures_path, notify)
% notify: a DataQueue (parallel) or a function handle (single worker); receives the 'start',
% 'progress' and 'done' messages local_message (above) turns into the operator's progress lines.
    result = struct('fault_id', item.fault_id, 'unit_id', item.unit_id, 'folder', item.folder, ...
        'success', false, 'cycles_to_failure', NaN, 'seconds', NaN, 'failure_mode', '', ...
        'h_at_termination', NaN, 'mode', item.mode, 'weight', item.weight);
    send_msg = @(m) local_notify(notify, m);
    c0 = 0;
    if strcmp(item.mode, 'continue')
        [~, unit_file] = RTFAlreadyDone(item.fault_id, item.unit_id);
        try
            c0 = double(h5readatt(unit_file, '/', 'cycles_to_failure'));
        catch
            % cosmetic only (progress display); RunRTFUnit.m reads the file itself
        end
    end
    send_msg(struct('type', 'start', 'fault_id', item.fault_id, 'unit_id', item.unit_id, 'c0', c0, 'weight', item.weight));
    progress_fcn = @(m) send_msg(local_tag(m, 'progress'));
    t_item = tic;
    try
        ok = RunRTFUnit(item.fault_id, item.unit_id, progress_fcn);
    catch ME
        ok = false;
        local_log_failure(failures_path, item, ME.message);
    end
    % Belt and braces alongside startup.m's SDI archive cap -- RunRTFUnit.m does not
    % call this itself (freezes that file), so it happens here, once per unit
    % (once per parfor iteration), matching RunScenario.m's own per-record granularity.
    try
        Simulink.sdi.clear;
    catch
        % SDI not present / nothing to clear -- non-fatal
    end
    result.success = ok;
    result.seconds = toc(t_item);
    if ok
        try
            [~, output_file] = RTFAlreadyDone(item.fault_id, item.unit_id);
            % A unit still capped (cap reached without failing) is a valid file but not 'done';
            % read the attributes either way.
            if isfile(output_file)
                result.cycles_to_failure = double(h5readatt(output_file, '/', 'cycles_to_failure'));
                result.failure_mode = char(h5readatt(output_file, '/', 'failure_mode'));
                result.h_at_termination = double(h5readatt(output_file, '/', 'h_at_termination'));
            end
        catch
            % informational only -- manifest row is still written without it
        end
    else
        local_log_failure(failures_path, item, 'RunRTFUnit returned false or threw (see above)');
    end
    send_msg(struct('type', 'done', 'fault_id', item.fault_id, 'unit_id', item.unit_id, 'success', result.success, ...
        'cycles_to_failure', result.cycles_to_failure, 'failure_mode', result.failure_mode, ...
        'h_at_termination', result.h_at_termination, 'weight', item.weight, 'mode', item.mode, 'c0', c0));
end

function local_notify(notify, msg)
    if isa(notify, 'parallel.pool.DataQueue')
        send(notify, msg);
    else
        notify(msg);
    end
end

function m = local_tag(m, type)
    m.type = type;
end

function local_log_failure(failures_path, item, err_msg)
    try
        fid = fopen(failures_path, 'a');
        if fid < 0, return; end
        fprintf(fid, '%s\tfault_id=%d\tfolder=%s\tunit_id=%d\terror=%s\n', ...
            datestr(now, 'yyyy-mm-dd HH:MM:SS'), item.fault_id, item.folder, item.unit_id, err_msg);
        fclose(fid);
    catch
        % best-effort logging only -- must never abort the pool
    end
end

function local_write_manifest(manifest_path, results)
    write_header = ~isfile(manifest_path);
    fid = fopen(manifest_path, 'a');
    if fid < 0
        warning('GenerateRTFParallel:ManifestWriteFailed', 'Could not open %s for append.', manifest_path);
        return;
    end
    if write_header
        fprintf(fid, 'fault_id,folder,unit_id,success,cycles_to_failure,seconds\n');
    end
    for i = 1:numel(results)
        r = results{i};
        fprintf(fid, '%d,%s,%d,%d,%g,%.3f\n', r.fault_id, r.folder, r.unit_id, double(r.success), ...
            r.cycles_to_failure, r.seconds);
    end
    fclose(fid);
end

function w = local_expected_new_cycles(unit_file)
% Expected number of cycles still to run for a capped unit, linearly extrapolated from its stored
% health trajectory: h grows by a near-constant mean per cycle, so the unit trips at the cycle where
% h reaches the median trip level H_TRIP (0.964, the median h at which the 6,830 terminated units
% tripped, P6R sizing). Used only to ORDER the dispatch and to weight the ETA, never to decide
% anything about a unit; a wrong estimate costs a slightly worse schedule and a rougher ETA.
    H_TRIP = 0.964;
    w = 250;   % fallback if the file cannot be read; RunRTFUnit.m will deal with the file itself
    try
        c0 = double(h5readatt(unit_file, '/', 'cycles_to_failure'));
        w0 = double(h5readatt(unit_file, '/', 'initial_wear'));
        h_end = double(h5read(unit_file, '/health_index', [c0 1], [1 1]));
        t_hat = c0 * (H_TRIP - w0) / max(h_end - w0, 1e-3);
        w = min(max(t_hat - c0, 1), ScenarioConfig.RTFCapCycles() - c0);
    catch
    end
end

function w = local_inflight_work(inflight)
% Expected-cycle weight already worked off by units still running (their progress so far).
    w = 0;
    for k = 1:numel(inflight)
        w = w + min(max(inflight(k).cycle - inflight(k).first + 1, 0), inflight(k).weight);
    end
end

function txt = local_describe_result(msg)
% The tail of a per-unit progress line, e.g. "failed at cycle 913 (h=0.962, temperature_limit)".
    if ~msg.success
        txt = 'FAILED (see rtf_parallel_failures.log)';
    elseif strncmp(msg.failure_mode, 'aborted', 7)
        txt = sprintf('stopped at cycle %d, still running (%s; h=%.3f)', msg.cycles_to_failure, msg.failure_mode, msg.h_at_termination);
    else
        verb = 'failed';
        if strcmp(msg.mode, 'continue'), verb = 'continued and failed'; end
        txt = sprintf('%s at cycle %d (h=%.3f, %s)', verb, msg.cycles_to_failure, msg.h_at_termination, msg.failure_mode);
    end
end

function txt = local_describe_inflight(inflight)
    if isempty(inflight)
        txt = '-';
        return;
    end
    parts = cell(1, numel(inflight));
    for k = 1:numel(inflight)
        if isnan(inflight(k).h)
            parts{k} = sprintf('%s c=%d', strrep(inflight(k).name, 'RTF_', ''), inflight(k).cycle);   % no progress message yet
        else
            parts{k} = sprintf('%s c=%d h=%.2f', strrep(inflight(k).name, 'RTF_', ''), inflight(k).cycle, inflight(k).h);
        end
    end
    txt = strjoin(parts, '; ');
end

function txt = local_fmt_duration(seconds)
    h = floor(seconds / 3600);
    m = floor(mod(seconds, 3600) / 60);
    txt = sprintf('%dh%02dm', h, m);
end

function txt = local_fmt_eta(elapsed, total_work, done_work)
% Remaining time from the expected-work fraction done so far; '?' until some work is done.
    if done_work <= 0
        txt = '?';
        return;
    end
    eta_s = elapsed * max(total_work - done_work, 0) / done_work;
    if eta_s < 3600
        txt = sprintf('~%dm', round(eta_s / 60));
    else
        txt = sprintf('~%dh', round(eta_s / 3600));
    end
end

function local_say(fid, fmt, varargin)
% Print to the terminal and mirror to the progress log.
    fprintf(fmt, varargin{:});
    if fid >= 0
        fprintf(fid, fmt, varargin{:});
    end
end

function local_close_log(fid)
    if fid >= 0, fclose(fid); end
end

function has_pct = local_has_pct()
    v = ver;
    has_pct = any(strcmpi({v.Name}, 'Parallel Computing Toolbox'));
end

function local_print_independent_commands(n_workers, fault_ids, rtf)
% Same rationale as GenerateDiagnosisParallel's helper of the same name: without the toolbox,
% N-way concurrency means N separate OS processes, each on a DISJOINT subset of mechanisms
% (never the same mechanism in two processes at once -- that would race on the same unit
% files within one mechanism folder, which the family lock above does not protect against for
% a hand-partitioned split).
    avonw_dir = fileparts(fileparts(mfilename('fullpath')));
    n_procs = min(n_workers, numel(fault_ids));
    buckets = cell(1, n_procs);
    for i = 1:numel(fault_ids)
        b = mod(i-1, n_procs) + 1;
        buckets{b} = [buckets{b}, fault_ids(i)];
    end
    for i = 1:n_procs
        folder_list = rtf.Folder(ismember(rtf.FaultID, buckets{i}));
        mech_str = ['{' strjoin(cellfun(@(f) ['''' f ''''], folder_list, 'UniformOutput', false), ',') '}'];
        fprintf('  matlab -batch "cd(''%s''); run(''setup_paths.m''); GenerateRTFParallel(1, %s)"\n', ...
            avonw_dir, mech_str);
    end
    if n_procs < n_workers
        fprintf('\n  (Only %d independent processes printed -- there are only %d mechanisms requested;\n', ...
            n_procs, numel(fault_ids));
        fprintf('   requesting more concurrency without the toolbox needs per-unit-range partitioning,\n');
        fprintf('   e.g. GenerateRTFParallel(1, {''...''}, [1 <n/2>]) and [<n/2+1> <n>] in two processes.)\n');
    end
end
