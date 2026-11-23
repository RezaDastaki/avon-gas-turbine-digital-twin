function ts = GenerateFaultMultiplierTimeseries(fault_id, severity, config)
% GenerateFaultMultiplierTimeseries - Generates timeseries multiplier for a fault
%
% Creates a MATLAB timeseries object for fault multiplier with support for:
%   - Step faults (instant activation)
%   - Linear ramp faults (gradual degradation)
%   - Oscillating faults (periodic variation)
%
% INPUTS:
%   fault_id  - Fault ID (1-57)
%   severity  - Severity level (0-5): 0=healthy, 1-5=increasing severity
%   config    - Configuration struct with fields:
%               .simulation_duration (seconds)
%               .dt (sampling interval, default 1.0 second)
%               .start_time (fault start time, default from fault def)
%               .ramp_duration (ramp time, default from fault def)
%               .frequency (oscillation frequency, default from fault def)
%
% OUTPUT:
%   ts - MATLAB timeseries object with:
%        - Time vector: [0, dt, 2*dt, ..., simulation_duration]
%        - Data: Multiplier values over time
%        - Linear interpolation
%
% EXAMPLES:
%   % Step fault (F15: Fuel regulator stuck, SEV3, starts at t=600s)
%   config.simulation_duration = 4800;
%   config.dt = 1.0;
%   config.start_time = 600;
%   ts = GenerateFaultMultiplierTimeseries(15, 3, config);
%   % Result: 1.0 for t<600, then constant 0.910 for t>=600
%
%   % Ramp fault (F56: Flowmeter drift, SEV3, ramps over 1200s)
%   config.start_time = 600;
%   config.ramp_duration = 1200;
%   ts = GenerateFaultMultiplierTimeseries(56, 3, config);
%   % Result: 1.0 for t<600, ramps 1.0→0.985 over 600-1800s, then 0.985 after
%
%   % Oscillate fault (F22: Pressure oscillation, SEV3, frequency 0.05 Hz)
%   config.start_time = 600;
%   config.frequency = 0.05;
%   ts = GenerateFaultMultiplierTimeseries(22, 3, config);
%   % Result: 1.0 for t<600, then oscillates ±3% at 0.05 Hz
%
% Date: 2025-12-31

%% Input Validation

if fault_id < 1 || fault_id > 57
    error('GenerateFaultMultiplierTimeseries:InvalidFaultID', ...
          'Fault ID must be between 1 and 57. Got: %d', fault_id);
end

if severity < 0 || severity > 5
    error('GenerateFaultMultiplierTimeseries:InvalidSeverity', ...
          'Severity must be between 0 and 5. Got: %d', severity);
end

if ~isfield(config, 'simulation_duration')
    error('GenerateFaultMultiplierTimeseries:MissingConfig', ...
          'config.simulation_duration is required');
end

%% Get Default Configuration

fault_defs = GetFaultDefinitions();

% Sampling interval (default 1 second)
if ~isfield(config, 'dt')
    config.dt = 1.0;
end

% Start time (default from fault definition, usually 0)
if ~isfield(config, 'start_time')
    config.start_time = fault_defs.DriftStartTime(fault_id);
end

% Ramp duration (default from fault definition)
if ~isfield(config, 'ramp_duration')
    config.ramp_duration = fault_defs.DriftDuration(fault_id);
end

% Oscillation frequency (default from fault definition)
if ~isfield(config, 'frequency')
    config.frequency = fault_defs.OscillationFrequency(fault_id);
end

%% Create Time Vector

time_vector = 0 : config.dt : config.simulation_duration;
num_points = length(time_vector);

%% Get Profile Type and Target Multiplier

profile_type = fault_defs.ProfileType{fault_id};
target_multiplier = GetFaultMultiplier(fault_id, severity);

%% Generate Multiplier Values Based on Profile Type

multiplier_values = ones(1, num_points);  % Start healthy (1.0)

