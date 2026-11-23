function labels = ComputeRTFUnitLabels(health_index, tail_S26_clean, limiter_active_fraction, mech)
% ComputeRTFUnitLabels - Derive a run-to-failure unit's per-cycle labels from its measured
% history. Pure post-processing math -- takes already-measured/already-accumulated per-cycle
% arrays and does NOT run or warm-start Simulink itself, so it is usable and testable ahead of
% RunRTFUnit.m/GenerateRTFFamily.m (-5.4).
%
% Inputs (each [C x 1], C = this unit's realised cycle count, the cycle the reference check
% tripped on):
%   health_index            - h(c), the latent damage variable in [0, ~1.5], already accumulated
%                              cycle-by-cycle elsewhere (the gamma process itself) -- this
%                              function does not generate it.
%   tail_S26_clean           - degC, this cycle's measured clean tail S26 (clean,
%                               never the indicated/stored channel).
%   limiter_active_fraction - [0,1], this cycle's measured fraction of the tail window with the
%                              846 degC limiter active.
%   mech                    - one row of GetRTFMechanisms's output: a scalar struct with
%                              .DeltaEOL and .PExponent for this mechanism.
%
% Output struct `labels`, all [C x 1] except the scalars noted:
%   severity_factor   - s_c
%   delta             - delta(c) = DeltaEOL * h(c)^PExponent (shaping map)
%   rul_cycles        - cycles_to_failure - c  (int; cycles_to_failure = C, the last row)
%   rul_seconds       - rul_cycles * ScenarioConfig.RTF_CYCLE_SECONDS
%   cycles_to_failure - scalar, == C
%   h_at_termination  - scalar, == health_index(end)
%

    health_index              = health_index(:);
    tail_S26_clean            = tail_S26_clean(:);
    limiter_active_fraction   = limiter_active_fraction(:);

    C = numel(health_index);
    if numel(tail_S26_clean) ~= C || numel(limiter_active_fraction) ~= C
        error('ComputeRTFUnitLabels: health_index, tail_S26_clean and limiter_active_fraction must be the same length.');
    end
    if C < 1
        error('ComputeRTFUnitLabels: need at least one cycle.');
    end

    % s_c = 2^((S26_tail_c - S26_ref)/T_DOUBLING) * (1 + BETA_LIMITER*limiter_active_fraction_c)
    severity_factor = 2 .^ ((tail_S26_clean - ScenarioConfig.RTF_S26_REF_C) / ScenarioConfig.RTF_T_DOUBLING_C) ...
                       .* (1 + ScenarioConfig.RTF_BETA_LIMITER * limiter_active_fraction);

    % delta(c) = delta_EOL * h(c)^p
    delta = mech.DeltaEOL * (health_index .^ mech.PExponent);

    cycles_to_failure = C;
    rul_cycles  = cycles_to_failure - (1:C)';
    rul_seconds = rul_cycles * ScenarioConfig.RTF_CYCLE_SECONDS;

    labels = struct();
    labels.severity_factor   = severity_factor;
    labels.delta              = delta;
    labels.rul_cycles         = rul_cycles;
    labels.rul_seconds        = rul_seconds;
    labels.cycles_to_failure  = cycles_to_failure;
    labels.h_at_termination   = health_index(end);

end
