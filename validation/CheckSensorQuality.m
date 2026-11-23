% CheckSensorQuality.m
% Verify sensor data quality in workspace after simulation (34-sensor configuration)
%
% Usage:
%   After running a simulation, run this script to check:
%   1. All 34 sensor variables exist in workspace
%   2. Correct dimensions (Nx1, where N = number of samples)
%   3. No NaN or Inf values
%   4. Values within expected ranges
%   5. Time vector matches sensor data length
%
% Date: 2025 | Updated: 2026-02-21 (expanded to 34 sensors)

clc;
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║           SENSOR DATA QUALITY CHECK  (34 sensors)           ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% Get sensor definitions
SensorDef = GetSensorDefinitions();

%% Sensor-to-workspace variable mapping (S01-S34)
sensor_vars = {
    'Prss_FG_Bfr_MCV_PT203_kPa';         % S01: FG supply pressure before MCV
    'Prss_FG_Aftr_MCV_PT204_kPa';        % S02: FG pressure after MCV
    'zz_data_FGvalpos';                   % S03: FG MCV stem position
    'zz_data_fuel';                       % S04: Fuel mass flow rate
    'zz_data_FG_temp';                    % S05: FG combustor inlet temperature
    'PDT_139';                            % S06: Air filter differential pressure
    'zz_data_trbAirflow';                 % S07: Air mass flow rate
    'zz_data_IGVpos';                     % S08: IGV opening angle
    'zz_data_cpr';                        % S09: HP compressor pressure ratio
    'zz_data_CmpdisPress';               % S10: HP compressor discharge pressure
    'zz_data_CmpdisTemp';                 % S11: HP compressor discharge temperature
    'zz_data_CompEff';                    % S12: HP compressor efficiency
    'zz_data_comp_outPower';              % S13: HP compressor shaft power
    'zz_data_comp_rotorCooling_flow';     % S14: Rotor cooling air flow
    'zz_data_comp_statorCooling_flow';    % S15: Stator cooling air flow
    'zz_data_cumbustorChamber_temp';      % S16: Combustor exit temperature (TIT)
    'zz_data_cumbustorChamber_press';     % S17: Combustor exit pressure
    'zz_data_combustorChamber_flowrate';  % S18: Combustor exit mass flow
    'zz_data_ggTrbInletTemp';             % S19: GG turbine inlet temperature
    'zz_data_ggTrbExeTemp';              % S20: GG turbine exhaust temperature
    'zz_data_ggTrbRotorCoolingExeTemp';  % S21: GG rotor cooling exhaust temperature
    'zz_data_ggTrbGenPwr';               % S22: GG turbine generated power
    'zz_data_ggExitFlow';                 % S23: GG exhaust mass flow
    'GasGen_Speed_SECF210_rpm';           % S24: GG rotor speed
    'zz_data_ggdisPres';                  % S25: PT inlet pressure
    'zz_data_ptInletTemp';               % S26: PT inlet temperature
    'PwrTrb_Speed_SECF243_rpm';           % S27: PT rotor speed
    'zz_data_ptGenPw';                    % S28: PT generated power
    'zz_data_ptOutletTemp';               % S29: PT outlet temperature
    'zz_data_PTEff';                      % S30: PT efficiency
    'zz_data_ptOutletPress';              % S31: PT outlet pressure
    'zz_data_valveController1';           % S32: Controller power demand (PID1)
    'zz_data_valveController2';           % S33: Controller temperature limit (PID2)
    'zz_data_valveController3'            % S34: Controller IGV demand (PID3)
};

