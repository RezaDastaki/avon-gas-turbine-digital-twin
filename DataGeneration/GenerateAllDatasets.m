% GenerateAllDatasets.m
% Master script to generate ALL dataset categories in sequence
%
% Pipeline:
%   0. Pre-flight: ValidatePipelineConfig
%   1. Healthy
%   2. Single-fault
%   3. Dual-fault
%   4. Triple-fault
%   5. Quad-fault
%   6. Post-run: DatasetAuditReport
%
% Mode: Controlled by ScenarioConfig.TESTING_MODE
%   - Testing mode: 46 files (1 healthy + 42 single + 3 multi-fault)
%   - Production mode: 31,375 files
%
% Date: 2025-12-29
% Updated: 2026-03-15 - pre-flight, failure log, pack counter, audit report

clc;
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║           COMPLETE DATASET GENERATION                       ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% Pre-flight validation
fprintf('Pre-flight checks...\n');
if exist('ValidatePipelineConfig', 'file') == 2
    % Non-fatal: an earlier validator may assume the old 34-channel / fixed-env
    % structure. A warning here must not block the run.
    try
        ValidatePipelineConfig(ScenarioConfig.GetActiveConfig(), ScenarioConfig.SIMULINK_MODEL);
    catch ME_pre
        fprintf('  [WARN] ValidatePipelineConfig raised: %s (continuing)\n', ME_pre.message);
    end
else
    fprintf('  [WARN] ValidatePipelineConfig.m not found — skipping pre-flight checks\n');
end
fprintf('\n');

%% Open failure log for append
failure_log = ScenarioConfig.FAILURE_LOG_FILE;
failure_log_fid = fopen(failure_log, 'a');
if failure_log_fid == -1
    warning('Could not open failure log for append: %s', failure_log);
end

%% Display configuration
config = ScenarioConfig.GetActiveConfig();
total_files = ScenarioConfig.EstimateFileCount();
file_count_total = 0;  % tracks files across all categories for pack calls

fprintf('Mode: %s\n', iif(ScenarioConfig.TESTING_MODE, 'TESTING', 'PRODUCTION'));
fprintf('Total files to generate: %d\n\n', total_files);

fprintf('Categories enabled:\n');
fprintf('  [%s] Healthy\n', iif(config.generate_healthy, 'X', ' '));
fprintf('  [%s] Single-Fault\n', iif(config.generate_single, 'X', ' '));
fprintf('  [%s] Dual-Fault\n', iif(config.generate_dual, 'X', ' '));
fprintf('  [%s] Triple-Fault\n', iif(config.generate_triple, 'X', ' '));
fprintf('  [%s] Quad-Fault\n\n', iif(config.generate_quad, 'X', ' '));

%% Confirm generation (skipped automatically under non-interactive/-batch execution,
%% where usejava('desktop') is false and input would error or hang)
if usejava('desktop')
    response = input('Start complete dataset generation? (y/n): ', 's');
    if ~strcmpi(response, 'y')
        fprintf('Generation cancelled by user.\n\n');
        return;
    end
else
    fprintf('Non-interactive session detected -- skipping confirmation prompt, proceeding automatically.\n\n');
end

%% Track overall progress
overall_start = tic;
OVERALL_categories_completed = 0;
OVERALL_categories_failed = 0;

%% 1. Generate Healthy Dataset
if config.generate_healthy
    fprintf('\n\n');
    fprintf('═══════════════════════════════════════════════════════════════\n');
    fprintf('  CATEGORY 1/5: HEALTHY DATASET\n');
    fprintf('═══════════════════════════════════════════════════════════════\n\n');

    try
        GenerateHealthyDataset;
        OVERALL_categories_completed = OVERALL_categories_completed + 1;
        fprintf('✓ Healthy dataset completed!\n\n');
    catch ME
        OVERALL_categories_failed = OVERALL_categories_failed + 1;
        fprintf('✗ Healthy dataset FAILED: %s\n\n', ME.message);
        if config.stop_on_quality_fail
            fprintf('Stopping due to error.\n\n');
            return;
        end
    end
end

