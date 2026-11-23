function P1b_02_fix_duty_command(modelName)
% P1B_02_FIX_DUTY_COMMAND - rewire SP Power from the model's hard-coded two-step ramp
% (8.667 MW for t<1500s, then a 300s ramp to 13 MW) to a constant
% workspace variable SP_POWER_CMD (default 13), implementing:
% duty is the fixed, hard-coded 13 MW design point from t=0, in both families, with no
% duty axis anywhere. This is NOT a new judgement call -- it is the exact mechanism
% P1_06_duty_envelope_probe.m already prototyped and validated on a throwaway copy; this script
% applies it permanently to AvonGasTurbineDgTwin_fixed, which every probe needs in order to
% be measuring the dataset's actual design rather than the model's legacy test-harness ramp.
%
% FOUND 2026-10-09, during every probe run so far this session (the sensor-drift
% probe, the depth sweep, and the first warm-start attempt) was simulated under the model's
% UNMODIFIED default duty profile -- the hard-coded Ramp2/Ramp3/Gain(13/45) chain -- NOT a
% constant 13 MW from t=0. P1_06 only ever applied the fix to a THROWAWAY probe copy
% (AvonGasTurbineDgTwin_probe.slx); nothing before this script ever applied it to
% AvonGasTurbineDgTwin_fixed itself. The warm-start probe's own checkpoint data is what surfaced
% it: residual-to-final was flat across 300-1200s then jumped sharply at 1800s, at EVERY ambient
% tested -- exactly the signature of the model's own 1500-1800s duty step, not a real settling
% transient. This invalidates the depth sweep run under the old wiring; it must be re-run after
% this fix. See for the full account and the correction this requires.
%
% Usage: P1b_02_fix_duty_command('AvonGasTurbineDgTwin_fixed')
%   (idempotent: if SP_Power_Cmd already exists, reports and does nothing)

if nargin < 1 || isempty(modelName)
    modelName = 'AvonGasTurbineDgTwin_fixed';
end

cd(fileparts(fileparts(mfilename('fullpath'))));
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
mdlFile = strrep(ScenarioConfig.SIMULINK_MODEL, 'AvonGasTurbineDgTwin', modelName);
load_system(mdlFile);
M = modelName;

if ~isempty(find_system(M, 'Name', 'SP_Power_Cmd'))
    fprintf('P1b_02: SP_Power_Cmd already present on %s -- no change.\n', M);
    return;
end

% Same pattern as P1_06_duty_envelope_probe.m: delete the Gain->Subsystem2 line and insert a
% Constant block driven by a workspace variable (default 13, matching).
delete_line(M, 'Gain/1', 'Subsystem2/2');
pos = get_param([M '/Gain'], 'Position');
add_block('simulink/Sources/Constant', [M '/SP_Power_Cmd'], ...
    'Value', 'SP_POWER_CMD', 'Position', [pos(1), pos(2)+80, pos(3), pos(4)+80]);
add_line(M, 'SP_Power_Cmd/1', 'Subsystem2/2', 'autorouting', 'on');
assignin('base', 'SP_POWER_CMD', 13);   % default; every probe script still sets it explicitly

save_system(M);
fprintf('P1b_02: SP Power rewired to workspace variable SP_POWER_CMD (default 13) on %s, saved.\n', M);
end
