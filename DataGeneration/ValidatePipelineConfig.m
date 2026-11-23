function ValidatePipelineConfig(cfg, model_name)
% ValidatePipelineConfig - Pre-flight validation before any dataset generation
%
% Runs 13 checks and aborts with an informative error if any check fails.
% Call once at the start of GenerateAllDatasets, before any simulation.
%
% Checks:
%   1. Simulink model file exists (does not attempt to load)
%   2. GetFaultDefinitions returns correct struct dimensions
%   3. All combo IDs reference valid fault IDs (no duplicates, no out-of-range)
%   4. GenerateFaultMultiplierArray can run for all 42 faults at SEV3 (dry run)
%   5. ScenarioConfig parameters are internally consistent (the ramp-vs-stored-window budget,
%)
%   6. Checkpoints/ directory exists (or can be created)
%   7. Data root resolves (nothing is created inside it)
%   8. Failure log file can be opened for append
%   9. Realised scenario count is 89
%  10. Realised total record count is 110,000 )
%  11. Model structural integrity -- CheckModelStructuralIntegrity.m:
%      no unrecorded dangling input port, and ENV_comp_inlet_temp_C/1 feeds exactly its two
%      known destinations. This is the check that would have caught severed
%      ambient line in seconds, with no simulation -- it runs here so the production driver
%      (GenerateAllDatasets.m, which already calls this validator) gets it for free.
%  12. Naming tables agree with FaultReference/fault_catalogue.csv (CheckNamingConsistency.m)
%  13. No run-to-failure seed collisions across the cycle-1000 boundary
%      (CheckRTFSeedCollisions.m, P6R; run here to cycle 1100, the full proof goes to 10,000)
%
% Inputs:
%   cfg        - struct from ScenarioConfig.GetActiveConfig
%   model_name - string, Simulink model path (ScenarioConfig.SIMULINK_MODEL)
%
% Date: 2026-03-15

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║             PRE-FLIGHT PIPELINE VALIDATION                  ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

errors = {};

%% Check 1: Simulink model file exists
fprintf('[1/13] Simulink model file...\n');
model_slx = [model_name, '.slx'];
if exist(model_slx, 'file') || exist(model_name, 'file')
    fprintf('  ✓ Model file found: %s\n', model_name);
else
    errors{end+1} = sprintf('Check 1 FAIL: Simulink model not found: %s', model_name);
    fprintf('  ✗ Model not found: %s\n', model_name);
end

%% Check 2: GetFaultDefinitions returns correct struct
fprintf('[2/13] GetFaultDefinitions() structure...\n');
try
    fd = GetFaultDefinitions();
    ok = true;

    if fd.Count ~= 42
        ok = false;
        errors{end+1} = sprintf('Check 2 FAIL: GetFaultDefinitions.Count = %d (expected 42)', fd.Count);
    end
    % Expected combo counts read from ScenarioConfig (not hardcoded) so this can't go stale again --
    % updated 2026-10-13 when the 18/22/15 stability-workaround combo tables were retired and
    % replaced by the 21/14/11-row co-occurrence rebuild.
    if size(fd.DualCombos, 1) ~= ScenarioConfig.N_DUAL_COMBOS
        ok = false;
        errors{end+1} = sprintf('Check 2 FAIL: DualCombos has %d rows (expected %d)', size(fd.DualCombos,1), ScenarioConfig.N_DUAL_COMBOS);
    end
    if size(fd.TripleCombos, 1) ~= ScenarioConfig.N_TRIPLE_COMBOS
        ok = false;
        errors{end+1} = sprintf('Check 2 FAIL: TripleCombos has %d rows (expected %d)', size(fd.TripleCombos,1), ScenarioConfig.N_TRIPLE_COMBOS);
    end
    if size(fd.QuadCombos, 1) ~= ScenarioConfig.N_QUAD_COMBOS
        ok = false;
        errors{end+1} = sprintf('Check 2 FAIL: QuadCombos has %d rows (expected %d)', size(fd.QuadCombos,1), ScenarioConfig.N_QUAD_COMBOS);
    end
    if length(fd.Names) ~= 42
        ok = false;
        errors{end+1} = sprintf('Check 2 FAIL: Names has %d entries (expected 42)', length(fd.Names));
    end

    if ok
        fprintf('  ✓ Count=42, DualCombos %d×2, TripleCombos %d×3, QuadCombos %d×4\n', ...
            ScenarioConfig.N_DUAL_COMBOS, ScenarioConfig.N_TRIPLE_COMBOS, ScenarioConfig.N_QUAD_COMBOS);
    end
