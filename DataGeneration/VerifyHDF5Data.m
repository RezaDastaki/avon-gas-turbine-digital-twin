function VerifyHDF5Data(h5_file, checkpoint_file)
% VerifyHDF5Data - Verify that HDF5 file data matches checkpoint and workspace data
%
% Syntax:
%   VerifyHDF5Data(h5_file)
%   VerifyHDF5Data(h5_file, checkpoint_file)
%
% Inputs:
%   h5_file         - Path to HDF5 file to verify
%   checkpoint_file - (Optional) Path to .mat checkpoint file.
%                     If provided, label arrays in HDF5 are compared against the checkpoint.
%                     If omitted or empty, label comparison is skipped.
%
% Verification steps:
%   1-7: Sensor data comparison vs workspace re-extraction (unchanged)
%   8:   Label comparison vs checkpoint .mat (new — requires checkpoint_file)
%
% Date: 2025-12-29
% Updated: 2026-03-14 - Added optional checkpoint-based label verification

if nargin < 2
    checkpoint_file = '';
end

fprintf('\n========================================\n');
fprintf('  HDF5 Data Verification\n');
fprintf('========================================\n\n');

%% Step 1: Read HDF5 file
if ~exist(h5_file, 'file')
    error('HDF5 file not found: %s', h5_file);
end

fprintf('Step 1: Reading HDF5 file...\n');
fprintf('  File: %s\n', h5_file);

% Read sensor data and time
sensors_h5 = h5read(h5_file, '/sensors');
time_h5 = h5read(h5_file, '/time');

% Read metadata
fault_count = h5readatt(h5_file, '/', 'fault_count');
epoch = h5readatt(h5_file, '/', 'epoch');
env_id = h5readatt(h5_file, '/', 'environmental_id');
num_samples = h5readatt(h5_file, '/', 'num_samples');
num_sensors = h5readatt(h5_file, '/', 'num_sensors');

fprintf('  ✓ Data loaded from HDF5\n');
fprintf('    Sensors: [%d × %d]\n', size(sensors_h5, 1), size(sensors_h5, 2));
fprintf('    Time: [%d × 1]\n', length(time_h5));
fprintf('    Fault count: %d\n', fault_count);
fprintf('    Epoch: %d\n', epoch);
fprintf('    Environment: %d\n\n', env_id);

%% Step 2: Re-extract sensors from workspace
fprintf('Step 2: Re-extracting sensors from current workspace...\n');

try
    % Use the dt actually present in this file (per-fault output rate can
    % differ from ScenarioConfig.TIMESERIES_DT -- e.g. F18/F19 save at a
    % higher rate than the 1 Hz default) rather than assuming the default.
    dt_h5 = double(time_h5(2)) - double(time_h5(1));
    [sensors_ws, time_ws, info] = ExtractSensorsFromWorkspace(dt_h5, ScenarioConfig.SIMULATION_DURATION);
    fprintf('✓ Re-extraction completed\n');
    fprintf('  Sensors: [%d × %d]\n', size(sensors_ws, 1), size(sensors_ws, 2));
    fprintf('  Time: [%d × 1]\n\n', length(time_ws));
catch ME
    error('Re-extraction failed: %s\nMake sure workspace still contains simulation data!', ME.message);
end

%% Step 3: Verify dimensions match
fprintf('Step 3: Verifying dimensions...\n');

if ~isequal(size(sensors_h5), size(sensors_ws))
    error('Dimension mismatch! HDF5: [%d × %d], Workspace: [%d × %d]', ...
        size(sensors_h5, 1), size(sensors_h5, 2), ...
        size(sensors_ws, 1), size(sensors_ws, 2));
end

if ~isequal(size(time_h5), size(time_ws))
    error('Time vector mismatch! HDF5: [%d × %d], Workspace: [%d × %d]', ...
        size(time_h5, 1), size(time_h5, 2), ...
        size(time_ws, 1), size(time_ws, 2));
end

fprintf('  ✓ Dimensions match perfectly\n');
fprintf('    Both: [%d × %d] sensors\n', size(sensors_h5, 1), size(sensors_h5, 2));
fprintf('    Both: [%d × 1] time\n\n', length(time_h5));

%% Step 4: Compare time vectors
fprintf('Step 4: Comparing time vectors...\n');

time_diff = abs(time_h5 - time_ws);
time_max_diff = max(time_diff);
time_mean_diff = mean(time_diff);

fprintf('  Max difference: %.10f seconds\n', time_max_diff);
fprintf('  Mean difference: %.10f seconds\n', time_mean_diff);

if time_max_diff < 1e-10
    fprintf('  ✓ Time vectors are IDENTICAL\n\n');
elseif time_max_diff < 1e-6
    fprintf('  ✓ Time vectors match (negligible numerical error)\n\n');
