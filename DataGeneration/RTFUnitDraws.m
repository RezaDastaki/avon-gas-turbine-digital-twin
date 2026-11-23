function [w0, lambda_u] = RTFUnitDraws(scenario_hash, unit_id)
% RTFUnitDraws - The two once-per-unit draws of a run-to-failure unit: the initial wear
% w0 and the unit's gamma frailty lambda_u (E = 1). The ONLY uses of the stream seeded by
% RTF_ACCUM_SEED_BASE -- every later random number in a unit comes from a per-cycle seed (see
% RTFGammaIncrement.m) -- so a unit's accumulator is fully determined by this call plus its
% per-cycle seeds.
%
% Shared by RunRTFUnit.m (which draws them) and RestoreRTFUnitState.m (which re-derives them to
% confirm a stored file really is this unit before continuing it).
%

    rng(ScenarioConfig.RTF_ACCUM_SEED_BASE + scenario_hash + unit_id * 613, 'twister');
    w0 = rand() * ScenarioConfig.RTF_W0_MAX_FRAC;                              % latent units, D_EOL==1 by construction
    lambda_u = gamrnd(ScenarioConfig.RTF_ACCUM_KAPPA, 1/ScenarioConfig.RTF_ACCUM_KAPPA);   % per-unit frailty, E=1
end
