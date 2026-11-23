function P4_22_revert_ambient_trend_input(modelName)
% P4_22_REVERT_AMBIENT_TREND_INPUT - Undoes P4_21_add_ambient_trend_input.m.
%
% B1 regression test ("the model must
% reproduce the current Healthy record to <1e-6 on every channel mean and std... a rewire that
% is not an identity at zero amplitude is a defect") FAILED -- not marginally: at a flat
% DeltaT=0 trend (verified, by a direct signal tap, to be numerically exactly constant at
% 22.24000 throughout, min=max=22.24), channels directly coupled to the GG rotor
% (S19/S20/S21/S24/S26/S29) differ from the pre-rewire baseline by 40-173 units, while fast
% states (S27 speed, S28 power) stay close. Two independent post-rewire runs with identical
% seeds ARE bit-identical to each other (isequal=1, max diff=0), which rules out general
% nondeterminism/chaos -- the Constant-to-FromWorkspace swap itself deterministically shifts the
% solver's trajectory independent finding (GG rotor speed has no
% settled equilibrium in large parts of the operating envelope) explains why: a system with a
% weak-or-absent restoring force is exactly the kind that even a electrically-identical block
% swap can measurably perturb, because nothing pulls the two trajectories back together.
%
% Per the spec's own explicit bail-out: "If... the rewire does not pass the regression
% test below, stop. Do not improvise a multi-block rewire on a Gate-A-validated model. Record
% the finding, leave the ambient constant per record." This script does exactly that: deletes
% the From Workspace block and restores the original Constant block, at its original position,
% wired to the same destination port, with the same Value expression.
%
% Usage: P4_22_revert_ambient_trend_input('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if ENV_comp_inlet_temp_C Constant already present, reports and does nothing)

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

OLD_BLOCK_NAME = 'ENV_comp_inlet_temp_C';
NEW_BLOCK_NAME = 'ENV_comp_inlet_temp_trend_input';

if ~isempty(find_system(M, 'BlockType', 'Constant', 'Value', 'ENV_comp_inlet_temp_C'))
    fprintf('P4_22: a Constant block reading ENV_comp_inlet_temp_C is already present on %s -- no change.\n', M);
    return;
end

candidates = find_system(M, 'Name', NEW_BLOCK_NAME);
if numel(candidates) ~= 1
    error('P4_22:NotExactlyOneBlock', ...
        'Expected exactly 1 block named %s, found %d.', NEW_BLOCK_NAME, numel(candidates));
end
fwBlock = candidates{1};

lineHandles = get_param(fwBlock, 'LineHandles');
outLine = lineHandles.Outport;
if ~ishandle(outLine) || numel(outLine) ~= 1
    error('P4_22:UnexpectedWiring', 'Expected exactly 1 outgoing line from %s, found %d.', ...
        fwBlock, numel(outLine));
end
dstPortHandle = get_param(outLine, 'DstPortHandle');
dstBlock = get_param(dstPortHandle, 'Parent');
dstPortNum = get_param(dstPortHandle, 'PortNumber');
if iscell(dstBlock), dstBlock = dstBlock{1}; end
if iscell(dstPortNum), dstPortNum = dstPortNum{1}; end
[~, dstShort] = fileparts(dstBlock);
dstSpec = sprintf('%s/%d', dstShort, dstPortNum);

pos = get_param(fwBlock, 'Position');
delete_line(outLine);
delete_block(fwBlock);

add_block('simulink/Sources/Constant', [M '/' OLD_BLOCK_NAME], ...
    'Value', 'ENV_comp_inlet_temp_C', 'Position', pos);
add_line(M, [OLD_BLOCK_NAME '/1'], dstSpec, 'autorouting', 'on');

save_system(M);
fprintf('P4_22: reverted -- %s restored as a Constant block reading ENV_comp_inlet_temp_C on %s, saved.\n', ...
    OLD_BLOCK_NAME, M);
end
