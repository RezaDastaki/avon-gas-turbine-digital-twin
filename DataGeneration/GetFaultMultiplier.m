function multiplier = GetFaultMultiplier(fault_id, severity_level)
% GetFaultMultiplier - Compute target multiplier for a given fault and severity
%
% Returns the peak (post-activation) multiplier used by GenerateFaultMultiplierArray
% to build the timeseries injected into Simulink. Also used by LoadScenarioToWorkspace
% for display logging.
%
% Formula (resolved 2026-10-13; the noise-referenced
% SEV1 rule, replacing the old linear/Factor formula):
%   delta_k      = Sev1Deviation * (Sev5Deviation/Sev1Deviation)^((k-1)/4),  k = severity_level
%   Degradation: multiplier = 1 - delta_k     Enhancement: multiplier = 1 + delta_k
%   F37 (sensor freeze): always returns 0.0 (< 0.5 triggers Switch+Memory freeze)
% Geometric, not linear: with SEV1 at the noise-referenced detection threshold and SEV5 one to two
% orders of magnitude above it, a linear ramp would waste most of the five levels above threshold.
% The 0.05 floor is REMOVED (C17 -- it never bound under the old formula and a silent clamp is
% worse than a multiplier going out of range and stopping the run); replaced with a hard error
% below. Sev1Deviation/Sev5Deviation per fault, and the full derivation,
%a sections.
%
% Inputs:
%   fault_id       - Fault ID (1-42)
%   severity_level - 0 (healthy) to 5 (maximum severity)
%
% Date: 2026-03-14 — Rebuilt for unified F01-F42 system

    if nargin < 2
        error('Both fault_id and severity_level are required');
    end
    if fault_id < 1 || fault_id > 42
        error('fault_id must be between 1 and 42. Got: %d', fault_id);
    end
    if severity_level < 0 || severity_level > 5
        error('severity_level must be between 0 and 5. Got: %d', severity_level);
    end

    % Healthy: no effect
    if severity_level == 0
        multiplier = 1.0;
        return;
    end

    % Special case: F37 — GG temp sensor freezing (Switch+Memory pattern)
    % The FAULT_37_multiplier Switch block uses threshold = 0.5:
    %   multiplier >= 0.5 → pass-through (normal reading)
    %   multiplier <  0.5 → frozen (last-known value held via Memory block)
    % Return 0.0 for any active severity to always trigger the freeze.
    if fault_id == 37
        multiplier = 0.0;
        return;
    end

    % Get fault definitions
    fault_defs = GetFaultDefinitions();
    delta1 = fault_defs.Sev1Deviation(fault_id);
    delta5 = fault_defs.Sev5Deviation(fault_id);

    % Geometric progression between the measured SEV1 (noise-referenced detection threshold) and
    % SEV5 (cutoff- or literature-anchored) deviations. severity_level=1 -> delta1 exactly;
    % severity_level=5 -> delta5 exactly.
    delta = delta1 * (delta5 / delta1) ^ ((severity_level - 1) / 4.0);

    if fault_defs.IsEnhancement(fault_id)
        multiplier = 1.0 + delta;
    else
        multiplier = 1.0 - delta;
        % No floor: a multiplier <= 0 can only arise from a bad band, and it must stop the
        % run, not be silently clamped.
        if multiplier <= 0
            error('GetFaultMultiplier:NonPositiveMultiplier', ...
                'Fault %d severity %d produced a non-positive multiplier (%.6f) -- bad Sev1/Sev5Deviation band.', ...
                fault_id, severity_level, multiplier);
        end
    end

end
