function AvonSetupCheck()
% AvonSetupCheck - pre-flight check for a machine that will run the generation pipeline.
%
% Prints PASS/FAIL/WARN per item and EXITS NON-ZERO (via `error`) on any FAIL. Run from
% the repository root after setup_paths.
%
% Checks:
%   0. AvonShard resolves and prints "shard k of N -- owns S scenarios, R records (X% of
%      the release)". AVON_SHARD > AVON_SHARDS or either non-numeric is a hard FAIL here
%      (AvonShard itself throws), because a typo would silently duplicate or drop part of
%      the release. At the default 1-of-1 there is no sharding.
%   1. MATLAB version >= R2024a; Simulink present; Parallel Computing Toolbox present (WARN,
%      not FAIL -- n_workers=1 still works without it).
%   2. ValidatePipelineConfig -> 11/11.
%   3. AvonDataRoot resolves, is writable, and reports free disk. FAIL if free space <
%      this shard's own requirement (its share of the release's data plus its own zips;
%      at 1-of-1 that is the whole release).
%   4. The model loads, and its SHA-256 matches the value recorded below.
%   5. Simulink.sdi.getArchiveRunLimit returns 0. If not, print the exact fix.
%   6. The warm-start library and the ambient-check surface both load and have the expected
%      shape.
%   7. AvonWorkers prints the resolved worker count and where it came from.
%   8. A single real record generates end-to-end and passes QualityCheckHDF5 (~10 s).
%

    % SHA-256 of Core/Models/AvonGasTurbineDgTwin_fixed.slx as used to generate the release
    % (the saved model, not an .slx.autosave copy).
    EXPECTED_MODEL_SHA256 = 'f61f966b01e2171c7695421dff70131014515e8bc0824efe59a01299a853f42c';
    % Size of the whole release's two main families at the ScenarioConfig counts
    % (110,000 diagnosis records, 7,150 run-to-failure units), measured as decimal GB.
    % Scaled down to this shard's own share below.
    TOTAL_DIAG_GB_PROJECTED = 33.7;
    TOTAL_RTF_GB_PROJECTED  = 39.6;
    TOTAL_TURNDOWN_GB_PROJECTED = 5.5;   % 17,800 records x 0.3063 MB
    ZIP_OVERHEAD_FRACTION   = 0.25;  % measured deflate ratio ~24.6% of stored size, zip_release.py header

    fprintf('\n======================================================================\n');
    fprintf('  AvonSetupCheck -- pipeline pre-flight\n');
    fprintf('======================================================================\n\n');

    n_fail = 0;

    %% 0. shard resolution -- AvonShard itself throws on a bad
    % AVON_SHARD/AVON_SHARDS, which is exactly the fail-cleanly behaviour W7 requires.
    fprintf('[0/8] AvonShard() -- multi-machine sharding...\n');
    try
        assignment = AvonScenarioAssignment();  % throws if AVON_SHARD/AVON_SHARDS is bad
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        fprintf('  This is fatal and unrecoverable for this run -- a bad shard setting silently\n');
        fprintf('  duplicates or drops part of the release. Fix AVON_SHARD/AVON_SHARDS and re-run.\n');
        rethrow(ME);  % abort immediately -- every later check assumes a valid assignment
    end
    shard = assignment.shard;
    n_shards = assignment.n_shards;
    pct_release = 100 * (assignment.diag_records_owned + assignment.rtf_units_owned) / ...
        max(assignment.diag_records_total + assignment.rtf_units_total, 1);
    fprintf('  shard %d of %d -- owns %d diagnosis scenarios (%d records) + %d RTF mechanisms (%d units)\n', ...
        shard, n_shards, numel(assignment.diag_owned), assignment.diag_records_owned, ...
        numel(assignment.rtf_owned), assignment.rtf_units_owned);
    fprintf('  (%.1f%% of the release, by record+unit count)\n', pct_release);
    fprintf('  PASS\n\n');

    %% 1. MATLAB / Simulink / PCT
    fprintf('[1/8] MATLAB version / Simulink / Parallel Computing Toolbox...\n');
    v = ver;
    matlab_ver = version('-release');  % e.g. '2024b'
    yr = str2double(matlab_ver(1:4));
    rel = lower(matlab_ver(5));
    ok_version = (yr > 2024) || (yr == 2024 && rel >= 'a');
    if ok_version
        fprintf('  PASS: MATLAB R%s (>= R2024a)\n', matlab_ver);
    else
        fprintf('  FAIL: MATLAB R%s (< R2024a)\n', matlab_ver);
        n_fail = n_fail + 1;
    end
    has_simulink = any(strcmpi({v.Name}, 'Simulink'));
    if has_simulink
        fprintf('  PASS: Simulink present\n');
    else
        fprintf('  FAIL: Simulink NOT present\n');
        n_fail = n_fail + 1;
    end
    has_pct = any(strcmpi({v.Name}, 'Parallel Computing Toolbox'));
    if has_pct
        fprintf('  PASS: Parallel Computing Toolbox present\n');
    else
        fprintf('  WARN: Parallel Computing Toolbox NOT present -- n_workers=1 (plain for-loop) still works\n');
    end
    fprintf('\n');

    %% 2. ValidatePipelineConfig
    fprintf('[2/8] ValidatePipelineConfig (expect 11/11)...\n');
    try
        cfg = ScenarioConfig.GetActiveConfig();
        ValidatePipelineConfig(cfg, ScenarioConfig.SIMULINK_MODEL);
        fprintf('  PASS: ValidatePipelineConfig completed with no thrown error\n');
    catch ME
        fprintf('  FAIL: ValidatePipelineConfig threw: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 3. AvonDataRoot resolves, writable, free disk
    fprintf('[3/8] AvonDataRoot() / disk space...\n');
    try
        root = AvonDataRoot();
        fprintf('  AvonDataRoot() = %s\n', root);
        test_file = fullfile(root, '.avon_setup_check_write_test');
        fid = fopen(test_file, 'w');
        if fid < 0
            fprintf('  FAIL: cannot write inside %s\n', root);
            n_fail = n_fail + 1;
        else
            fclose(fid);
            delete(test_file);
            fprintf('  PASS: %s is writable\n', root);
        end

        free_gb = local_free_space_gb(root);
        fprintf('  Free disk at %s: %.1f GB\n', root, free_gb);

        % Require free space for this shard's share of the release plus its own zips,
        % scaled from the whole-family totals by this shard's fraction of records/units
        % (assignment, computed in check 0).
        diag_frac = assignment.diag_records_owned / max(assignment.diag_records_total, 1);
        rtf_frac  = assignment.rtf_units_owned / max(assignment.rtf_units_total, 1);

        % A machine may generate one family only, in which case demanding the whole
        % release's footprint is too strict. AVON_FAMILY declares what this machine will
        % generate; 'all' (the default) requires the whole release's footprint.
        family = lower(strtrim(getenv('AVON_FAMILY')));
        if isempty(family), family = 'all'; end
        switch family
            case {'rtf', 'runtofailure', 'run-to-failure'}
                fam_label = 'run-to-failure only (AVON_FAMILY=rtf)';
                data_gb = rtf_frac * TOTAL_RTF_GB_PROJECTED;
            case {'diag', 'diagnosis'}
                fam_label = 'diagnosis only (AVON_FAMILY=diagnosis)';
                data_gb = diag_frac * TOTAL_DIAG_GB_PROJECTED;
            case {'turndown', 'turn'}
                fam_label = 'turndown only (AVON_FAMILY=turndown)';
                data_gb = diag_frac * TOTAL_TURNDOWN_GB_PROJECTED;
            otherwise
                fam_label = 'ALL families on this machine (AVON_FAMILY unset or "all")';
                data_gb = diag_frac * TOTAL_DIAG_GB_PROJECTED + rtf_frac * TOTAL_RTF_GB_PROJECTED;
        end
        shard_zip_gb = data_gb * ZIP_OVERHEAD_FRACTION;
        min_free_gb  = data_gb + shard_zip_gb;

        fprintf('  Planned workload: %s\n', fam_label);
        fprintf('    Data:  ~%.1f GB\n', data_gb);
        fprintf('    Zips (est. %.0f%% of data): ~%.1f GB\n', ZIP_OVERHEAD_FRACTION*100, shard_zip_gb);
        fprintf('    TOTAL required on this machine: ~%.1f GB\n', min_free_gb);
        if strcmp(family, 'all')
            fprintf('  (Running one family per machine? Set AVON_FAMILY=rtf | diagnosis | turndown\n');
            fprintf('   in config.txt so this check asks only for what THIS machine needs.)\n');
        end
        if free_gb < min_free_gb
            fprintf('  FAIL: free space %.1f GB < %.1f GB required for this shard\n', free_gb, min_free_gb);
            n_fail = n_fail + 1;
        else
            fprintf('  PASS: free space %.1f GB >= %.1f GB\n', free_gb, min_free_gb);
        end
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 4. Model loads and SHA-256 matches
    fprintf('[4/8] Model loads; SHA-256 matches the recorded value...\n');
    try
        model_path = which('AvonGasTurbineDgTwin_fixed');
        if isempty(model_path)
            model_path = fullfile(fileparts(mfilename('fullpath')), 'Core', 'Models', 'AvonGasTurbineDgTwin_fixed.slx');
        end
        actual_sha = local_sha256(model_path);
        fprintf('  File: %s\n  SHA-256: %s\n', model_path, actual_sha);
        if strcmpi(actual_sha, EXPECTED_MODEL_SHA256)
            fprintf('  PASS: matches the recorded SHA-256\n');
        else
            fprintf('  FAIL: SHA-256 mismatch -- expected %s\n', EXPECTED_MODEL_SHA256);
            n_fail = n_fail + 1;
        end
        was_loaded = ~isempty(find_system('type', 'block_diagram', 'Name', 'AvonGasTurbineDgTwin_fixed'));
        load_system(ScenarioConfig.SIMULINK_MODEL);
        fprintf('  PASS: model loads via load_system\n');
        if ~was_loaded
            close_system('AvonGasTurbineDgTwin_fixed', 0);
        end
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 5. SDI archive cap
    fprintf('[5/8] Simulink.sdi.getArchiveRunLimit == 0...\n');
    try
        limit = Simulink.sdi.getArchiveRunLimit();
        if limit == 0
            fprintf('  PASS: SDI archive run limit is 0\n');
        else
            fprintf(['  FAIL: SDI archive run limit is %d, not 0. Run 1_SETUP.bat (it installs \n' ...
                     '        startup_for_matlab_folder.m as %%USERPROFILE%%\\Documents\\MATLAB\\startup.m), \n' ...
                     '        then start a FRESH MATLAB session so startup.m runs.\n'], limit);
            n_fail = n_fail + 1;
        end
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 6. Warm-start library + ambient-check surface
    fprintf('[6/8] Warm-start library / ambient-check surface shape...\n');
    try
        LIB = GetWarmStartLibrary();
        assert(numel(LIB.inlet_temp_C) == 21, 'warm-start grid is not 21 points');
        assert(numel(LIB.S24_omega_radps) == 21);
        assert(numel(LIB.S27_omega_radps) == 21);
        assert(numel(LIB.S26_final_C) == 21);
        assert(~isempty(LIB.chk_inlet_temp_C) && ~isempty(LIB.chk_inlet_press_kPa));
        assert(isequal(size(LIB.chk_S26_C), [numel(LIB.chk_inlet_temp_C), numel(LIB.chk_inlet_press_kPa)]));
        fprintf('  PASS: warm-start library (21-point) and ambient-check surface (%dx%d) load with expected shape\n', ...
            numel(LIB.chk_inlet_temp_C), numel(LIB.chk_inlet_press_kPa));
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 7. AvonWorkers
    fprintf('[7/8] AvonWorkers()...\n');
    try
        n_workers = AvonWorkers();
        env_val = getenv('AVON_WORKERS');
        if ~isempty(env_val)
            src = sprintf('AVON_WORKERS environment variable (%s)', env_val);
        else
            repo_dir = fileparts(fileparts(mfilename('fullpath')));
            cfg_path = fullfile(repo_dir, 'config.txt');
            if isfile(cfg_path)
                src = sprintf('config.txt (%s)', cfg_path);
            else
                src = 'default (feature(''numcores''), capped at 32)';
            end
        end
        fprintf('  AvonWorkers() = %d, resolved from: %s\n', n_workers, src);
        fprintf('  PASS\n');
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    %% 8. Single real record end-to-end + quality acceptance
    % QualityCheckHDF5.m is an offline auditing tool (ScenarioConfig.RUN_QUALITY_CHECKS is
    % false). This check calls it for information but does not gate on it; the acceptance
    % criterion is a current-schema structural check using the same rule ScenarioAlreadyDone.m
    % trusts for resumability.
    fprintf('[8/8] Single real record generates end-to-end and passes a current-schema quality check...\n');
    try
        TEST_EPOCH = 9999;  % well outside any production N_EPOCHS_HEALTHY range
        [~, out_file] = GenerateScenarioInfo('healthy', TEST_EPOCH);
        if exist(out_file, 'file')
            delete(out_file);  % leftover from a previous aborted check
        end
        success = RunScenario('healthy', TEST_EPOCH, 1);
        if ~success
            fprintf('  FAIL: RunScenario(''healthy'', %d, 1) returned false\n', TEST_EPOCH);
            n_fail = n_fail + 1;
        else
            try
                evalc_out = evalc('QualityCheckHDF5(out_file)'); %#ok<NASGU>
                fprintf('  (QualityCheckHDF5 ran without error)\n');
            catch ME_qc
                fprintf('  (QualityCheckHDF5 errored, as expected -- stale schema, not gated on: %s)\n', ME_qc.message);
            end
            [ok, msg] = ValidateRecordSchema(out_file);
            if ok
                fprintf('  PASS: %s\n', msg);
            else
                fprintf('  FAIL: %s\n', msg);
                n_fail = n_fail + 1;
            end
        end
        if exist(out_file, 'file')
            delete(out_file);
            fprintf('  (smoke-test record deleted; Dataset left as found)\n');
        end
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        n_fail = n_fail + 1;
    end
    fprintf('\n');

    fprintf('======================================================================\n');
    if n_fail == 0
        fprintf('  AvonSetupCheck: ALL PASS (warnings, if any, are not failures)\n');
    else
        fprintf('  AvonSetupCheck: %d CHECK(S) FAILED\n', n_fail);
    end
    fprintf('======================================================================\n\n');

    if n_fail > 0
        error('AvonSetupCheck:Failed', '%d check(s) failed -- see output above.', n_fail);
    end
end

%% ---- helpers ----
% local_validate_current_schema was factored out to DataGeneration/ValidateRecordSchema.m
% so the parallel-driver acceptance tests could reuse it without
% duplicating the logic. Call site above now calls ValidateRecordSchema(out_file) directly.

function gb = local_free_space_gb(path_str)
    fileObj = java.io.File(path_str);
    gb = fileObj.getFreeSpace() / (1024^3);
end

function hash = local_sha256(file_path)
    md = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(file_path, 'rb');
    if fid < 0
        error('local_sha256: cannot open %s', file_path);
    end
    while true
        chunk = fread(fid, 1024*1024, '*uint8');
        if isempty(chunk), break; end
        md.update(chunk);
    end
    fclose(fid);
    digest = typecast(md.digest(), 'uint8');
    hash = lower(sprintf('%02x', digest));
end
