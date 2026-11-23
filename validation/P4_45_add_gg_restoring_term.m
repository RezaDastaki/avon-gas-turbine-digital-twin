function P4_45_add_gg_restoring_term(modelName)
% P4_45_ADD_GG_RESTORING_TERM - G3 mini-phase: close the GG rotor's torque balance with a confined
% restoring term, inside 'Subsystem/GasGenerator/rotor dynamic ' (trailing space in the real
% path) and nowhere else.
%
% Block diagram read directly from the loaded model, confirmed by PortConnectivity,
% before this script was written:
%   Sum8  = gen_turb - consm_comp                         (Inputs '|+-')
%   Sum9  = Sum8 - Loss                                   (Inputs '|+-')   <- "the bracket"
%   Gain4 = freq_rotor3(7250) * (pi/30)  = 759.2182 rad/s  (constant)
%   Sum7  = Gain4 + Memory Omega2                          = 759.2182 + omega
%   Sum9/Sum7 -> *0.5*(FG_flow/1.9141+1) -> *(1/60) -> Integrator1 -> rotor_speed (= S24, rad/s)
% matching closed-form ODE exactly.
%
% This adds a THIRD, additive input to Sum9 (Inputs '|+-' -> '|+-+'):
%   +G*(omega_set(T) - omega)     ==   -G*(omega - omega_set(T))     G = 98 kW/(rad/s)
% omega is the existing Memory Omega2 tap (same one Sum7 already reads -- no new algebraic
% loop). omega_set(T) arrives as a new GLOBAL Goto/From pair (tag 'GG_omega_set'), fed at root
% by a new Constant block reading the base-workspace variable ENV_gg_omega_set -- the same idiom
% already used for Cmprssr_inlet_temp/Amb_moisture_percent (global-scope root Goto, From block
% deep inside a subsystem, no port threading through each level).
%
% ENV_gg_omega_set itself is assigned by SetWarmStartInitialConditions.m (the measured library
% equilibrium already computed and already used as the GG integrator's own IC
% says to reuse it, not recompute it) and defaulted by RunSimulinkModel.m for any call that
% skips warm start. This script does not touch either pipeline file; see G3 notes in
% for that half of the change.
%
% Discipline: "build and verify on a scratch copy; apply to the production model
% only when A1-A4 are green." This script takes modelName as an argument for exactly that
% reason -- run it against a scratch copy first.
%
% Usage: P4_45_add_gg_restoring_term('AvonGasTurbineDgTwin_fixed_G3test')   % scratch
%        P4_45_add_gg_restoring_term('AvonGasTurbineDgTwin_fixed')         % production, after A1-A4 green
%   (idempotent: if GG_RestoringGain already present, reports and does nothing)

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

NEW_GAIN_NAME = 'GG_RestoringGain';
if ~isempty(find_system(M, 'Name', NEW_GAIN_NAME))
    fprintf('P4_45: %s already present on %s -- no change.\n', NEW_GAIN_NAME, M);
    return;
end

sub = [M '/Subsystem/GasGenerator/rotor dynamic '];

%% Pre-condition asserts -- fail loudly, not silently, on a changed hierarchy
sum9 = [sub '/Sum9'];
if ~strcmp(strtrim(get_param(sum9, 'Inputs')), '|+-')
    error('P4_45:Sum9Changed', ...
        'Expected Sum9 Inputs=''|+-''; found %s. Stop and check the hierarchy manually.', ...
        get_param(sum9, 'Inputs'));
end
sum9pc = get_param(sum9, 'PortConnectivity');
if ~strcmp(get_param(sum9pc(1).SrcBlock, 'Name'), 'Sum8') || ...
        ~strcmp(get_param(sum9pc(2).SrcBlock, 'Name'), 'Loss')
    error('P4_45:Sum9WiringChanged', ...
        'Expected Sum9 in1=Sum8, in2=Loss. Stop and check the hierarchy manually.');
end
memBlk = [sub '/Memory Omega2'];
if ~strcmp(get_param(memBlk, 'BlockType'), 'Memory')
    error('P4_45:MemoryBlockChanged', 'Expected a Memory block at %s.', memBlk);
end

%% 1. Root-level ENV_gg_omega_set Constant -> global Goto (same idiom as Goto2/Goto3/Goto4)
rootConstName = 'ENV_gg_omega_set_const';
if isempty(find_system(M, 'SearchDepth', 1, 'Name', rootConstName))
    add_block('simulink/Sources/Constant', [M '/' rootConstName], ...
        'Value', 'ENV_gg_omega_set', 'Position', [925 150 1070 170]);
end
gotoName = 'GG_omega_set_Goto';
if isempty(find_system(M, 'SearchDepth', 1, 'Name', gotoName))
    add_block('simulink/Signal Routing/Goto', [M '/' gotoName], ...
        'GotoTag', 'GG_omega_set', 'TagVisibility', 'global', ...
        'Position', [1090 150 1135 170]);
    add_line(M, [rootConstName '/1'], [gotoName '/1'], 'autorouting', 'on');
end

% Identity default for any bare model load that never calls SetWarmStartInitialConditions (e.g.
% probes that call sim directly) -- the model's own cold IC, so the restoring term starts at
% exactly 0 (omega == omega_set), matching pre-G3 behaviour at that one instant. Production runs
% always overwrite this via SetWarmStartInitialConditions before sim -- see that file's header.
assignin('base', 'ENV_gg_omega_set', pi / 30 * 7250);

%% 2. Inside 'rotor dynamic ': From(GG_omega_set) -> Sum(omega_set - omega) -> Gain(98) -> Sum9 in3
fromName = 'GG_omega_set_From';
add_block('simulink/Signal Routing/From', [sub '/' fromName], ...
    'GotoTag', 'GG_omega_set', 'Position', [20 400 95 420]);

diffName = 'GG_RestoringDiff';
add_block('simulink/Math Operations/Sum', [sub '/' diffName], ...
    'Inputs', '+-', 'Position', [120 395 150 425]);

add_block('simulink/Math Operations/Gain', [sub '/' NEW_GAIN_NAME], ...
    'Gain', '98', 'Position', [180 400 220 420]);

% Sum9 gains a third, '+' port -- the new term is already signed
% (G*(omega_set-omega) == -G*(omega-omega_set)), so it is additive, not a fourth '-' port.
set_param(sum9, 'Inputs', '|+-+');

add_line(sub, [fromName '/1'], [diffName '/1'], 'autorouting', 'on');
add_line(sub, 'Memory Omega2/1', [diffName '/2'], 'autorouting', 'on');
add_line(sub, [diffName '/1'], [NEW_GAIN_NAME '/1'], 'autorouting', 'on');
add_line(sub, [NEW_GAIN_NAME '/1'], 'Sum9/3', 'autorouting', 'on');

save_system(M);
fprintf(['P4_45: GG restoring term wired on %s -- Sum9 bracket now ', ...
    '(gen_turb-consm_comp)-Loss(w)+98*(w_set-w). Saved.\n'], M);
end
