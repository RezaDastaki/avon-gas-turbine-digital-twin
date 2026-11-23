function LIB = GetWarmStartLibrary()
% GetWarmStartLibrary - the single, process-cached load of the measured
% operating-point warm-start library (Core/Models/P4_operating_point_library.mat).
%
% Factored out of SetWarmStartInitialConditions.m (spec/9.2.3) so the
% drawn-vs-realised ambient check in ComputeLayer1RecordAttributes.m can reuse the SAME
% already-loaded library ("this check costs one interp1 and one mean") instead of opening the
% .mat a second time per record.
%
% added four chk_* variables to the SAME.mat file -- the
% ambient check's own 2-D (temperature x pressure) surface. They are a SEPARATE use of the
% file from the four warm-start variables below: GetWarmStartLibrary.m caches and returns both,
% but SetWarmStartInitialConditions.m reads only the first four (untouched, byte-identical --
% A6) and ComputeLayer1RecordAttributes.m reads only the chk_* four. A library built before
% has no chk_* variables; loading it must fail loudly, not silently fall back to the
% retired 1-D check.
%
% Output: LIB struct --
%   inlet_temp_C, S24_omega_radps, S27_omega_radps, S26_final_C   [21x1], 10:2:50 grid (warm start)
%   route, grid_description                                       (warm start)
%   chk_inlet_temp_C   [31x1] non-uniform 8-52 C grid (ambient check surface)
%   chk_inlet_press_kPa [Px1] 95-103 kPa grid (ambient check surface)
%   chk_S26_C, chk_S24_radps [31xP]           (ambient check surface)
%
%
% the turndown sub-family runs at a SECOND
% fixed duty (10 MW) whose equilibria and limiter boundary differ from the 13 MW design point
% so it needs its own warm-start/ambient-check artefacts. This
% function is NOT in the frozen list (item 1; only LoadScenarioToWorkspace.m:112 is the
% named exception), so the duty-aware SELECTION lives here -- every frozen caller
% (SetWarmStartInitialConditions.m, ComputeLayer1RecordAttributes.m) reads only the generic
% field names below and is unaware which file they came from. The cache key is the duty itself,
% so a single process is never trapped on whichever duty it first resolved.
%
% At 13 MW (the default / any value other than 10), behaviour is BYTE-IDENTICAL to before this
% change -- same file, same variable names, same error paths.

    persistent LIB_CACHE_BY_DUTY
    if isempty(LIB_CACHE_BY_DUTY)
        LIB_CACHE_BY_DUTY = containers.Map('KeyType', 'double', 'ValueType', 'any');
    end

    duty_mw = ScenarioConfig.DUTY_CMD_MW();
    if abs(duty_mw - 10) < 1e-9
        lib_path = 'Core/Models/P4_operating_point_library_10MW.mat';
        duty_key = 10;
    else
        lib_path = 'Core/Models/P4_operating_point_library.mat';
        duty_key = 13;
    end

    if ~isKey(LIB_CACHE_BY_DUTY, duty_key)
        if ~exist(lib_path, 'file')
            error('GetWarmStartLibrary:NoLibrary', ...
                'Warm-start library not found: %s. Run P4_20_build_operating_point_library.m (or, at 10 MW, the 10 MW build) first.', lib_path);
        end
        if duty_key == 10
            raw = load(lib_path, 'inlet_temp_C', 'S24_omega_radps', 'S27_omega_radps', 'S26_final_C', ...
                'chk_inlet_temp_C_10MW', 'chk_inlet_press_kPa_10MW', 'chk_S26_C_10MW', 'chk_S24_radps_10MW');
            required_chk = {'chk_inlet_temp_C_10MW', 'chk_inlet_press_kPa_10MW', 'chk_S26_C_10MW', 'chk_S24_radps_10MW'};
            for i = 1:numel(required_chk)
                if ~isfield(raw, required_chk{i})
                    error('GetWarmStartLibrary:NoAmbientCheckSurface', ...
                        ['%s missing from %s -- the 10 MW ambient-check surface ', ...
                         'has not been built. Build the 10 MW ambient-check surface first.'], ...
                        required_chk{i}, lib_path);
                end
            end
            % Re-key to the generic field names every frozen caller expects.
            entry.inlet_temp_C        = raw.inlet_temp_C;
            entry.S24_omega_radps     = raw.S24_omega_radps;
            entry.S27_omega_radps     = raw.S27_omega_radps;
            entry.S26_final_C         = raw.S26_final_C;
            entry.chk_inlet_temp_C    = raw.chk_inlet_temp_C_10MW;
            entry.chk_inlet_press_kPa = raw.chk_inlet_press_kPa_10MW;
            entry.chk_S26_C           = raw.chk_S26_C_10MW;
            entry.chk_S24_radps       = raw.chk_S24_radps_10MW;
        else
            entry = load(lib_path, 'inlet_temp_C', 'S24_omega_radps', 'S27_omega_radps', 'S26_final_C', ...
                'chk_inlet_temp_C', 'chk_inlet_press_kPa', 'chk_S26_C', 'chk_S24_radps');
            required_chk = {'chk_inlet_temp_C', 'chk_inlet_press_kPa', 'chk_S26_C', 'chk_S24_radps'};
            for i = 1:numel(required_chk)
                if ~isfield(entry, required_chk{i})
                    error('GetWarmStartLibrary:NoAmbientCheckSurface', ...
                        ['%s missing from %s -- the 2-D ambient-check surface ', ...
                         'has not been built. Run validation/P4_34_build_ambient_check_surface.m first.'], ...
                        required_chk{i}, lib_path);
                end
            end
        end
        LIB_CACHE_BY_DUTY(duty_key) = entry; %#ok<NASGU>
    end
    LIB = LIB_CACHE_BY_DUTY(duty_key);
end
