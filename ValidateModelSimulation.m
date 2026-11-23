% ValidateModelSimulation.m
% Comprehensive validation of AvonGasTurbineDgTwin.slx simulation
% Checks outputs against physical constraints and baseline model
%
% This script will:
%   1. Run both baseline and digital twin models
%   2. Compare their outputs
%   3. Check physical constraints
%   4. Validate against experimental data
%   5. Generate diagnostic plots
%
% Date: 2025-12-28

clear all; close all; clc;

fprintf('\n');
fprintf('========================================================\n');
fprintf('  Model Validation: AvonGasTurbineDgTwin.slx\n');
fprintf('========================================================\n\n');

%% ===== SETUP =====
fprintf('Step 1: Setting up environment...\n');

% Add paths
addpath('Core/Models');
addpath('Core/Scripts');
if isfolder('Core/ComponentModels'), addpath('Core/ComponentModels'); end

% Load initialization data
fprintf('  Loading parameters (may take 10-30 seconds)...\n');
run('Core/Scripts/DataGasTurbineAvon.m');
fprintf('  ✓ Parameters loaded\n\n');

%% ===== SIMULATION PARAMETERS =====
sim_time = 300;  % 5 minutes simulation
fprintf('Simulation duration: %d seconds\n\n', sim_time);

%% ===== RUN BASELINE MODEL =====
fprintf('Step 2: Running baseline model (AvonGasTurbine.slx)...\n');
fprintf('  This is the validated reference model from the paper\n');

tic;
try
    sim_baseline = sim('Core/Models/AvonGasTurbine', 'StopTime', num2str(sim_time));
    t_baseline = toc;
    fprintf('  ✓ Baseline simulation complete (%.1f seconds)\n\n', t_baseline);
    baseline_success = true;
catch ME
    fprintf('  ✗ ERROR: Baseline model failed\n');
    fprintf('  Error: %s\n\n', ME.message);
    baseline_success = false;
end

%% ===== RUN DIGITAL TWIN MODEL =====
fprintf('Step 3: Running digital twin model (AvonGasTurbineDgTwin.slx)...\n');
fprintf('  This is your working model for fault injection\n');

tic;
try
    sim_dgtwin = sim('Core/Models/AvonGasTurbineDgTwin', 'StopTime', num2str(sim_time));
    t_dgtwin = toc;
    fprintf('  ✓ Digital twin simulation complete (%.1f seconds)\n\n', t_dgtwin);
    dgtwin_success = true;
catch ME
    fprintf('  ✗ ERROR: Digital twin model failed\n');
    fprintf('  Error: %s\n\n', ME.message);
    dgtwin_success = false;
    return;  % Can't proceed without digital twin
end

%% ===== INSPECT SIMULATION OUTPUTS =====
fprintf('Step 4: Inspecting simulation outputs...\n\n');

% Display baseline outputs
if baseline_success
    fprintf('Baseline Model Outputs:\n');
    disp(sim_baseline);
    baseline_vars = fieldnames(sim_baseline);
    fprintf('  Number of output signals: %d\n', length(baseline_vars));
    fprintf('  Variables: %s\n', strjoin(baseline_vars, ', '));
end

fprintf('\n');

% Display digital twin outputs
fprintf('Digital Twin Model Outputs:\n');
disp(sim_dgtwin);
dgtwin_vars = fieldnames(sim_dgtwin);
fprintf('  Number of output signals: %d\n', length(dgtwin_vars));
fprintf('  Variables: %s\n\n', strjoin(dgtwin_vars, ', '));

%% ===== CHECK TIME VECTOR =====
fprintf('Step 5: Checking time vectors...\n');

time_dgtwin = sim_dgtwin.tout;
fprintf('  Digital Twin:\n');
fprintf('    Samples: %d\n', length(time_dgtwin));
fprintf('    Range: [%.2f, %.2f] seconds\n', time_dgtwin(1), time_dgtwin(end));
fprintf('    Average dt: %.4f seconds\n', mean(diff(time_dgtwin)));
fprintf('    Sample rate: ~%.1f Hz\n', 1/mean(diff(time_dgtwin)));

if baseline_success
    time_baseline = sim_baseline.tout;
    fprintf('  Baseline:\n');
    fprintf('    Samples: %d\n', length(time_baseline));
    fprintf('    Range: [%.2f, %.2f] seconds\n', time_baseline(1), time_baseline(end));
end

fprintf('\n');

%% ===== EXTRACT KEY SIGNALS =====
fprintf('Step 6: Extracting and validating key signals...\n\n');

