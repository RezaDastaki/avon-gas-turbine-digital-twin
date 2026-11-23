function P4_21_add_ambient_trend_input(modelName)
% P4_21_ADD_AMBIENT_TREND_INPUT: replace the ENV_comp_inlet_temp_C Constant block
% with a From Workspace block, so the compressor inlet temperature can carry a within-record
% linear trend instead of being a per-record constant. Same pattern as
% P1b_02_fix_duty_command.m's SP_Power_Cmd rewire: delete the Constant block, add a From
% Workspace block fed by a workspace variable, re-add the line, save_system.
%
% Discovery (not hard-coded): exactly ONE Constant block in AvonGasTurbineDgTwin_fixed reads
% ENV_comp_inlet_temp_C -- find_system(M, 'BlockType', 'Constant', 'Value', 'ENV_comp_inlet_temp_C')
% confirmed this on 2026-10-16 before this script was written. Per
% "if more than one block reads it... stop. Do not
% improvise a multi-block rewire."
%
% Usage: P4_21_add_ambient_trend_input('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if ENV_comp_inlet_temp_trend_input already present, reports and does nothing)

if nargin < 1 || isempty(modelName)
    modelName = 'AvonGasTurbineDgTwin_fixed';
end

cd(fileparts(fileparts(mfilename('fullpath'))));
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
% ScenarioConfig.SIMULINK_MODEL already points at the fixed model (Core/Models/<modelName>) --
% unlike when P1b_02_fix_duty_command.m's strrep pattern was written, it no longer needs rewriting.
mdlFile = ['Core/Models/' modelName];
load_system(mdlFile);
M = modelName;

NEW_BLOCK_NAME = 'ENV_comp_inlet_temp_trend_input';
if ~isempty(find_system(M, 'Name', NEW_BLOCK_NAME))
    fprintf('P4_21: %s already present on %s -- no change.\n', NEW_BLOCK_NAME, M);
    return;
end

candidates = find_system(M, 'BlockType', 'Constant', 'Value', 'ENV_comp_inlet_temp_C');
if numel(candidates) ~= 1
    error('P4_21:NotExactlyOneBlock', ...
        ['Expected exactly 1 Constant block reading ENV_comp_inlet_temp_C, found %d. Per spec ', ...
         'Sec3.2: stop, do not improvise a multi-block rewire.'], numel(candidates));
end
oldConst = candidates{1};

% Discover the destination port(s) this Constant feeds, so the rewire does not hard-code a
% downstream block path either.
lineHandles = get_param(oldConst, 'LineHandles');
outLine = lineHandles.Outport;
if ~ishandle(outLine) || numel(outLine) ~= 1
    error('P4_21:UnexpectedWiring', 'Expected exactly 1 outgoing line from %s, found %d.', ...
        oldConst, numel(outLine));
end
dstPortHandle = get_param(outLine, 'DstPortHandle');
dstBlock = get_param(dstPortHandle, 'Parent');
dstPortNum = get_param(dstPortHandle, 'PortNumber');
if iscell(dstBlock), dstBlock = dstBlock{1}; end
if iscell(dstPortNum), dstPortNum = dstPortNum{1}; end
% Resolve the destination's block-relative name/port spec for add_line (e.g. 'Subsystem2/2')
[~, dstShort] = fileparts(dstBlock);
dstSpec = sprintf('%s/%d', dstShort, dstPortNum);

pos = get_param(oldConst, 'Position');
delete_line(outLine);
delete_block(oldConst);

add_block('simulink/Sources/From Workspace', [M '/' NEW_BLOCK_NAME], ...
    'VariableName', 'ENV_comp_inlet_temp_trend', ...
    'SampleTime', '-1', ...
    'Position', pos);
add_line(M, [NEW_BLOCK_NAME '/1'], dstSpec, 'autorouting', 'on');

% Default/identity workspace variable for anything that loads the model standalone (e.g. probe
% scripts that never call LoadScenarioToWorkspace/GetAmbientTrendAmplitude): a flat [0,T]x[C,C]
% timeseries at the model's own default duty-tracking reference temperature -- identical to the
% old Constant's behaviour when amplitude=0 (B1's own identity requirement).
assignin('base', 'ENV_comp_inlet_temp_trend', [0 15; 6000 15]);

save_system(M);
fprintf('P4_21: ENV_comp_inlet_temp_C rewired from Constant to From Workspace (%s) on %s, saved.\n', ...
    NEW_BLOCK_NAME, M);
end
