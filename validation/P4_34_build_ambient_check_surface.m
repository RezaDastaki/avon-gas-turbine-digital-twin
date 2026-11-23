% P4_34_BUILD_AMBIENT_CHECK_SURFACE
%
% Builds the ambient check's SECOND library axis: a 2-D (compressor inlet temperature x
% compressor inlet pressure) measured surface, replacing the 1-D temperature-only lookup that
% false-failed 6 of 43 real records. Reuses P4_20's exact recipe --
% Healthy, fixed 13 MW duty, DUR=7800, OUT_DT=1, other three ambient axes at
% ScenarioConfig.AmbientConfig.nom, clean tail mean -- varying temperature AND pressure
% together on a 2-D grid instead of temperature alone.
%
% Grid:
%   Temperature -- 31 points, non-uniform: 8:2:16 (smooth), 17:1:32 (the kink band, resolved to
%   1 C because that is the only sizeable interpolation error source), 34:2:52 (pinned at 846).
%   Pressure -- phase 1, 5 points: 95, 97, 99.2, 101, 103 (99.2 is the existing library's nominal
%   pressure ON PURPOSE -- the new surface's 99.2 column is a free regression test against the
%   old 1-D library, A1). Phase 2 (4 more columns) runs ONLY if A3 demands it.
%
% SCOPE LIMIT, stated because it is the easiest thing here to get wrong: this script
% does NOT touch the four existing warm-start variables (inlet_temp_C, S24_omega_radps,
% S27_omega_radps, S26_final_C, S28_final_MW) read by SetWarmStartInitialConditions.m. It
% APPENDS four new chk_* variables to the SAME .mat file, read only by
% ComputeLayer1RecordAttributes.m via GetWarmStartLibrary.m. A6 proves the four warm-start
% variables are untouched.
%
% Output: four new variables appended to Core/Models/P4_operating_point_library.mat --
%   chk_inlet_temp_C  [31x1]
%   chk_inlet_press_kPa [Px1]  (P=5 phase 1, 9 if phase 2 runs)
%   chk_S26_C         [31xP]
%   chk_S24_radps     [31xP]
% plus phases/ in long format for inspection and for
% validator (P4_31_gate_s_validate.py reads THIS file, not P4_20's item 10).
%
% Usage (from the repository root): run('validation/P4_34_build_ambient_check_surface.m')

cd(fileparts(fileparts(mfilename('fullpath'))));
run('setup_paths.m');

PH    = [AvonLogDir() filesep];
MODEL = ScenarioConfig.SIMULINK_MODEL;
[~, shortname] = fileparts(MODEL);
if bdIsLoaded(shortname); close_system(shortname, 0); end
load_system(MODEL);
set_param(shortname, 'FastRestart', 'on');

DUR    = 7800;   % StopTime constant for the whole FastRestart session
OUT_DT = 1;

GRID_T = [8:2:16, 17:1:32, 34:2:52];   % 31-point non-uniform grid
GRID_P = [95, 97, 99.2, 101, 103];     % phase 1, 5 points

A = ScenarioConfig.AmbientConfig(); NOM = A.nom;

nT = numel(GRID_T);
nP = numel(GRID_P);
rows = {};  % long format: temp, press, completed, S26, S24, S27, S28

S26_C    = NaN(nT, nP);
S24_radps = NaN(nT, nP);
S27_radps = NaN(nT, nP);
S28_MW    = NaN(nT, nP);

t0 = tic;
idx = 0;
for iP = 1:nP
    P = GRID_P(iP);
    for iT = 1:nT
        T = GRID_T(iT);
        idx = idx + 1;
        fprintf('\n############ Ambient-check surface build %d/%d, T=%g C, P=%g kPa ############\n', ...
            idx, nT*nP, T, P);
        LoadScenarioToWorkspace('healthy', 180000 + idx, 1);
        assignin('base', 'ENV_comp_inlet_temp_C',    T);
        assignin('base', 'ENV_FG_pressure_kPa',      NOM.FG_pressure_kPa);
        assignin('base', 'ENV_FG_temp_C',            NOM.FG_temp_C);
        assignin('base', 'ENV_comp_inlet_press_kPa', P);
        assignin('base', 'ENV_ambient_moisture_pct', NOM.ambient_moisture_percent);
        assignin('base', 'SP_POWER_CMD', 13);

        ok = RunSimulinkModel(MODEL, DUR);
        if ~ok
            rows(end+1,:) = {T, P, 0, NaN, NaN, NaN, NaN}; %#ok<AGROW>
            fprintf('  T=%g C, P=%g kPa: FAILED\n', T, P);
            continue;
        end
        [sa, tv] = ExtractSensorsFromWorkspace(OUT_DT, DUR);
        tailIdx = tv >= DUR - 179;
        s24 = mean(sa(tailIdx, 24));
        s27 = mean(sa(tailIdx, 27));
        s26 = mean(sa(tailIdx, 26));
        s28 = mean(sa(tailIdx, 28));
        rows(end+1,:) = {T, P, 1, s26, s24, s27, s28}; %#ok<AGROW>
        S26_C(iT, iP)     = s26;
        S24_radps(iT, iP) = s24;
        S27_radps(iT, iP) = s27;
        S28_MW(iT, iP)    = s28;
        fprintf('  T=%g C, P=%g kPa: S26=%.3f C  S24=%.4f rad/s  S27=%.4f rad/s  S28=%.4f MW\n', ...
            T, P, s26, s24, s27, s28);
    end
end
fprintf('\nBuild pass done in %.1f s (%d points, %.2f s/point)\n', toc(t0), nT*nP, toc(t0)/(nT*nP));

LongT = cell2table(rows, 'VariableNames', ...
    {'inlet_temp_C','inlet_press_kPa','completed','S26_C','S24_radps','S27_radps','S28_MW'});
writetable(LongT, [PH 'P4_34_ambient_check_surface.csv']);
fprintf('Wrote %s\n', [PH 'P4_34_ambient_check_surface.csv']);

if any(LongT.completed == 0)
    error('P4_34:IncompleteGrid', '%d of %d grid points failed to complete -- fix before building the surface.', ...
        sum(LongT.completed == 0), height(LongT));
end

% --- Append the four chk_* variables to the EXISTING .mat (never rewrite the warm-start four) ---
chk_inlet_temp_C    = GRID_T(:);
chk_inlet_press_kPa = GRID_P(:);
chk_S26_C           = S26_C;
chk_S24_radps       = S24_radps;

libMatPath = 'Core/Models/P4_operating_point_library.mat';
save(libMatPath, 'chk_inlet_temp_C', 'chk_inlet_press_kPa', 'chk_S26_C', 'chk_S24_radps', '-append');
fprintf('Appended chk_* variables to %s\n', libMatPath);

disp(LongT);
fprintf('\n=== P4_34_build_ambient_check_surface: done ===\n');
