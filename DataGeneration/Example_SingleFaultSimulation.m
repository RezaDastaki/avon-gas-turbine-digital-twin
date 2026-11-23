% Example_SingleFaultSimulation.m
% Quick start example: Simulate a single fault scenario and save to HDF5
%
% This script demonstrates how to:
%   1. Configure a fault scenario
%   2. Run the Simulink model (when ready)
%   3. Save data in HDF5 format for machine learning
%
% Date: 2025

clear all; close all; clc;

fprintf('\n=== Single Fault Simulation Example ===\n\n');

%% ===== STEP 1: Configure the Fault =====

fprintf('Step 1: Configuring fault scenario...\n');

% Fault selection: F01 = Compressor Fouling, Severity 3
fault_id = 1;           % F01: Compressor fouling
severity_level = 3;     % Moderate severity (30-50% degradation)

% Create fault activation arrays
active_faults = zeros(1, 32);
active_faults(fault_id) = 1;  % Activate only fault F01

severities = zeros(1, 32);
severities(fault_id) = severity_level;

% Fault timing (staged injection)
onset_times = zeros(1, 32);
onset_times(fault_id) = 100;  % Fault starts at t=100 seconds

ramp_times = zeros(1, 32);
ramp_times(fault_id) = 20;    % Gradual onset over 20 seconds

% Initialize fault configuration
FaultConfig = InitializeFaultConfig(active_faults, severities, ...
    'OnsetTime', onset_times, ...
    'RampTime', ramp_times);

%% ===== STEP 2: Define Operating Conditions =====

fprintf('Step 2: Setting operating conditions...\n');

OperatingConditions = struct();
OperatingConditions.load_percent = 80;              % 80% load
OperatingConditions.ambient_temp_C = 25;            % 25°C ambient
OperatingConditions.ambient_pressure_kPa = 101.3;   % Sea level
OperatingConditions.operating_mode = 'steady_state';
OperatingConditions.description = 'F01 Compressor Fouling - Severity 3';

fprintf('  Load: %d%%\n', OperatingConditions.load_percent);
fprintf('  Ambient Temp: %.1f°C\n', OperatingConditions.ambient_temp_C);
fprintf('  Ambient Pressure: %.1f kPa\n\n', OperatingConditions.ambient_pressure_kPa);

%% ===== STEP 3: Simulation Setup =====

fprintf('Step 3: Preparing simulation...\n');

% Simulation parameters
sim_time = 600;         % 10 minutes
sample_time = 0.1;      % 10 Hz sampling
model_name = 'AvonGasTurbineDgTwin';

% Load the Simulink model (if not already loaded)
% load_system(model_name);

% Assign FaultConfig to base workspace (Simulink will read this)
assignin('base', 'FaultConfig', FaultConfig);
assignin('base', 'OperatingConditions', OperatingConditions);

fprintf('  Simulation Time: %d seconds\n', sim_time);
fprintf('  Sample Rate: %.1f Hz\n\n', 1/sample_time);

%% ===== STEP 4: Run Simulation =====

fprintf('Step 4: Running Simulink simulation...\n');
fprintf('  (This will take a few minutes...)\n\n');

% Run the simulation (fault injection not yet implemented in model)
% For now, run without fault injection to test extraction workflow
try
    % Run simulation
    fprintf('  Starting simulation...\n');
    sim('Core/Models/AvonGasTurbineDgTwin', 'StopTime', num2str(sim_time));
    fprintf('  ✓ Simulation complete\n\n');

    % Extract sensors from workspace using the extraction function
    fprintf('  Extracting sensor data from workspace...\n');
    [sensors_raw, timeVector, sensor_info] = ExtractSensorsFromWorkspace(sample_time, sim_time);
    fprintf('  ✓ Extracted %d sensors with %d samples\n\n', sensor_info.ExtractedSensors, length(timeVector));

    % For now, use same data for nominal (healthy) predictions
    % TODO: In future, run model twice (once healthy, once faulty)
    sensors_nominal = sensors_raw;
    fprintf('  NOTE: Using same data for nominal (fault injection not yet active)\n\n');

