function success = RunRTFUnit(fault_id, unit_id, progress_fcn)
% RunRTFUnit - generate ONE complete run-to-failure unit, end to end, for
% the mechanism whose diagnosis fault_id is given. Mirrors RunScenario.m's structure (load -> sim
% -> extract -> measurement model -> accumulate -> write) but per CYCLE, accumulating a latent
% damage variable across cycles until the reference-condition end-of-life check trips.
%
% Pipeline, per cycle c:
%   1. redraw the 5 ambient axes (per-cycle, seeded, the only per-cycle condition axis)
%   2. delta_c = DeltaEOL(mech) * h(c)^PExponent(mech)   (shaping map, h from the gamma
%      accumulator own per-unit frailty + per-cycle gamma increment, scaled by the
%      PREVIOUS cycle's measured severity factor)
%   3. hold FAULT_<fid>_multiplier CONSTANT for the whole cycle (never through DriftDuration --
%      P2_12's harness pattern, not GenerateFaultMultiplierArray)
%   4. warm start: BOTH rotors from the LIBRARY at this cycle's own redrawn ambient, every cycle
%      (G1 as amended -- the PT is no longer
%      carried from the previous cycle's final state)
%   5. simulate PREROLL + 300s; store only the last 300 samples at 1 Hz
%   6. measure tail S26 (clean), limiter_active_fraction, duty_achieved_MW, operating_regime, and
%      BOTH ambient-check statistics: an ABSOLUTE one (this cycle's clean
%      tail S26 vs the Healthy library's prediction at this cycle's own drawn ambient -- stored,
%      informational, NOT gated, because an RTF cycle's fault is persistent and deepening, so this
%      statistic grows with fault depth and cannot distinguish "wrong ambient" from "legitimately
%      hotter faulted plant") and a DIFFERENTIAL one (this cycle's measured
%      change in clean tail S26 vs the library's PREDICTED change for the drawn change in ambient,
%      against the PREVIOUS accepted cycle -- THE GATED statistic, because delta advances by one
%      small gamma increment between cycles while ambient is redrawn i.i.d. across the whole
%      envelope, so the fault's accumulated offset cancels to first order). Cycle 1 has no
%      predecessor and uses the absolute form (valid there: h<=0.05). The differential statistic
%      is an exact first difference of the absolute one, so a single-cycle
%      transient produces a benign same-sign-then-opposite-sign PAIR of large residuals; the gate
% therefore fires, and retries, only at RTF_AMBIENT_DIFF_PERSIST_N
%      consecutive SAME-SIGN breaches, not a single one.
%   7. apply the measurement model (bias drawn ONCE per unit -- see header note below; noise per
%      cycle) and append this cycle's [300 x 39] channel block
%   8. update the accumulator with this cycle's severity factor
%   9. every N-th cycle (adaptive cadence) run the reference-condition two-half EOL check
% terminate on the first trip; hard-cap abort otherwise
%
% MEASUREMENT-MODEL NOTE (a mechanical detail leaves silent, resolved here and recorded
% rather than left implicit): calibration bias, sensor-fault state and the calibration-age draw
% are drawn ONCE PER UNIT, not per cycle -- a run-to-failure unit is one continuous simulated
% engine's life, and its instrumentation does not get recalibrated between 300 s cycles. White
% measurement noise remains per-sample (rule (b), unchanged). None of the 13 RTF
% mechanisms are sensor faults (F33-F41), so ApplyMeasurementModel.m is always called with empty
% fault_ids here -- the unit's own fault acts entirely through the plant via the constant
% multiplier, never through the measurement layer.
%
% CONTINUATION (P6R, 2026-11-21). A unit stored as aborted at the cycle cap
% (failure_mode 'aborted_hard_cap', cycles_to_failure below the cap now in force; see
% RTFAlreadyDone.m) is not re-run from cycle 1: RestoreRTFUnitState.m rebuilds, from the file, all
% the state the loop carries between cycles, and the loop resumes at the next cycle. The result is
% bit-identical to running the unit fresh with the same cap, because nothing in the loop depends
% on anything that is not either restored or a pure function of (unit, cycle):
%   * the global RNG stream seeded once per unit (RTFUnitDraws.m) is used for w0 and lambda_u ONLY;
%   * every cycle re-seeds it -- the ambient draw from RTFCycleEpoch, the measurement model from
%     per-cycle noise seeds -- and the damage increment is drawn from the noise seed's stream
%     (RTFGammaIncrement.m), so no generator state needs saving or restoring.
% If the stored file cannot be restored consistently, the unit is simply regenerated from
% cycle 1 (identical result, longer). The finished unit is written whole to a temporary file and
% moved over the old one only on success.
%
% Inputs:
%   fault_id - the diagnosis-family fault_id this mechanism corresponds to (must be one of
%              GetRTFMechanisms.FaultID)
%   unit_id  - 1-based unit index within this mechanism's folder
%   progress_fcn - OPTIONAL function handle, called with a struct (fault_id, unit_id, cycle, h,
%              first_cycle) every few cycles. GenerateRTFParallel passes one that forwards to its
%              progress queue; omitted, nothing is reported.
%
% Output:
%   success - true if the unit terminated (tripped the EOL check) or was aborted at a cap
%             and the file was written; false if a cycle's simulation failed unrecoverably
%
% 2026-10-21; one-sided limiter test ported and
%         the ambient check's gate made PERSISTENCE-based (RTF_AMBIENT_DIFF_PERSIST_N)
% 2026-10-21; continuation of cycle-capped units, cycle cap raised
%         to 10,000, collision-free epochs from cycle 1000, atomic whole-unit write, P6R
% 2026-11-21

    if nargin < 3, progress_fcn = []; end
    RTF_PROGRESS_EVERY = 25;   % cycles between progress messages to the driver (~1.5 min of wall time)

    success = false;

    rtf = GetRTFMechanisms();
    mech_idx = find(rtf.FaultID == fault_id, 1);
    if isempty(mech_idx)
        error('RunRTFUnit:NotAMechanism', 'fault_id %d is not a run-to-failure mechanism.', fault_id);
    end
    mech = struct('DeltaEOL', rtf.DeltaEOL(mech_idx), 'PExponent', rtf.PExponent(mech_idx));
    folder_name = rtf.Folder{mech_idx};
    mechanism_name = rtf.Name{mech_idx};

    scenario_hash = ScenarioConfig.ScenarioHash('single', fault_id);  % one seed space with diagnosis (cross-cutting req. 1)
    fault_defs = GetFaultDefinitions();
    is_enhancement = fault_defs.IsEnhancement(fault_id);

    MODEL = ScenarioConfig.SIMULINK_MODEL;
    [~, shortname] = fileparts(MODEL);
    if bdIsLoaded(shortname); close_system(shortname, 0); end
    load_system(MODEL);
    % No FastRestart: cycle durations vary (ambient-dependent cycle-1 preroll,
    % fixed cycles 2+, a third duration for the reference check), and production never enables
    % FastRestart anywhere in DataGeneration/ -- matching that, not optimising around it.

    %% Unit-level (once-per-unit) draws -- the ONLY use of the stream seeded here (RTFUnitDraws.m)
    [w0, lambda_u] = RTFUnitDraws(scenario_hash, unit_id);
    gamma_scale = ScenarioConfig.RTF_ACCUM_THETA0 * lambda_u;   % stored as the gamma_scale attribute

    noise_seed     = ScenarioConfig.NOISE_BASE_SEED     + scenario_hash + unit_id * 41;
    bias_seed      = ScenarioConfig.BIAS_BASE_SEED      + scenario_hash + unit_id * 61;
    calib_age_seed = ScenarioConfig.CALIB_AGE_BASE_SEED + scenario_hash + unit_id * 71;
    hold_seed      = ScenarioConfig.HOLD_BASE_SEED      + scenario_hash + unit_id * 83;

    [output_file, ref_log_path] = RTFUnitPath(fault_id, unit_id);   % single builder, shared with RTFAlreadyDone
    cap_cycles = ScenarioConfig.RTFCapCycles();

    %% Continue a cycle-capped unit from its stored file, or start from cycle 1
    state = [];
    [~, ~, unit_status] = RTFAlreadyDone(fault_id, unit_id);
    if strcmp(unit_status, 'capped_pending')
        try
            state = RestoreRTFUnitState(output_file, ref_log_path, mech, scenario_hash, unit_id, noise_seed);
        catch ME_restore
            warning('RunRTFUnit:RestoreFailed', ...
                'F%02d unit %d: cannot continue the stored unit (%s) -- regenerating it from cycle 1.', ...
                fault_id, unit_id, ME_restore.message);
            state = [];
        end
    end

    %% Per-cycle accumulators (grown with end+1; a unit is at most cap_cycles long)
    % Channel blocks are kept per cycle and joined once at the end, as singles (the writer stores
    % singles, and single(double) is the same cast it would apply): a unit can run to thousands of
    % cycles, and appending to one growing array is quadratic in time and holds two copies.
    terminated = false; failure_mode = '';
    abort_reason = '';   % 'cycle_cap' or 'health_cap' when the unit is aborted rather than terminated
    h_at_term = NaN;
    if isempty(state)
        first_cycle = 1;
        h_hist = [];
        tailS26_hist = []; limiterFrac_hist = []; dutyMW_hist = []; regimeCode_hist = [];
        ambient_hist = [];  % [C x 5]
        ambientCheckResidual_hist = [];  % [C x 1] -- ; DIFFERENTIAL
        ambientCheckAbsolute_hist = [];  % [C x 1] -- informational, ungated
        sensor_blocks = {};       % {C x 1} of [300 x 39] singles, in cycle order
        true_value_blocks = {};   % {C x 1} of [300 x 5] singles, in cycle order
        true_value_present = [];  % set from the first cycle's sensor_info, unchanged thereafter
        ref_rows = {};   % log of every reference check performed

        h_c = w0;  % h BEFORE cycle 1's own increment is added -- h(c) is evaluated AFTER cycle c runs
        % bookkeeping for the DIFFERENTIAL ambient check, carried forward
        % from the last ACCEPTED attempt of the PREVIOUS cycle only (never from a rejected attempt --
        % set at the same point the cycle is accepted, below). Pure check bookkeeping: nothing here
        % touches an InitialCondition or the warm start (unlike the deleted prev_S27_final carry,
        %).
        prev_tail_S26_clean = NaN;
        prev_ambient_check_T_q = NaN;
        prev_ambient_check_P_q = NaN;
        prev_operating_regime_code = NaN;
        % Edit 2: cross-CYCLE persistence state for the ambient check's
        % breach gate. Carried forward from the last ACCEPTED cycle only
        % (updated at the same point prev_tail_S26_clean is, below) -- never from a rejected attempt.
        % consec_breach_sign uses 0 to mean "no active streak" (sign never returns 0 for a real
        % breach, since a breach requires abs(residual) > tol > 0).
        consec_breach_count = 0;
        consec_breach_sign = 0;
    else
        % Every variable the loop carries between cycles is restored from the file --
        % RestoreRTFUnitState.m lists them all and checks that the restore reproduces the stored
        % labels and the stored health trajectory exactly.
        first_cycle = state.C0 + 1;
        fprintf('  Continuing F%02d unit %d from cycle %d (stored: %d cycles, aborted at the cycle cap).\n', ...
            fault_id, unit_id, first_cycle, state.C0);
        h_hist = state.h_hist;
        tailS26_hist = state.tailS26_hist; limiterFrac_hist = state.limiterFrac_hist;
        dutyMW_hist = state.dutyMW_hist; regimeCode_hist = state.regimeCode_hist;
        ambient_hist = state.ambient_hist;
        ambientCheckResidual_hist = state.ambientCheckResidual_hist;
        ambientCheckAbsolute_hist = state.ambientCheckAbsolute_hist;
        sensor_blocks = {state.sensors_noisy_all};
        true_value_blocks = {state.true_values_all};
        true_value_present = state.true_value_present;
        ref_rows = state.ref_rows;
        h_c = state.h_c;
        prev_tail_S26_clean = state.prev_tail_S26_clean;
        prev_ambient_check_T_q = state.prev_ambient_check_T_q;
        prev_ambient_check_P_q = state.prev_ambient_check_P_q;
        prev_operating_regime_code = state.prev_operating_regime_code;
        consec_breach_count = state.consec_breach_count;
        consec_breach_sign = state.consec_breach_sign;
        clear state;   % the restored arrays now live in the variables above
    end
    c = first_cycle - 1;
    t_unit0 = tic;
    while true
        c = c + 1;
        if c > cap_cycles
            fprintf('  [CYCLE CAP] unit aborted at %d cycles (h=%.4f) without the EOL check tripping.\n', c-1, h_c);
            terminated = false;
            abort_reason = 'cycle_cap';
            h_at_term = h_c;
            c = c - 1;  % the cycle that actually ran and was stored is c-1, not this never-run c
            break;
        end

        %% Step 1: redraw ambient for this cycle (per-cycle, seeded; retried on settling failure)
        % RTFCycleEpoch keeps unit_id*1000 + c up to cycle 999 and a non-colliding block after.
        cycle_epoch = ScenarioConfig.RTFCycleEpoch(unit_id, c);
        cycle_attempt = 1;
        MAX_CYCLE_ATTEMPTS = 4;
        settled = false;
        any_sim_succeeded = false;
        while ~settled && cycle_attempt <= MAX_CYCLE_ATTEMPTS
            env = SampleEnvironmentMC(scenario_hash, cycle_epoch, cycle_attempt);

            %% Step 2: delta_c from the CURRENT accumulator state h_c (shaping map)
            delta_c = mech.DeltaEOL * (max(h_c, 0) ^ mech.PExponent);
            if is_enhancement
                mult_c = 1.0 + delta_c;
            else
                mult_c = 1.0 - delta_c;
                if mult_c <= 0
                    error('RunRTFUnit:NonPositiveMultiplier', ...
                        'F%02d cycle %d: delta_c=%.6f produced a non-positive multiplier.', fault_id, c, delta_c);
                end
            end

            %% Step 3: hold the multiplier constant for the whole cycle (P2_12 pattern, not ramped)
            if c == 1
                DUR = ScenarioConfig.GetPrerollSeconds(env.compressor_inlet_temp_C) + ScenarioConfig.RTF_CYCLE_SECONDS;
            else
                DUR = ScenarioConfig.RTF_PREROLL_S + ScenarioConfig.RTF_CYCLE_SECONDS;
            end
            t_mult = (0:1:DUR)';
            assignin('base', 'ENV_FG_pressure_kPa',      env.FG_pressure_kPa);
            assignin('base', 'ENV_FG_temp_C',            env.FG_temp_C);
            assignin('base', 'ENV_comp_inlet_temp_C',    env.compressor_inlet_temp_C);
            assignin('base', 'ENV_comp_inlet_press_kPa', env.compressor_inlet_press_kPa);
            assignin('base', 'ENV_ambient_moisture_pct', env.ambient_moisture_percent);
            % the plant's inlet-temperature source is a From Workspace
            % block reading ENV_comp_inlet_temp_trend (rewire). ENV_comp_inlet_temp_C is
            % still assigned above because ExtractSensorsFromWorkspace falls back to it, but NO
            % BLOCK READS IT any more -- without the line below the cycle runs on whatever a
            % previous diagnosis record left behind (29.15 degC measured).
            % FLAT, not trended: per-cycle ambient is the only per-cycle axis in this family,
            % no within-cycle trend was ever specified for RTF, and a flat per-cycle ambient
            % is the behaviour under which the RTF accumulator calibration and theta0 were measured -- a trend here would silently recalibrate the family.
            assignin('base', 'ENV_comp_inlet_temp_trend', ...
                [0, env.compressor_inlet_temp_C; DUR, env.compressor_inlet_temp_C]);
            assignin('base', 'SP_POWER_CMD', 13);
            assignin('base', sprintf('FAULT_%02d_multiplier', fault_id), [t_mult, mult_c*ones(size(t_mult))]);
            % Every other fault's multiplier must be the identity array -- a stale FAULT_NN_multiplier
            % from a previous call (healthy probes, other scripts) would silently inject it.
            for other_fid = 1:42
                if other_fid == fault_id, continue; end
                assignin('base', sprintf('FAULT_%02d_multiplier', other_fid), [t_mult, ones(size(t_mult))]);
            end

            %% Step 4: warm start -- G1 as amended
            if c == 1
                ok = RunSimulinkModel(MODEL, DUR, env.compressor_inlet_temp_C);
            else
                % re-seed BOTH rotors from the library at THIS cycle's own redrawn
                % ambient. The PT override that used to sit here (prev_S27_final) made a
                % cold->hot ambient jump unsettleable inside RTF_PREROLL_S = 300 s against the
                % PT's declared ~10^3 s time constant, so the settling check rejected EVERY cycle
                % drawn above 30 degC (0 of 300 survived attempt 1) and the
                % retry redrew it toward the 15 degC nominal -- collapsing the family's only
                % per-cycle condition axis and leaving theta0 wrong by 9.4x.
                % The diagnosis path has always re-seeded both rotors this way.
                SetWarmStartInitialConditions(shortname, env.compressor_inlet_temp_C);
                ok = RunSimulinkModel(MODEL, DUR);
            end
            if ~ok
                fprintf('  Cycle %d (attempt %d) simulation FAILED.\n', c, cycle_attempt);
                cycle_attempt = cycle_attempt + 1;
                continue;
            end
            any_sim_succeeded = true;

            [sa, tv, s_info] = ExtractSensorsFromWorkspace(1, DUR);
            preroll_this = DUR - ScenarioConfig.RTF_CYCLE_SECONDS;
            keep_idx = tv > preroll_this;
            sa_cycle = sa(keep_idx, :);
            tv_cycle = tv(keep_idx) - preroll_this;
            if isfield(s_info, 'TrueValueTapData')
                tv_tap_cycle = s_info.TrueValueTapData(keep_idx, :);
                if isempty(true_value_present), true_value_present = s_info.TrueValueTapPresent; end
            else
                tv_tap_cycle = NaN(size(sa_cycle,1), 5);
                if isempty(true_value_present), true_value_present = zeros(1,5); end
            end
            if size(sa_cycle, 1) ~= ScenarioConfig.RTF_CYCLE_SECONDS
                error('RunRTFUnit:SampleCountMismatch', 'Cycle %d: got %d stored samples, expected %d.', ...
                    c, size(sa_cycle,1), ScenarioConfig.RTF_CYCLE_SECONDS);
            end

            %% Settling check (same test as ComputeLayer1RecordAttributes.m's pt_speed_settled):
            % trailing-window linear drift of clean S27 vs its own measurement-noise sigma.
            try
                nm = GetSensorNoiseModel(); sigma_s27 = nm.sigma_noise(27);
            catch
                sigma_s27 = NaN;
            end
            win = min(60, size(sa_cycle,1));
            if ~isnan(sigma_s27)
                seg = sa_cycle(end-win+1:end, 27);
                p = polyfit(tv_cycle(end-win+1:end), seg, 1);
                settled = abs(p(1)) * win < sigma_s27;
            else
                settled = true;  % noise model unavailable -- cannot assess, do not block on it
            end

            %% Regime classification -- same window, same attempt. Mirrors
            % ComputeLayer1RecordAttributes.m's three-state rule on this cycle's own
            % 300-sample window (the whole window IS the tail here -- the multiplier is already
            % constant for the whole cycle, no baseline/fault-onset split inside a cycle).
            %
            % UNLIKE diagnosis Layer 1, spec does NOT gate RTF cycles on operating_regime --
            % only the settling check is named as a retry trigger there. An indeterminate regime IS
            % retried here anyway (folded into the SAME attempt loop as settling), because an RTF
            % trajectory's depth increases CONTINUOUSLY and so passes directly through the exact
            % duty_tracking/temperature_limited boundary far more often than diagnosis's discrete
            % severity levels ever do -- found by running this code for real (F03 unit 9002 cycle 3:
            % duty=11.806 MW outside the 2% band, limiter_active_fraction=0.578 short of 0.9,
            % S32 never saturated -- a genuine mid-transition 300 s window, not a defect). Retrying
            % with mildness (pulling ambient toward the clean nominal 15 C point) resolves this in
            % practice; if it is STILL indeterminate after all attempts, the cycle is kept and
            % logged rather than crashing the whole unit -- regime_code=0 ('indeterminate') is a
            % legitimate, documented, rare stored value for this family (never for diagnosis).
            TEMP_LIMIT_C = 846; RATED_MW = 13;
            tail_n = min(180, size(sa_cycle,1));
            S26c = sa_cycle(:,26); S28c = sa_cycle(:,28); S32c = sa_cycle(:,32);
            duty_achieved_MW = mean(S28c(end-tail_n+1:end));
            % Edit 1: PORTED from ComputeLayer1RecordAttributes.m ~114
            % -- the two-sided test |S26-846|<=1 was written when ambient was
            % constant per cycle/record, where S26 pins at 846 FROM BELOW and the upper bound is
            % harmless. With a within-cycle ambient trend and real fault-driven heating the plant
            % can OVERSHOOT its own 846 degC ceiling (measured: pooled max
            % clean S26 = 868.88 degC, 12.90% of samples above 847 degC), and a cycle running OVER
            % its own limit is the most temperature-limited cycle in the family, not a
            % duty_tracking one. This changes NO label that was correct before: the old band was
            % already [845,847], so only the above-847 overshoot moves. limiter_active_fraction
            % (computed from the same near_limit) therefore becomes one-sided too, deliberately:
            % it now counts OVER-LIMIT time, which severity factor also reads.
            % This is the completion on the path it missed,
            % not a new rule -- RunRTFUnit.m had never been ported when shipped.
            near_limit = S26c >= (TEMP_LIMIT_C - 1.0);
            limiter_active_fraction = mean(near_limit(end-tail_n+1:end));
            tail_near_limit = limiter_active_fraction >= 0.9;
            duty_within_2pct = abs(duty_achieved_MW - RATED_MW) / RATED_MW <= 0.02;
            controller_saturated_hi = any(S32c(end-tail_n+1:end) >= 59.9);
            if tail_near_limit
                regime_code = 2;  % temperature_limited
            elseif duty_within_2pct
                regime_code = 1;  % duty_tracking
            elseif controller_saturated_hi
                regime_code = 3;  % fault_limited (this unit's own fault is always active)
            else
                regime_code = 0;  % indeterminate -- retry, see note above
            end
            tail_S26_clean = mean(S26c(end-tail_n+1:end));

            %% Edit 1: the per-cycle drawn-vs-realised ambient check is
            % now DIFFERENTIAL. root cause: the diagnosis check's absolute form is valid
            % only in a pre-onset, fault-free window, which an RTF cycle never has (its fault is
            % persistent and deepening) -- so comparing a faulted plant against a Healthy
            % prediction on the ABSOLUTE statistic grows with fault depth until it breaches any
            % fixed tolerance (measured: 11 of 11 trial units died this way at a low,
            % mechanism-specific depth). The ABSOLUTE statistic is kept and stored -- it is a
            % free, genuine fault-progression signal -- but it is no longer gated here.
            try
                LIB_rtf = GetWarmStartLibrary();
                % Errors if the drawn ambient is outside the surface grid (caught below, as before).
                [S26_expected_rtf, T_q_rtf, P_q_rtf] = RTFExpectedTailS26(LIB_rtf, ...
                    env.compressor_inlet_temp_C, env.compressor_inlet_press_kPa);

                % ---- absolute statistic: INFORMATIONAL on the RTF path on
                %. Kept and stored because it is a free, genuine fault-progression
                % signal (it tracks delta_c against the Healthy equilibrium), in the same spirit
                % as the diagnosis path's ungated s24_library_offset_radps. NOT gated here.
                ambient_check_absolute_C = tail_S26_clean - S26_expected_rtf;

                % ---- differential statistic: THE GATED one. The fault's
                % accumulated offset cancels to first order because delta advances by one gamma
                % increment between consecutive cycles, while ambient is redrawn i.i.d. across
                % the whole 10-50 degC envelope. Cycle 1 has no predecessor, and the absolute
                % check IS valid there: h<=RTF_W0_MAX_FRAC=0.05, so delta/delta_EOL<=0.05^2.77 ~
                % 2.5e-4, four orders below the ~6% depth at which the absolute check breaks
                %. It also covers a defect class the differential form cannot see: a
                % CONSTANT ambient offset. Complementary, not a special case.
                if c == 1
                    ambient_check_residual_C = ambient_check_absolute_C;
                else
                    S26_expected_prev_rtf = RTFExpectedTailS26(LIB_rtf, prev_ambient_check_T_q, prev_ambient_check_P_q);
                    dS26_measured  = tail_S26_clean - prev_tail_S26_clean;
                    dS26_predicted = S26_expected_rtf - S26_expected_prev_rtf;
                    ambient_check_residual_C = dS26_measured - dS26_predicted;
                end
            catch ME_amb
                warning('RunRTFUnit:AmbientCheckFailed', '%s', ME_amb.message);
                ambient_check_absolute_C = NaN;
                ambient_check_residual_C = NaN;
            end
            % Same two-tier SHAPE as (ValidateGenerationLayer1.m), new RTF-only
            % constants (ScenarioConfig.m): the PINNED tier applies when EITHER this
            % cycle's OR the previous cycle's measured regime is temperature_limited, because a
            % pinned cycle suppresses dS26 on that side of the subtraction and the statistic is
            % then uninformative on that side alone -- selected on the MEASURED regime, never the
            % predicted surface value (load-bearing distinction, unchanged here).
            % At cycle 1 there is no previous cycle, so only this cycle's own regime applies.
            [ambient_check_breach, amb_tol_this_cycle] = RTFAmbientBreach(c, ambient_check_residual_C, ...
                regime_code, prev_operating_regime_code);

            %% Edit 2: PERSISTENCE rule. A
            % single breaching cycle is no longer sufficient to retry-then-fail the unit -- only
            % RTF_AMBIENT_DIFF_PERSIST_N (=3) CONSECUTIVE SAME-SIGN cycle-level breaches are
            % (measured: N=3 never occurs in benign Stage-1 data at any candidate tolerance, while
            % the defect class this check exists for -- a frozen/severed ambient -- breaches every
            % cycle). Evaluated HYPOTHETICALLY against the streak carried from the last ACCEPTED
            % cycle, as if THIS attempt were accepted -- which is what lets a retry (a fresh
            % redraw) break the streak by returning a non-breaching or opposite-sign residual.
            % The NaN branch is exempt from the persistence counter entirely and stays
            % unconditional/single-cycle (a NaN is a broken lookup, not a transient).
            is_nan_residual = isnan(ambient_check_residual_C);
            if is_nan_residual
                hypothetical_streak = NaN;
                persist_gate_fires = true;
            elseif ambient_check_breach
                this_breach_sign = sign(ambient_check_residual_C);
                if consec_breach_count > 0 && this_breach_sign == consec_breach_sign
                    hypothetical_streak = consec_breach_count + 1;
                else
                    hypothetical_streak = 1;
                end
                persist_gate_fires = hypothetical_streak >= ScenarioConfig.RTF_AMBIENT_DIFF_PERSIST_N;
            else
                hypothetical_streak = 0;
                persist_gate_fires = false;
            end

            needs_retry = (~settled) || (regime_code == 0) || persist_gate_fires;
            if ~settled
                fprintf('  Cycle %d (attempt %d): settling check failed (drift=%.4g vs sigma=%.4g) -- retrying cycle.\n', ...
                    c, cycle_attempt, abs(p(1))*win, sigma_s27);
            end
            if regime_code == 0
                fprintf('  Cycle %d (attempt %d): regime indeterminate (duty=%.3f, limiter_frac=%.3f, S32_hi=%d) -- retrying cycle.\n', ...
                    c, cycle_attempt, duty_achieved_MW, limiter_active_fraction, controller_saturated_hi);
            end
            if ambient_check_breach
                fprintf('  Cycle %d (attempt %d): ambient check breached (residual=%.4f, tol=%.1f, regime_code=%d, hypothetical_streak=%g, persist_gate=%d)%s\n', ...
                    c, cycle_attempt, ambient_check_residual_C, amb_tol_this_cycle, regime_code, ...
                    hypothetical_streak, persist_gate_fires, iif_str(persist_gate_fires, ' -- retrying cycle.', ' -- below persistence threshold, not retried on this dimension.'));
            end
            settled = ~needs_retry;  % drives the while-loop condition below
            if needs_retry
                cycle_attempt = cycle_attempt + 1;
            end
        end
        if ~any_sim_succeeded
            error('RunRTFUnit:AllCycleAttemptsFailed', ...
                'F%02d unit %d cycle %d: simulation failed on all %d attempts -- cannot proceed.', ...
                fault_id, unit_id, c, MAX_CYCLE_ATTEMPTS);
        end
        if ~settled && persist_gate_fires
            % Edit 2: the ambient check's PERSISTENCE gate was still
            % firing after the last attempt -- either an unresolved NaN lookup (unconditional,
            % single-cycle) or RTF_AMBIENT_DIFF_PERSIST_N consecutive same-sign breaches survived
            % every retry -- fail the unit loudly rather than write it (spec Edit 2,
            % continuing Edit 3's instruction for the case that still applies).
            error('RunRTFUnit:AmbientCheckNeverResolved', ...
                'F%02d unit %d cycle %d: ambient check gate still firing after %d attempts (%s) -- failing the unit rather than writing it.', ...
                fault_id, unit_id, c, MAX_CYCLE_ATTEMPTS, ...
                iif_str(is_nan_residual, 'NaN lookup failure', ...
                    sprintf('%g consecutive same-sign breaches, residual=%.4f, tol=%.1f', hypothetical_streak, ambient_check_residual_C, amb_tol_this_cycle)));
        end
        if ~settled
            warning('RunRTFUnit:CycleNeverResolved', ...
                'F%02d unit %d cycle %d did not settle / resolve a regime after %d attempts -- keeping the last attempt (regime_code=%d).', ...
                fault_id, unit_id, c, MAX_CYCLE_ATTEMPTS, regime_code);
        end

        %% update the cross-CYCLE persistence streak from this cycle's
        % own FINAL ACCEPTED attempt only (never from a rejected attempt -- same rule as
        % prev_tail_S26_clean, directly below). A NaN residual cannot reach this line: it is
        % either resolved to a finite value by a retry, or it fails the unit above.
        [consec_breach_count, consec_breach_sign] = RTFAdvanceStreak(ambient_check_breach, ...
            ambient_check_residual_C, consec_breach_count, consec_breach_sign);

        %% this cycle's attempt is now ACCEPTED (whether by settling
        % cleanly or by exhausting retries on the settling/regime-indeterminate case, which is
        % kept rather than thrown) -- carry its own state forward as "prev_*" for the NEXT
        % cycle's differential ambient check. Never updated from a rejected attempt: every
        % earlier attempt this cycle was overwritten by the next attempt's values before
        % reaching this line, so what is captured here is exactly the attempt that survives.
        prev_tail_S26_clean = tail_S26_clean;
        prev_ambient_check_T_q = T_q_rtf;
        prev_ambient_check_P_q = P_q_rtf;
        prev_operating_regime_code = regime_code;

        %% Step 7: measurement model (bias/noise/quant; no sensor faults among the 13 mechanisms)
        noise_seed_c = noise_seed + c*104729;
        [sensors_noisy_cycle, ~] = ApplyMeasurementModel(sa_cycle, tv_cycle, [], [], [], ...
            noise_seed_c, bias_seed, calib_age_seed, hold_seed + c*100519);
        sensor_blocks{end+1}     = single(sensors_noisy_cycle); %#ok<AGROW>
        true_value_blocks{end+1} = single(tv_tap_cycle); %#ok<AGROW>

        %% Step 8: update the accumulator (5.4) -- the INCREMENT uses THIS cycle's own
        % measured severity factor (the cycle that was just run), then h_c advances for the NEXT
        % cycle's delta_c (Step 2 above read h_c BEFORE this update, i.e. h(0)=w0 for cycle 1).
        %
        % STORED health_index(c) = h_c, the PRE-increment value that commanded CYCLE c's own
        % depth (delta_c, above) -- not the post-increment value. This is deliberate, not an
        % off-by-one: it keeps ComputeRTFUnitLabels.m's existing contract exactly self-consistent
        % (that function recomputes delta(c) = DeltaEOL*health_index(c)^p, and this is the only
        % indexing under which its recomputed delta matches what was ACTUALLY injected into
        % Simulink this cycle). h_at_termination is reported as the final cycle's PRE-increment
        % value for the same reason -- it differs from the true post-increment damage by one
        % cycle's increment (~k0*theta0 ~ 0.007 at s_c=1, small next to the unit ~1.0 crossing).
        s_c = 2 ^ ((tail_S26_clean - ScenarioConfig.RTF_S26_REF_C) / ScenarioConfig.RTF_T_DOUBLING_C) * ...
              (1 + ScenarioConfig.RTF_BETA_LIMITER * limiter_active_fraction);
        % Drawn from this cycle's own noise-seed stream (RTFGammaIncrement.m) -- the same numbers
        % the stream left behind after ApplyMeasurementModel, made explicit so a continued unit
        % can reproduce them without any saved generator state.
        inc = RTFGammaIncrement(noise_seed_c, size(sensors_noisy_cycle), gamma_scale, s_c);
        h_c_next = h_c + inc;

        h_hist(end+1,1)          = h_c;              %#ok<AGROW>
        tailS26_hist(end+1,1)    = tail_S26_clean;    %#ok<AGROW>
        limiterFrac_hist(end+1,1)= limiter_active_fraction; %#ok<AGROW>
        dutyMW_hist(end+1,1)     = duty_achieved_MW;  %#ok<AGROW>
        regimeCode_hist(end+1,1) = regime_code;       %#ok<AGROW>
        ambient_hist(end+1,:)    = [env.FG_pressure_kPa, env.FG_temp_C, env.compressor_inlet_temp_C, ...
                                     env.compressor_inlet_press_kPa, env.ambient_moisture_percent]; %#ok<AGROW>
        ambientCheckResidual_hist(end+1,1) = ambient_check_residual_C; %#ok<AGROW>
        ambientCheckAbsolute_hist(end+1,1) = ambient_check_absolute_C; %#ok<AGROW>

        if ~isempty(progress_fcn) && mod(c, RTF_PROGRESS_EVERY) == 0
            progress_fcn(struct('fault_id', fault_id, 'unit_id', unit_id, 'cycle', c, 'h', h_c_next, ...
                'first_cycle', first_cycle));
        end

        fprintf('  cycle %4d: h=%.4f->%.4f  delta=%.6f  mult=%.4f  tailS26=%.2f  regime=%d  s_c=%.3f  (ambientT=%.1fC)  ambChkDiff=%.4f  ambChkAbs=%.4f\n', ...
            c, h_c, h_c_next, delta_c, mult_c, tail_S26_clean, regime_code, s_c, env.compressor_inlet_temp_C, ...
            ambient_check_residual_C, ambient_check_absolute_C);

        %% Step 9: adaptive-cadence reference check
        run_ref_check = (h_c_next >= ScenarioConfig.RTF_H_NEAR) || (mod(c, ScenarioConfig.RTF_N_FAR) == 0);
        hard_cap_h = h_c_next >= ScenarioConfig.RTF_HARD_CAP_H;
        if run_ref_check || hard_cap_h
            [ref_tripped, ref_mode, ref_S26, ref_duty] = run_reference_check(MODEL, shortname, delta_c, fault_id, is_enhancement);
            ref_rows(end+1,:) = {c, h_c_next, ref_tripped, ref_mode, ref_S26, ref_duty}; %#ok<AGROW>
            fprintf('    [ref check @ cycle %d] S26=%.2f duty=%.4f tripped=%d mode=%s\n', c, ref_S26, ref_duty, ref_tripped, ref_mode);
            if ref_tripped
                terminated = true;
                failure_mode = ref_mode;
                h_at_term = h_c_next;
                h_c = h_c_next;
                break;
            end
        end
        if hard_cap_h
            fprintf('  [HEALTH CAP] unit aborted: h=%.4f >= %.2f without the EOL check tripping.\n', h_c_next, ScenarioConfig.RTF_HARD_CAP_H);
            terminated = false;
            abort_reason = 'health_cap';
            h_c = h_c_next;
            break;
        end
        h_c = h_c_next;
    end
    cycles_to_failure = c;
    fprintf('Unit F%02d/%04d done: %d cycles (%d new), %.1f s wall, terminated=%d, failure_mode=%s, h_at_term=%.4f\n', ...
        fault_id, unit_id, cycles_to_failure, cycles_to_failure - first_cycle + 1, toc(t_unit0), terminated, failure_mode, h_at_term);

    %% Labels, via the already-built, already-tested ComputeRTFUnitLabels.m
    labels = ComputeRTFUnitLabels(h_hist, tailS26_hist, limiterFrac_hist, mech);

    %% cycle_index: SAMPLE-level, [300*C x 1] -- which cycle each stored sample belongs to
    cycle_index = repelem((1:cycles_to_failure)', ScenarioConfig.RTF_CYCLE_SECONDS, 1);

    unit_attrs = struct();
    unit_attrs.mechanism = mechanism_name;
    unit_attrs.scenario_id = regexprep(folder_name, '^RTF_', '');   % 'Fxx_<code>' (folder minus RTF_ prefix)
    unit_attrs.fault_id = fault_id;
    unit_attrs.cycles_to_failure = cycles_to_failure;
    % 'aborted_hard_cap' = stopped at the CYCLE cap (RTFAlreadyDone.m queues such a unit for
    % continuation); 'aborted_health_cap' = stopped at the health ceiling RTF_HARD_CAP_H, which no
    % continuation can change, so it is final.
    unit_attrs.failure_mode = iif_str(terminated, failure_mode, ...
        iif_str(strcmp(abort_reason, 'health_cap'), 'aborted_health_cap', 'aborted_hard_cap'));
    unit_attrs.terminated_or_aborted = iif_str(terminated, 'terminated', 'aborted');
    unit_attrs.initial_wear = w0;
    unit_attrs.gamma_shape = ScenarioConfig.RTF_ACCUM_K0;
    unit_attrs.gamma_scale = ScenarioConfig.RTF_ACCUM_THETA0 * lambda_u;
    unit_attrs.delta_EOL = mech.DeltaEOL;
    unit_attrs.p_exponent = mech.PExponent;
    unit_attrs.h_at_termination = labels.h_at_termination;
    unit_attrs.S26_ref = ScenarioConfig.RTF_S26_REF_C;
    unit_attrs.T_DOUBLING = ScenarioConfig.RTF_T_DOUBLING_C;
    unit_attrs.BETA_LIMITER = ScenarioConfig.RTF_BETA_LIMITER;
    unit_attrs.unit_id = unit_id;
    unit_attrs.master_seed = scenario_hash;
    unit_attrs.scenario_hash = scenario_hash;
    unit_attrs.warm_start_route = 'measured_ic';
    unit_attrs.gg_warm_start_mode = 'library_per_cycle';
    unit_attrs.pt_warm_start_mode = 'library_per_cycle';  % PT no longer carried
    unit_attrs.true_value_tap_present = true_value_present;
    unit_attrs.health_index_hist = h_hist;
    unit_attrs.delta_hist = labels.delta;

    sensors_noisy_all = vertcat(sensor_blocks{:});   clear sensor_blocks;
    true_values_all   = vertcat(true_value_blocks{:}); clear true_value_blocks;

    %% Write the WHOLE unit to temporary files, then move them into place (rule 10). The CSV goes
    % first and the HDF5 last: RTFAlreadyDone judges a unit by its HDF5 alone, so a crash between
    % the two moves leaves the OLD unit still pending (and RestoreRTFUnitState drops any CSV rows
    % beyond that unit's last cycle) -- never a new unit that looks old, nor a half-written one.
    tmp_unit = [output_file '.partial'];
    tmp_ref  = [ref_log_path '.partial'];
    SaveRTFUnitToHDF5(sensors_noisy_all, true_values_all, tmp_unit, unit_attrs, cycle_index, labels, ...
        dutyMW_hist, limiterFrac_hist, regimeCode_hist, ambient_hist, ambientCheckResidual_hist, ...
        ambientCheckAbsolute_hist);

    % Reference-check log, for acceptance inspection -- not part of the unit schema ("its
    % output is NOT stored as data").
    if ~isempty(ref_rows)
        RefT = cell2table(ref_rows, 'VariableNames', {'cycle','h','tripped','failure_mode','ref_S26','ref_duty_MW'});
        writetable(RefT, tmp_ref, 'FileType', 'text', 'Delimiter', ',');
        movefile(tmp_ref, ref_log_path, 'f');
    end
    movefile(tmp_unit, output_file, 'f');

    success = true;
end

% -------------------------------------------------------------------------
function [tripped, mode, S26_ref, duty_ref] = run_reference_check(MODEL, shortname, delta_c, fault_id, is_enhancement)
% The reference-condition two-half EOL check: 15 C inlet,
% nominal, SP_POWER_CMD=13, no trend, 900 s, tail = last 10%. Held delta (this cycle's own,
%), warm-started library at 15 C. NOT carried from the production cycle's
% own rotor state -- it is a measurement ON the unit, decoupled from its trajectory.
    DUR = 900;
    t_mult = (0:1:DUR)';
    if is_enhancement
        mult_c = 1.0 + delta_c;
    else
        mult_c = 1.0 - delta_c;
    end
    A = ScenarioConfig.AmbientConfig(); NOM = A.nom;
    assignin('base', 'ENV_FG_pressure_kPa',      NOM.FG_pressure_kPa);
    assignin('base', 'ENV_FG_temp_C',            NOM.FG_temp_C);
    assignin('base', 'ENV_comp_inlet_temp_C',    NOM.compressor_inlet_temp_C);
    assignin('base', 'ENV_comp_inlet_press_kPa', NOM.compressor_inlet_press_kPa);
    assignin('base', 'ENV_ambient_moisture_pct', NOM.ambient_moisture_percent);
    % same reasoning as the per-cycle call site above -- the plant reads
    % ENV_comp_inlet_temp_trend, not ENV_comp_inlet_temp_C, since rewire. Flat two-point
    % array at this check's own nominal temperature and this function's own DUR.
    assignin('base', 'ENV_comp_inlet_temp_trend', ...
        [0, NOM.compressor_inlet_temp_C; DUR, NOM.compressor_inlet_temp_C]);
    assignin('base', 'SP_POWER_CMD', 13);
    assignin('base', sprintf('FAULT_%02d_multiplier', fault_id), [t_mult, mult_c*ones(size(t_mult))]);
    for other_fid = 1:42
        if other_fid == fault_id, continue; end
        assignin('base', sprintf('FAULT_%02d_multiplier', other_fid), [t_mult, ones(size(t_mult))]);
    end
    ok = RunSimulinkModel(MODEL, DUR, NOM.compressor_inlet_temp_C);
    if ~ok
        error('RunRTFUnit:ReferenceCheckFailed', 'F%02d: reference check simulation failed at delta=%.6f.', fault_id, delta_c);
    end
    [sa, tv] = ExtractSensorsFromWorkspace(1, DUR);
    tail = tv >= 0.9*DUR;
    S26_ref = mean(sa(tail, 26));
    duty_ref = mean(sa(tail, 28));
    S32_ref_max = max(sa(tail, 32));

    trip_temp = S26_ref >= 845.0;
    trip_duty = (duty_ref < 12.74) || (S32_ref_max >= 59.9);
    if trip_temp
        tripped = true; mode = 'temperature_limit';
    elseif trip_duty
        tripped = true; mode = 'duty_headroom';
    else
        tripped = false; mode = '';
    end
end

function s = iif_str(cond, a, b)
    if cond, s = a; else, s = b; end
end