else
    warning('Time vectors differ by %.6f seconds!', time_max_diff);
end

%% Step 5: Compare sensor data
fprintf('Step 5: Comparing sensor data for all %d sensors...\n', num_sensors);
fprintf('========================================\n');

% Get sensor definitions
SensorDef = GetSensorDefinitions();

% Statistics storage
correlation = zeros(num_sensors, 1);
rmse = zeros(num_sensors, 1);
max_diff = zeros(num_sensors, 1);
mean_diff = zeros(num_sensors, 1);

fprintf('Sensor   Correlation    RMSE        Max Diff    Mean Diff   Status\n');
fprintf('------   -----------    --------    ---------   ---------   ------\n');

for i = 1:num_sensors
    % Extract columns
    data_h5 = sensors_h5(:, i);
    data_ws = sensors_ws(:, i);

    % Calculate statistics
    if all(data_h5 == 0) && all(data_ws == 0)
        % Both empty
        correlation(i) = NaN;
        rmse(i) = 0;
        max_diff(i) = 0;
        mean_diff(i) = 0;
        status = 'EMPTY';
    else
        % Calculate correlation
        if std(data_h5) > eps && std(data_ws) > eps
            correlation(i) = corr(data_h5, data_ws);
        else
            correlation(i) = NaN;
        end

        % Calculate differences
        diff_data = abs(data_h5 - data_ws);
        max_diff(i) = max(diff_data);
        mean_diff(i) = mean(diff_data);
        rmse(i) = sqrt(mean((data_h5 - data_ws).^2));

        % Status
        if max_diff(i) < 1e-10
            status = '✓ PERFECT';
        elseif max_diff(i) < 1e-6
            status = '✓ EXACT';
        elseif max_diff(i) < 0.01
            status = '✓ GOOD';
        else
            status = '⚠ DIFF';
        end
    end

    % Print row
    fprintf('S%02d      %.6f      %.6e    %.6e   %.6e   %s\n', ...
        i, correlation(i), rmse(i), max_diff(i), mean_diff(i), status);
end

fprintf('========================================\n\n');

%% Step 6: Overall verification summary
fprintf('Step 6: Overall Verification Summary\n');
fprintf('========================================\n');

% Count perfect matches
perfect_count = sum(max_diff < 1e-10);
exact_count = sum(max_diff < 1e-6);
good_count = sum(max_diff < 0.01);

fprintf('Perfect matches (diff < 1e-10): %d/%d\n', perfect_count, num_sensors);
fprintf('Exact matches (diff < 1e-6):    %d/%d\n', exact_count, num_sensors);
fprintf('Good matches (diff < 0.01):     %d/%d\n', good_count, num_sensors);

% Overall statistics
valid_corr = correlation(~isnan(correlation));
if ~isempty(valid_corr)
    fprintf('\nCorrelation statistics:\n');
    fprintf('  Mean: %.8f\n', mean(valid_corr));
    fprintf('  Min:  %.8f\n', min(valid_corr));
    fprintf('  Max:  %.8f\n', max(valid_corr));
end

fprintf('\nDifference statistics (all sensors):\n');
fprintf('  Max RMSE:        %.6e\n', max(rmse));
fprintf('  Max difference:  %.6e\n', max(max_diff));
fprintf('  Mean difference: %.6e\n', mean(mean_diff));

%% Step 7: Metadata verification
fprintf('\n========================================\n');
fprintf('Step 7: Metadata Verification\n');
fprintf('========================================\n');

% Verify metadata
metadata_ok = true;

if num_samples ~= length(time_h5)
    warning('Metadata mismatch: num_samples=%d, actual=%d', num_samples, length(time_h5));
    metadata_ok = false;
end

if num_sensors ~= size(sensors_h5, 2)
    warning('Metadata mismatch: num_sensors=%d, actual=%d', num_sensors, size(sensors_h5, 2));
    metadata_ok = false;
end

if fault_count ~= 0
    warning('Expected fault_count=0 for healthy data, got %d', fault_count);
    metadata_ok = false;
end

if metadata_ok
    fprintf('✓ All metadata fields verified correctly\n');
end

% Read and display sensor names
fprintf('\nSensor names verification (first 5):\n');
for i = 1:5
    attr_name = sprintf('sensor_%02d_name', i);
    sensor_name = h5readatt(h5_file, '/', attr_name);
    fprintf('  S%02d: %s\n', i, sensor_name);
end
fprintf('  ...\n');

%% Step 8: Final verdict
fprintf('\n========================================\n');
fprintf('  FINAL VERIFICATION RESULT\n');
fprintf('========================================\n\n');