catch ME
    warning('Simulation failed: %s', ME.message);
    fprintf('  Falling back to synthetic data for demonstration...\n\n');

    % Generate synthetic data as fallback
    timeVector = (0:sample_time:sim_time)';
    N = length(timeVector);

    % Simulate sensor data with fault effects
    sensors_nominal = 50 + randn(N, 20) * 0.5;  % Nominal (healthy) predictions

    % Raw sensors: healthy before onset, degraded after
    sensors_raw = sensors_nominal + randn(N, 20) * 0.1;  % Start near nominal

    % Add fault effect after onset time
    fault_onset_idx = find(timeVector >= onset_times(fault_id), 1);
    fault_magnitude = 15;  % Severity 3 causes ~15 unit deviation

    % Affect compressor-related sensors (S09, S10, S11)
    for sensor = 9:11
        % Gradual ramp over ramp_time
        ramp_end_idx = find(timeVector >= onset_times(fault_id) + ramp_times(fault_id), 1);
        ramp_indices = fault_onset_idx:ramp_end_idx;
        ramp_factor = linspace(0, 1, length(ramp_indices));

        sensors_raw(ramp_indices, sensor) = sensors_raw(ramp_indices, sensor) + ...
            fault_magnitude * ramp_factor';

        % Full fault after ramp
        if ramp_end_idx < N
            sensors_raw((ramp_end_idx+1):end, sensor) = ...
                sensors_raw((ramp_end_idx+1):end, sensor) + fault_magnitude;
        end
    end

    fprintf('  ✓ Synthetic data generated\n');
    fprintf('    Samples: %d\n', N);
    fprintf('    Duration: %.1f seconds\n\n', timeVector(end));
end

%% ===== STEP 5: Save to HDF5 =====

fprintf('Step 5: Saving data to HDF5 format...\n');

% Create output filename
output_folder = 'TestOutput';
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

filename = fullfile(output_folder, 'F01_CompressorFouling_S3_Example.h5');

% Save using the HDF5 function
SaveToHDF5(filename, timeVector, sensors_raw, sensors_nominal, FaultConfig, OperatingConditions);

fprintf('  ✓ Data saved successfully!\n');
fprintf('    File: %s\n\n', filename);

%% ===== STEP 6: Verify HDF5 File =====

fprintf('Step 6: Verifying HDF5 file structure...\n');

% Display HDF5 contents
h5disp(filename);

% Read back a sample dataset
fprintf('\nReading sample data from HDF5:\n');
time_read = h5read(filename, '/time_series/time');
sensor_S09_raw = h5read(filename, '/time_series/raw_sensors/S09_HP_compressor_pressure_ratio');
sensor_S09_nominal = h5read(filename, '/time_series/nominal_predictions/S09_nominal');
sensor_S09_residual = h5read(filename, '/time_series/physics_residuals/S09_residual');

fprintf('  Time vector: %d samples, range [%.1f, %.1f] seconds\n', ...
    length(time_read), time_read(1), time_read(end));
fprintf('  S09 (Compressor PR): Mean raw = %.2f, Mean nominal = %.2f\n', ...
    mean(sensor_S09_raw), mean(sensor_S09_nominal));
fprintf('  S09 Residual: Mean = %.2f, Max = %.2f\n', ...
    mean(sensor_S09_residual), max(abs(sensor_S09_residual)));

%% ===== STEP 7: Quick Visualization =====

fprintf('\nStep 7: Creating visualization...\n');

figure('Position', [100, 100, 1200, 800]);

% Plot 1: Compressor Pressure Ratio (Affected by fault)
subplot(3, 2, 1);
plot(time_read, sensor_S09_nominal, 'b-', 'LineWidth', 1.5);
hold on;
plot(time_read, sensor_S09_raw, 'r-', 'LineWidth', 1.5);
plot([onset_times(fault_id), onset_times(fault_id)], ylim, 'k--', 'LineWidth', 1);
xlabel('Time (s)');
ylabel('Compressor Pressure Ratio');
title('S09: HP Compressor Pressure Ratio');
legend('Nominal (Healthy)', 'Raw (Faulty)', 'Fault Onset');
grid on;