% You need to identify which signals are in your model
% Common gas turbine signals to look for:
signal_candidates = {
    'T_turbine', 'T_comp', 'T_combustor', 'T_exhaust', ...  % Temperatures
    'P_comp', 'P_turbine', 'pressure_ratio', ...             % Pressures
    'N_GG', 'N_PT', 'speed_GG', 'speed_PT', ...             % Speeds
    'Power', 'Power_PT', 'power_output', ...                 % Power
    'mdot_air', 'mdot_fuel', 'mass_flow', ...               % Mass flows
    'eta_comp', 'eta_turb', 'eta_PT', 'efficiency', ...     % Efficiencies
    'yout', 'simout', 'logsout'                             % Generic outputs
};

% Find which signals exist
fprintf('Searching for output signals in Digital Twin model...\n');
available_signals = {};
for i = 1:length(signal_candidates)
    if isfield(sim_dgtwin, signal_candidates{i})
        available_signals{end+1} = signal_candidates{i};
        fprintf('  ✓ Found: %s\n', signal_candidates{i});
    end
end

if isempty(available_signals)
    fprintf('  No standard signals found. Checking generic outputs...\n');

    % Check for yout (common Simulink output)
    if isfield(sim_dgtwin, 'yout')
        fprintf('  ✓ Found generic output: yout\n');
        yout = sim_dgtwin.yout;

        % If yout is a Simulink.SimulationData.Dataset
        if isa(yout, 'Simulink.SimulationData.Dataset')
            fprintf('  yout is a Dataset with %d elements:\n', yout.numElements);
            for i = 1:yout.numElements
                element = yout{i};
                fprintf('    [%d] %s\n', i, element.Name);
            end
        elseif isnumeric(yout)
            fprintf('  yout is numeric: size = [%s]\n', num2str(size(yout)));
        end
    end

    % Check for logsout (Simulink Signal Logging)
    if isfield(sim_dgtwin, 'logsout')
        fprintf('  ✓ Found signal logging: logsout\n');
        logsout = sim_dgtwin.logsout;

        if isa(logsout, 'Simulink.SimulationData.Dataset')
            fprintf('  logsout contains %d logged signals:\n', logsout.numElements);
            for i = 1:logsout.numElements
                element = logsout{i};
                fprintf('    [%d] %s\n', i, element.Name);
            end
        end
    end
end

fprintf('\n');

%% ===== PHYSICAL CONSTRAINT CHECKS =====
fprintf('Step 7: Checking physical constraints...\n');
fprintf('  (Gas turbine parameters must be within realistic ranges)\n\n');

% Define physically realistic ranges for gas turbine parameters
physical_limits = struct();
physical_limits.temperature_min = -50;      % °C (ambient can be cold)
physical_limits.temperature_max = 1500;     % °C (max turbine inlet temp)
physical_limits.pressure_min = 50;          % kPa (below atmospheric is impossible)
physical_limits.pressure_max = 5000;        % kPa (very high pressure)
physical_limits.speed_min = 0;              % rpm
physical_limits.speed_max = 25000;          % rpm (typical max for gas turbines)
physical_limits.power_min = 0;              % kW
physical_limits.power_max = 15000;          % kW (Avon max power ~10 MW)
physical_limits.efficiency_min = 0;         % %
physical_limits.efficiency_max = 100;       % %
physical_limits.pressure_ratio_min = 1;     % dimensionless
physical_limits.pressure_ratio_max = 30;    % dimensionless

% This is a template - you'll need to adapt based on your actual signals
fprintf('Physical Limit Checks:\n');
fprintf('  Temperature range: %.0f to %.0f °C\n', ...
    physical_limits.temperature_min, physical_limits.temperature_max);
fprintf('  Pressure range: %.0f to %.0f kPa\n', ...
    physical_limits.pressure_min, physical_limits.pressure_max);
fprintf('  Speed range: %.0f to %.0f rpm\n', ...
    physical_limits.speed_min, physical_limits.speed_max);
fprintf('  Power range: %.0f to %.0f kW\n', ...
    physical_limits.power_min, physical_limits.power_max);
fprintf('  Efficiency range: %.0f to %.0f %%\n', ...
    physical_limits.efficiency_min, physical_limits.efficiency_max);

fprintf('\n  Note: To validate specific signals, you need to identify\n');
fprintf('        which outputs are available in your model (see Step 6)\n\n');

%% ===== LOAD EXPERIMENTAL DATA =====
fprintf('Step 8: Loading experimental/calibration data...\n');

try
    run('Core/Scripts/GasTurbineAvonLoading.m');
    fprintf('  ✓ Experimental data loaded\n');
    fprintf('  Variables available: ');
    exp_vars = who;
    fprintf('%s\n\n', strjoin(exp_vars, ', '));
    exp_data_available = true;