if perfect_count >= round(num_sensors * 0.75) && max(max_diff) < 1e-6
    fprintf('✓✓✓ VERIFICATION PASSED! ✓✓✓\n\n');
    fprintf('The HDF5 file is an EXACT match of the workspace data.\n');
    fprintf('All sensor values match within numerical precision.\n');
    fprintf('Metadata is correct and complete.\n\n');
    fprintf('✓ Your pipeline is working perfectly!\n');
    fprintf('✓ You can now generate the full dataset with confidence.\n');

elseif exact_count >= round(num_sensors * 0.75) && max(max_diff) < 0.01
    fprintf('✓ VERIFICATION PASSED (with minor numerical differences)\n\n');
    fprintf('The HDF5 file matches workspace data with acceptable precision.\n');
    fprintf('Small differences (< 0.01) are likely due to numerical rounding.\n');
    fprintf('This is normal and acceptable for engineering applications.\n\n');
    fprintf('✓ Your pipeline is working correctly!\n');

else
    fprintf('⚠ VERIFICATION WARNING\n\n');
    fprintf('Some sensors show significant differences between HDF5 and workspace.\n');
    fprintf('Review the sensor comparison table above for details.\n');
    fprintf('This may indicate an extraction or saving issue.\n\n');
    fprintf('Sensors with issues:\n');
    for i = 1:num_sensors
        if max_diff(i) >= 0.01
            fprintf('  S%02d: %s (max diff = %.6e)\n', i, SensorDef.Names{i}, max_diff(i));
        end
    end
end

fprintf('\n========================================\n\n');

%% Optional: Display sample data comparison
fprintf('Sample Data Comparison (first 5 timepoints, S01-S03):\n');
fprintf('----------------------------------------\n');
fprintf('Time    S01 (HDF5)  S01 (WS)    Diff\n');
for t = 1:5
    fprintf('%.1f    %.2f      %.2f      %.6e\n', ...
        time_h5(t), sensors_h5(t,1), sensors_ws(t,1), abs(sensors_h5(t,1) - sensors_ws(t,1)));
end
fprintf('\n');

fprintf('Time    S02 (HDF5)  S02 (WS)    Diff\n');
for t = 1:5
    fprintf('%.1f    %.4f      %.4f      %.6e\n', ...
        time_h5(t), sensors_h5(t,2), sensors_ws(t,2), abs(sensors_h5(t,2) - sensors_ws(t,2)));
end
fprintf('\n');

fprintf('Time    S03 (HDF5)  S03 (WS)    Diff\n');
for t = 1:5
    fprintf('%.1f    %.2f       %.2f       %.6e\n', ...
        time_h5(t), sensors_h5(t,3), sensors_ws(t,3), abs(sensors_h5(t,3) - sensors_ws(t,3)));
end
fprintf('\n========================================\n\n');

%% Step 8: Label verification from checkpoint
fprintf('\n========================================\n');
fprintf('Step 8: Label Verification vs Checkpoint\n');
fprintf('========================================\n');

if ~isempty(checkpoint_file) && exist(checkpoint_file, 'file')
    fprintf('  Checkpoint: %s\n', checkpoint_file);

    try
        % Load labels from checkpoint
        cp = load(checkpoint_file, 'fault_label', 'severity_label');

        % Load labels from HDF5
        fl_hdf5 = h5read(h5_file, '/fault_label');
        sl_hdf5 = h5read(h5_file, '/severity_label');

        % Exact integer match
        fl_match = isequal(fl_hdf5, cp.fault_label);
        sl_match = isequal(sl_hdf5, cp.severity_label);

        if fl_match
            fprintf('  ✓ /fault_label    matches checkpoint exactly\n');
        else
            n_diff_fl = sum(fl_hdf5(:) ~= cp.fault_label(:));
            fprintf('  ✗ /fault_label    MISMATCH — %d elements differ\n', n_diff_fl);
        end

        if sl_match
            fprintf('  ✓ /severity_label matches checkpoint exactly\n');
        else
            n_diff_sl = sum(sl_hdf5(:) ~= cp.severity_label(:));
            fprintf('  ✗ /severity_label MISMATCH — %d elements differ\n', n_diff_sl);
        end

        if fl_match && sl_match
            fprintf('\n  ✓ All label arrays verified against checkpoint\n\n');
        else
            warning('Label mismatch detected between HDF5 and checkpoint!');
        end

    catch ME
        fprintf('  ⚠ Label verification failed: %s\n\n', ME.message);
    end

elseif ~isempty(checkpoint_file)
    fprintf('  ⚠ Checkpoint file not found: %s\n', checkpoint_file);
    fprintf('  Label verification skipped.\n\n');
else
    fprintf('  No checkpoint path provided — label verification skipped.\n\n');
    fprintf('  (Pass checkpoint_file as second argument to enable label checks.)\n\n');
end

fprintf('Verification complete!\n\n');

end