% Plot 2: Residual
subplot(3, 2, 2);
plot(time_read, sensor_S09_residual, 'k-', 'LineWidth', 1.5);
hold on;
plot([onset_times(fault_id), onset_times(fault_id)], ylim, 'r--', 'LineWidth', 1);
xlabel('Time (s)');
ylabel('Residual (Raw - Nominal)');
title('S09: Physics Residual');
legend('Residual', 'Fault Onset');
grid on;

% Plot 3: Multiple sensors (raw)
subplot(3, 2, 3);
sensor_S10_raw = h5read(filename, '/time_series/raw_sensors/S10_HP_compressor_outlet_temp');
sensor_S11_raw = h5read(filename, '/time_series/raw_sensors/S11_HP_compressor_efficiency');
plot(time_read, sensor_S09_raw, 'r-', 'LineWidth', 1.2);
hold on;
plot(time_read, sensor_S10_raw, 'g-', 'LineWidth', 1.2);
plot(time_read, sensor_S11_raw, 'b-', 'LineWidth', 1.2);
plot([onset_times(fault_id), onset_times(fault_id)], ylim, 'k--', 'LineWidth', 1);
xlabel('Time (s)');
ylabel('Measurement Value');
title('Compressor Sensors (Raw)');
legend('S09: Pressure Ratio', 'S10: Outlet Temp', 'S11: Efficiency', 'Fault Onset');
grid on;

% Plot 4: Residuals for multiple sensors
subplot(3, 2, 4);
sensor_S10_residual = h5read(filename, '/time_series/physics_residuals/S10_residual');
sensor_S11_residual = h5read(filename, '/time_series/physics_residuals/S11_residual');
plot(time_read, sensor_S09_residual, 'r-', 'LineWidth', 1.2);
hold on;
plot(time_read, sensor_S10_residual, 'g-', 'LineWidth', 1.2);
plot(time_read, sensor_S11_residual, 'b-', 'LineWidth', 1.2);
plot([onset_times(fault_id), onset_times(fault_id)], ylim, 'k--', 'LineWidth', 1);
xlabel('Time (s)');
ylabel('Residual');
title('Compressor Sensors (Residuals)');
legend('S09 Residual', 'S10 Residual', 'S11 Residual', 'Fault Onset');
grid on;

% Plot 5: Fault activation timeline
subplot(3, 2, [5, 6]);
fault_signal = zeros(size(time_read));
fault_signal(time_read >= onset_times(fault_id)) = severity_level;
area(time_read, fault_signal, 'FaceColor', [1, 0.7, 0.7], 'EdgeColor', 'r', 'LineWidth', 1.5);
xlabel('Time (s)');
ylabel('Severity Level');
title(sprintf('Fault Activation Timeline: %s', FaultConfig.FaultNames{fault_id}));
ylim([0, 6]);
yticks(0:5);
grid on;

sgtitle(sprintf('Fault Diagnosis Data Visualization\n%s at Severity %d', ...
    FaultConfig.FaultNames{fault_id}, severity_level), 'FontSize', 14, 'FontWeight', 'bold');

fprintf('  ✓ Visualization complete\n\n');

%% ===== COMPLETION =====

fprintf('========================================\n');
fprintf('  EXAMPLE COMPLETE\n');
fprintf('========================================\n');
fprintf('You have successfully:\n');
fprintf('  ✓ Configured a fault scenario (F01, Severity 3)\n');
fprintf('  ✓ Simulated gas turbine operation (demo mode)\n');
fprintf('  ✓ Saved dual-stream data to HDF5 format\n');
fprintf('  ✓ Verified data structure\n');
fprintf('  ✓ Created visualizations\n\n');
fprintf('Next Steps:\n');
fprintf('  1. Modify AvonGasTurbineDgTwin.slx to include fault injection\n');
fprintf('  2. Replace synthetic data with actual simulation\n');
fprintf('  3. Run GenerateCompleteDataset.m for full dataset\n');
fprintf('  4. Use HDF5 files for machine learning training\n');
fprintf('========================================\n\n');
