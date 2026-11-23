% P4_20_BUILD_OPERATING_POINT_LIBRARY
%
% Builds the warm-start library: the ambient -> PT/GG rotor-speed equilibrium map on a
% 21-point compressor-inlet-temperature grid (10 to 50 C, 2 C steps), at the fixed 13 MW design
% duty, Healthy, other four ambient axes at ScenarioConfig.AmbientConfig.nom.
%
% ROUTE A (full Simulink.op.ModelOperatingPoint snapshot) vs ROUTE B (measured initial
% conditions on the two rotor integrators)/2.3. Route A was tried first, per spec:
%   - P1b_05's 3rd obstacle (all-zero/missing sensors after a restore) reproduces IMMEDIATELY
%     (not "from the 3rd point on") when sensors are read via a bare evalin('base', ...) after a
%     LoadInitialState restore -- because GasGen_Speed_SECF210_rpm/PwrTrb_Speed_SECF243_rpm are
%     NOT auto-populated into the base workspace by sim when its return value is captured (as
%     it must be, to get the SaveCompleteFinalSimState object back); they only land in base
%     workspace via RunSimulinkModel.m's own post-sim extraction loop
%     (assignin('base', prop, simOut.(prop)) over every non-empty SimulationOutput property).
%   - Using THAT extraction pattern, a real restore-and-continue test (4 ambients, snapshot at
%     t=7800s, restored run to t=8100s) WORKS for the two channels that matter: S27 reproduces
%     the measured equilibrium (513.23 / 513.23 / 487.24 / 447.66 rad/s at 10/20/35/50 C,
%     matching) and drifts by <=0.0065 rad/s over the next 300s
%     -- i.e. Route A IS mechanically viable for S24/S27, once routed through the right
%     extraction call. (snapshotTime is READ-ONLY in this MATLAB release, so the restored run's
%     clock cannot be reset to 0; it must continue the snapshot's own absolute clock instead --
%     this is the one change from the spec's literal prescription, forced by the API.)
%   - BUT: `snapshotTime` being non-zero means every one of the OTHER 37 channels -- most
%     extracted via ExtractSensorsFromWorkspace.m's extract_zz helper, whose t_src is HARD-
%     CODED as linspace(0, target_duration, size(data,1)), ignoring the real 'time' variable
%     entirely -- would be silently misread for a restored run. Making Route A correct for
%     production would require patching that shared extraction function (used by every one of
%     the 110,000 diagnosis records and every RTF cycle) to accept a nonzero start time. That is
%     a materially larger, more invasive change than this task's budget, and the spec does not
%     ask for it -- Route B needs zero such changes and is the explicitly sanctioned fallback.
%   - CONCLUSION: ship Route B as the active route. Route A's partial result (S24/S27 only, via
%     the corrected extraction pattern) is recorded here and as a finding,
%     not engineered further.
%
% Route B: 21 long (7800s) Healthy runs on the grid, reading the clean S24/S27 tail mean
% directly (consistent with -- these are ground-truth plant states, not instrument
% readings, so there is no measurement-model distinction here: S24/S27 raw ARE the "clean"
% signal already, ExtractSensorsFromWorkspace never applies ApplyMeasurementModel.m).
%
% Output: P4_operating_point_library.mat (struct array: inlet_temp_C, S24_omega_radps,
%         S27_omega_radps, route='measured_ic'), next to the model, plus a CSV for inspection.
%
% Usage (from the repository root): run('validation/P4_20_build_operating_point_library.m')

cd(fileparts(fileparts(mfilename('fullpath'))));
run('setup_paths.m');

PH    = [AvonLogDir() filesep];
MODEL = ScenarioConfig.SIMULINK_MODEL;
[~, shortname] = fileparts(MODEL);
if bdIsLoaded(shortname); close_system(shortname, 0); end
load_system(MODEL);
set_param(shortname, 'FastRestart', 'on');

