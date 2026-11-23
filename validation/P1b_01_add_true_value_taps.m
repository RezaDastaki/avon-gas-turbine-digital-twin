function P1b_01_add_true_value_taps(modelName)
% P1B_01_ADD_TRUE_VALUE_TAPS - add To Workspace taps for the TRUE (pre-fault-injection) value
% of every drifting sensor, on AvonGasTurbineDgTwin_fixed.
%
% WHY: the logged channel is the INDICATED (possibly biased/frozen/drifted) value. The model
% still computes the true internal value upstream of each fault's injection point; it is simply
% never logged. This taps it, named <S..>_true, wired as a NEW group in
% ExtractSensorsFromWorkspace (NOT into /sensors, which must keep a stable 39-channel count).
%
% Tap points (found by static trace + confirmed by the Task-1/Task-4 verification run,
% P1b_00_discover_sensor_fault_taps.m / P1b_00b_fanout_trace.m, 2026-10-09):
%   S19_true (GG turbine inlet temp, pre stator-cooling mix) <- GasGenerator/cooling 1 output
%       (same line that feeds FAULT_37_SensorFreez/In1 -- the start of the F37->36->35->34->33
%       cascade). NOTE: the cascade's OUTPUT (Manual Switch7_Switch -> Sum -> To Workspace16)
%       feeds ONLY the S19 logger -- it has NO other destination anywhere in the model (verified
%       by exhaustive fan-out trace on both AvonGasTurbineDgTwin_fixed and the original,
%       unfixed AvonGasTurbineDgTwin). So S19_true vs S19 tests a fault path that, as currently
%       wired, cannot reach the plant -- see this script's own verification step and
%.
%   S24_true (GG rotor speed) <- the line into FAULT_38_GGSpeedSensor/In1 (GasGenerator's own
%       "freq_Rotor"-station output, which ALSO fans out directly to Manual Switch1_Switch's
%       bypass input (in3) and to the real governor path (freq_Rotor) -- i.e. the plant's own
%       speed feedback is independent of the FAULT_38 chain).
%   S27_true (PT rotor speed) <- the line into FAULT_39_PTSpeedSensor/In1 (PowerTurbine's own
%       speed output).
%   S04_true (fuel mass flow) <- the line into FAULT_41_FGSensorDrift/In1 ("FG MCV model1"
%       subsystem's own flow output).
%   S26_true (PT inlet / GG exhaust temp, the 846 degC limiter's own feedback) <- the SAME
%       GasGenerator output port (out2) that already feeds Trb_exTemp and To Workspace5 (S26)
%       directly, with NO fault multiplier anywhere on this path. Tapped anyway, per the spec,
%       for the documented record that S26_true == S26 identically (no sensor fault touches the
%       limiter's own feedback in the current wiring).
%
% Usage: P1b_01_add_true_value_taps('AvonGasTurbineDgTwin_fixed')
%   (idempotent: re-running with the taps already present is a no-op per tap, reported as such)

if nargin < 1 || isempty(modelName)
    modelName = 'AvonGasTurbineDgTwin_fixed';
end

cd(fileparts(fileparts(mfilename('fullpath'))));
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
mdlFile = strrep(ScenarioConfig.SIMULINK_MODEL, 'AvonGasTurbineDgTwin', modelName);
if ~exist([mdlFile '.slx'], 'file')
    error('P1b_01:NoModel', '%s.slx not found', mdlFile);
end
load_system(mdlFile);
M = modelName;

taps = struct( ...
    'varName',  {'S19_true', 'S24_true', 'S27_true', 'S04_true', 'S26_true'}, ...
    'tapLine',  { ...
        [M '/Subsystem/GasGenerator/FAULT_37_SensorFreez'], ...   % tap its In1 line
        [M '/Subsystem/FAULT_38_GGSpeedSensor'], ...
        [M '/Subsystem/FAULT_39_PTSpeedSensor'], ...
        [M '/Subsystem/FAULT_41_FGSensorDrift'], ...
        [M '/Subsystem/Trb_exTemp'] ...                           % tap its own input line directly
    }, ...
    'portIdx',  {1, 1, 1, 1, 1});

fprintf('=== P1b_01_add_true_value_taps on %s ===\n', M);
added = 0; skipped = 0;
for k = 1:numel(taps)
    varName = taps(k).varName;
    towsName = [taps(k).varName '_tap'];
    % Idempotency: does a To Workspace block with this VariableName already exist?
    existing = find_system(M, 'BlockType', 'ToWorkspace', 'VariableName', varName);
    if ~isempty(existing)
        fprintf('  %-10s already tapped at %s -- skipping\n', varName, existing{1});
        skipped = skipped + 1;
        continue;
    end

    targetBlk = taps(k).tapLine;
    ph = get_param(targetBlk, 'PortHandles');
    inport = ph.Inport(taps(k).portIdx);
    lineH = get_param(inport, 'Line');
    if lineH == -1
        error('P1b_01:NoLine', 'Input port %d of %s has no connected line', taps(k).portIdx, targetBlk);
    end
    srcBlk = get_param(lineH, 'SrcBlockHandle');
    srcPortH = get_param(lineH, 'SrcPortHandle');
    srcPortNum = get_param(srcPortH, 'PortNumber');
    srcPos = get_param(srcBlk, 'Position');
    % add_line only works within ONE subsystem level -- the new block must live in the SAME
    % subsystem as the source block, not at the model's top level (the source is typically
    % several levels deep, e.g. .../GasGenerator/cooling 1).
    parentSys = get_param(srcBlk, 'Parent');

    % Place the new To Workspace block near the source block, offset downward so it does not
    % overlap existing wiring.
    newBlk = [parentSys '/' varName '_ToWS'];
    offsetY = 60 + 30 * mod(k, 3);
    pos = [srcPos(3)+20, srcPos(2)+offsetY, srcPos(3)+120, srcPos(2)+offsetY+30];
    add_block('simulink/Sinks/To Workspace', newBlk, 'Position', pos);
    set_param(newBlk, 'VariableName', varName, 'SampleTime', '-1', 'SaveFormat', 'Array');

    % Branch a new line from the SAME source port to the new block's input, within parentSys.
    % Port handles are robust to block names containing spaces (e.g. "cooling 1"); add_line
    % creates a branch automatically when the source port already has a line, without
    % disturbing the existing line/destination at all.
    newPh = get_param(newBlk, 'PortHandles');
    add_line(parentSys, srcPortH, newPh.Inport(1), 'autorouting', 'on');

    fprintf('  %-10s tapped: port %d of %s (in %s) -> new block %s\n', ...
        varName, srcPortNum, getfullname(srcBlk), parentSys, newBlk);
    added = added + 1;
end

if added > 0
    save_system(M);
    fprintf('Saved %s.slx (%d tap(s) added, %d already present).\n', M, added, skipped);
else
    fprintf('No changes (%d tap(s) already present).\n', skipped);
end

fprintf('=== Done ===\n');
end