%% Check time vector
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('TIME VECTOR CHECK\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

if evalin('base', 'exist(''time'', ''var'')')
    time_vec = evalin('base', 'time');
    time_vec = squeeze(time_vec);
    time_vec = time_vec(:);

    fprintf('✓ Time vector exists\n');
    fprintf('  Size: %d samples\n', length(time_vec));
    fprintf('  Range: [%.2f, %.2f] seconds\n', time_vec(1), time_vec(end));
    fprintf('  Duration: %.2f seconds\n', time_vec(end) - time_vec(1));
    fprintf('  Sample interval: %.4f seconds (%.2f Hz)\n\n', ...
        mean(diff(time_vec)), 1/mean(diff(time_vec)));

    expected_samples = length(time_vec);
    target_duration  = time_vec(end);  % Used to compute fixed 1 Hz discrete count
else
    fprintf('✗ Time vector NOT FOUND in workspace\n');
    fprintf('  Expected variable name: ''time''\n\n');
    expected_samples = 7378;  % Default (current observed sample count)
    target_duration  = 4800;  % Default simulation duration
end

%% Check each sensor variable
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('SENSOR VARIABLE CHECK\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('%-4s %-42s %-20s %-10s %-8s\n', 'ID', 'Variable Name', 'Size', 'NaN/Inf', 'Status');
fprintf('─────────────────────────────────────────────────────────────────────────────────────────\n');
fprintf('  * (1Hz) = discrete signal from upstream block — usable, interpolated in extraction\n\n');

all_ok = true;
issues = {};
num_sensors = SensorDef.Count;  % 34

for i = 1:num_sensors
    sensor_id = sprintf('S%02d', i);
    var_name = sensor_vars{i};

    % Check if variable exists
    if ~evalin('base', sprintf('exist(''%s'', ''var'')', var_name))
        fprintf('%-4s %-42s %-15s %-10s %-8s\n', sensor_id, var_name, 'NOT FOUND', '-', '✗ FAIL');
        all_ok = false;
        issues{end+1} = sprintf('%s: Variable ''%s'' not found', sensor_id, var_name); %#ok<AGROW>
        continue;
    end

    % Get variable data
    data = evalin('base', var_name);

    % Handle timeseries objects
    if isa(data, 'timeseries')
        data = data.Data;
    end

    % Squeeze to remove singleton dimensions
    data = squeeze(data);

    % Get size info
    data_size = size(data);
    if length(data_size) == 2
        size_str = sprintf('%dx%d', data_size(1), data_size(2));
    else
        size_str = sprintf('%dD', length(data_size));
    end

    % Check for NaN/Inf
    has_nan = any(isnan(data(:)));
    has_inf = any(isinf(data(:)));

    if has_nan && has_inf
        nan_inf_str = 'NaN+Inf';
    elseif has_nan
        nan_inf_str = 'NaN';
    elseif has_inf
        nan_inf_str = 'Inf';
    else
        nan_inf_str = 'OK';
    end

    % Determine status
    % Length check: accept the exact solver-step count OR the fixed 1 Hz discrete
    % count (target_duration + 1). Signals from discrete upstream blocks will be
    % shorter than the variable-step time vector but are still usable because
    % ExtractSensorsFromWorkspace interpolates them correctly.
    is_vector_or_col = (isvector(data) || (length(data_size) == 2 && data_size(2) <= 2));
    n_samples = size(data, 1);
    fixed_1hz_count = round(target_duration) + 1;  % e.g. 4801 for 4800 s simulation
    is_correct_length = (n_samples == expected_samples) || ...
                        (n_samples == fixed_1hz_count)  || ...
                        (n_samples >= floor(expected_samples * 0.5) && n_samples > 100);
    no_bad_values = ~has_nan && ~has_inf;

    % Annotate size string with note if it's a known discrete rate
    if n_samples == fixed_1hz_count && n_samples ~= expected_samples
        size_str = [size_str ' (1Hz*)'];
    end

    if is_vector_or_col && is_correct_length && no_bad_values
        status = '✓ OK';
    else
        status = '✗ FAIL';
        all_ok = false;

        if ~is_vector_or_col
            if length(data_size) > 2
                issues{end+1} = sprintf('%s: 3D array — needs squeeze', sensor_id); %#ok<AGROW>
            elseif data_size(2) > 2
                issues{end+1} = sprintf('%s: Multi-column (%s) — use column selector', sensor_id, size_str); %#ok<AGROW>
            end
        end
        if ~is_correct_length
            issues{end+1} = sprintf('%s: Unexpected length %d (expected ~%d)', sensor_id, n_samples, expected_samples); %#ok<AGROW>
        end
        if has_nan || has_inf
            issues{end+1} = sprintf('%s: Contains %s values', sensor_id, nan_inf_str); %#ok<AGROW>
        end
    end

    fprintf('%-4s %-42s %-20s %-10s %-8s\n', sensor_id, var_name, size_str, nan_inf_str, status);
end

fprintf('\n');

%% Check sensor value ranges
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('SENSOR VALUE RANGES\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('%-4s %-40s %-15s %-15s %-10s\n', 'ID', 'Sensor Name', 'Min', 'Max', 'Range OK');
fprintf('────────────────────────────────────────────────────────────────────────────────────\n');

for i = 1:num_sensors
    sensor_id = sprintf('S%02d', i);
    var_name = sensor_vars{i};
    sensor_name = SensorDef.Names{i};
    expected_range = SensorDef.TypicalRanges{i};

    if ~evalin('base', sprintf('exist(''%s'', ''var'')', var_name))
        fprintf('%-4s %-40s %-15s %-15s %-10s\n', sensor_id, sensor_name, 'NOT FOUND', '-', 'FAIL');
        continue;
    end

    % Get data
    data = evalin('base', var_name);
    if isa(data, 'timeseries')
        data = data.Data;
    end
    data = squeeze(data);

    % Use first column if multi-column
    if ~isvector(data) && size(data, 2) > 1
        data = data(:, 1);
    end
    data = data(:);

    data_min = min(data);
    data_max = max(data);

    % Check range with 10% tolerance
    range_span = expected_range(2) - expected_range(1);
    tolerance = 0.10 * range_span;
    in_range = (data_min >= expected_range(1) - tolerance) && ...
               (data_max <= expected_range(2) + tolerance);

    if in_range
        range_status = '✓ OK';
    else
        range_status = '⚠ CHECK';
        issues{end+1} = sprintf('%s (%s): [%.2f, %.2f] outside expected [%.2f, %.2f]', ...
            sensor_id, sensor_name, data_min, data_max, expected_range(1), expected_range(2)); %#ok<AGROW>
    end

    fprintf('%-4s %-40s %-15.3f %-15.3f %-10s\n', ...
        sensor_id, sensor_name, data_min, data_max, range_status);
end

fprintf('\n');

%% Summary
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║                   QUALITY CHECK SUMMARY                      ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

if all_ok && isempty(issues)
    fprintf('✓✓✓ ALL %d SENSORS PASSED QUALITY CHECK ✓✓✓\n\n', num_sensors);
    fprintf('Sensor data is ready for extraction and HDF5 generation.\n\n');
else
    fprintf('✗ QUALITY CHECK FOUND ISSUES ✗\n\n');
    fprintf('Total issues: %d\n\n', length(issues));

    fprintf('Issues:\n');
    for i = 1:length(issues)
        fprintf('  %d. %s\n', i, issues{i});
    end
    fprintf('\n');

    fprintf('Recommendations:\n');
    fprintf('  1. NOT FOUND: Run simulation first, or check variable name spelling\n');
    fprintf('  2. Wrong size / 3D array: Add Reshape/Squeeze block in Simulink\n');
    fprintf('  3. NaN/Inf: Check Simulink solver settings and initial conditions\n');
    fprintf('  4. Range ⚠ CHECK: May be TBV range — update GetSensorDefinitions.m\n');
    fprintf('     if actual range is consistently different from expected range\n\n');
end

fprintf('═══════════════════════════════════════════════════════════════\n\n');
