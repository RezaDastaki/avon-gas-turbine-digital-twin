function [success, warm_start_info] = RunSimulinkModel(model_name, duration, warm_start_temp_C)
% RunSimulinkModel - Execute Simulink model simulation
%
% Inputs:
%   model_name - Simulink model name (e.g., 'Core/Models/AvonGasTurbineDgTwin')
%   duration - Simulation duration in seconds (default: 4800)
%   warm_start_temp_C - (optional) the record's drawn compressor-inlet temperature.
%       When supplied, the two rotor-speed integrator initial conditions (PT, GG) are set from
%       the nearest point on the measured operating-point library
%       (Core/Models/P4_operating_point_library.mat, built by
%       validation/P4_20_build_operating_point_library.m) before sim runs -- Route B,
% Omit (or pass []) for the old cold-start
%       behaviour, unchanged for any existing caller.
%
% Outputs:
%   success - true if simulation completed successfully, false otherwise
%   warm_start_info - struct with .route ('measured_ic' or 'cold') and .temp_C (the library grid
%       point actually used, or NaN for 'cold') S4, stored per
%       file as warm_start_route / warm_start_temp_C attributes.
%
% This function:
%   1. Opens the Simulink model (if not already open)
%   2. Sets simulation parameters
%   3. Runs the simulation
%   4. Handles errors gracefully
%   5. Leaves workspace data intact for saving
%
% Date: 2025-12-29
%
% G6 -- FastRestart/StopTime hazard (added
% 2026-10-17). THIS FUNCTION DOES NOT ENABLE FastRestart -- nothing in
% <repo>/DataGeneration/ does, and production must stay that way (the measured cost of not using
% it is 11% 10.99 vs 9.79 simulated-seconds per record). If a FUTURE session enables FastRestart
% here or in any probe/Gate-S script, it MUST NOT vary StopTime within one FastRestart session:
% a session compiled at one StopTime returns a DIFFERENT S24 (GG rotor speed) trajectory when run
% at a different StopTime -- 7.6 rad/s = 14 sigma at t=6000s, measured -- while every other
% channel stays bit-identical. Mechanism: every state with a restoring force returns to the same
% equilibrium however the run is driven; S24 has none (the GG rotor has no speed-dependent load,
%), so it integrates and remembers the compiled StopTime. Either reload the model
% when the duration changes (set_param(mdl,'FastRestart','off'); close_system(mdl,0); load_system)
% or group same-duration runs into their own session -- a script that must mix durations reloads,
% it does not optimise.

    if nargin < 2 || isempty(duration)
        duration = 4800;  % Default: 4800 seconds (80 minutes)
    end
    if nargin < 3
        warm_start_temp_C = [];
    end

    success = false;
    warm_start_info = struct('route', 'cold', 'temp_C', NaN);

    try
        fprintf('\n========================================\n');
        fprintf('  Running Simulink Simulation\n');
        fprintf('========================================\n');
        fprintf('Model: %s\n', model_name);
        fprintf('Duration: %.1f seconds (%.1f minutes)\n', duration, duration/60);
        fprintf('Starting simulation...\n\n');

        % Start timer
        tic;

        %% Check if model exists
        if ~exist([model_name '.slx'], 'file') && ~exist([model_name '.mdl'], 'file')
            error('Simulink model not found: %s', model_name);
        end

        %% Load model (if not already loaded)
        try
            load_system(model_name);
            fprintf('✓ Model loaded\n');
        catch ME
            % Model might already be loaded
            fprintf('Model already loaded or loading failed: %s\n', ME.message);
        end

        %% Set simulation parameters
        % set_param requires the bare loaded model name, not a path (e.g.
        % 'Core/Models/AvonGasTurbineDgTwin' is a valid load_system target
        % but an invalid set_param target -- previously this whole block
        % silently failed on every run via the catch below).
        [~, model_short_name] = fileparts(model_name);
        try
            % Set stop time
            set_param(model_short_name, 'StopTime', num2str(duration));

            % Solver settings (use config if available)
            if ScenarioConfig.USE_FAST_SOLVER
                set_param(model_short_name, 'Solver', 'ode23t');  % Faster for stiff systems
                fprintf('✓ Solver set to ode23t (fast mode)\n');
            else
                % Use default solver (typically ode45 or variable-step)
                fprintf('✓ Using default solver\n');
            end

            % Configure output times to match ScenarioConfig.TIMESERIES_DT sampling
            output_dt = ScenarioConfig.TIMESERIES_DT;
            output_times = 0:output_dt:duration;
            set_param(model_short_name, 'OutputOption', 'SpecifiedOutputTimes');
            set_param(model_short_name, 'OutputTimes', mat2str(output_times));

            % Save options.
            % SaveState is turned OFF — the state array (xout: all continuous
            % states x every timestep) is never used by extraction and is a large
            % memory/temp consumer. Signal logging (logsout / ToWorkspace zz_data_*)
            % and time are unaffected.
            set_param(model_short_name, 'SaveState', 'off');
            set_param(model_short_name, 'SaveOutput', 'on');
            set_param(model_short_name, 'OutputSaveName', 'yout');
            set_param(model_short_name, 'SaveFormat', 'Array');

            % Ensure time is saved
            set_param(model_short_name, 'SaveTime', 'on');
            set_param(model_short_name, 'TimeSaveName', 'time');

            fprintf('✓ Simulation parameters configured\n');
            fprintf('✓ Output times set for %.2g Hz sampling (0:%.2g:%d)\n', 1/output_dt, output_dt, duration);

        catch ME
            warning('Could not set all simulation parameters: %s', ME.message);
            % Continue anyway - model might have fixed parameters
        end

        %% Warm start (Route B): set the PT/GG rotor-speed integrator initial
        % conditions from the measured operating-point library, nearest grid point.
        % removes the physical residual that a cold
        % start leaves above the duty_tracking/temperature_limited boundary (up to 65.6 rad/s at
        % 50 degC) supersedes analytic formula, which
        % returns the cold IC (513.4 rad/s) at every ambient and is wrong above the boundary.
        if ~isempty(warm_start_temp_C)
            try
                lib = SetWarmStartInitialConditions(model_short_name, warm_start_temp_C);
                warm_start_info.route  = 'measured_ic';
                warm_start_info.temp_C = lib.nearest_temp_C;
                fprintf('✓ Warm start applied: nearest grid point %.0f C (drawn %.2f C) -- PT=%.4f rad/s, GG=%.4f rad/s\n', ...
                    lib.nearest_temp_C, warm_start_temp_C, lib.S27_omega_radps, lib.S24_omega_radps);
            catch ME
                warning('RunSimulinkModel:WarmStartFailed', ...
                    'Could not apply warm start (%s); proceeding cold.', ME.message);
                warm_start_info = struct('route', 'cold', 'temp_C', NaN);
            end
        end

        %% Run simulation
        fprintf('\nRunning simulation (this may take a while)...\n');

        % Use sim function for programmatic execution
        simOut = sim(model_name, 'StopTime', num2str(duration));

        elapsed = toc;

        fprintf('\n✓ Simulation completed successfully!\n');
        fprintf('Elapsed time: %.1f seconds (%.1f minutes)\n', elapsed, elapsed/60);
        fprintf('Real-time factor: %.2fx\n', duration / elapsed);

        %% Extract logged signals from SimulationOutput and save to base workspace
        fprintf('Extracting logged signals to workspace...\n');

        extracted_count = 0;

        % SimulationOutput objects can have different structures
        % Try multiple methods to extract data
        if isobject(simOut)
            try
                % Method 1: Check for logsout (most common for logged signals)
                if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
                    fprintf('  Found logsout with %d signals\n', simOut.logsout.numElements);

                    % Extract each element from logsout
                    for i = 1:simOut.logsout.numElements
                        element = simOut.logsout.getElement(i);

                        % Get signal name and data
                        signal_name = element.Name;
                        signal_data = element.Values;

                        % Convert timeseries to array if needed
                        if isa(signal_data, 'timeseries')
                            signal_data = signal_data.Data;
                        end

                        % Save to base workspace
                        assignin('base', signal_name, signal_data);
                        extracted_count = extracted_count + 1;
                    end
                end

                % Method 2: Check for yout (model outputs)
                if isprop(simOut, 'yout') && ~isempty(simOut.yout)
                    assignin('base', 'yout', simOut.yout);
                    extracted_count = extracted_count + 1;
                end

                % Method 3: Check for time
                if isprop(simOut, 'time') && ~isempty(simOut.time)
                    assignin('base', 'time', simOut.time);
                    extracted_count = extracted_count + 1;
                elseif isprop(simOut, 'tout') && ~isempty(simOut.tout)
                    assignin('base', 'time', simOut.tout);
                    extracted_count = extracted_count + 1;
                end

                % Method 4: Try to get all properties and extract them
                props = properties(simOut);
                for i = 1:length(props)
                    prop_name = props{i};

                    % Skip metadata and already processed fields
                    if strcmp(prop_name, 'SimulationMetadata') || ...
                       strcmp(prop_name, 'ErrorMessage') || ...
                       strcmp(prop_name, 'logsout')
                        continue;
                    end

                    try
                        prop_data = simOut.(prop_name);

                        % Only save if it's data (not empty, not metadata)
                        if ~isempty(prop_data) && ~ischar(prop_data)
                            assignin('base', prop_name, prop_data);
                            extracted_count = extracted_count + 1;
                        end
                    catch
                        % Skip properties that can't be accessed
                    end
                end

                fprintf('✓ Extracted %d signals/outputs to workspace\n', extracted_count);

            catch ME
                fprintf('⚠ Warning: Could not extract all signals: %s\n', ME.message);
                fprintf('  Simulation data may be in ''ans'' variable\n');
            end
        end

        fprintf('========================================\n\n');

        success = true;

    catch ME
        elapsed = toc;

        fprintf('\n✗ Simulation FAILED!\n');
        fprintf('Error: %s\n', ME.message);
        fprintf('Elapsed time before failure: %.1f seconds\n', elapsed);
        fprintf('========================================\n\n');

        % Display stack trace for debugging
        fprintf('Stack trace:\n');
        for i = 1:length(ME.stack)
            fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
        fprintf('\n');

        success = false;

        % Rethrow if stop on error is enabled
        if ScenarioConfig.STOP_ON_ERROR
            rethrow(ME);
        end
    end

end
