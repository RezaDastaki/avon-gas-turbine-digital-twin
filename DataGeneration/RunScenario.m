function success = RunScenario(scenario_type, epoch, attempt, varargin)
% RunScenario - Master automation for one scenario/epoch/attempt.
%
% Pipeline (10 steps, one gate): Load -> Sim -> Extract(39ch, pre-roll trimmed) -> Labels ->
% Checkpoint -> MeasurementModel -> Validate -> [QA Layer 1 gate] -> SaveHDF5 -> QualityCheck ->
% Verify -> Cleanup.
%
% CHANGE: sim_duration, the onset range and the stored window are now the
% record-timing redesign -- per-record ambient-dependent pre-roll,
% simulated but discarded, then exactly STORED_SAMPLES=4200 stored samples. A new Step 7.5, QA
% Layer 1 (ComputeLayer1RecordAttributes.m / ValidateGenerationLayer1.m), gates every record
% before it is written -- a failure retries exactly like a Simulink failure. SaveWorkspaceToHDF5
% now takes a record_attrs struct and writes the new /sensors (26,N) + /internal (13,N) schema.
%
% CHANGE: Step 6 is now ApplyMeasurementModel.m (sensor-fault
% gain/offset, bias, noise, quantisation, F37's graded hold), not the bare AddGaussianNoise.m —
% see ApplyMeasurementModel.m. AddGaussianNoise.m is no longer
% called from this pipeline; kept only for any external caller that still wants the earlier
% level-relative noise/bias model.
%
% EARLIER CHANGES:
%   - Signature carries `attempt` (>=1). On failure the driver re-runs the same
%     epoch with attempt+1, which reseeds the MC environment/severity/onset and
%     makes the environment milder, so epoch numbering stays gap-free.
%   - Environment & severity are MC-sampled inside LoadScenarioToWorkspace (no
%     env_id / severity passed in).
%   - 39 channels (34 physical + 5 ambient context); type-driven noise + bias;
%     float32 storage; no ENV folder in the path.
%
% Usage:
%   RunScenario('healthy', epoch, attempt)
%   RunScenario('single',  epoch, attempt, fault_id)
%   RunScenario('dual',    epoch, attempt, combo_id)     % triple/quad likewise
%
% Output: success - true if the file was generated and passed validation.
%
% Date: 2026-07-26

    if nargin < 3 || isempty(attempt), attempt = 1; end

    success = false;
    t0 = tic;
    h5_file = '';
    checkpoint_file = '';

    try
        fprintf('\n=== RunScenario: %s | epoch %d | attempt %d ===\n', ...
            upper(scenario_type), epoch, attempt);

        %% STEP 1: Load scenario (samples env + severity + onset)
        scenario_info     = LoadScenarioToWorkspace(scenario_type, epoch, attempt, varargin{:});
        env               = scenario_info.env;
        fault_ids         = scenario_info.fault_ids;
        severity_levels   = scenario_info.severity_levels;
        fault_start_times = scenario_info.fault_start_times;
        scenario_hash     = scenario_info.scenario_hash;
        combo_id          = scenario_info.combo_id;
        preroll_s         = scenario_info.preroll_s;     % ambient-dependent, unstored
        sim_duration      = scenario_info.sim_duration;   % preroll_s + ScenarioConfig.STORED_SAMPLES
        ambient_trend_amplitude_C = scenario_info.ambient_trend_amplitude_C;   %

        %% STEP 2: Simulink simulation
        % sim_duration is THIS RECORD'S OWN total (pre-roll + stored window),
        % not the flat ScenarioConfig.SIMULATION_DURATION default -- see LoadScenarioToWorkspace.m.
        fprintf('STEP 2/10: Running Simulink (%d s = %d s pre-roll + %d s stored)...\n', ...
            sim_duration, preroll_s, ScenarioConfig.STORED_SAMPLES);
        % warm-start the PT/GG rotor speeds from the measured
        % operating-point library on this record's drawn compressor-inlet temperature, so the
        % pre-roll only has to absorb the residual, not the full cold-IC-to-equilibrium gap.
        % with a within-record ambient trend, the commanded
        % inlet temperature AT t=0 -- where the warm start is actually applied -- is
        % T - ambient_trend_amplitude_C/2, not the record's mean T. Query the library at that
        % t=0 value instead. ambient_trend_amplitude_C is NaN whenever no trend is drawn (the
        % NaN guard below is load-bearing -- T - NaN/2 would poison the query), and a drawn
        % amplitude of exactly 0 leaves the query exactly T, which is what makes B1
        % identity hold by construction. This changes ONLY the query
        % argument -- SetWarmStartInitialConditions.m / GetWarmStartLibrary.m / the .mat library
        % are untouched, and this is NOT the same term as
        % ComputeLayer1RecordAttributes.m's T_eff, which is evaluated at the
        % window midpoint, not at t=0 -- do not conflate the two.
        warm_start_query_C = env.compressor_inlet_temp_C;
        if ~isnan(ambient_trend_amplitude_C)
            warm_start_query_C = warm_start_query_C - ambient_trend_amplitude_C / 2;
        end
        [sim_success, warm_start_info] = RunSimulinkModel(ScenarioConfig.SIMULINK_MODEL, ...
            sim_duration, warm_start_query_C);
        if ~sim_success
            error('Simulation failed (attempt %d).', attempt);
        end

        %% STEP 3: Extract sensors (39 channels), discarding the unstored pre-roll
        fprintf('STEP 3/10: Extracting channels...\n');
        output_dt = ScenarioConfig.GetOutputDt(fault_ids);
        [sensors_full, time_full, sensor_info] = ExtractSensorsFromWorkspace( ...
            output_dt, sim_duration);
        % Keep only tau in [1, STORED_SAMPLES], i.e. absolute time in (preroll_s, preroll_s +
        % STORED_SAMPLES] -- the pre-roll itself is simulated (to absorb the warm-start residual)
        % but never stored.
        keep_idx            = time_full > preroll_s;
        sensors_raw          = sensors_full(keep_idx, :);
        time_vector          = time_full(keep_idx) - preroll_s;   % re-zero so stored tau starts at dt
        % TrueValueTapData is clean simulator state (not run through
        % ApplyMeasurementModel.m), trimmed with the SAME keep_idx as sensors_raw so it lines up
        % sample-for-sample with the stored window, same as every other channel array.
        if isfield(sensor_info, 'TrueValueTapData')
            sensor_info.TrueValueTapData = sensor_info.TrueValueTapData(keep_idx, :);
        end
        sensor_info.Duration    = ScenarioConfig.STORED_SAMPLES;
        sensor_info.num_samples = size(sensors_raw, 1);
        expected_samples = round(ScenarioConfig.STORED_SAMPLES / output_dt);
        if sensor_info.num_samples ~= expected_samples
            error('Stored sample count mismatch after pre-roll trim: got %d, expected %d.', ...
                sensor_info.num_samples, expected_samples);
        end

        % fault_start_times (from Step 1) is in ABSOLUTE simulation time
        % (preroll_s + tau_onset) -- that is correct for building the Simulink multiplier arrays
        % (already done, in LoadScenarioToWorkspace), but every consumer from here on
        % (GenerateFaultLabels below, and the fault_start_times HDF5 attribute) works against
        % time_vector, which is now RE-ZEROED to the stored window's own t=0 (tau=1..4200). Without
        % this re-basing, labels would desync from the stored data by exactly preroll_s -- caught
        % before Step 4, not discovered downstream.
        fault_start_times = fault_start_times - preroll_s;
        fprintf('  extracted %d channels, %d samples\n', sensor_info.num_sensors, sensor_info.num_samples);
        if sensor_info.num_missing > 0
            warning('%d physical sensors missing.', sensor_info.num_missing);
            missing_pct = (sensor_info.num_missing / sensor_info.PhysicalCount) * 100;
            if missing_pct > 25 && ScenarioConfig.STOP_ON_ERROR
                error('Too many missing sensors (%.1f%%).', missing_pct);
            end
        end

        %% STEP 4: Fault labels [N x 42]
        fprintf('STEP 4/10: Generating labels...\n');
        fault_defs = GetFaultDefinitions();
        [fault_label, severity_label] = GenerateFaultLabels( ...
            time_vector, fault_ids, severity_levels, fault_start_times, fault_defs);

        %% STEP 5: Checkpoint (.mat) — keyed on scenario hash/epoch/attempt
        if ScenarioConfig.SAVE_CHECKPOINTS
            checkpoint_dir = ScenarioConfig.CHECKPOINT_DIR;
            if ~exist(checkpoint_dir, 'dir'), mkdir(checkpoint_dir); end
            chk_id = sprintf('%s_H%d_E%04d_A%d', lower(scenario_type), scenario_hash, epoch, attempt);
            checkpoint_file = fullfile(checkpoint_dir, sprintf('%s.mat', chk_id));

            fault_start_times_cp = fault_start_times; %#ok<NASGU>
            fault_ids_cp         = fault_ids;         %#ok<NASGU>
            severity_levels_cp   = severity_levels;   %#ok<NASGU>
            scenario_type_cp     = scenario_type;     %#ok<NASGU>
            env_cp               = env;               %#ok<NASGU>
            save(checkpoint_file, 'sensors_raw', 'time_vector', 'fault_label', ...
                'severity_label', 'fault_start_times_cp', 'fault_ids_cp', ...
                'severity_levels_cp', 'env_cp', 'epoch', 'scenario_type_cp', '-v7.3');
        end

        %% STEP 6: Measurement model — sensor faults, bias, noise, quantisation, hold
        fprintf('STEP 6/10: Applying measurement model...\n');
        % F37's hold now operates DOWNSTREAM of noise/bias/quantisation (holds the last
        % REPORTED sample, per C19 — see ApplyMeasurementModel.m step 6), so S19's noise/bias
        % are no longer zeroed here; the earlier special-case for that is retired.
        noise_seed     = ScenarioConfig.NOISE_BASE_SEED     + scenario_hash + epoch * 41 + attempt * 104729;
        bias_seed      = ScenarioConfig.BIAS_BASE_SEED      + scenario_hash + epoch * 61 + attempt * 100003;
        calib_age_seed = ScenarioConfig.CALIB_AGE_BASE_SEED + scenario_hash + epoch * 71 + attempt * 100477;
        hold_seed      = ScenarioConfig.HOLD_BASE_SEED      + scenario_hash + epoch * 83 + attempt * 100519;
        [sensors_noisy, meas_info] = ApplyMeasurementModel(sensors_raw, time_vector, ...
            fault_ids, severity_levels, fault_start_times, noise_seed, bias_seed, calib_age_seed, hold_seed);
        fprintf('  t_since_cal=%.3f yr', meas_info.t_since_cal);
        if ~isnan(meas_info.f37_frozen_fraction_achieved)
            fprintf('  F37 frozen_fraction target=%.2f achieved=%.4f', ...
                meas_info.f37_frozen_fraction_target, meas_info.f37_frozen_fraction_achieved);
        end
        fprintf('\n');
        % t_since_cal and f37_frozen_fraction_achieved are now threaded to the
        % HDF5 writer as per-record attributes -- see Step 8 below and SaveSensorsToHDF5.m.

        %% STEP 7: Validate physical sensor data
        fprintf('STEP 7/10: Validating...\n');
        [is_valid, failed_cols, reasons] = ValidateSensorData(sensors_noisy, sensors_raw);
        if ~is_valid
            for fc = 1:numel(failed_cols)
                fprintf('  col %d failed: %s\n', failed_cols(fc), reasons{fc});
            end
            error('Sensor validation failed (%d columns).', numel(failed_cols));
        end

        %% STEP 7.5: QA Layer 1 -- the generation-time acceptance gate
        % "QA strategy": a record is written only if it passes every check here. A
        % failure triggers a retry (this error is caught by the same catch block that handles a
        % Simulink failure, which re-runs with attempt+1); nothing is ever silently kept. This is
        % the structural fix for how the draft data's spin-down defect shipped -- NaN/Inf/sample-
        % count checks (Step 7 above) all passed on every collapsed record.
        fprintf('STEP 7.5/10: QA Layer 1...\n');
        % audit: the operating-point attributes are measured on
        % sensors_raw -- the CLEAN, pre-measurement-model array -- because they are ground truth
        % about the simulated plant, not instrument readings. See that function's header for the
        % measured reason (S26's sigma_bias is 15.14 degC against a 1 degC limiter test).
        % the drawn-vs-realised ambient check needs this record's
        % drawn ambient, pre-roll and full simulated duration -- all already local by Step 2/1.
        % the check's second library axis needs the drawn inlet
        % pressure too (env.compressor_inlet_press_kPa) -- the DRAWN value, not a realised one,
        % so a severed inlet-pressure path also fails this check.
        record_attrs = ComputeLayer1RecordAttributes(sensors_raw, time_vector, fault_start_times, ...
            numel(fault_ids), env.compressor_inlet_temp_C, env.compressor_inlet_press_kPa, ...
            preroll_s, sim_duration, ambient_trend_amplitude_C);
        fprintf('  regime=%s  duty_achieved=%.3f MW  limiter_active_fraction=%.3f  controller_saturated=%d (hi=%d lo=%d)  tail_S26=%.1f  ambient_check_residual_C=%.2f\n', ...
            record_attrs.operating_regime, record_attrs.duty_achieved_MW, ...
            record_attrs.limiter_active_fraction, record_attrs.controller_saturated, ...
            record_attrs.controller_saturated_hi, record_attrs.controller_saturated_lo, ...
            mean(sensors_raw(end-179:end, 26)), record_attrs.ambient_check_residual_C);
        % pass the true-value tap data/presence through so Layer 1 can fail a
        % record whose tap is declared present but came through all-NaN.
        if isfield(sensor_info, 'TrueValueTapData')
            tv_data = sensor_info.TrueValueTapData;
            tv_present = sensor_info.TrueValueTapPresent;
        else
            tv_data = []; tv_present = [];
        end
        [layer1_pass, layer1_reasons] = ValidateGenerationLayer1(sensors_noisy, sensors_raw, time_vector, ...
            fault_ids, severity_levels, fault_start_times, fault_label, severity_label, record_attrs, ...
            tv_data, tv_present);
        if ~layer1_pass
            for ri = 1:numel(layer1_reasons)
                fprintf('  Layer 1 FAIL: %s\n', layer1_reasons{ri});
            end
            error('QA Layer 1 failed (%d checks), attempt %d.', numel(layer1_reasons), attempt);
        end

        %% STEP 8: Save to HDF5 (26/13-channel split, chunked+compressed, writer)
        fprintf('STEP 8/10: Saving HDF5...\n');
        record_attrs.preroll_discarded_s          = preroll_s;
        record_attrs.t_since_cal                  = meas_info.t_since_cal;
        record_attrs.f37_frozen_fraction_target   = meas_info.f37_frozen_fraction_target;
        record_attrs.f37_frozen_fraction_achieved = meas_info.f37_frozen_fraction_achieved;
        record_attrs.attempt_used                 = attempt;
        % Seed provenance (criterion S4 -- "any
        % record must be reproducible from its own stored attributes"). scenario_hash is an input
        % to every seed formula in the pipeline (noise, bias, calibration age, hold, environment,
        % onset) and was not being stored, so a user could not regenerate a record from the file
        % alone. Added.
        record_attrs.scenario_hash                = scenario_hash;
        % criterion S4: a user reproducing a record needs to know
        % which initial condition it started from.
        % -- FOR attribute meaning changed, name unchanged: on a
        % record with a drawn ambient trend, warm_start_temp_C now records the library's nearest
        % 2 degC node to the record's t=0 commanded temperature (T - ambient_trend_amplitude_C/2),
        % not to the record's mean drawn compressor_inlet_temp_C. On a record with no trend
        % (ambient_trend_amplitude_C = NaN) the two are identical, so this only matters for
        % Task-9-trended records. Do not rename the attribute acceptance A1/A6.
        record_attrs.warm_start_route             = warm_start_info.route;
        record_attrs.warm_start_temp_C            = warm_start_info.temp_C;
        % the realised within-record ambient trend amplitude.
        record_attrs.ambient_trend_amplitude_C    = ambient_trend_amplitude_C;
        switch lower(scenario_type)
            case 'healthy'
                h5_file = SaveWorkspaceToHDF5(scenario_type, epoch, attempt, env, ...
                    sensors_noisy, time_vector, sensor_info, fault_label, severity_label, fault_start_times, record_attrs);
            case 'single'
                h5_file = SaveWorkspaceToHDF5(scenario_type, epoch, attempt, env, ...
                    sensors_noisy, time_vector, sensor_info, fault_label, severity_label, fault_start_times, record_attrs, ...
                    fault_ids(1), severity_levels(1));
            otherwise  % dual/triple/quad
                h5_file = SaveWorkspaceToHDF5(scenario_type, epoch, attempt, env, ...
                    sensors_noisy, time_vector, sensor_info, fault_label, severity_label, fault_start_times, record_attrs, ...
                    combo_id, severity_levels);
        end
        fprintf('  saved: %s\n', h5_file);

        %% STEP 9: Quality checks (non-fatal)
        if ScenarioConfig.RUN_QUALITY_CHECKS
            try
                QualityCheckHDF5(h5_file);
            catch ME
                fprintf('  quality check warning: %s\n', ME.message);
                if ScenarioConfig.STOP_ON_QUALITY_FAIL, rethrow(ME); end
            end
        end

        %% STEP 10: Verify HDF5 vs checkpoint (non-fatal)
        if ScenarioConfig.RUN_WORKSPACE_VERIFICATION && ~isempty(checkpoint_file)
            try
                VerifyHDF5Data(h5_file, checkpoint_file);
            catch ME
                fprintf('  verification warning: %s\n', ME.message);
                if ScenarioConfig.STOP_ON_QUALITY_FAIL, rethrow(ME); end
            end
        end

        fprintf('=== COMPLETE (%.1f s) ===\n', toc(t0));
        success = true;

    catch ME
        fprintf('=== FAILED (attempt %d): %s ===\n', attempt, ME.message);
        for i = 1:numel(ME.stack)
            fprintf('   %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
        end
        success = false;
        if ScenarioConfig.STOP_ON_ERROR, rethrow(ME); end
    end

    %% CLEANUP (always)
    try
        evalin('base', 'clearvars zz_data_*');
        evalin('base', 'clearvars PDT_* Prss_* GasGen_* PwrTrb_* Temp_*');
        for ci = 1:42
            evalin('base', sprintf('clearvars FAULT_%02d_multiplier', ci));
        end
        evalin('base', 'clearvars ENV_FG_pressure_kPa ENV_FG_temp_C ENV_comp_inlet_temp_C');
        evalin('base', 'clearvars ENV_comp_inlet_press_kPa ENV_ambient_moisture_pct');
        % ENV_comp_inlet_temp_trend (rewire target -- the
        % variable the plant's From Workspace block actually reads) was NOT in this list, which is
        % what let a diagnosis record's trend silently leak into a later same-session RunRTFUnit
        % call (29.15 degC measured). Cleared here independently of RunRTFUnit
        % assigning its own flat trend every cycle -- belt and braces, per spec Edit 2.
        evalin('base', 'clearvars ENV_comp_inlet_temp_trend');
        evalin('base', 'clearvars fault_active fault_severity');
    catch
    end

    % Clear the Simulink Data Inspector run repository. sim streams every run's
    % logged signals into a repository under %TEMP%\MathWorks\...; without this it
    % accumulates one run per file and grows to roughly the whole dataset's size on
    % the C: drive. Clearing after each file caps it at a single run's worth.
    try
        Simulink.sdi.clear;
    catch
        % SDI not present / nothing to clear — non-fatal
    end

end
