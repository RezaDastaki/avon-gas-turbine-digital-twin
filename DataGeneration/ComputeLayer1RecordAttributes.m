function attrs = ComputeLayer1RecordAttributes(sensors_clean, time_vector, fault_start_times, ...
    n_faults_active, drawn_temp_C, drawn_press_kPa, preroll_s, sim_duration_total, ambient_trend_amplitude_C)
% ComputeLayer1RecordAttributes - the measured, per-record operating-point
% attributes that both the HDF5 writer and the QA Layer 1 gate need.
% Written once, used twice, so the writer's stored attributes and the gate's pass/fail
% criteria can never disagree about what was measured.
%
% MEASURED ON THE CLEAN (pre-measurement-model) ARRAY -- corrected
% 2026-10-13. These attributes are GROUND
% TRUTH about the simulated plant and controller, in exactly the same sense as fault_label /
% severity_label -- they are not instrument readings. Computing them from the post-measurement-
% model array was a real defect, not a stylistic choice: S26 carries sigma_bias = 15.14 degC of
% per-record calibration bias and sigma_noise = 2.06 degC (P3_noise_model.csv; IEC 60584
% thermocouple above 800 degC), so the limiter test |S26 - 846| <= 1 degC -- which is exactly
% right on the clean signal, where a temperature-limited engine sits at 846.0 degC at every
% ambient from 25 to 50 degC (measured) -- almost never fires
% on the indicated signal. Under the old wiring the majority of the release (62.5 % of records
% draw an ambient above 25 degC) would have been mislabelled 'indeterminate'. The same applies
% to the settling test, whose OLS slope over a 60-sample window carries a noise-only term of
% 0.447*sigma even on a perfectly settled record.
%
% Inputs:
%   sensors_clean     - [N x 39] PRE-measurement-model channel array, S01..S39 columns
%                        (RunScenario.m's sensors_raw -- NOT sensors_noisy)
%   time_vector       - [N x 1] STORED-window-relative time, 1..STORED_SAMPLES seconds
%   fault_start_times - per-active-fault onset times, STORED-window-relative (already
%                        re-based by RunScenario.m; see that file's Step 3/4 comment)
%   n_faults_active   - number of faults active in this record (0 for Healthy). Used ONLY by
%                        the 'fault_limited' regime rule below, where it is a known generation
%                        parameter, never an inference from the data.
%
% Output: attrs struct --
%   duty_achieved_MW        - tail-window (last 180 s) mean of S28
%   operating_regime        - 'duty_tracking' | 'temperature_limited' | 'fault_limited',
%                              MEASURED not inferred; 'indeterminate' only ever as a hard
%                              Layer 1 failure
%   limiter_active_fraction - fraction of stored samples with S26 within 1 degC of 846
%   controller_saturated    - true if S32 reaches EITHER PID limit (+60 or -30) anywhere
%   controller_saturated_hi - true if S32 >= 59.9 anywhere (the "cannot make the duty" limit)
%   controller_saturated_lo - true if S32 <= -29.9 anywhere (the floor; no longer expected
%                              under the fixed-13MW-duty design --
%                              so this flag alone is evidence worth surfacing, not silently OK)
%   pt_speed_settled        - true if S27's baseline-window linear drift is below its own
%                              measurement-noise sigma
%   steady_state_start_s    - first tau (seconds into the stored window) at which a trailing
%                              60 s window of S27 first satisfies the drift-below-sigma test;
%                              NaN if it never does within the baseline window
%   in_calibration_envelope - achieved load >= 45% of rated (13 MW) -- the companion paper's
%                              validated floor
%   baseline_end_tau        - last stored sample strictly before the earliest fault onset
%                              (= STORED_SAMPLES for Healthy / no active faults)
%   ambient_check_residual_C: baseline-window clean S26 mean
%                              minus the warm-start library's 2-D (temperature x pressure)
%                              surface at (T_eff, drawn_press_kPa), bilinearly interpolated.
%                              Signed, degC. GATED in ValidateGenerationLayer1.m at
%                              +/-AMBIENT_CHECK_TOL_C.
%   ambient_check_window_n  - realised length of the window the ambient check was computed over
%                              (180 unless the baseline is shorter)
%   s24_library_offset_radps - informational only (spec, not a gate): baseline-window
%                              clean S24 mean minus the surface's chk_S24_radps at (T_eff, drawn
%                              pressure)
%
% Inputs added:
%   drawn_temp_C              - this record's drawn compressor_inlet_temp_C (env.compressor_inlet_temp_C)
%   preroll_s                 - this record's (unstored) pre-roll duration, seconds
%   sim_duration_total        - this record's full simulated duration, preroll_s + STORED_SAMPLES
%   ambient_trend_amplitude_C - within-record signed trend amplitude; NaN or 0 when no
%                              trend is active (as of 2026-10-17 has not shipped -- see
%                              LoadScenarioToWorkspace.m -- so this is always NaN in production
%                              and T_eff reduces to the constant drawn_temp_C). Spec
%
% Input added (spec/12.5):
%   drawn_press_kPa           - this record's drawn compressor_inlet_press_kPa
%                              (env.compressor_inlet_press_kPa). The check's second library
%                              axis -- the drawn (not realised) value is used deliberately, so a
%                              severed/grounded inlet-PRESSURE path also fails this check, which
% temperature-only version did not cover.
%
% ambient check added; 2-D surface added by
%

    if nargin < 4 || isempty(n_faults_active), n_faults_active = 0; end
    if nargin < 5, drawn_temp_C = NaN; end
    if nargin < 6, drawn_press_kPa = NaN; end
    if nargin < 7 || isempty(preroll_s), preroll_s = 0; end
    if nargin < 8 || isempty(sim_duration_total), sim_duration_total = NaN; end
    if nargin < 9 || isempty(ambient_trend_amplitude_C), ambient_trend_amplitude_C = NaN; end
    STORED_SAMPLES = ScenarioConfig.STORED_SAMPLES; %#ok<NASGU> (documents the expected N)
    N = size(sensors_clean, 1);

    S26 = sensors_clean(:, 26);   % PT_inlet_temperature (degC)
    S27 = sensors_clean(:, 27);   % PT_rotor_speed (rad/s)
    S28 = sensors_clean(:, 28);   % PT_generated_power (MW)
    S32 = sensors_clean(:, 32);   % Controller_power_demand (dimensionless PID output)

    %% duty_achieved_MW — tail-window (last 180 s) mean of S28
    tail_n = min(180, N);
    attrs.duty_achieved_MW = mean(S28(end-tail_n+1:end));

    %% limiter_active_fraction and operating_regime (temperature limiter: S26 at or above 845)
    % ONE-SIDED, not a symmetric band. The old two-sided
    % test |S26-846|<=1 was written when ambient was constant per record, where S26 pins at 846
    % FROM BELOW and the upper bound is harmless. With within-record ambient trend
    % the plant can OVERSHOOT its own 846 degC ceiling by up
    % to ~9 degC in a ~1 degC sliver per drawn pressure, and a record running 9 degC OVER its own
    % limit is the most temperature-limited record in the release, not a duty_tracking one. This
    % changes NO label that was correct before shipped: the old band was already [845,847],
    % so every existing temperature_limited record (S26 = 846.0 exactly) and every duty_tracking
    % record below 845 is untouched -- only the above-847 overshoot moves. limiter_active_fraction
    % (computed from the same near_limit) therefore becomes one-sided too, deliberately: it now
    % counts OVER-LIMIT time, which run-to-failure severity factor also reads.
    TEMP_LIMIT_C = 846;
    near_limit = S26 >= (TEMP_LIMIT_C - 1.0);
    attrs.limiter_active_fraction = mean(near_limit);
    tail_near_limit = mean(near_limit(end-tail_n+1:end)) >= 0.9;  % limiter active through the tail
    RATED_MW = 13;
    % duty-guarded, additive, inside the
    % permitted exception (the ValidateGenerationLayer1.m precedent already
    % applied): 'duty_tracking' must mean tracking the COMMANDED duty, not the
    % engine's 13 MW nameplate rating -- the two were only ever the same number because the fixed-duty design
    % fixed commanded duty AT 13 MW. The turndown family commands 10 MW, and
    % without this guard a perfectly-on-duty 10 MW record (duty_achieved=10.000) reads
    % |10-13|/13=23% and falls through to 'indeterminate', a hard QA Layer 1 failure -- measured
    % on a real batch: 222/231 attempts indeterminate, 0 duty_tracking, 0 that ever recovered on
    % retry. Inert at 13 MW: ScenarioConfig.DUTY_CMD_MW returns 13 unless
    % AVON_DUTY_CMD_MW is set, so RATED_MW_FOR_REGIME == RATED_MW == 13 for every main-family and
    % RTF-adjacent diagnosis record, G1/G2 below prove it numerically rather than by inspection.
    RATED_MW_FOR_REGIME = ScenarioConfig.DUTY_CMD_MW();
    duty_within_2pct = abs(attrs.duty_achieved_MW - RATED_MW_FOR_REGIME) / RATED_MW_FOR_REGIME <= 0.02;

    %% controller_saturated — EITHER PID limit
    attrs.controller_saturated_hi = any(S32 >= 59.9);
    attrs.controller_saturated_lo = any(S32 <= -29.9);
    attrs.controller_saturated    = attrs.controller_saturated_hi || attrs.controller_saturated_lo;

    %% operating_regime -- THREE measured states. Decided,
    % resolving the open finding recorded rather than invented.
    %
    % Evaluation order is deliberate, not arbitrary: the 846 degC limiter is the engine's
    % physical ceiling, so if it is holding through the tail then that is what the record IS,
    % whatever else is also true. Then exact duty tracking. Then the third state.
    %
    % 'fault_limited' is the state the two-label scheme had no name for: the engine cannot
    % deliver the fixed 13 MW command, the temperature limiter is NOT the binding constraint,
    % and the power loop is pinned at its upper limit asking for more. It is measured, in this
    % model, on F17 (fuel nozzle clogging) at depth 0.50 -- duty 12.71 MW, S32 = 25.1 rising to
    % a full +60.000 by depth 0.45, with S26 nowhere near 846. A fuel-path
    % fault starves the engine, so there is no excess heat to reach the thermal ceiling. The
    % candidates are the flow-limiting faults (F07, F10, F11, F14, F17) and the multi-fault
    % combinations containing them.
    %
    % The n_faults_active >= 1 clause makes the label's name literally true instead of an
    % inference (D2: 'measured, not inferred'), and -- deliberately -- leaves the SAME
    % symptom in a Healthy record as 'indeterminate', i.e. a hard Layer 1 failure. A Healthy
    % engine that cannot make 13 MW with no thermal reason is precisely the draft data's
    % spin-down defect: it must fail the gate, not acquire a label. Measured reference: Healthy
    % delivers 13.0000 MW at every ambient up to 23 degC and is cleanly temperature-limited
    % (S26 = 846.0 exactly) from 25 to 50 degC.
    if tail_near_limit
        attrs.operating_regime = 'temperature_limited';
    elseif duty_within_2pct
        attrs.operating_regime = 'duty_tracking';
    elseif attrs.controller_saturated_hi && n_faults_active >= 1
        attrs.operating_regime = 'fault_limited';
    else
        % No legitimate measured state fits -- record it and let Layer 1 FAIL the record
        % (ValidateGenerationLayer1.m). 'indeterminate' is never written to the release.
        attrs.operating_regime = 'indeterminate';
    end

    %% baseline window: samples strictly before the earliest fault onset (whole record if none)
    if isempty(fault_start_times)
        baseline_end_tau = N;
    else
        baseline_end_tau = max(1, min(N, floor(min(fault_start_times)) - 1));
    end
    attrs.baseline_end_tau = baseline_end_tau;

    %% drawn-vs-realised ambient check -- the defect class this
    % exists to catch: nothing in the pipeline previously compared the plant's realised
    % operating point against the ambient the record drew, so a 104 degC error (the severed
    % ambient line) passed QA Layer 1 as a benign duty_tracking record.
    %
    % Window: the LAST 180 stored samples of the pre-onset baseline -- one code path
    % for every record, faulted or not, because the baseline is fault-free by construction.
    % ValidatePipelineConfig Check 5 guarantees >=600 baseline samples, but assert rather than
    % trust it: if baseline_end_tau < 180, use the whole baseline and record the realised length.
    AMBIENT_CHECK_WIN = 180;
    window_n = min(AMBIENT_CHECK_WIN, baseline_end_tau);
    window_idx = (baseline_end_tau - window_n + 1):baseline_end_tau;
    attrs.ambient_check_window_n = window_n;

    % T_eff: constant drawn_temp_C unless within-record trend is active.
    % As of 2026-10-17 has not shipped (ambient_trend_amplitude_C is always NaN in
    % production -- LoadScenarioToWorkspace.m), so this branch is inert; it is wired here, per
    % spec, so landing later needs no change to this function, only to its caller.
    if isnan(ambient_trend_amplitude_C) || ambient_trend_amplitude_C == 0 || isnan(sim_duration_total)
        T_eff = drawn_temp_C;
    else
        t_mid_full = preroll_s + mean(time_vector(window_idx));
        T_eff = drawn_temp_C + ambient_trend_amplitude_C * (t_mid_full / sim_duration_total - 0.5);
    end

    try
        LIB = GetWarmStartLibrary();

        % the grid spans 8-52 degC and 95-103 kPa --
        % every legal draw (ScenarioConfig.AmbientConfig) is inside it. Clamp to the grid bounds
        % and ASSERT the clamp moved nothing by more than 1e-6: a larger clamp means a draw
        % outside AmbientConfig, which is itself a defect and must fail the record loudly (both
        % values in the message), not be silently absorbed by interp2's own extrapolation.
        T_lo = min(LIB.chk_inlet_temp_C);  T_hi = max(LIB.chk_inlet_temp_C);
        P_lo = min(LIB.chk_inlet_press_kPa); P_hi = max(LIB.chk_inlet_press_kPa);
        T_q = min(max(T_eff, T_lo), T_hi);
        P_q = min(max(drawn_press_kPa, P_lo), P_hi);
        if abs(T_q - T_eff) > 1e-6
            error('ComputeLayer1RecordAttributes:AmbientCheckTempOutsideGrid', ...
                'T_eff=%.4f degC outside the ambient-check grid [%.1f, %.1f] (clamped to %.4f)', ...
                T_eff, T_lo, T_hi, T_q);
        end
        if abs(P_q - drawn_press_kPa) > 1e-6
            error('ComputeLayer1RecordAttributes:AmbientCheckPressOutsideGrid', ...
                'drawn_press_kPa=%.4f kPa outside the ambient-check grid [%.1f, %.1f] (clamped to %.4f)', ...
                drawn_press_kPa, P_lo, P_hi, P_q);
        end

        % Bilinear: LIB.chk_S26_C/chk_S24_radps are [31 x P], rows = chk_inlet_temp_C, columns =
        % chk_inlet_press_kPa. interp2(X,Y,Z,...) wants X = column coords (pressure),
        % Y = row coords (temperature). No 'extrap' -- the clamp above already guarantees the
        % query is in-bounds, so an out-of-grid NaN from interp2 would mean this assert itself
        % has a bug, and that must surface as a hard failure too, not be masked by extrapolation.
        S26_expected = interp2(LIB.chk_inlet_press_kPa, LIB.chk_inlet_temp_C, LIB.chk_S26_C, ...
            P_q, T_q, 'linear');
        S24_expected = interp2(LIB.chk_inlet_press_kPa, LIB.chk_inlet_temp_C, LIB.chk_S24_radps, ...
            P_q, T_q, 'linear');
        baseline_S26_mean = mean(S26(window_idx));
        baseline_S24_mean = mean(sensors_clean(window_idx, 24));
        attrs.ambient_check_residual_C   = baseline_S26_mean - S26_expected;
        attrs.s24_library_offset_radps   = baseline_S24_mean - S24_expected;
    catch ME
        % The library must always be loadable in production (the .mat
        % ships with the pipeline) -- a load failure, a missing chk_* surface, or an out-of-grid
        % draw here is itself a defect worth surfacing, not a reason to silently skip the check.
        % Fail the record via NaN -> completeness check (ValidateGenerationLayer1.m).
        warning('ComputeLayer1RecordAttributes:AmbientCheckLibraryFailed', '%s', ME.message);
        attrs.ambient_check_residual_C = NaN;
        attrs.s24_library_offset_radps = NaN;
    end

    %% pt_speed_settled / steady_state_start_s — trailing-window linear-drift-vs-noise test
    % (repair 3: drift over the window must be smaller than the channel's
    % own measurement-noise sigma, not a fixed percent-to-asymptote band).
    try
        nm = GetSensorNoiseModel();
        sigma_s27 = nm.sigma_noise(27);
    catch
        sigma_s27 = NaN;  % noise model unavailable -- settled-ness cannot be assessed
    end
    win = 60;  % the benchmark window length sigma_window is itself defined over
    attrs.pt_speed_settled     = false;
    attrs.steady_state_start_s = NaN;
    if ~isnan(sigma_s27) && baseline_end_tau >= win
        for t0 = 1:(baseline_end_tau - win + 1)
            seg = S27(t0:t0+win-1);
            p = polyfit(time_vector(t0:t0+win-1), seg, 1);
            drift_over_window = abs(p(1)) * win;  % total drift across the window, same units as sigma
            if drift_over_window < sigma_s27
                attrs.pt_speed_settled     = true;
                attrs.steady_state_start_s = time_vector(t0);
                break;
            end
        end
        % Also check the window ending at baseline_end_tau -- the condition that actually
        % matters for "is the pre-onset baseline settled by the time the fault starts".
        if baseline_end_tau >= win
            seg = S27(baseline_end_tau-win+1:baseline_end_tau);
            p = polyfit(time_vector(baseline_end_tau-win+1:baseline_end_tau), seg, 1);
            attrs.pt_speed_settled = attrs.pt_speed_settled && (abs(p(1)) * win < sigma_s27);
        end
        % Keep the two attributes consistent: a record that is NOT settled must not also report
        % a steady-state start time.
        if ~attrs.pt_speed_settled
            attrs.steady_state_start_s = NaN;
        end
    end

    %% in_calibration_envelope — achieved load >= 45% of rated (companion paper's validated floor)
    % DELIBERATELY uses the literal RATED_MW (13), NOT RATED_MW_FOR_REGIME: this attribute means
    % percentage of the engine's physical 13 MW NAMEPLATE rating ("the companion
    % paper validated the twin over 45-100% of rated load"), a statement about the machine, not
    % about whichever duty happens to be commanded. Do not "fix" this to match the regime test
    % above -- that would be the wrong fix, confusing the two meanings this constant's name
    % always carried under one number only because made commanded duty = 13 MW too.
    attrs.in_calibration_envelope = (attrs.duty_achieved_MW / RATED_MW) >= 0.45;

end
