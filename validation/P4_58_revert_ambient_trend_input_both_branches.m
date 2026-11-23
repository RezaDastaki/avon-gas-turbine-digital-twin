function P4_58_revert_ambient_trend_input_both_branches(modelName)
% P4_58_REVERT_AMBIENT_TREND_INPUT_BOTH_BRANCHES - undoes
% P4_57_add_ambient_trend_input_both_branches.m, with the SAME destination-set discipline (by
% name, both branches) as the forward script -- not the single-destination pattern P4_22 used,
% which is exactly how P4_21/P4_22's add-then-revert cycle produced severed wire
% in the first place.
%
% Used ONLY if B1 identity regression fails again (the bail-out): "revert with the same discipline... and C12 closes for
% good as a declared limitation." After reverting T2's library replay
% (P4_26_verify_repair_library_replay.m) must be re-run to confirm the repaired-but-pre-Task-9
% model state is intact.
%
% Usage: P4_58_revert_ambient_trend_input_both_branches('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if ENV_comp_inlet_temp_C Constant already present, reports and does nothing)
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

    OLD_BLOCK_NAME = 'ENV_comp_inlet_temp_C';
    NEW_BLOCK_NAME = 'ENV_comp_inlet_temp_trend_input';
    EXPECTED = sort(["Subsystem2/7", "Manual Switch2_Switch/1"]);

    if ~isempty(find_system(M, 'SearchDepth', 1, 'BlockType', 'Constant', 'Value', 'ENV_comp_inlet_temp_C'))
        fprintf('P4_58: a Constant block reading ENV_comp_inlet_temp_C is already present on %s -- no change.\n', M);
        close_system(M, 0);
        return;
    end

    candidates = find_system(M, 'SearchDepth', 1, 'Name', NEW_BLOCK_NAME);
    if numel(candidates) ~= 1
        close_system(M, 0);
        error('P4_58:NotExactlyOneBlock', 'Expected exactly 1 block named %s, found %d.', ...
            NEW_BLOCK_NAME, numel(candidates));
    end
    fwBlock = candidates{1};

    pc = get_param(fwBlock, 'PortConnectivity');
    dstBlockHandles = pc(1).DstBlock;
    dstPortNums0    = pc(1).DstPort;
    destNamesBefore = strings(0);
    for d = 1:numel(dstBlockHandles)
        blkPath = getfullname(dstBlockHandles(d));
        [~, shortBlk] = fileparts(blkPath);
        destNamesBefore(end+1) = sprintf('%s/%d', shortBlk, dstPortNums0(d) + 1); %#ok<AGROW>
    end
    if numel(destNamesBefore) ~= 2 || ~all(sort(destNamesBefore) == EXPECTED)
        close_system(M, 0);
        error('P4_58:UnexpectedDestinations', 'Expected exactly {%s}, found {%s}. Stop, change nothing.', ...
            strjoin(EXPECTED, ', '), strjoin(sort(destNamesBefore), ', '));
    end

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    backupPath = sprintf('Core/Models/%s_preRevertT9_%s.slx', M, ts);
    copyfile(slxPath, backupPath);
    fprintf('P4_58: pre-revert copy saved to %s\n', backupPath);

    pos = get_param(fwBlock, 'Position');
    lineHandles = get_param(fwBlock, 'LineHandles');
    outLine = lineHandles.Outport;
    if ~ishandle(outLine) || numel(outLine) ~= 1
        close_system(M, 0);
        error('P4_58:UnexpectedLineCount', 'Expected exactly 1 (branched) outgoing Line object, found %d.', ...
            numel(outLine));
    end
    delete_line(outLine);
    delete_block(fwBlock);

    add_block('simulink/Sources/Constant', [M '/' OLD_BLOCK_NAME], ...
        'Value', 'ENV_comp_inlet_temp_C', 'Position', pos);
    add_line(M, [OLD_BLOCK_NAME '/1'], 'Subsystem2/7', 'autorouting', 'on');
    add_line(M, [OLD_BLOCK_NAME '/1'], 'Manual Switch2_Switch/1', 'autorouting', 'on');

    % Post-condition, by name, both branches.
    pcAfter = get_param([M '/' OLD_BLOCK_NAME], 'PortConnectivity');
    destNamesAfter = strings(0);
    for d = 1:numel(pcAfter(1).DstBlock)
        blkPath = getfullname(pcAfter(1).DstBlock(d));
        [~, shortBlk] = fileparts(blkPath);
        destNamesAfter(end+1) = sprintf('%s/%d', shortBlk, pcAfter(1).DstPort(d) + 1); %#ok<AGROW>
    end
    if numel(destNamesAfter) ~= 2 || ~all(sort(destNamesAfter) == EXPECTED)
        close_system(M, 0);
        error('P4_58:PostConditionFailed', 'After revert, destinations are {%s}, expected {%s}. NOT SAVED.', ...
            strjoin(sort(destNamesAfter), ', '), strjoin(EXPECTED, ', '));
    end

    save_system(M);
    fprintf('P4_58: reverted -- %s restored as a Constant reading ENV_comp_inlet_temp_C, both branches, on %s. Saved: %s\n', ...
        OLD_BLOCK_NAME, M, slxPath);

    close_system(M, 0);
end
