function inc = RTFGammaIncrement(noise_seed_c, noise_size, gamma_scale, s_c)
% RTFGammaIncrement - One cycle's increment of a run-to-failure unit's latent damage h
% (5.4): inc = gamrnd(k0, gamma_scale) * s_c, where gamma_scale = theta0 * lambda_u is the
% unit's own frailty-scaled scale and s_c is the cycle's measured severity factor.
%
% WHERE THE RANDOMNESS COMES FROM (P6R finding). RunRTFUnit.m seeds the global stream once per
% unit and uses it for w0 and lambda_u ONLY. Every cycle then re-seeds it (SampleEnvironmentMC,
% then ApplyMeasurementModel's calibration-age, bias and, last, noise seed), so by the time the
% increment is drawn the global stream sits exactly where ApplyMeasurementModel left it: seeded
% with this cycle's noise seed and advanced past one randn(300, 39) draw. The increment is
% therefore a pure function of (unit, cycle) and needs no saved generator state -- which is what
% lets a stored unit be continued, and a continued unit equal a fresh run, bit for bit.
%
% This function makes that dependency explicit instead of leaving it to the side effect of a
% neighbouring call: it re-seeds with the same seed, burns the same randn block, then draws. It
% produces the identical number (tested against 6,830 stored units' trajectories and by P6R's
% T1/T2), and RunRTFUnit.m and RestoreRTFUnitState.m both call it, so the fresh and the
% continued path cannot drift apart.
%
% Inputs:
%   noise_seed_c - this cycle's measurement-noise seed: NOISE_BASE_SEED + scenario_hash +
%                  unit_id*41 + c*104729 (the seed RunRTFUnit passes to ApplyMeasurementModel)
%   noise_size   - [rows cols] of the cycle's measurement array, i.e. of the randn block
%                  ApplyMeasurementModel draws ([300 39])
%   gamma_scale  - the unit's frailty-scaled gamma scale (stored root attribute gamma_scale)
%   s_c          - the cycle's severity factor
%

    rng(noise_seed_c, 'twister');
    randn(noise_size(1), noise_size(2));   % the noise block ApplyMeasurementModel consumes; value unused
    inc = gamrnd(ScenarioConfig.RTF_ACCUM_K0, gamma_scale) * s_c;
end
