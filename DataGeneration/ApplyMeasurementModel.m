function [sensors_final, meas_info, sensors_after_fault] = ApplyMeasurementModel(sensors_raw, time_vector, ...
    fault_ids, severity_levels, fault_start_times, noise_seed, bias_seed, calib_age_seed, hold_seed)
% ApplyMeasurementModel - The measurement layer. Replaces the bare AddGaussianNoise.m call in RunScenario.m Step 6. Applies, in the
% prescribed order, to the extracted [N x 39] channel matrix:
%
%   1. true simulated value           (sensors_raw, as extracted)
%   2. sensor-fault gain / offset     F33-F36, F38-F41 (transducer-level errors; F37 at step 6)
%   3. calibration bias               per record, per channel
%   4. white measurement noise        per sample
%   5. ADC quantisation                round to the channel's LSB (span/2^quant_bits)
%   6. hold / freeze                  F37 — a signal-path fault downstream of the ADC
%
% All nine sensor faults (F33-F41) move here from Simulink proved every
% one of them is logger_only (zero plant/controller effect at any severity), so applying them
% here instead is EQUIVALENT, not approximate Sec[Task2] for the per-fault
% equivalence measurement. F33/F34/F38/F39/F41 keep the SAME multiplicative-gain operation and
% ramp/step shape as before (reusing GenerateFaultMultiplierArray.m exactly, so the timing code
% is not duplicated); F35/F36/F40 CHANGE to additive per the severity redesign (an additive
% offset cannot be expressed on the old Simulink Product-block path, which is what makes this
% refactor necessary, not merely cosmetic).
%
% Inputs:
%   sensors_raw        [N x 39] double  — ExtractSensorsFromWorkspace.m output, unmodified
%   time_vector        [N x 1]  double  — matching time axis
%   fault_ids          [1 x k]  double  — active fault IDs for this scenario (may be empty)
%   severity_levels    [1 x k]  double  — parallel to fault_ids, 1-5
%   fault_start_times  [1 x k]  double  — parallel to fault_ids, onset time (s)
%   noise_seed, bias_seed, calib_age_seed, hold_seed - integer RNG seeds (ScenarioConfig's
%       (scenario_hash, epoch, attempt)-keyed convention; see ScenarioConfig.m's comment block)
%
% Outputs:
%   sensors_final [N x 39] double — fully processed channels, ready for ValidateSensorData/HDF5
%   meas_info     struct — what was actually drawn/applied this record (for attributes/QA):
%       .t_since_cal           scalar, the record's own U(0,1) calibration-age draw
%       .bias_vec              [1x39] the realised per-channel bias offset
%       .sensor_fault_applied  containers.Map fault_id -> struct(channel, kind, magnitude)
%       .f37_frozen_fraction_target / .f37_frozen_fraction_achieved (NaN if F37 inactive)
%   sensors_after_fault [N x 39] double — post step 2 (sensor-fault gain/offset), pre steps 3-6
%       (bias/noise/quant/hold). Exposed so a caller (e.g. equivalence-proof script)
%       can compare the deterministic fault effect directly without re-implementing step 2.
%

    [N, C] = size(sensors_raw);
    if C ~= 39
        error('ApplyMeasurementModel:BadInput', 'Expected 39 channels, got %d.', C);
    end
    DUR = time_vector(end);
    DT  = time_vector(2) - time_vector(1);

    nm = GetSensorNoiseModel();
    fault_defs = GetFaultDefinitions();

    sensors = sensors_raw;  % step 1: true value, start from here

    % ===================== STEP 2: sensor-fault gain / offset =====================
    % Channel map: fault_id -> target column. S19=19, S24=24, S27=27, S04=4.
    GAIN_FAULTS   = [33, 34, 38, 39, 41];   % multiplicative, same shape as before
    ADD_SCALED    = 40;                      % additive, magnitude = Sev1/Sev5Deviation delta * ref reading
    ADD_FIXEDPCT  = [35, 36];                % additive, companion-paper 1/2/3/4/5% of ref reading (NOT geometric)
    TARGET_COL = containers.Map({33,34,35,36,38,39,40,41}, {19,19,19,19,24,27,4,4});

    sensor_fault_applied = containers.Map('KeyType', 'double', 'ValueType', 'any');

    for k = 1:numel(fault_ids)
        fid = fault_ids(k);
        if ~isKey(TARGET_COL, fid); continue; end
        col = TARGET_COL(fid);
        sev = severity_levels(k);
        t0  = fault_start_times(k);

        if ismember(fid, GAIN_FAULTS)
            cfg = struct('simulation_duration', DUR, 'dt', DT, 'start_time', t0);
            marr = GenerateFaultMultiplierArray(fid, sev, cfg);   % [Nm x 2]: [t, multiplier]
            mult_on_grid = interp1(marr(:,1), marr(:,2), time_vector, 'linear', 'extrap');
            if col == 19
                % F33/F34: the Simulink cascade on S19 multiplies the ABSOLUTE (Kelvin) value,
                % not the degC reading directly -- confirmed by direct measurement, not assumed
                % (P3_04_diagnose_ramp_discrepancy.m: old-path SEV5 = 1185.06525 exactly equals
                % (1115.6264+273.15)*1.05-273.15, not 1115.6264*1.05=1171.408 -- a pre-existing
                % Kelvin-basis conversion block on this cascade, the same one noted in
                % ExtractSensorsFromWorkspace.m's S19_true comment). Reproduced here exactly so
                % F33/F34 keep their already-measured Sev1Deviation/Sev5Deviation calibration.
                sensors(:, col) = (sensors(:, col) + 273.15) .* mult_on_grid - 273.15;
            else
                sensors(:, col) = sensors(:, col) .* mult_on_grid;
            end
            sensor_fault_applied(fid) = struct('channel', col, 'kind', 'gain', ...
                'target_multiplier', GetFaultMultiplier(fid, sev));

        elseif fid == ADD_SCALED
            cfg = struct('simulation_duration', DUR, 'dt', DT, 'start_time', t0);
            marr = GenerateFaultMultiplierArray(fid, sev, cfg);
            mult_on_grid = interp1(marr(:,1), marr(:,2), time_vector, 'linear', 'extrap');
            deviation = mult_on_grid - 1.0;              % 0 pre-onset, +/-delta post-onset
            ref_reading = nm.reference_reading(col);
            offset = deviation * ref_reading;
            sensors(:, col) = sensors(:, col) + offset;
            sensor_fault_applied(fid) = struct('channel', col, 'kind', 'additive_scaled', ...
                'magnitude_at_sev', deviation(end) * ref_reading);

        elseif ismember(fid, ADD_FIXEDPCT)
            % companion paper Table 4's own band for GG temp sensor bias --
            % +/-1/2/3/4/5% of the nominal S19 reading at the reference condition, converted
            % ONCE into a fixed degC offset (linear in severity, NOT the geometric Sev1/Sev5Deviation
            % progression every other fault uses -- paper-anchored, not invented).
            ref_reading = nm.reference_reading(col);
            magnitude = sev * 0.01 * ref_reading;
            if fid == 36; magnitude = -magnitude; end   % F36 = GG temp bias (-)
            step_shape = double(time_vector >= t0);
            sensors(:, col) = sensors(:, col) + magnitude * step_shape;
            sensor_fault_applied(fid) = struct('channel', col, 'kind', 'additive_fixed_pct', ...
                'magnitude_degC', magnitude);
        end
    end

    sensors_after_fault = sensors;

    % ===================== STEP 3: calibration bias =====================
    rng(calib_age_seed, 'twister');
    t_since_cal = rand();   % ~U(0,1) years, ONE draw per record, shared across all 39 channels
    sigma_bias_record = sqrt(nm.sigma_noise.^2 + (nm.drift_rate_abs * t_since_cal).^2);

    rng(bias_seed, 'twister');
    bias_vec = sigma_bias_record .* randn(1, C);

    sensors = sensors + bias_vec;   % broadcast per-channel constant over all N samples

    % ===================== STEP 4: white measurement noise =====================
    rng(noise_seed, 'twister');
    noise_mat = nm.sigma_noise .* randn(N, C);
    sensors = sensors + noise_mat;

    % ===================== STEP 5: ADC quantisation =====================
    q = (nm.span_max - nm.span_min) ./ (2 .^ nm.quant_bits);
    for c = 1:C
        if q(c) > 0
            sensors(:, c) = round(sensors(:, c) / q(c)) * q(c);
        end
    end

    % ===================== STEP 6: hold / freeze (F37) =====================
    f37_target = NaN; f37_achieved = NaN;
    f37_idx = find(fault_ids == 37, 1);
    if ~isempty(f37_idx)
        sev = severity_levels(f37_idx);
        t0  = fault_start_times(f37_idx);
        FROZEN_FRACTION = [0.10, 0.30, 0.55, 0.80, 1.00];
        f37_target = FROZEN_FRACTION(sev);

        onset_idx = find(time_vector >= t0, 1, 'first');
        if ~isempty(onset_idx)
            n_post = N - onset_idx + 1;
            target_held_count = round(f37_target * n_post);

            CHUNK_LEN = 60;   % samples (1 minute at 1 Hz) — matches the benchmark window length
            n_chunks = ceil(n_post / CHUNK_LEN);
            rng(hold_seed, 'twister');
            chunk_order = randperm(n_chunks);

            is_held = false(n_post, 1);
            held_so_far = 0;
            for ci = chunk_order
                c_start = (ci - 1) * CHUNK_LEN + 1;
                c_end   = min(ci * CHUNK_LEN, n_post);
                c_len   = c_end - c_start + 1;
                remaining = target_held_count - held_so_far;
                if remaining <= 0
                    break;
                elseif remaining >= c_len
                    is_held(c_start:c_end) = true;
                    held_so_far = held_so_far + c_len;
                else
                    % partial chunk: hold the first `remaining` samples of this chunk only,
                    % so the achieved total lands exactly on target (within one sample)
                    is_held(c_start:c_start + remaining - 1) = true;
                    held_so_far = held_so_far + remaining;
                    break;
                end
            end
            f37_achieved = held_so_far / n_post;

            col = 19;  % S19
            last_val = sensors(max(onset_idx - 1, 1), col);
            for n = 1:n_post
                idx = onset_idx + n - 1;
                if is_held(n)
                    sensors(idx, col) = last_val;
                else
                    last_val = sensors(idx, col);
                end
            end
        end
    end

    sensors_final = sensors;

    meas_info = struct();
    meas_info.t_since_cal = t_since_cal;
    meas_info.bias_vec = bias_vec;
    meas_info.sensor_fault_applied = sensor_fault_applied;
    meas_info.f37_frozen_fraction_target = f37_target;
    meas_info.f37_frozen_fraction_achieved = f37_achieved;
end
