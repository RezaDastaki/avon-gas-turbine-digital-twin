function [breach, tol] = RTFAmbientBreach(c, residual, regime_code, prev_regime_code)
% RTFAmbientBreach - Does one cycle's gated ambient-check residual breach its tolerance?
%. The PINNED tier applies when EITHER this cycle's OR the previous cycle's
% measured regime is temperature_limited (regime code 2), because a pinned cycle suppresses dS26
% on that side of the differential statistic; at cycle 1 there is no previous cycle. A NaN
% residual always counts as a breach. Selected on the MEASURED regime, never the predicted
% surface value (load-bearing distinction).
%
% Shared by RunRTFUnit.m (live) and RestoreRTFUnitState.m (which replays the stored residuals to
% rebuild the persistence streak a continued unit must carry), so the two apply one rule.
%

    pinned_tier = (regime_code == 2) || (c > 1 && prev_regime_code == 2);
    if pinned_tier
        tol = ScenarioConfig.RTF_AMBIENT_DIFF_TOL_PINNED_C;
    else
        tol = ScenarioConfig.RTF_AMBIENT_DIFF_TOL_C;
    end
    breach = isnan(residual) || (abs(residual) > tol);
end