DUR    = 7800;   % the longest per-record total in the release (3600 preroll + 4200 stored)
OUT_DT = 1;
GRID_T = 10:2:50;   % 21-point, 2 C grid

A = ScenarioConfig.AmbientConfig(); NOM = A.nom;

rows = {};
t0 = tic;
for T = GRID_T
    fprintf('\n############ Warm-start library build, inlet=%g C ############\n', T);
    LoadScenarioToWorkspace('healthy', 160000 + round(T*10), 1);
    assignin('base', 'ENV_comp_inlet_temp_C',    T);
    assignin('base', 'ENV_FG_pressure_kPa',      NOM.FG_pressure_kPa);
    assignin('base', 'ENV_FG_temp_C',            NOM.FG_temp_C);
    assignin('base', 'ENV_comp_inlet_press_kPa', NOM.compressor_inlet_press_kPa);
    assignin('base', 'ENV_ambient_moisture_pct', NOM.ambient_moisture_percent);
    assignin('base', 'SP_POWER_CMD', 13);

    ok = RunSimulinkModel(MODEL, DUR);
    if ~ok
        rows(end+1,:) = {T, 0, NaN, NaN, NaN, NaN}; %#ok<AGROW>
        fprintf('  T=%g C: FAILED\n', T);
        continue;
    end
    [sa, tv] = ExtractSensorsFromWorkspace(OUT_DT, DUR);
    tailIdx = tv >= DUR - 179;
    s24 = mean(sa(tailIdx, 24));
    s27 = mean(sa(tailIdx, 27));
    s26 = mean(sa(tailIdx, 26));
    s28 = mean(sa(tailIdx, 28));
    rows(end+1,:) = {T, 1, s24, s27, s26, s28}; %#ok<AGROW>
    fprintf('  T=%g C: S24=%.4f rad/s  S27=%.4f rad/s  S26=%.2f C  S28=%.4f MW\n', T, s24, s27, s26, s28);
end
fprintf('\nBuild pass done in %.1f s (%d points)\n', toc(t0), numel(GRID_T));

LibT = cell2table(rows, 'VariableNames', {'inlet_temp_C','completed','S24_omega_radps', ...
    'S27_omega_radps','S26_final_C','S28_final_MW'});
writetable(LibT, [PH 'P4_20_operating_point_library.csv']);
fprintf('Wrote %s\n', [PH 'P4_20_operating_point_library.csv']);

if any(LibT.completed == 0)
    error('P4_20:IncompleteGrid', '%d of %d grid points failed to complete -- fix before building the .mat library.', ...
        sum(LibT.completed == 0), height(LibT));
end

% --- Build the .mat library RunSimulinkModel.m/RunScenario.m will actually read ---
inlet_temp_C     = LibT.inlet_temp_C;
S24_omega_radps  = LibT.S24_omega_radps;
S27_omega_radps  = LibT.S27_omega_radps;
route            = repmat({'measured_ic'}, height(LibT), 1);
grid_description  = ['Route B (measured initial conditions), 21-point 2 C grid, 10-50 C, ', ...
    'Healthy, fixed 13 MW duty, other 4 ambient axes at AmbientConfig().nom. ', ...
    'P4_scenario_grid_and_storage.md Sec2.3; Route A findings in the header comment above.'];

% S26_final_C/S28_final_MW added: the drawn-vs-realised ambient check
% (ComputeLayer1RecordAttributes.m, GetWarmStartLibrary.m) interpolates S26_final_C against
% this grid, so a rebuild of this library must keep saving it.
S26_final_C      = LibT.S26_final_C;
S28_final_MW     = LibT.S28_final_MW;

libMatPath = 'Core/Models/P4_operating_point_library.mat';
save(libMatPath, 'inlet_temp_C', 'S24_omega_radps', 'S27_omega_radps', 'S26_final_C', ...
    'S28_final_MW', 'route', 'grid_description');
fprintf('Wrote %s\n', libMatPath);

disp(LibT);
fprintf('\n=== P4_20_build_operating_point_library: done ===\n');
