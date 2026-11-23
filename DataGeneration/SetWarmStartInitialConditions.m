function result = SetWarmStartInitialConditions(model_short_name, drawn_temp_C)
% SetWarmStartInitialConditions - Route B.
%
% Sets the PT and GG rotor-speed integrator InitialCondition parameters from the measured
% operating-point library (Core/Models/P4_operating_point_library.mat, built by
% validation/P4_20_build_operating_point_library.m: 21-point, 2 degC grid, 10-50 degC,
% Healthy, fixed 13 MW duty), nearest-grid-point lookup on the record's drawn compressor-inlet
% temperature.
%
% Block paths are DISCOVERED, not hard-coded ("Do not
% hard-code a block path you have not confirmed in the loaded model") -- find_system by
% BlockType + subsystem-name pattern, so a model restructuring fails loudly here rather than
% silently warm-starting the wrong state.
%
% Inputs:
%   model_short_name - the LOADED model's bare name (set_param/find_system target, not a path)
%   drawn_temp_C     - this record's drawn compressor_inlet_temp_C
%
% Output:
%   result - struct: nearest_temp_C, S24_omega_radps, S27_omega_radps, pt_block, gg_block
%

    % loaded once per process via GetWarmStartLibrary.m, not re-read here,
    % so ComputeLayer1RecordAttributes.m's ambient check reuses the SAME cached library.
    LIB = GetWarmStartLibrary();

    [~, nearest_idx] = min(abs(LIB.inlet_temp_C - drawn_temp_C));
    result.nearest_temp_C   = LIB.inlet_temp_C(nearest_idx);
    result.S24_omega_radps  = LIB.S24_omega_radps(nearest_idx);
    result.S27_omega_radps  = LIB.S27_omega_radps(nearest_idx);

    pt_candidates = find_system(model_short_name, 'BlockType', 'Integrator');
    is_pt = contains(pt_candidates, '/PowerTurbine/') & contains(pt_candidates, 'rotor dynamic') & ...
        endsWith(pt_candidates, 'Integrator1');
    is_gg = contains(pt_candidates, '/GasGenerator/') & contains(pt_candidates, 'rotor dynamic') & ...
        endsWith(pt_candidates, 'Integrator1');

    if sum(is_pt) ~= 1
        error('SetWarmStartInitialConditions:PTBlockNotFound', ...
            'Expected exactly 1 PowerTurbine rotor-dynamic Integrator1, found %d. Model hierarchy may have changed -- stop and check manually.', sum(is_pt));
    end
    if sum(is_gg) ~= 1
        error('SetWarmStartInitialConditions:GGBlockNotFound', ...
            'Expected exactly 1 GasGenerator rotor-dynamic Integrator1, found %d. Model hierarchy may have changed -- stop and check manually.', sum(is_gg));
    end

    result.pt_block = pt_candidates{is_pt};
    result.gg_block = pt_candidates{is_gg};

    set_param(result.pt_block, 'InitialCondition', num2str(result.S27_omega_radps, '%.10g'));
    set_param(result.gg_block, 'InitialCondition', num2str(result.S24_omega_radps, '%.10g'));
end
