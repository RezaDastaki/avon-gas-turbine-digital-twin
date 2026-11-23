function P4_25_repair_ambient_line(modelName)
% P4_25_REPAIR_AMBIENT_LINE.
%
% Repairs the severed compressor-inlet-temperature line on the PRODUCTION model. The root
% Constant ENV_comp_inlet_temp_C (SID 6809) lost its branch to Manual Switch2_Switch/1 (SID 6708)
% during the P4_21/P4_22 add-then-revert cycle that re-saved the model at 2026-10-16 22:11 -- the
% Constant's single outgoing Line fanned out to TWO destinations (Subsystem2/7, the controller's
% correction term, and Manual Switch2_Switch/1, the plant's actual inlet-temperature input), and
% P4_21.m's rewire captured dstBlock{1}/dstPortNum{1} off a 2-element DstPortHandle vector,
% silently keeping only the first. Since that save, the plant branch has been implicitly grounded
% at 0 degC on every record, whatever ambient was drawn; only the controller's correction term
% still saw the real draw. Confirmed 2026-10-17 by a read-only PortConnectivity probe: the
% Constant has exactly 1 outgoing destination (Subsystem2/7) and Manual Switch2_Switch port 1's
% SrcBlock is -1 (unconnected).
%
% One idempotent add_line. Four pre-conditions, all asserted, none assumed (spec
% items 1-4). A timestamped pre-edit copy of the .slx is taken before any write, because
% recorded the pre-session model state as "no longer exists anywhere on
% disk" -- that must not be true twice.
%
% Usage: P4_25_repair_ambient_line('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if port 1 of Manual Switch2_Switch is already fed by ENV_comp_inlet_temp_C,
%   reports 'already repaired' and returns WITHOUT calling save_system -- the .slx file's
%   modification timestamp must be provably unchanged on a second run; T1 checks this.)
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

    %% Pre-condition 1: exactly one Constant block reading ENV_comp_inlet_temp_C
    constCandidates = find_system(M, 'SearchDepth', 1, 'BlockType', 'Constant', ...
        'Value', 'ENV_comp_inlet_temp_C');
    if numel(constCandidates) ~= 1
        close_system(M, 0);
        error('P4_25:NotExactlyOneConstant', ...
            'Expected exactly 1 root Constant block reading ENV_comp_inlet_temp_C, found %d. Stop -- change nothing.', ...
            numel(constCandidates));
    end
    constBlock = constCandidates{1};

    %% Pre-condition 2: exactly one block named Manual Switch2_Switch
    swCandidates = find_system(M, 'SearchDepth', 1, 'Name', 'Manual Switch2_Switch');
    if numel(swCandidates) ~= 1
        close_system(M, 0);
        error('P4_25:NotExactlyOneSwitch', ...
            'Expected exactly 1 root block named ''Manual Switch2_Switch'', found %d. Stop -- change nothing.', ...
            numel(swCandidates));
    end
    swBlock = swCandidates{1};

    %% Pre-conditions 3/4: read port 1's SrcBlock and branch on what it already is
    pc = get_param(swBlock, 'PortConnectivity');
    srcOfPort1 = pc(1).SrcBlock;   % -1 (double) if unconnected; a block handle otherwise

    alreadyConnectedToTarget = false;
    if ~(isnumeric(srcOfPort1) && isequal(srcOfPort1, -1)) && ~isempty(srcOfPort1)
        srcHandle = srcOfPort1;
        if iscell(srcHandle), srcHandle = srcHandle{1}; end
        srcBlockPath = getfullname(srcHandle);
        if strcmp(srcBlockPath, constBlock)
            alreadyConnectedToTarget = true;
        else
            close_system(M, 0);
            error('P4_25:DifferentDefect', ...
                ['Manual Switch2_Switch port 1 is connected to %s, not to %s. This is a DIFFERENT ', ...
                 'defect from the one this script repairs -- stop, change nothing, and have a human ', ...
                 'read this before anything writes to the model.'], srcBlockPath, constBlock);
        end
    end

    if alreadyConnectedToTarget
        fprintf('P4_25: already repaired -- Manual Switch2_Switch/1 is already fed by %s. No change.\n', ...
            constBlock);
        close_system(M, 0);
        return;
    end

    %% Port 1 is genuinely unconnected -- repair it.
    % Timestamped pre-edit copy, taken before any write to the production .slx.
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    backupPath = sprintf('Core/Models/%s_prerepair_%s.slx', M, ts);
    copyfile(slxPath, backupPath);
    fprintf('P4_25: pre-repair copy saved to %s\n', backupPath);

    destCountBefore = numel(get_param(constBlock, 'LineHandles').Outport);
    % (both the pre-repair AND post-repair Outport count are 1, since one Line object fans out to
    % multiple destinations; report the actual destination count via PortConnectivity instead.)
    pcBefore = get_param(constBlock, 'PortConnectivity');
    nDestBefore = numel(pcBefore(1).DstBlock);

    add_line(M, 'ENV_comp_inlet_temp_C/1', 'Manual Switch2_Switch/1', 'autorouting', 'on');
    save_system(M);

    % Re-read and confirm.
    pcAfter = get_param(swBlock, 'PortConnectivity');
    srcAfter = pcAfter(1).SrcBlock;
    if iscell(srcAfter), srcAfter = srcAfter{1}; end
    if isnumeric(srcAfter) && isequal(srcAfter, -1)
        close_system(M, 0);
        error('P4_25:RepairDidNotTake', 'add_line ran but Manual Switch2_Switch/1 is still unconnected.');
    end
    srcAfterPath = getfullname(srcAfter);
    if ~strcmp(srcAfterPath, constBlock)
        close_system(M, 0);
        error('P4_25:RepairConnectedWrongSource', ...
            'Manual Switch2_Switch/1 is now connected to %s, not %s.', srcAfterPath, constBlock);
    end

    pcConstAfter = get_param(constBlock, 'PortConnectivity');
    nDestAfter = numel(pcConstAfter(1).DstBlock);

    fprintf('P4_25: repair applied. %s/1 destination count: %d -> %d\n', ...
        constBlock, nDestBefore, nDestAfter);
    fprintf('P4_25: Manual Switch2_Switch/1 is now fed by %s. Saved: %s\n', constBlock, slxPath);

    close_system(M, 0);
end