switch profile_type
    case 'step'
        %% Step Profile: Instant fault activation
        % Before start_time: multiplier = 1.0 (healthy)
        % At start_time: instant jump to target_multiplier
        % After start_time: constant at target_multiplier

        fault_start_idx = find(time_vector >= config.start_time, 1, 'first');

        if ~isempty(fault_start_idx)
            multiplier_values(fault_start_idx:end) = target_multiplier;
        end

    case 'linear_ramp'
        %% Linear Ramp Profile: Gradual degradation
        % Before start_time: multiplier = 1.0 (healthy)
        % During ramp: linear transition from 1.0 to target_multiplier
        % After ramp ends: constant at target_multiplier

        fault_start_idx = find(time_vector >= config.start_time, 1, 'first');
        ramp_end_time = config.start_time + config.ramp_duration;
        fault_end_idx = find(time_vector >= ramp_end_time, 1, 'first');

        if ~isempty(fault_start_idx)
            if config.ramp_duration == 0
                % Zero ramp duration = instant step
                multiplier_values(fault_start_idx:end) = target_multiplier;
            else
                % Linear ramp
                if ~isempty(fault_end_idx)
                    % Ramp phase
                    ramp_indices = fault_start_idx : fault_end_idx - 1;
                    num_ramp_points = length(ramp_indices);

                    if num_ramp_points > 1
                        % Linear interpolation from 1.0 to target_multiplier
                        ramp_values = linspace(1.0, target_multiplier, num_ramp_points);
                        multiplier_values(ramp_indices) = ramp_values;
                    end

                    % Constant phase after ramp
                    multiplier_values(fault_end_idx:end) = target_multiplier;
                else
                    % Ramp extends beyond simulation duration
                    ramp_indices = fault_start_idx : num_points;
                    num_ramp_points = length(ramp_indices);

                    if num_ramp_points > 1
                        elapsed_times = time_vector(ramp_indices) - config.start_time;
                        progress = elapsed_times / config.ramp_duration;  % 0 to 1
                        progress = min(progress, 1.0);  % Clamp to 1.0

                        % Linear transition
                        multiplier_values(ramp_indices) = 1.0 + progress .* (target_multiplier - 1.0);
                    end
                end
            end
        end

    case 'oscillate'
        %% Oscillate Profile: Sinusoidal variation
        % Before start_time: multiplier = 1.0 (healthy, no oscillation)
        % After start_time: multiplier = 1.0 + amplitude * sin(2*pi*f*t)
        % Amplitude is based on severity (SEV1=1% SEV5=5%)

        fault_start_idx = find(time_vector >= config.start_time, 1, 'first');

        if ~isempty(fault_start_idx)
            % Calculate amplitude based on severity
            % For oscillations, severity determines oscillation amplitude
            % SEV1 = ±1% SEV2 = ±2% ..., SEV5 = ±5%
            if severity > 0
                amplitude = severity * 0.01;  % 1% per severity level
            else
                amplitude = 0;  % Healthy = no oscillation
            end

            % Generate oscillation
            oscillation_times = time_vector(fault_start_idx:end) - config.start_time;

            if config.frequency > 0
                oscillation = amplitude * sin(2 * pi * config.frequency * oscillation_times);
                multiplier_values(fault_start_idx:end) = 1.0 + oscillation;
            else
                % No frequency specified, treat as constant offset
                multiplier_values(fault_start_idx:end) = 1.0 + amplitude;
            end
        end

    otherwise
        error('GenerateFaultMultiplierTimeseries:InvalidProfile', ...
              'Unknown profile type: %s for fault ID %d', profile_type, fault_id);
end

%% Create Timeseries Object

ts = timeseries(multiplier_values, time_vector);
ts.Name = sprintf('FAULT_%02d_multiplier', fault_id);
ts.TimeInfo.Units = 'seconds';
ts.DataInfo.Units = 'multiplier';

% Set interpolation method to linear (smooth transitions)
ts.DataInfo.Interpolation = tsdata.interpolation('linear');

%% Add Metadata

ts.UserData.fault_id = fault_id;
ts.UserData.fault_name = fault_defs.Names{fault_id};
ts.UserData.severity = severity;
ts.UserData.profile_type = profile_type;
ts.UserData.target_multiplier = target_multiplier;
ts.UserData.start_time = config.start_time;

if strcmp(profile_type, 'linear_ramp')
    ts.UserData.ramp_duration = config.ramp_duration;
elseif strcmp(profile_type, 'oscillate')
    ts.UserData.frequency = config.frequency;
    ts.UserData.amplitude = severity * 0.01;
end

end