%% 2. Generate Single-Fault Dataset
if config.generate_single
    fprintf('\n\n');
    fprintf('═══════════════════════════════════════════════════════════════\n');
    fprintf('  CATEGORY 2/5: SINGLE-FAULT DATASET\n');
    fprintf('═══════════════════════════════════════════════════════════════\n\n');

    try
        GenerateSingleFaultDataset;
        OVERALL_categories_completed = OVERALL_categories_completed + 1;
        fprintf('✓ Single-fault dataset completed!\n\n');
    catch ME
        OVERALL_categories_failed = OVERALL_categories_failed + 1;
        fprintf('✗ Single-fault dataset FAILED: %s\n\n', ME.message);
        if config.stop_on_quality_fail
            fprintf('Stopping due to error.\n\n');
            return;
        end
    end
end

%% 3. Generate Dual-Fault Dataset
if config.generate_dual
    fprintf('\n\n');
    fprintf('═══════════════════════════════════════════════════════════════\n');
    fprintf('  CATEGORY 3/5: DUAL-FAULT DATASET\n');
    fprintf('═══════════════════════════════════════════════════════════════\n\n');

    try
        GenerateDualFaultDataset;
        OVERALL_categories_completed = OVERALL_categories_completed + 1;
        fprintf('✓ Dual-fault dataset completed!\n\n');
    catch ME
        OVERALL_categories_failed = OVERALL_categories_failed + 1;
        fprintf('✗ Dual-fault dataset FAILED: %s\n\n', ME.message);
        if config.stop_on_quality_fail
            fprintf('Stopping due to error.\n\n');
            return;
        end
    end
end

%% 4. Generate Triple-Fault Dataset
if config.generate_triple
    fprintf('\n\n');
    fprintf('═══════════════════════════════════════════════════════════════\n');
    fprintf('  CATEGORY 4/5: TRIPLE-FAULT DATASET\n');
    fprintf('═══════════════════════════════════════════════════════════════\n\n');

    try
        GenerateTripleFaultDataset;
        OVERALL_categories_completed = OVERALL_categories_completed + 1;
        fprintf('✓ Triple-fault dataset completed!\n\n');
    catch ME
        OVERALL_categories_failed = OVERALL_categories_failed + 1;
        fprintf('✗ Triple-fault dataset FAILED: %s\n\n', ME.message);
        if config.stop_on_quality_fail
            fprintf('Stopping due to error.\n\n');
            return;
        end
    end
end

%% 5. Generate Quad-Fault Dataset
if config.generate_quad
    fprintf('\n\n');
    fprintf('═══════════════════════════════════════════════════════════════\n');
    fprintf('  CATEGORY 5/5: QUAD-FAULT DATASET\n');
    fprintf('═══════════════════════════════════════════════════════════════\n\n');

    try
        GenerateQuadFaultDataset;
        OVERALL_categories_completed = OVERALL_categories_completed + 1;
        fprintf('✓ Quad-fault dataset completed!\n\n');
    catch ME
        OVERALL_categories_failed = OVERALL_categories_failed + 1;
        fprintf('✗ Quad-fault dataset FAILED: %s\n\n', ME.message);
        if config.stop_on_quality_fail
            fprintf('Stopping due to error.\n\n');
            return;
        end
    end
end

%% Close failure log
if failure_log_fid ~= -1
    fclose(failure_log_fid);
end

%% Final Summary
overall_time = toc(overall_start);

fprintf('\n\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║        COMPLETE DATASET GENERATION FINISHED                 ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

fprintf('Final Summary:\n');
fprintf('  Categories completed: %d\n', OVERALL_categories_completed);
fprintf('  Categories failed: %d\n', OVERALL_categories_failed);
fprintf('  Total time: %.1f hours (%.1f days)\n', overall_time/3600, overall_time/86400);
fprintf('  Completed: %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));

fprintf('═══════════════════════════════════════════════════════════════\n\n');

%% Post-run audit report
if exist('DatasetAuditReport', 'file') == 2
    fprintf('Running dataset audit report...\n');
    try
        DatasetAuditReport(config, ScenarioConfig.AUDIT_REPORT_FILE);
    catch ME_audit
        fprintf('[WARN] DatasetAuditReport failed: %s\n', ME_audit.message);
    end
else
    fprintf('[INFO] DatasetAuditReport.m not found — skipping audit.\n');
    fprintf('       Check failure log: %s\n', failure_log);
end

fprintf('\nFor production run: set TESTING_MODE = false in ScenarioConfig.m\n\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% Helper function
function result = iif(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