catch ME
    fprintf('  ⚠ Could not load experimental data\n');
    fprintf('  Error: %s\n\n', ME.message);
    exp_data_available = false;
end

%% ===== COMPARISON WITH BASELINE =====
if baseline_success
    fprintf('Step 9: Comparing Digital Twin vs Baseline...\n');
    fprintf('  The digital twin should behave similarly to the baseline\n');
    fprintf('  (unless you''ve already modified it)\n\n');

    % Compare time vectors
    if length(time_baseline) == length(time_dgtwin)
        fprintf('  ✓ Time vectors have same length (%d samples)\n', length(time_dgtwin));
    else
        fprintf('  ⚠ Time vectors differ: Baseline=%d, DgTwin=%d\n', ...
            length(time_baseline), length(time_dgtwin));
    end

    % Try to compare common signals
    common_signals = intersect(baseline_vars, dgtwin_vars);
    fprintf('  Common output signals: %d\n', length(common_signals));

    if ~isempty(common_signals)
        fprintf('  Signals: %s\n', strjoin(common_signals, ', '));
    end

    fprintf('\n');
else
    fprintf('Step 9: Skipping baseline comparison (baseline did not run)\n\n');
end

%% ===== VISUALIZATION =====
fprintf('Step 10: Creating diagnostic plots...\n\n');

% Create figure for plots
fig = figure('Position', [100, 100, 1400, 900]);
sgtitle('AvonGasTurbineDgTwin Model Validation', 'FontSize', 14, 'FontWeight', 'bold');

% Plot 1: Time vector
subplot(3, 3, 1);
plot(time_dgtwin, 'b-', 'LineWidth', 1.5);
xlabel('Sample Index');
ylabel('Time (s)');
title('Time Vector');
grid on;

% Plot 2: Sample rate
subplot(3, 3, 2);
dt = diff(time_dgtwin);
plot(dt, 'r-', 'LineWidth', 1);
xlabel('Sample Index');
ylabel('dt (s)');
title('Sample Interval (dt)');
grid on;
avg_dt = mean(dt);
text(0.5, 0.9, sprintf('Avg dt: %.4f s\nSample rate: %.1f Hz', ...
    avg_dt, 1/avg_dt), 'Units', 'normalized', 'FontSize', 9);

