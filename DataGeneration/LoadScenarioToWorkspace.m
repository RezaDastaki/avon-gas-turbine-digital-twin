function scenario_info = LoadScenarioToWorkspace(scenario_type, epoch, attempt, varargin)
% LoadScenarioToWorkspace - Load scenario parameters to workspace for Simulink
%
% Environment and severity are Monte-Carlo sampled PER EPOCH (mixed
% within one folder per fault/combo). This function:
%   - samples the ambient/operating condition (SampleEnvironmentMC) and sets
%     the ENV_* base-workspace variables,
%   - samples severity (stratified for single faults; independent MC for
%     multi-fault),
%   - samples a per-fault activation time,
%   - builds the FAULT_NN_multiplier injection arrays.
%
% The `attempt` counter (>=1) reseeds every per-epoch draw so a failed epoch is
% re-run with DIFFERENT conditions under the SAME epoch number (see the driver
% retry loop). Higher attempts also make SampleEnvironmentMC milder.
% NOTE: single-fault severity is deliberately attempt-INDEPENDENT (the label is
% kept stable; only the collapse-driving environment/onset change on retry).
%
% Inputs:
%   scenario_type - 'healthy', 'single', 'dual', 'triple', or 'quad'
%   epoch         - epoch number (>=1)
%   attempt       - attempt number (>=1; increment on failure)
%   varargin:
%       'healthy' : (none)
%       'single'  : fault_id
%       'dual'    : combo_id
%       'triple'  : combo_id
%       'quad'    : combo_id
%
% Output:
%   scenario_info - struct with scenario metadata (env, fault_ids,
%                   severity_levels, fault_start_times, epoch, attempt,
%                   scenario_hash, env_id=0)
%
% Date: 2026-07-26 (per-epoch MC environment + severity; attempt retries)

    if nargin < 3 || isempty(attempt), attempt = 1; end

    %% Resolve fault IDs from scenario type
    combo_id = [];
    switch lower(scenario_type)
        case 'healthy'
            fault_ids = [];
        case 'single'
            if isempty(varargin), error('single requires fault_id'); end
            fault_ids = varargin{1};
        case 'dual'
            if isempty(varargin), error('dual requires combo_id'); end
            combo_id = varargin{1};
            fdefs = GetFaultDefinitions();
            fault_ids = fdefs.DualCombos(combo_id, :);
        case 'triple'
            if isempty(varargin), error('triple requires combo_id'); end
            combo_id = varargin{1};
            fdefs = GetFaultDefinitions();
            fault_ids = fdefs.TripleCombos(combo_id, :);
        case 'quad'
            if isempty(varargin), error('quad requires combo_id'); end
            combo_id = varargin{1};
            fdefs = GetFaultDefinitions();
            fault_ids = fdefs.QuadCombos(combo_id, :);
        otherwise
            error('scenario_type must be: healthy, single, dual, triple, or quad');
    end

    scenario_hash = ScenarioConfig.ScenarioHash(scenario_type, fault_ids);

    %% Sample severities (per epoch)
    switch lower(scenario_type)
        case 'healthy'
            severity_levels = [];
        case 'single'
            severity_levels = ScenarioConfig.SampleSingleFaultSeverity(fault_ids(1), epoch);
        otherwise  % dual/triple/quad
            severity_levels = ScenarioConfig.SampleMultiFaultSeveritiesV2( ...
                scenario_hash, epoch, attempt, numel(fault_ids));
    end

    %% Sample environment (continuous, solver-safe, milder on retries)
    env = SampleEnvironmentMC(scenario_hash, epoch, attempt);

    %% Clear only STALE simulation outputs from any previous run (blacklist).
    % NB: do NOT use a "clearvars -except <whitelist>" here — the drivers run in
    % the base workspace and rely on their own loop variables (combo_ids,
    % fault_ids, epochs, retry_max, idx, ...); a whitelist clear would wipe them.
    fprintf('Clearing stale simulation variables...\n');
    evalin('base', 'clearvars zz_data_*');
    evalin('base', 'clearvars PDT_* Prss_* GasGen_* PwrTrb_* Temp_*');
    evalin('base', 'clearvars fault_active fault_severity');
    for ci = 1:42
        evalin('base', sprintf('clearvars FAULT_%02d_multiplier', ci));
    end

    %% Set environmental variables in base workspace (Constant blocks)
    fprintf('Loading MC-sampled environment (attempt %d, mildness %.2f)...\n', ...
        attempt, env.mildness);
    assignin('base', 'ENV_FG_pressure_kPa',    env.FG_pressure_kPa);
    assignin('base', 'ENV_FG_temp_C',          env.FG_temp_C);
    assignin('base', 'ENV_comp_inlet_temp_C',  env.compressor_inlet_temp_C);
    assignin('base', 'ENV_comp_inlet_press_kPa', env.compressor_inlet_press_kPa);
    assignin('base', 'ENV_ambient_moisture_pct', env.ambient_moisture_percent);

    % Fixed duty command (no DRAWN duty axis anywhere in the
    % release; ScenarioConfig.DUTY_CMD_MW is a second FIXED setpoint for the turndown sub-family,
    % never sampled per record). AvonGasTurbineDgTwin_fixed's
    % 'SP_Power_Cmd' block was rewired by P1b_02_fix_duty_command.m to read this workspace
    % variable; nothing set it here before this fix, so the fixed model's StopTime=0 error
    % ("Invalid setting ... for parameter 'Value'") would have hit every real production run the
    % moment ScenarioConfig.SIMULINK_MODEL was pointed at the fixed model --
    % found by this session's fresh-MATLAB-session RunScenario verification, fixed
    % here rather than left for to catch, since the fix is the literal, already-decided
    % constant and nothing else.
    assignin('base', 'SP_POWER_CMD', ScenarioConfig.DUTY_CMD_MW());

    %% Simulation configuration
    % sim_duration is PER-RECORD, not the flat config
    % default -- it depends on the pre-roll, which depends on this record's own drawn ambient
    % (env.compressor_inlet_temp_C, sampled above). GetSimulationDuration/GetPrerollSeconds
    % encapsulate the 1800s/3600s-near-the-regime-boundary rule.
    config_obj   = ScenarioConfig.GetActiveConfig();
    dt           = config_obj.timeseries_dt;
    preroll_s    = ScenarioConfig.GetPrerollSeconds(env.compressor_inlet_temp_C);
    sim_duration = ScenarioConfig.GetSimulationDuration(env.compressor_inlet_temp_C);

    % RE-ATTEMPT, 2026-10-20. The first
    % attempt's B1 failure is WITHDRAWN: it was
    % severed wire, not model pathology. The model was repaired and the
    % rewire re-applied feeding BOTH original destinations
    % (P4_57_add_ambient_trend_input_both_branches.m). The within-record linear trend is
    % now drawn and fed to the model's From Workspace block on every record.
    %
    % TEST-ONLY HOOK (global TASK9_FORCE_DELTA_T_C): used ONLY by the B1 identity-regression test
    % harness to force DeltaT=0 deterministically -- GetAmbientTrendAmplitude's own
    % draw is U(0.5,2.0) signed and can never land on exactly 0, so B1 cannot be exercised through
    % the real random draw. Unset (empty) on every production call; grep
    % TASK9_FORCE_DELTA_T_C to find the one test script that sets it. When unset, this branch is
    % byte-for-byte what GetAmbientTrendAmplitude alone would have produced.
    global TASK9_FORCE_DELTA_T_C
    if ~isempty(TASK9_FORCE_DELTA_T_C)
        ambient_trend_amplitude_C = TASK9_FORCE_DELTA_T_C;
        t_trend = (0:dt:sim_duration)';
        trend_timeseries = [t_trend, env.compressor_inlet_temp_C + ...
            ambient_trend_amplitude_C * (t_trend / sim_duration - 0.5)];
    else
        [ambient_trend_amplitude_C, trend_timeseries] = GetAmbientTrendAmplitude( ...
            scenario_hash, epoch, attempt, env.compressor_inlet_temp_C, sim_duration, dt);
    end
    assignin('base', 'ENV_comp_inlet_temp_trend', trend_timeseries);

    %% Fault activation arrays (42 unified faults)
    fault_active   = zeros(1, 42);
    fault_severity = zeros(1, 42);
    if ~isempty(fault_ids)
        for i = 1:numel(fault_ids)
            fault_active(fault_ids(i))   = 1;
            fault_severity(fault_ids(i)) = severity_levels(i);
        end
    end
    assignin('base', 'fault_active', fault_active);
    assignin('base', 'fault_severity', fault_severity);

    %% Per-fault epoch/attempt-specific activation times
    % the draw below is now two steps.
    % tau_onset is STORED-WINDOW-RELATIVE (how many samples into the 4200-sample stored record the
    % fault activates), drawn from the renamed FAULT_START_TAU_MIN/MAX bounds using the inclusive
    % two-arg randi form (no off-by-one). t_start, which is what the Simulink multiplier array and
    % every downstream consumer actually use, is tau_onset PLUS this record's own pre-roll -- the
    % absolute simulation-time onset. Multi-fault records draw each fault's tau independently (as
    % before), but all share the one record-level pre-roll.
    tau_min          = ScenarioConfig.FAULT_START_TAU_MIN;
    tau_max          = ScenarioConfig.FAULT_START_TAU_MAX;
    fault_start_seed = ScenarioConfig.FAULT_START_SEED;

    fault_start_times_out = zeros(1, numel(fault_ids));
    fault_start_map = zeros(1, 42);
    if ~isempty(fault_ids)
        for k = 1:numel(fault_ids)
            fid = fault_ids(k);
            rng(fault_start_seed + fid * 997 + epoch * 37 + attempt * 7919, 'twister');
            tau_onset = randi([tau_min, tau_max]);
            t_start   = preroll_s + tau_onset;
            fault_start_times_out(k) = t_start;
            fault_start_map(fid)     = t_start;
        end
    end

    %% Generate FAULT_NN_multiplier arrays for all 42 faults
    fprintf('Generating fault multiplier arrays...\n');
    array_config = struct();
    array_config.simulation_duration = sim_duration;
    array_config.dt = dt;

    % (measurement layer): F33-F41, the nine sensor faults, move OUT of Simulink
    % entirely proved every one is logger_only (zero plant/controller
    % effect at any severity), and the equivalence proof confirms applying them
    % in ApplyMeasurementModel.m instead reproduces the same behaviour (F33/34/38/39/41) or the
    % deliberately-redesigned one (F35/36/40's new additive bands; F37's new graded hold). Their
    % FAULT_NN_multiplier is therefore ALWAYS the inert constant-1 array below, regardless of
    % fault_active(i) -- fault_active/fault_severity (used for labels, below) are UNCHANGED, so
    % the dataset's fault_label/severity_label still show these faults as present; only the
    % Simulink injection is disabled.
    SENSOR_FAULTS_MOVED_OUT = 33:41;

    for i = 1:42
        if ismember(i, SENSOR_FAULTS_MOVED_OUT)
            array_config.start_time    = 0;
            array_config.ramp_duration = ScenarioConfig.GetFaultRampDuration(i);
            array_config.frequency     = ScenarioConfig.GetFaultFrequency(i);
            mult_array = GenerateFaultMultiplierArray(i, 0, array_config);
        elseif fault_active(i) == 1
            severity = fault_severity(i);
            array_config.start_time    = fault_start_map(i);
            array_config.ramp_duration = ScenarioConfig.GetFaultRampDuration(i);
            array_config.frequency     = ScenarioConfig.GetFaultFrequency(i);
            mult_array = GenerateFaultMultiplierArray(i, severity, array_config);
        else
            array_config.start_time    = 0;
            array_config.ramp_duration = ScenarioConfig.GetFaultRampDuration(i);
            array_config.frequency     = ScenarioConfig.GetFaultFrequency(i);
            mult_array = GenerateFaultMultiplierArray(i, 0, array_config);
        end
        assignin('base', sprintf('FAULT_%02d_multiplier', i), mult_array);
    end

    %% Scenario info
    scenario_info = struct();
    scenario_info.scenario_type    = scenario_type;
    scenario_info.env_id           = 0;            % 0 => MC-sampled (no fixed env)
    scenario_info.env              = env;
    scenario_info.preroll_s        = preroll_s;     % ambient-dependent, unstored
    scenario_info.sim_duration     = sim_duration;  % preroll_s + ScenarioConfig.STORED_SAMPLES
    scenario_info.combo_id         = combo_id;
    scenario_info.fault_ids        = fault_ids;
    scenario_info.severity_levels  = severity_levels;
    scenario_info.fault_start_times = fault_start_times_out;
    scenario_info.epoch            = epoch;
    scenario_info.attempt          = attempt;
    scenario_info.scenario_hash    = scenario_hash;
    scenario_info.ambient_trend_amplitude_C = ambient_trend_amplitude_C;  % C24: realised draw

    %% Summary
    fprintf('\n--- Scenario Loaded ---\n');
    fprintf('Type: %s | Epoch: %d | Attempt: %d\n', upper(scenario_type), epoch, attempt);
    fprintf('Ambient: FGp=%.0f kPa, FGt=%.1f C, inT=%.1f C, inP=%.1f kPa, RH=%.0f%%\n', ...
        env.FG_pressure_kPa, env.FG_temp_C, env.compressor_inlet_temp_C, ...
        env.compressor_inlet_press_kPa, env.ambient_moisture_percent);
    if ~isempty(fault_ids)
        for i = 1:numel(fault_ids)
            fprintf('  F%02d SEV%d @ t=%.0fs\n', fault_ids(i), severity_levels(i), fault_start_times_out(i));
        end
    else
        fprintf('  Faults: None (Healthy)\n');
    end
    fprintf('----------------------------\n\n');

end