catch ME
    errors{end+1} = sprintf('Check 2 FAIL: GetFaultDefinitions() error: %s', ME.message);
    fprintf('  ✗ GetFaultDefinitions() threw: %s\n', ME.message);
    fd = [];
end

%% Check 3: All combo IDs reference valid fault IDs
fprintf('[3/13] Combo table validity...\n');
if ~isempty(fd)
    combo_ok = true;
    all_combos = {fd.DualCombos, fd.TripleCombos, fd.QuadCombos};
    combo_names = {'DualCombos', 'TripleCombos', 'QuadCombos'};
    for ci = 1:3
        C = all_combos{ci};
        for ri = 1:size(C,1)
            row = C(ri,:);
            if any(row < 1) || any(row > 42)
                combo_ok = false;
                errors{end+1} = sprintf('Check 3 FAIL: %s row %d has out-of-range ID: %s', ...
                    combo_names{ci}, ri, mat2str(row));
            end
            if length(unique(row)) < length(row)
                combo_ok = false;
                errors{end+1} = sprintf('Check 3 FAIL: %s row %d has duplicate IDs: %s', ...
                    combo_names{ci}, ri, mat2str(row));
            end
        end
    end
    if combo_ok
        fprintf('  ✓ All combo IDs in range [1,42], no duplicates within rows\n');
    end
else
    fprintf('  [SKIP] Skipped (GetFaultDefinitions failed in Check 2)\n');
end

%% Check 4: GenerateFaultMultiplierArray dry run for all 42 faults
fprintf('[4/13] GenerateFaultMultiplierArray dry run (F01-F42, SEV3)...\n');
try
    test_cfg = struct('simulation_duration', 120, 'dt', 1.0, ...
                      'start_time', 60, 'ramp_duration', 30, 'frequency', 0.0);
    n_ok = 0;
    for fid = 1:42
        fd_tmp = GetFaultDefinitions();
        test_cfg.frequency     = fd_tmp.OscillationFrequency(fid);
        test_cfg.ramp_duration = fd_tmp.DriftDuration(fid);
        arr = GenerateFaultMultiplierArray(fid, 3, test_cfg);
        if size(arr, 2) == 2 && size(arr, 1) == 121
            n_ok = n_ok + 1;
        end
    end
    if n_ok == 42
        fprintf('  ✓ All 42 faults produced valid [121×2] arrays\n');
    else
        errors{end+1} = sprintf('Check 4 FAIL: Only %d/42 faults produced valid arrays', n_ok);
        fprintf('  ✗ Only %d/42 faults OK\n', n_ok);
    end
catch ME
    errors{end+1} = sprintf('Check 4 FAIL: %s', ME.message);
    fprintf('  ✗ Error: %s\n', ME.message);
end

%% Check 5: ScenarioConfig internal consistency
% the pre-fix version of this check was ITSELF the bug
% found -- it compared against SIMULATION_DURATION/FAULT_START_MAX with no "+1800 s
% developed tail" term, so it would have passed the very geometry that left F21/F25/F26/F30 with
% 0 s of post-ramp settled signature. Rewritten to assert the real budget in STORED-WINDOW terms
% which is independent of the now-variable pre-roll/SIMULATION_DURATION.
fprintf('[5/13] ScenarioConfig consistency...\n');
cfg_ok = true;
if ScenarioConfig.FAULT_START_TAU_MIN >= ScenarioConfig.FAULT_START_TAU_MAX
    cfg_ok = false;
    errors{end+1} = 'Check 5 FAIL: FAULT_START_TAU_MIN >= FAULT_START_TAU_MAX';
end
DEVELOPED_MIN_S = 1800;  % the quasi-static hold P2_08_severity_delta_grid.m calibrated against
max_ramp = max(GetFaultDefinitions().DriftDuration);
ramp_budget = ScenarioConfig.STORED_SAMPLES - ScenarioConfig.FAULT_START_TAU_MAX - DEVELOPED_MIN_S;
if max_ramp > ramp_budget
    cfg_ok = false;
    errors{end+1} = sprintf(['Check 5 FAIL: max(DriftDuration) (%d) > ramp budget (%d) = ', ...
        'STORED_SAMPLES (%d) - FAULT_START_TAU_MAX (%d) - DEVELOPED_MIN_S (%d). A ramp this long ', ...
        'would not hold the commanded severity for the >=1800s hold the severity bands were ', ...
        'calibrated against.'], ...
        max_ramp, ramp_budget, ScenarioConfig.STORED_SAMPLES, ScenarioConfig.FAULT_START_TAU_MAX, DEVELOPED_MIN_S);