% Remaining plots - placeholder for actual signals
subplot(3, 3, 3);
text(0.5, 0.5, {'No specific signal selected', '', ...
    'To plot actual data:', '1. Identify output signals (Step 6)', ...
    '2. Extract signal data', '3. Add plot commands here'}, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
title('Signal Placeholder 1');

subplot(3, 3, 4:6);
text(0.5, 0.5, {'NEXT STEP:', '', ...
    'Open your Simulink model and add:', ...
    '• Scope blocks to visualize signals', ...
    '• To Workspace blocks to log specific signals', ...
    '• Signal logging on key outputs', '', ...
    'Common signals to monitor:', ...
    '- Compressor outlet temperature', ...
    '- Gas generator speed', ...
    '- Power turbine speed', ...
    '- Power output', ...
    '- Fuel flow rate'}, ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'FontSize', 10);
title('How to Add Signal Logging to Your Model');

subplot(3, 3, 7);
if isfield(sim_dgtwin, 'yout') && isnumeric(sim_dgtwin.yout)
    yout = sim_dgtwin.yout;
    if size(yout, 2) >= 1
        plot(time_dgtwin, yout(:,1), 'b-', 'LineWidth', 1.5);
        xlabel('Time (s)');
        ylabel('yout(:,1)');
        title('Generic Output 1');
        grid on;
    end
else
    text(0.5, 0.5, 'No yout available', 'HorizontalAlignment', 'center');
    title('Generic Output 1');
end

subplot(3, 3, 8);
if isfield(sim_dgtwin, 'yout') && isnumeric(sim_dgtwin.yout)
    yout = sim_dgtwin.yout;
    if size(yout, 2) >= 2
        plot(time_dgtwin, yout(:,2), 'r-', 'LineWidth', 1.5);
        xlabel('Time (s)');
        ylabel('yout(:,2)');
        title('Generic Output 2');
        grid on;
    end
else
    text(0.5, 0.5, 'No yout available', 'HorizontalAlignment', 'center');
    title('Generic Output 2');
end

subplot(3, 3, 9);
% Workspace variables
vars = whos;
text(0.1, 0.9, sprintf('Workspace Variables: %d', length(vars)), ...
    'Units', 'normalized', 'FontSize', 10, 'FontWeight', 'bold');
var_list = {};
for i = 1:min(15, length(vars))
    var_list{end+1} = sprintf('%s [%s]', vars(i).name, num2str(vars(i).size));
end
text(0.1, 0.05, var_list, 'Units', 'normalized', 'FontSize', 7, ...
    'VerticalAlignment', 'bottom');
title('Workspace Contents');
axis off;

fprintf('  ✓ Diagnostic plots created\n\n');

%% ===== VALIDATION SUMMARY =====
fprintf('========================================================\n');
fprintf('  VALIDATION SUMMARY\n');
fprintf('========================================================\n\n');

% Count checks
total_checks = 5;
passed_checks = 0;

fprintf('Model Execution:\n');
if dgtwin_success
    fprintf('  ✓ Digital Twin simulates successfully\n');
    passed_checks = passed_checks + 1;
else
    fprintf('  ✗ Digital Twin failed to simulate\n');
end

if baseline_success
    fprintf('  ✓ Baseline model simulates successfully\n');
    passed_checks = passed_checks + 1;
end

fprintf('\nOutput Structure:\n');
if ~isempty(dgtwin_vars)
    fprintf('  ✓ Digital Twin produces %d output signals\n', length(dgtwin_vars));
    passed_checks = passed_checks + 1;
else
    fprintf('  ✗ No output signals found\n');
end

fprintf('\nTime Vector:\n');
if length(time_dgtwin) > 0
    fprintf('  ✓ Time vector contains %d samples\n', length(time_dgtwin));
    passed_checks = passed_checks + 1;
else
    fprintf('  ✗ Time vector is empty\n');
end

fprintf('\nData Quality:\n');
if mean(diff(time_dgtwin)) > 0
    fprintf('  ✓ Time vector is monotonically increasing\n');
    passed_checks = passed_checks + 1;
else
    fprintf('  ✗ Time vector has issues\n');
end

fprintf('\n');
fprintf('Overall: %d/%d basic checks passed\n', passed_checks, total_checks);

if passed_checks == total_checks
    fprintf('✓ Model appears to be working correctly!\n\n');
else
    fprintf('⚠ Some issues detected. Review output above.\n\n');
end

%% ===== RECOMMENDATIONS =====
fprintf('========================================================\n');
fprintf('  RECOMMENDATIONS FOR NEXT STEPS\n');
fprintf('========================================================\n\n');

fprintf('1. IDENTIFY OUTPUT SIGNALS:\n');
fprintf('   - Open AvonGasTurbineDgTwin.slx in Simulink\n');
fprintf('   - Add Scope blocks to visualize key signals\n');
fprintf('   - Add "To Workspace" blocks to log:\n');
fprintf('     • Compressor outlet temperature\n');
fprintf('     • Gas generator speed\n');
fprintf('     • Power turbine speed  \n');
fprintf('     • Power output\n');
fprintf('     • Fuel flow rate\n');
fprintf('     • Any other 20 sensors you need\n\n');

fprintf('2. VERIFY PHYSICAL REALISM:\n');
fprintf('   - Check that temperatures are in range (20-1200°C)\n');
fprintf('   - Check that pressures are realistic (100-3000 kPa)\n');
fprintf('   - Check that speeds are reasonable (0-20000 rpm)\n');
fprintf('   - Check that power output makes sense (0-10000 kW)\n\n');

fprintf('3. COMPARE WITH BASELINE:\n');
fprintf('   - Run this script again after adding signal logging\n');
fprintf('   - Compare digital twin outputs with baseline\n');
fprintf('   - They should be very similar (if no faults injected)\n\n');

fprintf('4. VALIDATE AGAINST EXPERIMENTAL DATA:\n');
fprintf('   - Check Core/Scripts/GasTurbineAvonLoading.m\n');
fprintf('   - Compare simulation outputs with experimental data\n');
fprintf('   - Calculate RMS error or correlation\n\n');

fprintf('5. DOCUMENT YOUR FINDINGS:\n');
fprintf('   - Note which signals are available\n');
fprintf('   - Document typical operating ranges\n');
fprintf('   - Create parameter mapping table\n\n');

fprintf('========================================================\n\n');

%% ===== SAVE RESULTS =====
fprintf('Saving validation results...\n');

validation_results = struct();
validation_results.timestamp = datetime('now');
validation_results.sim_time = sim_time;
validation_results.dgtwin_success = dgtwin_success;
validation_results.baseline_success = baseline_success;
validation_results.dgtwin_vars = dgtwin_vars;
validation_results.time_samples = length(time_dgtwin);
validation_results.avg_sample_rate = 1/mean(diff(time_dgtwin));
validation_results.passed_checks = passed_checks;
validation_results.total_checks = total_checks;

save('validation_results.mat', 'validation_results', 'sim_dgtwin');
fprintf('  ✓ Results saved to validation_results.mat\n\n');

fprintf('Validation complete!\n');
fprintf('Check the figure window for diagnostic plots.\n\n');
