function SaveToHDF5(filename, timeVector, sensors_raw, sensors_nominal, FaultConfig, OperatingConditions)
% SaveToHDF5 - Save gas turbine fault diagnosis data to HDF5 format
%
% Syntax:
%   SaveToHDF5(filename, timeVector, sensors_raw, sensors_nominal, FaultConfig, OperatingConditions)
%
% Inputs:
%   filename            - Full path to HDF5 file (will be created/overwritten)
%   timeVector          - Time vector [N x 1] in seconds
%   sensors_raw         - Raw sensor measurements [N x 20]
%   sensors_nominal     - Nominal predictions from digital twin [N x 20]
%   FaultConfig         - Fault configuration struct from InitializeFaultConfig
%   OperatingConditions - Struct with fields:
%                         .load_percent (e.g., 80)
%                         .ambient_temp_C (e.g., 25)
%                         .ambient_pressure_kPa (e.g., 101.3)
%                         .operating_mode (e.g., 'steady_state', 'transient_startup')
%                         .description (optional text description)
%
% HDF5 Structure Created:
%   /metadata/
%       - description, fault_type, severity_level, active_faults, severity_vector
%       - operating_condition, ambient_temp_C, ambient_pressure_kPa, load_percent
%       - sample_rate_Hz, duration_seconds, generation_date, digital_twin_version
%   /time_series/
%       - time [N]
%       /raw_sensors/ - S01_FG_skid_pressure ... S20_Overall_thermal_efficiency [N each]
%       /nominal_predictions/ - S01_nominal ... S20_nominal [N each]
%       /physics_residuals/ - S01_residual ... S20_residual [N each]
%   /labels/
%       - fault_class, severity, fault_onset_times [32]
%
% Example:
%   % After simulation with fault
%   SaveToHDF5('F01_S3.h5', tout, sensors_raw, sensors_nominal, FaultConfig, OpCond);
%
% Date: 2025

    fprintf('\n=== Saving Data to HDF5 ===\n');
    fprintf('File: %s\n', filename);

    % Get sensor definitions
    SensorDef = GetSensorDefinitions();

    % Validate inputs
    N = length(timeVector);
    if size(sensors_raw, 1) ~= N || size(sensors_raw, 2) ~= 20
        error('sensors_raw must be [N x 20] where N = length(timeVector)');
    end
    if size(sensors_nominal, 1) ~= N || size(sensors_nominal, 2) ~= 20
        error('sensors_nominal must be [N x 20] where N = length(timeVector)');
    end

    % Delete existing file if it exists
    if exist(filename, 'file')
        delete(filename);
        fprintf('  Removed existing file\n');
    end

    % Compute physics residuals
    physics_residuals = sensors_raw - sensors_nominal;

    % Compute sample rate
    if N > 1
        dt = mean(diff(timeVector));
        sample_rate_Hz = 1 / dt;
    else
        sample_rate_Hz = 0;
    end
    duration_seconds = timeVector(end) - timeVector(1);

    %% ===== METADATA GROUP =====
    fprintf('  Writing metadata...\n');

    % Determine fault description
    if FaultConfig.NumActiveFaults == 0
        fault_description = 'Healthy baseline operation';
        fault_type_str = 'Healthy';
        severity_level = 0;
    elseif FaultConfig.NumActiveFaults == 1
        active_idx = find(FaultConfig.ActiveFaults, 1);
        fault_type_str = FaultConfig.FaultNames{active_idx};
        severity_level = FaultConfig.Severity(active_idx);
        fault_description = sprintf('%s at severity level %d', fault_type_str, severity_level);
    else
        fault_type_str = 'Multi_Fault';
        severity_level = max(FaultConfig.Severity(FaultConfig.ActiveFaults == 1));
        active_names = FaultConfig.FaultNames(FaultConfig.ActiveFaults == 1);
        fault_description = sprintf('Multi-fault: %s', strjoin(active_names, ', '));
    end

    % Create metadata group
    h5create(filename, '/metadata/description', size(fault_description), 'Datatype', 'string');
    h5write(filename, '/metadata/description', string(fault_description));

    h5create(filename, '/metadata/fault_type', size(fault_type_str), 'Datatype', 'string');
    h5write(filename, '/metadata/fault_type', string(fault_type_str));

    h5create(filename, '/metadata/severity_level', 1);
    h5write(filename, '/metadata/severity_level', severity_level);

    h5create(filename, '/metadata/active_faults', 32);
    h5write(filename, '/metadata/active_faults', FaultConfig.ActiveFaults);

    h5create(filename, '/metadata/severity_vector', 32);
    h5write(filename, '/metadata/severity_vector', FaultConfig.Severity);

    % Operating conditions
    if ~isfield(OperatingConditions, 'operating_mode')
        OperatingConditions.operating_mode = 'steady_state';
    end
    h5create(filename, '/metadata/operating_condition', size(OperatingConditions.operating_mode), 'Datatype', 'string');
    h5write(filename, '/metadata/operating_condition', string(OperatingConditions.operating_mode));

    h5create(filename, '/metadata/ambient_temp_C', 1);
    h5write(filename, '/metadata/ambient_temp_C', OperatingConditions.ambient_temp_C);

    h5create(filename, '/metadata/ambient_pressure_kPa', 1);
    h5write(filename, '/metadata/ambient_pressure_kPa', OperatingConditions.ambient_pressure_kPa);

    h5create(filename, '/metadata/load_percent', 1);
    h5write(filename, '/metadata/load_percent', OperatingConditions.load_percent);

    % Temporal metadata
    h5create(filename, '/metadata/sample_rate_Hz', 1);
    h5write(filename, '/metadata/sample_rate_Hz', sample_rate_Hz);

    h5create(filename, '/metadata/duration_seconds', 1);
    h5write(filename, '/metadata/duration_seconds', duration_seconds);

    % Generation info
    generation_date = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    h5create(filename, '/metadata/generation_date', size(generation_date), 'Datatype', 'string');
    h5write(filename, '/metadata/generation_date', string(generation_date));

    digital_twin_version = 'AvonW_PhD_Research';
    h5create(filename, '/metadata/digital_twin_version', size(digital_twin_version), 'Datatype', 'string');
    h5write(filename, '/metadata/digital_twin_version', string(digital_twin_version));

    %% ===== TIME SERIES GROUP =====
    fprintf('  Writing time series data...\n');

    % Time vector
    h5create(filename, '/time_series/time', N, 'Datatype', 'double');
    h5write(filename, '/time_series/time', timeVector);

    % Raw sensors (Stream 1)
    for i = 1:SensorDef.Count
        dataset_name = sprintf('/time_series/raw_sensors/%s_%s', ...
            SensorDef.ShortNames{i}, SensorDef.Names{i});
        h5create(filename, dataset_name, N, 'Datatype', 'double');
        h5write(filename, dataset_name, sensors_raw(:, i));

        % Add unit attribute
        h5writeatt(filename, dataset_name, 'unit', SensorDef.Units{i});
        h5writeatt(filename, dataset_name, 'subsystem', SensorDef.Subsystems{i});
    end

    % Nominal predictions (Stream 2)
    for i = 1:SensorDef.Count
        dataset_name = sprintf('/time_series/nominal_predictions/%s_nominal', ...
            SensorDef.ShortNames{i});
        h5create(filename, dataset_name, N, 'Datatype', 'double');
        h5write(filename, dataset_name, sensors_nominal(:, i));

        % Add unit attribute
        h5writeatt(filename, dataset_name, 'unit', SensorDef.Units{i});
    end

    % Physics residuals (Computed)
    for i = 1:SensorDef.Count
        dataset_name = sprintf('/time_series/physics_residuals/%s_residual', ...
            SensorDef.ShortNames{i});
        h5create(filename, dataset_name, N, 'Datatype', 'double');
        h5write(filename, dataset_name, physics_residuals(:, i));

        % Add unit attribute
        h5writeatt(filename, dataset_name, 'unit', SensorDef.Units{i});
    end

    %% ===== LABELS GROUP =====
    fprintf('  Writing labels...\n');

    % Fault class (0 = healthy, 1-32 = fault ID)
    if FaultConfig.NumActiveFaults == 0
        fault_class = 0;
    elseif FaultConfig.NumActiveFaults == 1
        fault_class = find(FaultConfig.ActiveFaults, 1);
    else
        fault_class = 99;  % Multi-fault indicator
    end

    h5create(filename, '/labels/fault_class', 1);
    h5write(filename, '/labels/fault_class', fault_class);

    h5create(filename, '/labels/severity', 1);
    h5write(filename, '/labels/severity', severity_level);

    % Fault onset times for each fault type
    h5create(filename, '/labels/fault_onset_times', 32);
    h5write(filename, '/labels/fault_onset_times', FaultConfig.OnsetTime);

    %% ===== COMPLETION =====
    file_info = dir(filename);
    file_size_MB = file_info.bytes / (1024^2);

    fprintf('  Complete!\n');
    fprintf('  Samples: %d\n', N);
    fprintf('  Duration: %.1f seconds\n', duration_seconds);
    fprintf('  Sample Rate: %.2f Hz\n', sample_rate_Hz);
    fprintf('  File Size: %.2f MB\n', file_size_MB);
    fprintf('============================\n\n');
end