end
if ScenarioConfig.PREROLL_DEFAULT_S <= 0 || ScenarioConfig.PREROLL_REGIME_S < ScenarioConfig.PREROLL_DEFAULT_S
    cfg_ok = false;
    errors{end+1} = 'Check 5 FAIL: PREROLL_REGIME_S must be >= PREROLL_DEFAULT_S > 0';
end
% the timing block promises
% "600..1199 settled pre-onset samples, always >= 600". Nothing previously enforced that a later
% edit to FAULT_START_TAU_MIN would not silently shorten every record's baseline -- assert it.
MIN_PREONSET_BASELINE = 600;
if ScenarioConfig.FAULT_START_TAU_MIN - 1 < MIN_PREONSET_BASELINE
    cfg_ok = false;
    errors{end+1} = sprintf(['Check 5 FAIL: FAULT_START_TAU_MIN - 1 (%d) < minimum pre-onset ', ...
        'baseline (%d). the timing design requires every record to have at least %d settled ', ...
        'samples before the earliest possible onset.'], ...
        ScenarioConfig.FAULT_START_TAU_MIN - 1, MIN_PREONSET_BASELINE, MIN_PREONSET_BASELINE);
end
if cfg_ok
    fprintf('  ✓ FAULT_START_TAU_MIN < MAX; max(DriftDuration)=%d s <= ramp budget=%d s; ', ...
        max_ramp, ramp_budget);
    fprintf('pre-onset baseline=%d s >= %d s\n', ScenarioConfig.FAULT_START_TAU_MIN - 1, MIN_PREONSET_BASELINE);
end

%% Check 6: Checkpoints/ directory exists or can be created
fprintf('[6/13] Checkpoints directory...\n');
chk_dir = ScenarioConfig.CHECKPOINT_DIR;
if ~exist(chk_dir, 'dir')
    try
        mkdir(chk_dir);
        fprintf('  ✓ Created: %s\n', chk_dir);
    catch ME
        errors{end+1} = sprintf('Check 6 FAIL: Cannot create %s: %s', chk_dir, ME.message);
        fprintf('  ✗ Cannot create: %s\n', chk_dir);
    end
else
    fprintf('  ✓ Exists: %s\n', chk_dir);
end

%% Check 7: data root resolves (release layout 2026-11-23)
fprintf('[7/13] Data root...\n');
% The data root IS the release tree (DIAG_*, RTF_*, DiagnosisTurndown directly inside it). This
% check creates NOTHING inside it: scenario folders are created by the writers on first write, and
% the root may legitimately be a read-only copy of the release.
if isfolder(ScenarioConfig.DATASET_BASE_DIR)
    fprintf('  ✓ Data root: %s\n', ScenarioConfig.DATASET_BASE_DIR);
else
    errors{end+1} = sprintf('Check 7 FAIL: data root %s does not exist', ScenarioConfig.DATASET_BASE_DIR);
end

%% Check 8: Failure log can be opened for append
fprintf('[8/13] Failure log file...\n');
log_file = ScenarioConfig.FAILURE_LOG_FILE;
log_dir = fileparts(log_file);
if ~isempty(log_dir) && ~exist(log_dir, 'dir')
    mkdir(log_dir);
end
fid = fopen(log_file, 'a');
if fid == -1
    errors{end+1} = sprintf('Check 8 FAIL: Cannot open failure log for append: %s', log_file);
    fprintf('  ✗ Cannot open: %s\n', log_file);
else
    fclose(fid);
    fprintf('  ✓ Failure log writable: %s\n', log_file);
end

%% Check 9: Realised scenario count is 89
fprintf('[9/13] Scenario count...\n');
n_scenarios = 1 + numel(cfg.single_fault_ids) + numel(cfg.dual_fault_combos) + ...
    numel(cfg.triple_fault_combos) + numel(cfg.quad_fault_combos);
if n_scenarios ~= 89
    errors{end+1} = sprintf('Check 9 FAIL: realised scenario count is %d (expected 89 = 1 Healthy + 42 single + 21 dual + 14 triple + 11 quad)', n_scenarios);
    fprintf('  ✗ Scenario count = %d (expected 89)\n', n_scenarios);
