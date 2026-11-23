function [ok, findings] = CheckModelStructuralIntegrity(model_path, baseline_csv)
% CheckModelStructuralIntegrity -. Production code: runs
% in the production path (ValidatePipelineConfig.m Check 11), not just at.
%
% Two tests, not one -- a dangling-port scan alone would miss a wire moved to the WRONG
% CONNECTED destination, which is a defect of exactly the same family as:
%
%   Test A - the dangling-input-port set equals the recorded baseline, by set equality (not
%            "at most N"). The baseline is 5 rows: pre-existing scope/plot wiring found in both
%            the production model and the untouched reference model:
%            a Sum in system_4400, three Mux ports in system_4654, a Sum in
%            system_4909. Repairing them is out of scope; this test exists so an EXTRA dangling
%            port (a new defect) fails loudly, while a MISSING one (something tidied) warns
%            loudly instead of passing silently as an improvement.
%   Test B - ENV_comp_inlet_temp_C/1 has EXACTLY two destinations, Subsystem2/7 and
%            Manual Switch2_Switch/1, asserted by name. This is the test that would have caught
% defect on the day it was made, in one second, with no simulation.
%
% Inputs:
%   model_path   - Simulink model name or path (load_system argument), e.g. ScenarioConfig.SIMULINK_MODEL
%   baseline_csv - path to P4_27_model_port_baseline.csv. If it does not exist, THIS CALL WRITES
%                  IT from what it finds, and that first-run result must be read by a human
%                  before being trusted (see the "first run" branch below) -- escalate if it is
%                  not exactly 5 rows.
%
% Outputs:
%   ok       - true iff both Test A and Test B pass
%   findings - struct: dangling_ports (table: BlockPath, SID, PortNumber, BlockType),
%              test_a_pass, test_a_message, test_b_pass, test_b_message, baseline_written (bool)
%
% Mechanics: load_system if the model is not already loaded, and close_system at the end ONLY IF
% this function loaded it -- a caller that already has the model open (e.g. the production
% driver, mid-generation) must not have it closed out from under it.
%
% Deliberately does NOT use find_system(...,'LookUnderMasks','all',...) despite the spec's own
% pseudocode comment suggesting it -- see the inline comment at the scan itself for the measured
% reason (it pulls in ~30 benign unconnected ports from inside standard MathWorks library blocks
% and the 5-row baseline below does not include any of them).
%

    if nargin < 2 || isempty(baseline_csv)
        baseline_csv = fullfile(fileparts(mfilename('fullpath')), 'P4_27_model_port_baseline.csv');
    end

    [~, shortname] = fileparts(model_path);
    wasLoaded = bdIsLoaded(shortname);
    if ~wasLoaded
        load_system(model_path);
    end
    M = shortname;

    %% Scan every block for unconnected INPUT ports.
    % PortConnectivity returns one entry per port, in order [inports, outports, enable,
    % trigger, ...] (get_param(b,'Ports')). Only the first Ports(1) entries are inputs -- an
    % output port's entry also carries an (irrelevant, empty) SrcBlock, so entry index alone
    % cannot distinguish them; Ports(1) can. Confirmed by direct probe, 2026-10-17: a connected
    % input's SrcBlock is a block HANDLE (double); a genuinely dangling one (the
    % severed-line defect, before its repair) was observed as the scalar -1, NOT []; an unused/absent port (e.g. the
    % 4th port on a 3-input Manual Switch, which is really its 1 output) is []. Both -1 and []
    % are therefore treated as unconnected here -- checking isempty alone would have missed
    % exactly the defect this scan exists to catch.
    % Deliberately NOT 'LookUnderMasks','all': that descends into every masked/linked LIBRARY
    % block's own internal implementation -- e.g. the three standard MathWorks "PID Controller"
    % blocks (MaskType 'PID 1dof', LinkStatus 'resolved', confirmed by probe) each carry ~10
    % internal Out1 ports that are legitimately unconnected because the corresponding optional
    % branch (anti-windup, tracking mode, ...) is disabled for this configuration -- normal,
    % vendor-supplied, and nothing to do with this project's authored wiring. With 'all' this
    % scan found 35 dangling ports; without it, exactly the expected 5 (verified against the
    % recorded baseline below) -- this project's own subsystems (Subsystem, GasGenerator,
    % PowerTurbine, cooling 2, ...) are confirmed unmasked (MaskType '', LinkStatus 'none') and
    % are found either way, so nothing of ours is hidden by leaving this flag off.
    blks = find_system(M, 'FollowLinks', 'on', 'Type', 'block');
    rows = {};
    for bi = 1:numel(blks)
        b = blks{bi};
        try
            portsVec = get_param(b, 'Ports');
            nIn = portsVec(1);
        catch
            continue;  % no Ports param (e.g. annotations) -- not a block with ports
        end
        if nIn < 1, continue; end
        try
            pc = get_param(b, 'PortConnectivity');
        catch
            continue;
        end
        try
            sid = get_param(b, 'SID');
        catch
            sid = '';
        end
        try
            btype = get_param(b, 'BlockType');
        catch
            btype = '';
        end
        for p = 1:min(nIn, numel(pc))
            src = pc(p).SrcBlock;
            unconnected = isempty(src) || (isnumeric(src) && isscalar(src) && src == -1);
            if unconnected
                rows(end+1, :) = {b, sid, p, btype}; %#ok<AGROW>
            end
        end
    end
    danglingT = cell2table(rows, 'VariableNames', {'BlockPath', 'SID', 'PortNumber', 'BlockType'});
    findings.dangling_ports = danglingT;

    %% Test A: set equality against the recorded baseline.
    findings.baseline_written = false;
    if ~exist(baseline_csv, 'file')
        fid = fopen(baseline_csv, 'w');
        fprintf(fid, ['# P4_27_model_port_baseline.csv structural-scan baseline.\n', ...
            '# Written on the FIRST run of CheckModelStructuralIntegrity.m, after the ambient-line repair.\n', ...
            '# Why the baseline is 5 rows and not 0: these are pre-existing scope/plot wiring,\n', ...
            '# found in BOTH the production model and the untouched reference model\n', ...
            '# -- a Sum in system_4400, three Mux ports in\n', ...
            '# system_4654, a Sum in system_4909. Repairing them is out of scope for this project;\n', ...
            '# testing for SET EQUALITY against this recorded baseline is strictly stronger than a\n', ...
            '# threshold of "at most 6" would be, because it also catches a port going from\n', ...
            '# connected to dangling (or vice versa) even when the COUNT happens to stay the same.\n']);
        fclose(fid);
        writetable(danglingT, baseline_csv, 'WriteMode', 'append', 'WriteVariableNames', true);
        findings.baseline_written = true;
        if height(danglingT) ~= 5
            findings.test_a_pass = false;
            findings.test_a_message = sprintf(['FIRST RUN wrote a baseline of %d rows, not the expected 5. ', ...
                'STOP AND ESCALATE: this is a second structural defect, not a baseline. Read %s by hand ', ...
                'before trusting it.'], height(danglingT), baseline_csv);
        else
            findings.test_a_pass = true;
            findings.test_a_message = sprintf('First run: wrote baseline of exactly 5 rows to %s.', baseline_csv);
        end
    else
        baselineT = readtable(baseline_csv);
        % Set-equality on (BlockPath, PortNumber) -- SID/BlockType carried for readability only.
        curKey = strcat(danglingT.BlockPath, '#', string(danglingT.PortNumber));
        baseKey = strcat(string(baselineT.BlockPath), '#', string(baselineT.PortNumber));
        extra = setdiff(curKey, baseKey);
        missing = setdiff(baseKey, curKey);
        if ~isempty(extra)
            findings.test_a_pass = false;
            findings.test_a_message = sprintf('Test A FAIL: %d EXTRA dangling port(s) not in the baseline: %s', ...
                numel(extra), strjoin(extra, '; '));
        elseif ~isempty(missing)
            findings.test_a_pass = true;   % a missing port is a loud WARNING, not a failure
            findings.test_a_message = sprintf(['Test A WARNING (pass): %d baseline port(s) no longer dangling ', ...
                '(something was tidied -- not this project''s business, but recorded): %s'], ...
                numel(missing), strjoin(missing, '; '));
        else
            findings.test_a_pass = true;
            findings.test_a_message = 'Test A pass: dangling-port set matches the baseline exactly.';
        end
    end

    %% Test B: the compressor-inlet-temperature source has exactly two destinations, by name.
    % RE-ATTEMPT: the root Constant ENV_comp_inlet_temp_C is
    % now (if shipped) a From Workspace block, ENV_comp_inlet_temp_trend_input, VariableName
    % 'ENV_comp_inlet_temp_trend' (P4_57_add_ambient_trend_input_both_branches.m). Check whichever
    % source block is actually present -- the Constant (pre-Task-9 / declared-limitation state) or
    % the From Workspace block -- so this test keeps meaning what it says in
    % either outcome, instead of hard-failing the moment the source block's TYPE changes while its
    % two-destination WIRING stays exactly what requires.
    constCandidates = find_system(M, 'SearchDepth', 1, 'BlockType', 'Constant', ...
        'Value', 'ENV_comp_inlet_temp_C');
    fwCandidates = find_system(M, 'SearchDepth', 1, 'BlockType', 'FromWorkspace', ...
        'VariableName', 'ENV_comp_inlet_temp_trend');
    if numel(constCandidates) == 1 && numel(fwCandidates) == 0
        srcBlock = constCandidates{1};
    elseif numel(fwCandidates) == 1 && numel(constCandidates) == 0
        srcBlock = fwCandidates{1};
    else
        findings.test_b_pass = false;
        findings.test_b_message = sprintf(['Test B FAIL: expected exactly 1 compressor-inlet-temperature ', ...
            'source block (Constant ENV_comp_inlet_temp_C XOR FromWorkspace ENV_comp_inlet_temp_trend), ', ...
            'found %d Constant + %d FromWorkspace.'], numel(constCandidates), numel(fwCandidates));
        srcBlock = '';
    end
    if ~isempty(srcBlock)
        pcConst = get_param(srcBlock, 'PortConnectivity');
        % DstBlock is an array of destination BLOCK HANDLES (not paths/cells); DstPort is an
        % array of 0-BASED destination port numbers -- confirmed by direct probe, 2026-10-17
        % (pre-fix code read get_param(dstPortHandle,'Parent') on what is actually a port
        % NUMBER, not a handle, which errors -- exactly the bug class own P4_21.m
        % rewire fell into when it read a fanned-out DstPortHandle/DstBlock pair).
        dstBlockHandles = pcConst(1).DstBlock;
        dstPortNums0    = pcConst(1).DstPort;
        destNames = strings(0);
        for d = 1:numel(dstBlockHandles)
            blkPath = getfullname(dstBlockHandles(d));
            [~, shortBlk] = fileparts(blkPath);
            destNames(end+1) = sprintf('%s/%d', shortBlk, dstPortNums0(d) + 1); %#ok<AGROW>
        end
        destNames = sort(destNames);
        expected = sort(["Subsystem2/7", "Manual Switch2_Switch/1"]);
        if numel(destNames) == 2 && all(destNames == expected)
            findings.test_b_pass = true;
            findings.test_b_message = 'Test B pass: ENV_comp_inlet_temp_C/1 feeds exactly Subsystem2/7 and Manual Switch2_Switch/1.';
        else
            findings.test_b_pass = false;
            findings.test_b_message = sprintf('Test B FAIL: ENV_comp_inlet_temp_C/1 destinations are {%s}, expected {%s}.', ...
                strjoin(destNames, ', '), strjoin(expected, ', '));
        end
    end

    ok = findings.test_a_pass && findings.test_b_pass;

    if ~wasLoaded
        close_system(M, 0);
    end
end
