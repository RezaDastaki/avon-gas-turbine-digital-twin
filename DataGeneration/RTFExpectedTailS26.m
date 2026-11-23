function [S26_expected, T_q, P_q] = RTFExpectedTailS26(LIB, T_C, P_kPa)
% RTFExpectedTailS26 - The warm-start library's Healthy prediction of clean tail S26 at a drawn
% compressor-inlet temperature and pressure: the 2-D (temperature x pressure) measured bilinear
% surface of the per-cycle ambient check. One call site shared by
% RunRTFUnit.m (the check itself) and RestoreRTFUnitState.m (which needs the identical number to
% rebuild a stored cycle's clean tail S26 from the stored absolute residual), so the two cannot
% evaluate the surface differently.
%
% Inputs:  LIB = GetWarmStartLibrary; T_C, P_kPa = the cycle's drawn ambient.
% Outputs: S26_expected (degC) and the query point actually used (T_q, P_q). Errors if the drawn
%          ambient lies outside the surface's grid, exactly as the check always has (a clamped
%          query would silently hide an out-of-range draw).
%

    T_q = min(max(T_C,   min(LIB.chk_inlet_temp_C)),  max(LIB.chk_inlet_temp_C));
    P_q = min(max(P_kPa, min(LIB.chk_inlet_press_kPa)), max(LIB.chk_inlet_press_kPa));
    if abs(T_q - T_C) > 1e-6 || abs(P_q - P_kPa) > 1e-6
        error('RTFExpectedTailS26:OutsideGrid', ...
            'drawn ambient (T=%.4f, P=%.4f) is outside the ambient-check grid.', T_C, P_kPa);
    end
    S26_expected = interp2(LIB.chk_inlet_press_kPa, LIB.chk_inlet_temp_C, LIB.chk_S26_C, P_q, T_q, 'linear');
end
