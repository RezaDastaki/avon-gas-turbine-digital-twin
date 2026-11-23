function multiplier_array = GenerateFaultMultiplierArray(fault_id, severity, config)
% GenerateFaultMultiplierArray - Generates array multiplier for a fault
%
% Creates a simple MATLAB array (Nx1) for fault multiplier with support for:
%   - Step faults (instant activation)
%   - Linear ramp faults (gradual degradation)
%   - Oscillating faults (periodic variation)
%   - Freeze faults (F37 only: multiplier → 0.0 to trigger Switch+Memory pattern)
%
% SIMPLER ALTERNATIVE TO TIMESERIES:
%   - Returns plain array (7445×1 or 4801×1 depending on config)
%   - Works reliably with From Workspace blocks in Simulink
%   - Avoids 3D dimension issues (no 1×1×N problems)
%   - Array index corresponds to simulation sample number
%
% INPUTS:
%   fault_id  - Fault ID (1-42)
%   severity  - Severity level (0-5): 0=healthy, 1-5=increasing severity
%   config    - Configuration struct with fields:
%               .simulation_duration (seconds)
%               .dt (sampling interval, default 1.0 second)
%               .start_time (fault start time, default from fault def)
%               .ramp_duration (ramp time, default from fault def)
%               .frequency (oscillation frequency, default from fault def)
%
% OUTPUT:
%   multiplier_array - [N × 2] matrix where N = simulation_duration/dt + 1
%                      Column 1: Time values [0, dt, 2*dt, ..., simulation_duration]
%                      Column 2: Multiplier values at each time step
%                      (Format required by Simulink From Workspace blocks)
%
% EXAMPLES:
%   % Step fault (F15: Fuel regulator stuck, SEV3, starts at t=0s)
%   config.simulation_duration = 4800;
%   config.dt = 1.0;
%   config.start_time = 0;
%   mult = GenerateFaultMultiplierArray(15, 3, config);
%   % Result: 4801×2 matrix
%   %   Column 1: [0; 1; 2; ...; 4800] (time)
%   %   Column 2: [0.910; 0.910; ...; 0.910] (multiplier)
%
%   % Ramp fault (F56: Flowmeter drift, SEV3, ramps over 1200s)
%   config.start_time = 600;
%   config.ramp_duration = 1200;
%   mult = GenerateFaultMultiplierArray(56, 3, config);
%   % Result: 4801×2 matrix, col2 = 1.0 for t<600, ramps 1.0→0.985, then 0.985
%
% Date: 2025-12-31

%% Input Validation

if fault_id < 1 || fault_id > 42
    error('GenerateFaultMultiplierArray:InvalidFaultID', ...
          'Fault ID must be between 1 and 42. Got: %d', fault_id);
end

if severity < 0 || severity > 5
    error('GenerateFaultMultiplierArray:InvalidSeverity', ...
          'Severity must be between 0 and 5. Got: %d', severity);
end

if ~isfield(config, 'simulation_duration')
    error('GenerateFaultMultiplierArray:MissingConfig', ...
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

multiplier_values = ones(num_points, 1);  % Start healthy (1.0) - COLUMN VECTOR

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
                        multiplier_values(ramp_indices) = ramp_values(:);  % Force column
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
                        multiplier_values(ramp_indices) = 1.0 + progress(:) .* (target_multiplier - 1.0);
                    end
                end
            end
        end

    case 'oscillate'
        %% Oscillate Profile: Sinusoidal variation
        % Before start_time: multiplier = 1.0 (healthy, no oscillation)
        % After start_time: multiplier = 1.0 + (target-1) * sin(2*pi*f*(t-t_start))
        % Amplitude is (target_multiplier - 1.0), which is negative for degradation faults.
        % Result: swings symmetrically between target_multiplier and (2 - target_multiplier).

        fault_start_idx = find(time_vector >= config.start_time, 1, 'first');

        if ~isempty(fault_start_idx)
            oscillation_times = time_vector(fault_start_idx:end) - config.start_time;
            amplitude = target_multiplier - 1.0;  % negative for degradation, positive for enhancement

            if config.frequency > 0
                oscillation = amplitude * sin(2 * pi * config.frequency * oscillation_times);
                multiplier_values(fault_start_idx:end) = 1.0 + oscillation(:);  % Force column
            else
                % No frequency specified, treat as constant offset at target
                multiplier_values(fault_start_idx:end) = target_multiplier;
            end
        end

    case 'freeze'
        %% Freeze Profile: F37 GG temp sensor freeze (Switch+Memory Simulink pattern)
        % Before start_time: multiplier = 1.0  (Switch passes live signal)
        % At and after start_time: multiplier = 0.0  (< 0.5 threshold activates Memory block)
        % severity=0 (inactive/healthy): multiplier stays 1.0 throughout — no freeze
        % severity_level > 0: any active severity triggers freeze identically

        if target_multiplier < 0.5  % Only freeze when fault is actually active
            fault_start_idx = find(time_vector >= config.start_time, 1, 'first');
            if ~isempty(fault_start_idx)
                multiplier_values(fault_start_idx:end) = 0.0;
            end
        end
        % target_multiplier >= 0.5 (severity=0, healthy): multiplier_values stays at 1.0

    otherwise
        error('GenerateFaultMultiplierArray:InvalidProfile', ...
              'Unknown profile type: %s for fault ID %d', profile_type, fault_id);
end

%% Return [Time, Data] Matrix for Simulink From Workspace

% Simulink From Workspace blocks expect [N×2] matrix:
% Column 1: Time values
% Column 2: Data values

time_column = time_vector(:);  % Ensure column vector
data_column = multiplier_values(:);  % Ensure column vector

multiplier_array = [time_column, data_column];  % [N×2] matrix

end
