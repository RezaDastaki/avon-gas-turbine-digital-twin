function state = RestoreRTFUnitState(unit_file, refcheck_file, mech, scenario_hash, unit_id, noise_seed)
% RestoreRTFUnitState - Rebuild, from a stored run-to-failure unit file, every piece of state
% RunRTFUnit.m carries from one cycle to the next, so the unit can be CONTINUED from the cycle
% after its last stored one and come out bit-identical to the same unit run fresh (P6R, R3/R5).
% Used for units that were right-censored at a cycle cap.
%
% Nothing here is estimated: each value is either read back exactly (HDF5 stores the same doubles
% and singles the writer was given) or recomputed by the same code path the live loop uses. The
% restore then CHECKS itself, and errors rather than hand back a state that does not reproduce
% the file:
%   * w0 and gamma_scale are re-derived from the unit's seeds and must equal the stored
%     initial_wear and gamma_scale attributes (so the file really is this unit under the current
%     seed formulas);
%   * every stored cycle's clean tail S26 is rebuilt (below) and the severity factor and delta
%     recomputed from it by ComputeRTFUnitLabels must equal the stored arrays exactly;
%   * the whole stored health trajectory is replayed: h(c+1) must equal h(c) plus that cycle's
%     RTFGammaIncrement, for every cycle -- proof the accumulator's randomness is a function of
%     (unit, cycle) alone.
%
% CROSS-CYCLE STATE IN RunRTFUnit.m, AND HOW EACH PIECE IS RESTORED (R5)
%   h_c                      replay: stored health_index(C) + RTFGammaIncrement(cycle C), using
%                            the stored gamma_scale and the stored severity_factor(C)
%   lambda_u, w0             stored attributes gamma_scale (used as is) and initial_wear; the
%                            seed re-derivation above is the consistency check
%   h_hist, delta            /health_index, /delta
%   mult_c                   not carried -- recomputed each cycle from h_c
%   tailS26_hist             rebuilt: stored /ambient_check_absolute_C(c) plus the library surface
%                            at cycle c's stored ambient. abs = tail - surface and both lie within
%                            a factor of two of each other, so by Sterbenz's lemma the
%                            subtraction was exact and the addition returns the original tail
%                            bit for bit; checked through the severity factor (above)
%   limiterFrac_hist, dutyMW_hist, regimeCode_hist, ambient_hist,
%   ambientCheckResidual_hist, ambientCheckAbsolute_hist
%                            the stored per-cycle datasets of the same names
%   sensors_noisy_all, true_values_all
%                            /sensors + /internal re-interleaved by ScenarioConfig.RTF_*_IDX, and
%                            /true_values (singles, as stored)
%   true_value_present       stored attribute true_value_tap_present
%   prev_tail_S26_clean, prev_ambient_check_T_q / _P_q, prev_operating_regime_code
%                            the last stored cycle's rebuilt tail S26, its stored ambient clamped
%                            to the surface grid, and its stored regime code
%   consec_breach_count/_sign  replay of the stored residuals and regime codes through
%                            RTFAmbientBreach + RTFAdvanceStreak, the rule the live loop uses
%   reference-check cadence  stateless -- a function of h_c_next and c (RunRTFUnit.m step 9)
%   ref_rows                 the refchecks CSV rows up to the last stored cycle (a crash between
%                            the CSV and the HDF5 replace can leave extra rows behind; they are
%                            dropped)
%   noise/bias/calibration seeds, RNG streams
%                            re-derived from the unit's seed formulas; no generator state is
%                            stored or needed (RTFGammaIncrement.m)
%
% Output: struct with C0 (cycles already stored), h_c, the *_hist arrays, the single-precision
% sensor and true-value blocks, true_value_present, the prev_* bookkeeping, the streak, ref_rows,
% w0 and gamma_scale.
%

    ra = @(name) h5readatt(unit_file, '/', name);

    C0 = double(ra('cycles_to_failure'));
    w0 = double(ra('initial_wear'));
    gamma_scale = double(ra('gamma_scale'));

    health_index = double(h5read(unit_file, '/health_index'));
    delta_stored = double(h5read(unit_file, '/delta'));
    sev_stored   = double(h5read(unit_file, '/severity_factor'));
    state.dutyMW_hist      = double(h5read(unit_file, '/duty_achieved_MW'));
    state.limiterFrac_hist = double(h5read(unit_file, '/limiter_active_fraction'));
    state.regimeCode_hist  = double(h5read(unit_file, '/operating_regime_code'));
    state.ambient_hist     = double(h5read(unit_file, '/ambient'));
    state.ambientCheckResidual_hist = double(h5read(unit_file, '/ambient_check_residual_C'));
    state.ambientCheckAbsolute_hist = double(h5read(unit_file, '/ambient_check_absolute_C'));
    sensors_stored  = h5read(unit_file, '/sensors');
    internal_stored = h5read(unit_file, '/internal');
    true_stored     = h5read(unit_file, '/true_values');

    n = ScenarioConfig.RTF_CYCLE_SECONDS;
    if size(sensors_stored, 1) ~= n * C0 || size(internal_stored, 1) ~= n * C0 || size(true_stored, 1) ~= n * C0 ...
            || numel(health_index) ~= C0 || size(state.ambient_hist, 1) ~= C0
        error('RestoreRTFUnitState:ShapeMismatch', '%s: stored array sizes disagree with cycles_to_failure = %d.', unit_file, C0);
    end

    %% The file must be THIS unit under the CURRENT seed formulas
    [w0_re, lambda_re] = RTFUnitDraws(scenario_hash, unit_id);
    if w0_re ~= w0 || ScenarioConfig.RTF_ACCUM_THETA0 * lambda_re ~= gamma_scale
        error('RestoreRTFUnitState:SeedMismatch', ...
            '%s: stored initial_wear/gamma_scale do not match what unit %d''s seeds produce now.', unit_file, unit_id);
    end

    %% Clean tail S26 per cycle, then the labels recomputed from it must equal the stored ones
    LIB = GetWarmStartLibrary();
    tail_S26 = zeros(C0, 1);
    T_q = 0; P_q = 0;
    for c = 1:C0
        [S26_expected, T_q, P_q] = RTFExpectedTailS26(LIB, state.ambient_hist(c, 3), state.ambient_hist(c, 4));
        tail_S26(c) = state.ambientCheckAbsolute_hist(c) + S26_expected;
    end
    labels = ComputeRTFUnitLabels(health_index, tail_S26, state.limiterFrac_hist, mech);
    if ~isequal(labels.severity_factor, sev_stored) || ~isequal(labels.delta, delta_stored)
        error('RestoreRTFUnitState:LabelMismatch', ...
            '%s: rebuilt tail S26 does not reproduce the stored severity_factor/delta exactly.', unit_file);
    end

    %% Replay the accumulator over the whole stored trajectory
    n_channels = size(sensors_stored, 2) + size(internal_stored, 2);
    h_next = zeros(C0, 1);
    for c = 1:C0
        inc = RTFGammaIncrement(noise_seed + c * 104729, [n, n_channels], gamma_scale, sev_stored(c));
        h_next(c) = health_index(c) + inc;
    end
    if ~isequal(h_next(1:end-1), health_index(2:end))
        error('RestoreRTFUnitState:AccumulatorReplayMismatch', ...
            '%s: replaying the gamma increments does not reproduce the stored health_index.', unit_file);
    end
    if health_index(1) ~= w0
        error('RestoreRTFUnitState:AccumulatorReplayMismatch', '%s: health_index(1) is not initial_wear.', unit_file);
    end
    state.h_c = h_next(end);   % h AFTER the last stored cycle's increment: cycle C0+1's h_c

    %% Per-cycle bookkeeping
    state.C0 = C0;
    state.h_hist = health_index;
    state.tailS26_hist = tail_S26;
    state.prev_tail_S26_clean = tail_S26(end);
    state.prev_ambient_check_T_q = T_q;
    state.prev_ambient_check_P_q = P_q;
    state.prev_operating_regime_code = state.regimeCode_hist(end);

    count = 0; sgn = 0;
    for c = 1:C0
        prev_code = NaN;
        if c > 1, prev_code = state.regimeCode_hist(c - 1); end
        breach = RTFAmbientBreach(c, state.ambientCheckResidual_hist(c), state.regimeCode_hist(c), prev_code);
        [count, sgn] = RTFAdvanceStreak(breach, state.ambientCheckResidual_hist(c), count, sgn);
    end
    state.consec_breach_count = count;
    state.consec_breach_sign = sgn;

    %% Channel blocks, in the writer's [300*C x 39] order, as singles
    sens = zeros(n * C0, n_channels, 'single');
    sens(:, ScenarioConfig.RTF_SENSORS_IDX)  = sensors_stored;
    sens(:, ScenarioConfig.RTF_INTERNAL_IDX) = internal_stored;
    state.sensors_noisy_all = sens;
    state.true_values_all = true_stored;
    state.true_value_present = double(ra('true_value_tap_present'));
    state.w0 = w0;
    state.gamma_scale = gamma_scale;

    %% Reference-check log
    state.ref_rows = {};
    if isfile(refcheck_file)
        opts = detectImportOptions(refcheck_file);
        opts = setvartype(opts, 'failure_mode', 'char');
        T = readtable(refcheck_file, opts);
        T = T(T.cycle <= C0, :);
        for i = 1:height(T)
            mode = T.failure_mode{i};
            if isempty(mode), mode = ''; end
            state.ref_rows(end+1, :) = {T.cycle(i), T.h(i), logical(T.tripped(i)), char(mode), T.ref_S26(i), T.ref_duty_MW(i)}; %#ok<AGROW>
        end
    end
end
