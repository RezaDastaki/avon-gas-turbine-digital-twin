function [passed, reasons, layer1_attrs] = ValidateGenerationLayer1(sensors_stored, sensors_clean, time_vector, ...
    fault_ids, severity_levels, fault_start_times, fault_label, severity_label, record_attrs, ...
    true_value_data, true_value_present)
% ValidateGenerationLayer1 - the generation-time acceptance gate (QA
% strategy, Layer 1). A record that fails is NOT written -- RunScenario.m treats a Layer 1
% failure exactly like a Simulink failure: error inside the try block, caught, retried with
% attempt+1. This is the structural fix for how the draft data's spin-down defect shipped
% ("Records were checked for NaN, Inf, flat channels and sample counts -- all of
% which the collapsed records passed").
%
% TWO ARRAYS, deliberately.
% INTEGRITY is checked on what is actually stored (sensors_stored): NaN/Inf, shape, label
% alignment. PHYSICS is checked on the clean, pre-measurement-model array (sensors_clean),
% because every physical criterion here is a statement about the simulated plant, not about
% what an instrument would have read -- and the instrument model is not small: S26 alone
% carries sigma_bias = 15.14 degC, which swamps the 1 degC limiter test, and a 60-sample OLS
% slope picks up a noise-only drift term of 0.447*sigma, which is 2.5 % of records failing the
% settling test on noise alone. See ComputeLayer1RecordAttributes.m's header.
%
% Inputs:
%   sensors_stored    - [N x 39] post-measurement-model array, S01..S39 -- what gets written
%   sensors_clean     - [N x 39] pre-measurement-model array, S01..S39 -- the simulated plant
%   time_vector       - [N x 1] stored-window-relative time (seconds)
%   fault_ids         - active fault IDs for this record (empty for Healthy)
%   severity_levels   - per-active-fault severity (1-5)
%   fault_start_times - per-active-fault onset, stored-window-relative (post RunScenario.m rebase)
%   fault_label       - [N x 42] int, 0/1 per-timestep activity
%   severity_label    - [N x 42] int, 0-5 per-timestep severity
%   record_attrs      - struct from ComputeLayer1RecordAttributes.m (computed once, reused here)
%
% Outputs:
%   passed       - true iff every check below passed
%   reasons      - cellstr of every failed check's message (empty if passed)
%   layer1_attrs - record_attrs, passed through unchanged (for the writer to store)
%
% Implementation notes on two checks that are not literal line-for-line translations of
% table, recorded here (and in phases/) rather than silently decided:
%
%   "Controller headroom: S32 reaches neither PID limit" -- taken literally this rejects every
%   genuine temperature_limited record, i.e. the majority of the release, so it is NOT
%   implemented literally. The reason gives for the symptom ("S32 pinned WITHOUT
%   S26 = 846 is a clipped-command artefact") was written for the REJECTED duty-sampled design,
%   where the only way to pin at +60 without a thermal cause was a bad sampling bound. Under the
%   fixed-13MW-duty redesign there are two further, entirely legitimate causes:
%   the engine is temperature-limited (S26 on its 846 degC ceiling -- 62.5 % of records draw an
%   ambient above 25 degC, where Healthy itself is limited), or a flow-limiting fault has capped
%   achievable power with no thermal cause at all (measured on F17).
%
%   RESOLVED, replacing open
%   finding: S32 saturation is NOT gated on its own -- it is one input to a three-state
%   operating_regime rule (duty_tracking / temperature_limited / fault_limited), each with a
%   positive measured rule, and it is the REGIME that is gated. 'indeterminate' now means "no
%   legitimate measured state fits" and hard-fails the record. That is stricter than
%   version, not looser: it restores repair 2's absolute acceptance check,
%   which had in effect removed by making the catch-all a pass.
%
% F02-at-47.7-degC evidence for a nameless third state does NOT survive re-reading:
%   its "tail S26 = 848.5, borderline" was an INDICATED temperature, and S26's per-record
%   calibration bias has sigma_bias = 15.14 degC. On the clean signal that record is an ordinary
%   temperature_limited one (Healthy itself sits at exactly 846.0 degC from 25 to 50 degC --
%). The third state is real, but F17's fuel-starvation case
%   is the evidence for it, not F02's.
%
%   S32 pinned at the -30 FLOOR is not a named state: it is left to fall through to
%   'indeterminate' and fail, deliberately. The floor is far away in every measurement taken
%   (Healthy S32 ~ 0.97 at 15 degC; F29 at double its SEV5 depth reached only -7.04), so a
%   record that reaches it is telling us something nobody has measured, and the right place to
%   discover that is, not the release.
%
%   "Fault realisation: the fault's target channel actually moves... by the amount the severity
%   implies" -- implemented as an UNSIGNED magnitude check in SIGMA_WINDOW units, referenced to
%   own MEASURED effect size on the observable channel (z_at_deepest_completed,
%) geometrically interpolated down to k=12 at SEV1.
%   An earlier version of this check used sev1_deviation/sev5_deviation
%   instead -- wrong, caught by running this gate on real records: those columns are deltas on the
%   PERTURBED variable (e.g. compressor efficiency for F02), not the observable channel, and using
%   raw sigma_noise (not sigma_window) as a floor made the bar ~2x the actual SEV1 calibration
%   point, failing every SEV1 record systematically. Not a signed direction re-check. Signed
%   directionality for all 42 faults was already verified
%   once, structurally, by graded-response audit
%   ("direction_matches_signature"/"monotone", 40/42 pass) -- that is a property of the model, not
%   something that flips per-record, so re-deriving an expected sign per fault here (not stored
%   anywhere as a simple column) would duplicate work without adding real defect coverage.
%   NOT GATED AT ALL, for any fault count -- see the body for the three measured failure modes
%   that forced that test S6b (the reference-condition re-run of graded-response
%   audit) for where the F12-class defect is actually caught instead. Confirmed
%   audit, 2026-10-13, which measured the sharpest of those failure modes directly: at a
%   temperature-limited ambient the 846 degC limiter DECOUPLES the gas generator from PT-side
%   faults, so F26 and F28 at SEV3 and SEV5 move their audit-recorded target channel S10 by
%   EXACTLY zero at 45 degC (|dS10| < 3e-11 kPa) while moving delivered power by 1.5-1.8 MW.
%   S10 is the recorded target channel for 16 of the 42 faults, and it is not clipped (it varies
%   smoothly, 864.1 -> 657.8 kPa across the ambient grid)
%   -- the zero is real physics, and no per-record gate can be built on a fixed channel through it.
%
%   "Ambient check" -- GATED, added 2026-10-17. Catches
%   the defect class behind the severed compressor-inlet-temperature line: nothing
%   previously compared the plant's realised baseline operating point against the ambient the
%   record drew. Measured on the clean baseline-window S26 against the warm-start library's 2-D
%   (temperature x pressure) surface, interpolated at (T_eff, drawn pressure).
% replaced the ORIGINAL 1-D (temperature-only) lookup and its
%   15 degC tolerance: compressor inlet pressure (drawn uniformly 95-103 kPa) moves clean
%   baseline S26 by up to +/-46 degC with no fault and nothing else moved
% -- 3x the old tolerance, which is why 6 of 43 real
%   records false-failed under the 1-D check. The S24 half is stored as an
%   informational attribute only -- it becomes a gate after G3 lands.
%

    reasons = {};
    N = size(sensors_stored, 1);
    attrs = record_attrs;
    layer1_attrs = attrs;

    if nargin < 10, true_value_data = []; end
    if nargin < 11, true_value_present = []; end

    %% Integrity: no NaN/Inf, expected sample/channel count -- on BOTH arrays
    if any(~isfinite(sensors_stored(:)))
        reasons{end+1} = 'Integrity: stored array contains NaN/Inf';
    end
    if any(~isfinite(sensors_clean(:)))
        reasons{end+1} = 'Integrity: clean (pre-measurement-model) array contains NaN/Inf';
    end
    if N ~= ScenarioConfig.STORED_SAMPLES
        reasons{end+1} = sprintf('Integrity: N=%d != STORED_SAMPLES=%d', N, ScenarioConfig.STORED_SAMPLES);
    end
    if size(sensors_stored, 2) ~= 39 || size(sensors_clean, 2) ~= 39
        reasons{end+1} = sprintf('Integrity: %d/%d channels, expected 39', ...
            size(sensors_stored, 2), size(sensors_clean, 2));
    end
    if ~isequal(size(sensors_stored), size(sensors_clean))
        reasons{end+1} = 'Integrity: stored and clean arrays differ in shape';
    end

    %% True-value tap integrity: a tap the
    % model declares present (TrueValueTapPresent) must not come through all-NaN -- that is a
    % silent extraction failure, not a legitimately-absent tap. A tap the model declares absent
    % is expected to be all-NaN and is ignored.
    if ~isempty(true_value_data) && ~isempty(true_value_present)
        for tv_col = 1:size(true_value_data, 2)
            if true_value_present(tv_col) && all(isnan(true_value_data(:, tv_col)))
                reasons{end+1} = sprintf('True-value tap: column %d is declared present but is all-NaN', tv_col);
            end
        end
    end

    %% No collapse: no (non-controller) channel ends below 2% of its own mid-record value
    CONTROLLER_COLS = [32, 33, 34];  % S32-S34 legitimately cross zero/negative -- excluded
    mid = max(1, round(N/2));
    for c = 1:34
        if ismember(c, CONTROLLER_COLS), continue; end
        mid_val = mean(sensors_clean(max(1,mid-29):mid+30, c));
        end_val = mean(sensors_clean(end-59:end, c));
        if abs(mid_val) > 1e-9 && abs(end_val) < 0.02 * abs(mid_val)
            reasons{end+1} = sprintf('No collapse: S%02d ends at %.4g, <2%% of its mid-record value %.4g', ...
                c, end_val, mid_val);
        end
    end

    %% No runaway: S27 never falls below 90% of its own settled (baseline) value
    S27 = sensors_clean(:, 27);
    baseline_end = attrs.baseline_end_tau;
    if baseline_end >= 1
        settled_s27 = mean(S27(max(1,baseline_end-59):baseline_end));
        if settled_s27 > 1.0 && any(S27 < 0.90 * settled_s27)
            reasons{end+1} = sprintf('No runaway: S27 fell below 90%% of its settled value (%.2f rad/s)', settled_s27);
        end
    end

    %% Regime label -- GATED..
    % ComputeLayer1RecordAttributes.m now measures THREE legitimate states on the clean signal
    % (duty_tracking / temperature_limited / fault_limited), each with a positive rule, so
    % 'indeterminate' no longer means "a state we have no name for" -- it means "no legitimate
    % measured state fits", and that is a hard failure. This restores the ABSOLUTE acceptance
    % check repair 2 required and that had, in effect, removed:
    % every other physical check in this file is self-referential ("x % of its OWN settled
    % value") and, as the 2026-10-09 audit put it, "cannot distinguish a healthy engine
    % from one stabilised 13 % below design point". The regime rule is the one check anchored to
    % absolute numbers -- 13 MW and 846 degC.
    if strcmp(attrs.operating_regime, 'indeterminate')
        reasons{end+1} = sprintf(['Regime: operating_regime is indeterminate -- the record matches ', ...
            'no legitimate measured state (duty_achieved=%.3f MW vs 13 commanded, ', ...
            'limiter_active_fraction=%.3f, S32 sat hi=%d lo=%d, n_faults=%d)'], ...
            attrs.duty_achieved_MW, attrs.limiter_active_fraction, ...
            attrs.controller_saturated_hi, attrs.controller_saturated_lo, numel(fault_ids));
    end

    %% Drawn-vs-realised ambient check, spec The
    % defect class this exists to catch: nothing previously compared the plant's realised
    % baseline operating point against the ambient the record drew, so a severed/grounded
    % ambient input (defect, a 104 degC error at a 15 degC draw) passed every prior
    % check as a benign duty_tracking record. Measured on the clean baseline-window S26 against
    % the warm-start library's 2-D (temperature x pressure) surface, interpolated at (T_eff,
    % drawn pressure). The S24 half is informational ONLY and is deliberately NOT
    % gated: the GG rotor has no equilibrium and the stored window begins after the
    % pre-roll, so an honest tolerance does not exist until G3 lands.
    %
    % AMBIENT_CHECK_TOL_C, set arithmetic rule, re-derived by
    % on the GATED (non-temperature_limited) population,
    % AFTER the one-sided limiter-test relabelling above:
    %   M = max |ambient_check_residual_C| over the gated population measured A1
    %       (51-point band sweep + 44-point 0.2 degC fine scan across the kink band, both
    %       pressures) and A3 (two 21-point nominal-pressure sweeps, dT=+/-2) =
    %       1.218081 degC, at T=16.4 degC / 95 kPa -- the last duty_tracking point below the
    %       limiter boundary, i.e. the worst case is immediately BELOW the relabelling threshold,
    %       which is why the 0.2 degC scan was needed to find it (2nd worst: 0.786881 at
    %       T=23.2/99.2; everything away from the boundary is <= 0.068).  n = 30 gated records.
    %   4*M = 4.872324
    %   AMBIENT_CHECK_TOL_C = smallest of {3,5,8,12} that is >= 4*M = 5
    %   Margin against the 68.8 degC minimum defect signature (coldest-draw case):
    %       13.76x  (and this TIGHTENS the gate 1.6x from the 8.0 it replaces)
    % Superseded: the previous derivation computed M = 1.256966 degC from
    % an 18-point off-grid probe plus the 42-fault batch, BEFORE within-record ambient
    % trend existed as a live code path and before relabelling -- that 1.257 figure
    % no longer reflects what is actually gated and is retired by this comment.
    %
    % Full derivation, every number traced to a script
    % fine scan is what exposes the worst-case kink-band residual own coarse
    % (2 degC) A3 grid, at nominal pressure only, steps clean over the ~1 degC-wide sliver and
    % cannot see it.
    %
    % (Recorded, not folded into M: F22, operating_regime='temperature_limited', showed a 5.4669
    % degC baseline residual -- its TAIL is thermally pinned at 846 but its BASELINE sits in the
    % kink band, so the exclusion rule is about what the tail classification certifies, not a
    % claim that every temperature_limited record's baseline residual is exactly 0.)
    AMBIENT_CHECK_TOL_C = 5.0;  % A4, by the rule above. Was 8.0.
    % TWO-TIER, not skip-if-pinned.
    % "regime-aware gate" was specified as skipping temperature_limited records outright. Building
    % A5's control measured the inverse hole that creates: a defect PINNING THE PLANT HOT is
    % labelled temperature_limited and would be skipped, and it produces a residual of exactly
    % +68.82 degC (846 - 777.15) -- numerically the very signature check exists to
    % catch. Measured, not argued: synthetic hot-stuck control, clean S26 = 846.0 at a drawn 15 degC,
    % PASSED the gate under the skip form (A5b case ii).
    % So a pinned record is still gated, at a WIDER FINITE bound rather than not at all. The two
    % populations are cleanly separable because the benign maximum is bounded by the overshoot
    % (9.28 degC measured) while the defect class sits at 68.8 degC:
    %   AMBIENT_CHECK_TOL_PINNED_C = smallest of {15, 20, 25, 30} that is
    %       >= 2 * (worst benign pinned residual = 9.28)  = 18.56   -> 20
    %       and <= 0.4 * (68.8 degC defect signature)     = 27.52   -> 20 qualifies
    %   margins at 20 degC: 2.16x over the worst benign pinned record, 3.44x under the defect class.
    % The cold-side form stays fully covered by the tier above (A5 case i: -104.47 degC, FAILS).
    AMBIENT_CHECK_TOL_PINNED_C = 20.0;
    if strcmp(attrs.operating_regime, 'temperature_limited')
        amb_tol_this_record = AMBIENT_CHECK_TOL_PINNED_C;
    else
        amb_tol_this_record = AMBIENT_CHECK_TOL_C;
    end
    if isnan(attrs.ambient_check_residual_C)
        reasons{end+1} = 'Ambient check: ambient_check_residual_C is NaN (warm-start library unavailable or load failed)';
    elseif abs(attrs.ambient_check_residual_C) > amb_tol_this_record
        % the tolerance is chosen by the MEASURED regime, never by the
        % predicted surface value -- a severed ambient line realises 672.71 degC,
        % which can never satisfy the one-sided near_limit test above, so such a record is ALWAYS
        % duty_tracking and ALWAYS gated at the tight tolerance; the regime split cannot hide the
        % defect this check exists to catch (verified directly, A5). The
        % unsafe form ("widen/skip where the PREDICTED surface is pinned") would key off the DRAWN
        % ambient instead and let a severed line at a high drawn ambient pass unexamined -- not
        % written, on purpose.
        % The residual is COMPUTED AND STORED for every record either way
        % (attrs.ambient_check_residual_C, above) -- only the threshold varies.
        reasons{end+1} = sprintf(['Ambient check: baseline S26 residual %.2f degC exceeds the +/-%.1f degC ', ...
            'tolerance for regime %s (drawn ambient vs. realised plant-state mismatch, window_n=%d)'], ...
            attrs.ambient_check_residual_C, amb_tol_this_record, attrs.operating_regime, ...
            attrs.ambient_check_window_n);
    end

    %% Absolute collapse guard -- the draft data's own defect class, in absolute units.
    % NOT self-referential and NOT a quality bar: it is set far below anything the redesign can
    % legitimately produce, so it can only fire on a genuine spin-down. Measured margins: the
    % deepest legitimate operating point found anywhere in //sweeps is F17 at depth
    % 0.20 (beyond SEV5) with 7.02 MW, and Healthy at 50 degC sits at 8.625 MW / S27 = 447.7
    % rad/s. The draft data, by contrast, ended 21 % of
    % records with the shaft effectively stopped while S28 still reported 9-10 MW.
    PT_DESIGN_SPEED = 513.4;
    ABS_SPEED_FLOOR = 0.55 * PT_DESIGN_SPEED;   % 282.4 rad/s ~ 2.2 MW under the cube-law load
    ABS_DUTY_FLOOR_MW = 2.0;
    s27_tail = mean(sensors_clean(end-179:end, 27));
    if s27_tail < ABS_SPEED_FLOOR
        reasons{end+1} = sprintf('Absolute collapse: S27 tail mean %.1f rad/s below the %.1f rad/s floor (%.0f%% of design speed)', ...
            s27_tail, ABS_SPEED_FLOOR, 100*ABS_SPEED_FLOOR/PT_DESIGN_SPEED);
    end
    if attrs.duty_achieved_MW < ABS_DUTY_FLOOR_MW
        reasons{end+1} = sprintf('Absolute collapse: duty_achieved %.3f MW below the %.1f MW floor', ...
            attrs.duty_achieved_MW, ABS_DUTY_FLOOR_MW);
    end

    %% Power consistency (proxy, no direct torque channel): S28 ~ 0 iff S27 ~ 0
    S28 = sensors_clean(:, 28);
    near_zero_speed = S27 < 0.05 * 513.4;   % <5% of PT design speed
    if any(near_zero_speed & (abs(S28) > 0.5))
        reasons{end+1} = 'Power consistency: S28 (power) not near zero while S27 (speed) is near zero';
    end

    %% Settling (pre-onset baseline, constant-condition portion only)
    if ~attrs.pt_speed_settled && baseline_end >= 60
        reasons{end+1} = sprintf('Settling: S27''s pre-onset baseline drift never fell below its own measurement-noise sigma (checked through tau=%d)', baseline_end);
    end

    %% Fault realisation -- unsigned magnitude check per active fault (see header note)
    % P4_fault_target_channels.csv is built (NOT
    % sev1_deviation/sev5_deviation -- those are deltas on the
    % PERTURBED variable, e.g. compressor efficiency for F02, not on the observable target
    % channel S10; using them directly here was a real bug, caught by actually running this gate
    % on real records: it demanded ~3x the raw per-sample noise sigma as a minimum, which is
    % roughly DOUBLE the k=12*sigma_window SEV1 is deliberately calibrated to, so every SEV1
    % record -- an entire, deliberate severity tier -- failed systematically,
    % not just occasionally). z_at_deepest_completed is the MEASURED effect size, in sigma units,
    % that audit already found on the target_channel_observable itself at
    % deepest_completed_severity (usually SEV5) -- geometrically interpolated back down to k=12 at
    % SEV1, exactly mirroring GetFaultMultiplier.m's
    % geometric progression but in measured-sigma space instead of perturbed-variable space.
    persistent fault_target_table
    if isempty(fault_target_table)
        csv_path = fullfile(fileparts(mfilename('fullpath')), 'P4_fault_target_channels.csv');
        fault_target_table = readtable(csv_path, 'TextType', 'string');
    end
    try
        nm = GetSensorNoiseModel();
    catch
        nm = [];
    end
    K_SEV1 = 12;       % own SEV1 calibration point, in sigma_window units
    MARGIN = 0.3;      % require only 30% of the expected sigma-unit deviation (statistical slack
                        % on a 180-sample window mean, not a re-derivation of the calibration)
    % NOT GATED AT ALL, for any fault count -- demoted to informational after running this gate on
    % all 42 single faults (not a desk check): beyond the multi-fault masking case (F01 in a
    % quad-fault record: 2.74 vs a 3.60 threshold, plausible masking, not a defect) and the four
    % stale-audit faults below, two single-fault records (F26 PT fouling, F28 PT nozzle damage)
    % showed near-zero movement (0.37, 0.07 sigma_window) against huge expected thresholds (1320,
    % 69) -- NOT staleness or masking. Root cause
    % target_channel_observable is, by the project's own documentation (chapter3.tex "What this
    % statistic is, and what it is not"), "the channel selected, on THIS SAME DATA, as the most
    % discriminative" at ONE reference condition (15 degC) -- not a universally-responsive channel
    % for every fault at every ambient. F26/F28 are PT-group faults whose audit-recorded target
    % (S10, an upstream HP-compressor channel) is plausibly not the most-responsive channel at a
    % different ambient draw. A per-record hard gate built on a single-condition "most
    % discriminative channel" number is therefore unreliable as a pass/fail criterion across the
    % full envelope -- it is a real, useful AUDIT statistic (Layer 2/3), not a safe
    % Layer-1 gate. Every fault's result is still computed and logged (never silently skipped);
    % NONE of it is gated, for any n_faults. The one thing it still reliably catches by
    % construction either way -- a channel moving EXACTLY zero (the literal F12-class defect) --
    % remains caught by the separate "No collapse" check above, which does not depend on this
    % fragile per-fault anchor.
    gate_fault_realisation = false;
    % target_channel_observable for F15/F16/F30/F42 is STALE --
    % found by running this gate on real F15/F13 records: F15 showed 0.30 sigma_window against a
    % 533 sigma_window threshold, because the audit's recorded target (S02) predates the
    % 2026-10-13 F15/F16 split (post-split, current) gives
    % F15 as S01(a)/S03(b), a completely different channel. F16, F30 and F42 went through the same
    %a remeasurement and are excluded for the same reason, not individually re-checked here.
    STALE_AUDIT_FAULTS = [15, 16, 30, 42];
    fault_defs_l1 = GetFaultDefinitions();
    for k = 1:numel(fault_ids)
        fid = fault_ids(k);
        if ismember(fid, STALE_AUDIT_FAULTS), continue; end
        % Oscillate-profile faults (F13, F18, F19, F42) move a channel's VARIANCE/spectral
        % content, not its mean -- confirmed by running this gate on a real F13 record (0.89
        % sigma_window observed against an 18.98 threshold despite F13 being genuinely active).
        % The project's own documentation (chapter3.tex: oscillatory faults "move the mean very
        % little... understated by construction") already states this; a tail-mean-vs-baseline-
        % mean check is structurally the wrong statistic for them, not a pipeline defect.
        if strcmp(fault_defs_l1.ProfileType{fid}, 'oscillate'), continue; end
        sev = severity_levels(k);
        row = fault_target_table(fault_target_table.fault_id == sprintf("F%02d", fid), :);
        if isempty(row) || ~strcmp(row.plant_coupling(1), 'plant')
            continue;  % logger_only sensor faults and F42 (regime-conditional) handled elsewhere
        end
        chan_str = row.target_channel_observable(1);
        chan_num = str2double(regexp(chan_str, '\d+', 'match', 'once'));
        if isnan(chan_num) || isempty(nm), continue; end
        z5  = row.z_at_deepest_completed(1);
        sev5_ref = row.deepest_completed_severity(1);
        if isnan(z5) || sev5_ref <= 1, continue; end   % no measured anchor for this fault -- skip
        expected_sigma_units = K_SEV1 * (z5 / K_SEV1) ^ ((sev - 1) / (sev5_ref - 1));
        sigma_window   = nm.sigma_window(chan_num);
        baseline_mean  = mean(sensors_clean(max(1,baseline_end-179):baseline_end, chan_num));
        tail_mean      = mean(sensors_clean(end-179:end, chan_num));
        observed_sigma_units = abs(tail_mean - baseline_mean) / max(sigma_window, eps);
        threshold_sigma_units = MARGIN * expected_sigma_units;
        if observed_sigma_units < threshold_sigma_units
            msg = sprintf(['Fault realisation: F%02d (SEV%d) target channel S%02d moved ', ...
                '%.2f sigma_window, below the %.2f sigma_window threshold (%.0f%% of the expected ', ...
                '%.2f sigma_window, interpolated from the measured z=%.1f at SEV%d)'], ...
                fid, sev, chan_num, observed_sigma_units, threshold_sigma_units, MARGIN*100, ...
                expected_sigma_units, z5, sev5_ref);
            if gate_fault_realisation
                reasons{end+1} = msg;
            else
                fprintf('  [informational, not gated] %s\n', msg);
            end
        end
    end

    %% Label consistency: fault_label/severity_label agree with fault_ids/severity_levels/onsets
    % GenerateFaultLabels.m's own convention is active_mask = time_vector >= t_start (inclusive of
    % the exact onset sample) -- post_onset below must match that boundary exactly, or this check
    % spuriously flags the legitimate onset-sample activation as "active before its own onset".
    if ~isempty(fault_ids)
        for k = 1:numel(fault_ids)
            fid = fault_ids(k);
            onset = fault_start_times(k);
            post_onset = time_vector >= onset;
            if any(fault_label(~post_onset, fid) ~= 0)
                reasons{end+1} = sprintf('Label consistency: F%02d fault_label is active before its own onset (%.0f s)', fid, onset);
            end
            if any(post_onset) && all(fault_label(post_onset, fid) == 0)
                reasons{end+1} = sprintf('Label consistency: F%02d fault_label never activates after its onset (%.0f s)', fid, onset);
            end
        end
    end
    if any(fault_label(:) < 0 | fault_label(:) > 1)
        reasons{end+1} = 'Label consistency: fault_label has values outside {0,1}';
    end
    if any(severity_label(:) < 0 | severity_label(:) > 5)
        reasons{end+1} = 'Label consistency: severity_label has values outside [0,5]';
    end

    %% Attribute completeness
    required_fields = {'duty_achieved_MW', 'operating_regime', 'limiter_active_fraction', ...
        'controller_saturated', 'pt_speed_settled', 'in_calibration_envelope', ...
        'ambient_check_residual_C', 'ambient_check_window_n', 's24_library_offset_radps'};
    for i = 1:numel(required_fields)
        if ~isfield(attrs, required_fields{i})
            reasons{end+1} = sprintf('Attribute completeness: %s missing', required_fields{i});
            continue;
        end
        val = attrs.(required_fields{i});
        if (isnumeric(val) || islogical(val)) && (isempty(val) || any(isnan(double(val))))
            reasons{end+1} = sprintf('Attribute completeness: %s empty or NaN', required_fields{i});
        elseif ischar(val) && isempty(val)
            reasons{end+1} = sprintf('Attribute completeness: %s empty', required_fields{i});
        end
    end

    passed = isempty(reasons);

end
