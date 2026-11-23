function P4_57_add_ambient_trend_input_both_branches(modelName)
% P4_57_ADD_AMBIENT_TREND_INPUT_BOTH_BRANCHES - RE-ATTEMPT. Supersedes P4_21_add_ambient_trend_input.m, which
% deleted the root Constant ENV_comp_inlet_temp_C and restored only ONE of its TWO outgoing
% destinations -- exactly the severed-wire defect, caught by the B1 identity regression. This script feeds BOTH original
% destinations from the new From Workspace block:
%
%   ENV_comp_inlet_temp_C/1 --+--> Subsystem2/7              (controller: GG droop temp correction)
%                             +--> Manual Switch2_Switch/1   (PLANT: compressor inlet temperature)
%
% Numbering note: the spec names this script P4_28_add_ambient_trend_input_both_
% branches.m, but P4_28_test_ambient_check.m already existed under that number by the time this
% session ran (written for ambient-check tests), and P4_29..P4_56 were taken too
% (the G2 fallback, the throughput reconciliation theta0 re-solve --
% all dated 2026-10-19/20, after this spec section was written). Renumbered to the next free
% slot, P4_57. Recorded (re-attempt).
%
% Pre-conditions asserted (items 1-3), NONE assumed:
%   1. exactly one root Constant block, Value = 'ENV_comp_inlet_temp_C'
%   2. its output has EXACTLY two destinations, Subsystem2/7 and Manual Switch2_Switch/1
%      (this is Test B, reused here as a PRE-condition: if it does not hold
%      repair was not applied to this model copy -- stop, do not improvise, do not guess)
% Post-condition asserted before save_system:
%   3. the new From Workspace block's output has EXACTLY those same two destinations, by name.
%      This is the whole lesson: P4_21/P4_22's own verification ("a logging tap
%      confirmed min=max=22.24 reaching CompInletTempC") was true and proved nothing, because it
%      looked at the branch that survived. A destination-SET assertion, not a single-tap probe.
%
% A timestamped pre-edit copy of the .slx is taken before any write (same discipline as
% P4_25_repair_ambient_line.m) recorded the pre-P4_21 state as "no
% longer exists anywhere on disk"; that must not be true a second time.
%
% Usage: P4_57_add_ambient_trend_input_both_branches('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if ENV_comp_inlet_temp_trend_input already present, reports and does nothing)
%

    if nargin < 1 || isempty(modelName)
        modelName = 'AvonGasTurbineDgTwin_fixed';
    end

    cd(fileparts(fileparts(mfilename('fullpath'))));
    M = modelName;
    mdlFile = ['Core/Models/' M];
    slxPath = [mdlFile '.slx'];

    if bdIsLoaded(M), close_system(M, 0); end
    load_system(mdlFile);

    NEW_BLOCK_NAME = 'ENV_comp_inlet_temp_trend_input';
    EXPECTED = sort(["Subsystem2/7", "Manual Switch2_Switch/1"]);

    if ~isempty(find_system(M, 'SearchDepth', 1, 'Name', NEW_BLOCK_NAME))
        fprintf('P4_57: %s already present on %s -- no change.\n', NEW_BLOCK_NAME, M);
        close_system(M, 0);
        return;
    end

    %% Pre-condition 1: exactly one root Constant block reading ENV_comp_inlet_temp_C
    constCandidates = find_system(M, 'SearchDepth', 1, 'BlockType', 'Constant', ...
        'Value', 'ENV_comp_inlet_temp_C');
    if numel(constCandidates) ~= 1
        close_system(M, 0);
        error('P4_57:NotExactlyOneConstant', ...
            ['Expected exactly 1 root Constant block reading ENV_comp_inlet_temp_C, found %d. ', ...
             'Stop and change nothing -- the ambient-line repair was not applied to this copy.'], ...
            numel(constCandidates));
    end
    oldConst = constCandidates{1};

    %% Pre-condition 2: exactly the two named destinations
    [destNamesBefore, dstBlockHandlesBefore, dstPortNums0Before] = local_dest_names(oldConst); %#ok<ASGLU>
    if numel(destNamesBefore) ~= 2 || ~all(sort(destNamesBefore) == EXPECTED)
        close_system(M, 0);
        error('P4_57:UnexpectedDestinations', ...
            ['Expected exactly {%s}, found {%s}. Stop -- the ambient-line ', ...
             'repair was not applied to this model copy, do not improvise.'], ...
            strjoin(EXPECTED, ', '), strjoin(sort(destNamesBefore), ', '));
    end
    fprintf('P4_57: pre-condition confirmed -- %s/1 feeds exactly {%s}.\n', ...
        oldConst, strjoin(sort(destNamesBefore), ', '));

    %% Timestamped pre-edit backup, before any write.
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    backupPath = sprintf('Core/Models/%s_preT9_%s.slx', M, ts);
    copyfile(slxPath, backupPath);
    fprintf('P4_57: pre-edit copy saved to %s\n', backupPath);

    %% Delete the Constant and its (single, branched) outgoing line.
    pos = get_param(oldConst, 'Position');
    lineHandles = get_param(oldConst, 'LineHandles');
    outLine = lineHandles.Outport;
    if ~ishandle(outLine) || numel(outLine) ~= 1
        close_system(M, 0);
        error('P4_57:UnexpectedLineCount', ...
            'Expected exactly 1 (branched) outgoing Line object from %s, found %d.', ...
            oldConst, numel(outLine));
    end
    delete_line(outLine);
    delete_block(oldConst);

    %% Add the From Workspace block, fed by ENV_comp_inlet_temp_trend (the [t, T(t)] array
    % GetAmbientTrendAmplitude.m builds and LoadScenarioToWorkspace.m assigns).
    add_block('simulink/Sources/From Workspace', [M '/' NEW_BLOCK_NAME], ...
        'VariableName', 'ENV_comp_inlet_temp_trend', ...
        'SampleTime', '-1', ...
        'Position', pos);

    %% Re-add BOTH destinations -- the single instruction that changes vs. P4_21.
    add_line(M, [NEW_BLOCK_NAME '/1'], 'Subsystem2/7', 'autorouting', 'on');
    add_line(M, [NEW_BLOCK_NAME '/1'], 'Manual Switch2_Switch/1', 'autorouting', 'on');

    %% Default/identity workspace variable for anything that loads the model standalone without
    % calling LoadScenarioToWorkspace/GetAmbientTrendAmplitude (e.g. a probe script) -- a flat
    % [0,T]x[15,15] timeseries, matching P4_21's same convention.
    assignin('base', 'ENV_comp_inlet_temp_trend', [0 15; 6000 15]);

    %% Post-condition: assert the NEW block's output has EXACTLY the same two destinations, BY
    % NAME, before save_system. This is the whole lesson -- do
    % NOT verify by tapping the signal at one destination.
    newBlock = [M '/' NEW_BLOCK_NAME];
    [destNamesAfter] = local_dest_names(newBlock);
    if numel(destNamesAfter) ~= 2 || ~all(sort(destNamesAfter) == EXPECTED)
        % Do not save a half-wired model -- close without saving and report exactly what is wrong.
        close_system(M, 0);
        error('P4_57:PostConditionFailed', ...
            ['After rewiring, %s/1 feeds {%s}, expected {%s}. NOT SAVED. This is exactly the ', ...
             'severed-wire defect class -- stop and escalate, do not retry blindly.'], ...
            newBlock, strjoin(sort(destNamesAfter), ', '), strjoin(EXPECTED, ', '));
    end
    fprintf('P4_57: post-condition confirmed -- %s/1 feeds exactly {%s}.\n', ...
        newBlock, strjoin(sort(destNamesAfter), ', '));

    save_system(M);
    fprintf('P4_57: ENV_comp_inlet_temp_C rewired from Constant to From Workspace (%s), BOTH branches preserved, on %s. Saved: %s\n', ...
        NEW_BLOCK_NAME, M, slxPath);

    close_system(M, 0);
end

% -------------------------------------------------------------------------
function [destNames, dstBlockHandles, dstPortNums0] = local_dest_names(blockPath)
% Same PortConnectivity-based destination discovery as CheckModelStructuralIntegrity.m's Test B
% and P4_25_repair_ambient_line.m -- NOT the LineHandles/DstPortHandle pattern P4_21 used, which
% silently truncated a fanned-out line to its first destination.
    pc = get_param(blockPath, 'PortConnectivity');
    dstBlockHandles = pc(1).DstBlock;
    dstPortNums0    = pc(1).DstPort;
    destNames = strings(0);
    for d = 1:numel(dstBlockHandles)
        blkPath = getfullname(dstBlockHandles(d));
        [~, shortBlk] = fileparts(blkPath);
        destNames(end+1) = sprintf('%s/%d', shortBlk, dstPortNums0(d) + 1); %#ok<AGROW>
    end
end
