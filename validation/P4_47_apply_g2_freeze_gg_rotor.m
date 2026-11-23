function P4_47_apply_g2_freeze_gg_rotor(modelName)
% P4_47_APPLY_G2_FREEZE_GG_ROTOR - G3 mini-phase, G2 FALLBACK (the named fallback).
%
% G3 (the confined restoring term, P4_45_add_gg_restoring_term.m) was built, applied to a
% scratch copy and measured: G3-A1 FAILED. The settling test itself passed everywhere (every
% ambient reaches a true, flat equilibrium -- slope < 1e-4 rad/s/s), but the settled value misses
% omega_set(T) by far more than the 0.5 rad/s tolerance at 10 of 11 grid points:
%   -6.62 rad/s at 10C, -4.88 at 15C, ... +0.70 at 40C, +5.14 at 50C (only 35C, at -0.35, passes).
% Root cause, confirmed by direct signal instrumentation: the GG power residual
% (gen_turb - consm_comp) is NOT small -- it is the same -648..+504 kW range
% already measured, and it is essentially omega-independent (neither port depends on GG speed
% pre-G3). At equilibrium, Sum9=0 forces G*(omega-omega_set) = residual_kW, so
% offset = residual_kW/G = up to 6.6 rad/s at G=98 -- 13x the acceptance tolerance. G=98 was
% derived from the affinity-law time-constant construction, not from this balance, and
% no G large enough to hit 0.5 rad/s (G >~ 1300) would still give the tau~=10^3 s
% expects. This is exactly the failure mode the spec named in advance, not an invented judgement
% call: "if A2 fails, or A1 is not green in one sitting, fall back to G2."
%
% G2: ONE block parameter. 'Subsystem/GasGenerator/rotor dynamic '/J_rotor1 Gain: '1/60' -> '0'.
% domega/dt is then identically 0 -- S24 has NO DYNAMICS AT ALL, frozen at whatever IC
% SetWarmStartInitialConditions.m sets it to (already in place, untouched by this
% change). The G3 restoring-term network (Sum9's 3rd input, the Goto/From pair, the root
% Constant) is NOT built here -- G2 supersedes G3, it does not extend it.
%
% Discipline: build and verify on a scratch copy; apply to the production model
% only when A1-A4 are green.
%
% Usage: P4_47_apply_g2_freeze_gg_rotor('AvonGasTurbineDgTwin_fixed_G2test')   % scratch
%        P4_47_apply_g2_freeze_gg_rotor('AvonGasTurbineDgTwin_fixed')         % production, after A1-A4 green
%   (idempotent: if J_rotor1's Gain is already '0', reports and does nothing)

if nargin < 1 || isempty(modelName)
    modelName = 'AvonGasTurbineDgTwin_fixed';
end

cd(fileparts(fileparts(mfilename('fullpath'))));
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
mdlFile = ['Core/Models/' modelName];
load_system(mdlFile);
M = modelName;

sub = [M '/Subsystem/GasGenerator/rotor dynamic '];
jBlock = [sub '/J_rotor1'];

if ~strcmp(get_param(jBlock, 'BlockType'), 'Gain')
    error('P4_47:BlockChanged', 'Expected a Gain block at %s.', jBlock);
end
curGain = strtrim(get_param(jBlock, 'Gain'));
if strcmp(curGain, '0')
    fprintf('P4_47: %s Gain is already 0 on %s -- no change.\n', jBlock, M);
    return;
end
if ~strcmp(curGain, '1/60')
    error('P4_47:UnexpectedGain', ...
        'Expected J_rotor1 Gain=''1/60''; found %s. Stop and check the hierarchy manually.', curGain);
end

set_param(jBlock, 'Gain', '0');
save_system(M);
fprintf('P4_47: J_rotor1 Gain 1/60 -> 0 on %s -- GG rotor (S24) now has no dynamics. Saved.\n', M);
end
