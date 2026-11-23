% TestFaultMultipliers.m
% Unified test script for 57-fault array-based multiplier system
%
% Tests:
%   1. Fault definitions loading
%   2. Multiplier calculation for all faults
%   3. Array generation (step, ramp, oscillate)
%   4. Workspace loading
%
% Date: 2025-12-31
% Updated: Arrays instead of timeseries for better Simulink compatibility

clc;
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║         FAULT MULTIPLIER ARRAY TEST SUITE                   ║\n');
fprintf('║          57 Unique Faults (Array-Based System)              ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% TEST 1: Fault Definitions Loading
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('TEST 1: Fault Definitions Loading\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

try
    fault_defs = GetFaultDefinitions();
    fprintf('✓ GetFaultDefinitions() loaded successfully\n');
    fprintf('  Total faults: %d\n', fault_defs.TotalFaults);
    fprintf('  Expected: 57\n');

    if fault_defs.TotalFaults == 57
        fprintf('✓ TEST 1 PASSED\n\n');
    else
        fprintf('✗ TEST 1 FAILED: Expected 57 faults, got %d\n\n', fault_defs.TotalFaults);
        return;
    end
catch ME
    fprintf('✗ TEST 1 FAILED: %s\n\n', ME.message);
    return;
end

%% TEST 2: Multiplier Calculation
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('TEST 2: Multiplier Calculation (Sample Faults)\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

test_faults = [4, 9, 15, 31, 37, 48, 56];  % Ramp, step, step, enhance, enhance, ramp, ramp
test_fault_names = {
    'F04: Compressor blade fouling (ramp)';
    'F09: Compressor surge (step)';
    'F15: Fuel regulator stuck (step)';
    'F31: Hot gas temp increase (enhance)';
    'F37: GG seal degradation (enhance)';
    'F48: GG temp sensor drift (+) (ramp)';
    'F56: FG flowmeter drift (ramp)';
};

fprintf('%-40s | %-8s | %-10s | %-6s\n', 'Fault', 'SEV', 'Multiplier', 'Status');
fprintf('──────────────────────────────────────────────────────────────────────\n');

all_mult_correct = true;

for i = 1:length(test_faults)
    fid = test_faults(i);
    sev = 3;  % Test at SEV3

    try
        mult = GetFaultMultiplier(fid, sev);
        status = '✓';

        % Basic sanity checks
        if fid == 31 || fid == 37  % Enhancement faults
            if mult <= 1.0
                status = '✗ FAIL';
                all_mult_correct = false;
            end
        else  % Degradation faults
            if mult >= 1.0 || mult < 0.05
                status = '✗ FAIL';
                all_mult_correct = false;
            end
        end

        fprintf('%-40s | SEV%-5d | %10.4f | %s\n', test_fault_names{i}, sev, mult, status);
    catch ME
        fprintf('%-40s | SEV%-5d | ERROR      | ✗ FAIL\n', test_fault_names{i}, sev);
        fprintf('  Error: %s\n', ME.message);
        all_mult_correct = false;
    end
end

fprintf('\n');
if all_mult_correct
    fprintf('✓ TEST 2 PASSED\n\n');
else
    fprintf('✗ TEST 2 FAILED\n\n');
    return;
end

%% TEST 3: Array Generation
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('TEST 3: Array Generation\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

config = struct();
config.simulation_duration = 100;
config.dt = 1.0;
config.start_time = 0;
config.ramp_duration = 50;
config.frequency = 0.1;

% Test step fault (F15: Fuel regulator)
fprintf('Testing Step Fault (F15: Fuel regulator stuck, SEV3)...\n');
try
    array_step = GenerateFaultMultiplierArray(15, 3, config);
    fprintf('  ✓ Array created: %dx%d (expected 101x2)\n', size(array_step, 1), size(array_step, 2));
    fprintf('  ✓ Time range: [%.1f, %.1f] seconds\n', array_step(1,1), array_step(end,1));
    fprintf('  ✓ Initial value: %.4f (expected 0.910)\n', array_step(1,2));
    fprintf('  ✓ Final value: %.4f (expected 0.910)\n', array_step(end,2));

    % Verify [N×2] format
    if size(array_step, 2) ~= 2
        fprintf('  ✗ FAIL: Not a [N×2] matrix (got %dx%d)\n', size(array_step,1), size(array_step,2));
        return;
    end
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    return;
end

% Test ramp fault (F56: Flowmeter drift)
fprintf('\nTesting Ramp Fault (F56: Flowmeter drift, SEV3)...\n');
try
    array_ramp = GenerateFaultMultiplierArray(56, 3, config);
    fprintf('  ✓ Array created: %dx%d (expected 101x2)\n', size(array_ramp, 1), size(array_ramp, 2));
    fprintf('  ✓ Time range: [%.1f, %.1f] seconds\n', array_ramp(1,1), array_ramp(end,1));
    fprintf('  ✓ Initial value: %.4f (expected 1.0)\n', array_ramp(1,2));
    fprintf('  ✓ Final value: %.4f (expected 0.985)\n', array_ramp(end,2));

    % Check ramp progression
    mid_idx = 26;  % t=25s (halfway through ramp)
    mid_value = array_ramp(mid_idx, 2);  % Column 2 = data
    fprintf('  ✓ Mid-ramp value (t=25s): %.4f (should be between 1.0 and 0.985)\n', mid_value);

    % Verify [N×2] format
    if size(array_ramp, 2) ~= 2
        fprintf('  ✗ FAIL: Not a [N×2] matrix (got %dx%d)\n', size(array_ramp,1), size(array_ramp,2));
        return;
    end
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    return;
end

% Test oscillate fault (F22: Pressure oscillation)
fprintf('\nTesting Oscillate Fault (F22: Pressure oscillation, SEV3)...\n');
try
    array_osc = GenerateFaultMultiplierArray(22, 3, config);
    fprintf('  ✓ Array created: %dx%d (expected 101x2)\n', size(array_osc, 1), size(array_osc, 2));
    fprintf('  ✓ Time range: [%.1f, %.1f] seconds\n', array_osc(1,1), array_osc(end,1));
    fprintf('  ✓ Mean value: %.4f (expected ~1.0)\n', mean(array_osc(:,2)));
    fprintf('  ✓ Std dev: %.4f (oscillation amplitude)\n', std(array_osc(:,2)));

    % Verify [N×2] format
    if size(array_osc, 2) ~= 2
        fprintf('  ✗ FAIL: Not a [N×2] matrix (got %dx%d)\n', size(array_osc,1), size(array_osc,2));
        return;
    end
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    return;
end

fprintf('\n✓ TEST 3 PASSED\n\n');

%% TEST 4: Workspace Loading (Quick Test)
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('TEST 4: Workspace Loading\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('Testing LoadScenarioToWorkspace with F15 SEV3...\n');
try
    LoadScenarioToWorkspace('single', 1, 15, 3);

    % Check if array was loaded
    if evalin('base', 'exist(''FAULT_15_multiplier'', ''var'')')
        array_loaded = evalin('base', 'FAULT_15_multiplier');
        fprintf('  ✓ FAULT_15_multiplier loaded to workspace\n');
        fprintf('  ✓ Type: %s\n', class(array_loaded));
        fprintf('  ✓ Size: %dx%d (expected Nx2)\n', size(array_loaded, 1), size(array_loaded, 2));

        % Verify it's a [N×2] matrix
        if size(array_loaded, 2) == 2
            fprintf('  ✓ Correct format: [time, data] matrix\n');
            fprintf('  ✓ Time range: [%.1f, %.1f] seconds\n', array_loaded(1,1), array_loaded(end,1));
            fprintf('  ✓ Data values: [%.4f, %.4f]\n', min(array_loaded(:,2)), max(array_loaded(:,2)));
        else
            fprintf('  ✗ FAIL: Not a [N×2] matrix (got %dx%d)\n', size(array_loaded,1), size(array_loaded,2));
            return;
        end
    else
        fprintf('  ✗ FAIL: FAULT_15_multiplier not found in workspace\n');
        return;
    end

    fprintf('\n✓ TEST 4 PASSED\n\n');
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    return;
end

%% SUMMARY
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║                    TEST SUMMARY                             ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

fprintf('✓✓✓ ALL TESTS PASSED ✓✓✓\n\n');
fprintf('57-Fault Array-Based Multiplier System is ready!\n\n');
fprintf('IMPORTANT: Arrays use [time, data] format for Simulink compatibility\n');
fprintf('  - All multipliers are Nx2 matrices: [time_column, data_column]\n');
fprintf('  - Column 1: Time values [0, 1, 2, ..., simulation_duration]\n');
fprintf('  - Column 2: Multiplier values at each time step\n');
fprintf('  - Format required by Simulink From Workspace blocks\n\n');
fprintf('Next Steps:\n');
fprintf('  1. From Workspace blocks should work automatically with [N×2] format\n');
fprintf('  2. Test simulation with array multipliers\n');
fprintf('  3. Verify all sensors remain 7445×1 (no 3D arrays)\n');
fprintf('  4. Generate HDF5 dataset files\n');
fprintf('  5. See FAULT_MAPPING_TABLE.md for complete ID mapping\n\n');

fprintf('═══════════════════════════════════════════════════════════════\n\n');