else
    fprintf('  ✓ 89 scenarios (1 Healthy + 42 single + 21 dual + 14 triple + 11 quad)\n');
end

%% Check 10: Realised total record count is 110,000.
%% No calibrated constant depends on the record count.
fprintf('[10/13] Total record count...\n');
n_records = cfg.n_epochs_healthy + numel(cfg.single_fault_ids) * cfg.n_epochs_single + ...
    numel(cfg.dual_fault_combos) * cfg.n_epochs_dual + ...
    numel(cfg.triple_fault_combos) * cfg.n_epochs_triple + ...
    numel(cfg.quad_fault_combos) * cfg.n_epochs_quad;
EXPECTED_TOTAL_RECORDS = 110000;
if ScenarioConfig.TESTING_MODE
    fprintf('  [SKIP] TESTING_MODE is on -- record-count check only applies to production config\n');
elseif n_records ~= EXPECTED_TOTAL_RECORDS
    errors{end+1} = sprintf('Check 10 FAIL: realised total record count is %d (expected %d)', n_records, EXPECTED_TOTAL_RECORDS);
    fprintf('  ✗ Total record count = %d (expected %d)\n', n_records, EXPECTED_TOTAL_RECORDS);
else
    fprintf('  ✓ 110,000 total records (8,000 Healthy + 42x1,500 + 21x800 + 14x800 + 11x1,000)\n');
end

%% Check 11: Model structural integrity
fprintf('[11/13] Model structural integrity...\n');
try
    baseline_csv = fullfile(fileparts(mfilename('fullpath')), 'P4_27_model_port_baseline.csv');
    [struct_ok, struct_findings] = CheckModelStructuralIntegrity(model_name, baseline_csv);
    if struct_ok
        fprintf('  ✓ %s\n  ✓ %s\n', struct_findings.test_a_message, struct_findings.test_b_message);
    else
        if ~struct_findings.test_a_pass
            errors{end+1} = sprintf('Check 11 FAIL (Test A): %s', struct_findings.test_a_message);
            fprintf('  ✗ %s\n', struct_findings.test_a_message);
        end
        if ~struct_findings.test_b_pass
            errors{end+1} = sprintf('Check 11 FAIL (Test B): %s', struct_findings.test_b_message);
            fprintf('  ✗ %s\n', struct_findings.test_b_message);
        end
    end
catch ME
    errors{end+1} = sprintf('Check 11 FAIL: CheckModelStructuralIntegrity threw: %s', ME.message);
    fprintf('  ✗ Error: %s\n', ME.message);
end

%% Check 12: Naming tables agree with FaultReference/fault_catalogue.csv (naming scheme 2026-11-21)
fprintf('[12/13] Naming consistency (fault_catalogue.csv)...\n');
try
    CheckNamingConsistency(false);
    fprintf('  ✓ Names, codes, RTF folders and 89 scenario folder names match the catalogue\n');
catch ME
    errors{end+1} = sprintf('Check 12 FAIL: %s', ME.message);
    fprintf('  ✗ %s\n', ME.message);
end

%% Check 13: No run-to-failure seed collisions (P6R, R4)
fprintf('[13/13] Run-to-failure seed collisions...\n');
try
    seed_summary = CheckRTFSeedCollisions(1100, false);
    fprintf('  ✓ %d mechanisms x %d units x %d cycles: no ENV/NOISE/unit-seed collision across the cycle-1000 boundary\n', ...
        seed_summary.mechanisms, seed_summary.units, seed_summary.max_cycles);
catch ME
    errors{end+1} = sprintf('Check 13 FAIL: %s', ME.message);
    fprintf('  ✗ %s\n', ME.message);
end

%% Summary
fprintf('\n');
if isempty(errors)
    fprintf('╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║         ✓ ALL 13 PRE-FLIGHT CHECKS PASSED                   ║\n');
    fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');
else
    fprintf('╔══════════════════════════════════════════════════════════════╗\n');
    fprintf('║         ✗ PRE-FLIGHT CHECKS FAILED (%d errors)              ║\n', length(errors));
    fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');
    fprintf('Errors:\n');
    for ei = 1:length(errors)
        fprintf('  [%d] %s\n', ei, errors{ei});
    end
    fprintf('\n');
    error('ValidatePipelineConfig:Failed', ...
          'Pre-flight validation failed with %d error(s). Fix issues before running generation.', ...
          length(errors));
end

end
