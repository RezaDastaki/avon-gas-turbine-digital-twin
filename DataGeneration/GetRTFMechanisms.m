function rtf = GetRTFMechanisms()
% GetRTFMechanisms - The 13 run-to-failure mechanisms and their shaping parameters.
%
% Source of truth for membership and the per-mechanism trajectory shape
% (rtf_member='yes';
% DESIGN_run_to_failure.md for folder names). Do not hand-maintain this list elsewhere --
% GenerateRTFFamily.m, RunRTFUnit.m and RTFAlreadyDone.m should all read it from here.
%
% Returns struct with parallel [13x1] arrays:
%   FaultID        - the diagnosis-family fault_id this mechanism corresponds to (1-42)
%   Name            - released fault name
%   Folder          - on-disk mechanism folder name (DESIGN_run_to_failure.md)
%   DeltaEOL        - the deviation axis value at end-of-life depth
%                     (rtf_depth_max)
%   DeltaSEV1       - the deviation axis value at the diagnosis family's SEV1 crossing
%                     (k=12 noise-referenced rule)
%   PExponent       - log(DeltaSEV1/DeltaEOL) / log(0.20), the derived shaping exponent --
%                     stored, not recomputed, so a future change to DeltaSEV1/DeltaEOL is forced
%                     to re-derive it rather than silently drift
%
% NOTE: F25 (GGInletPressureLoss) and F30 (PTNetPowerLoss) are DROPPED and
% deliberately absent here, per the two renames in DESIGN_run_to_failure.md/--
% no folder under either name is ever created.
%

    rtf.FaultID = [2; 3; 5; 11; 16; 17; 21; 22; 23; 24; 26; 27; 28];

    rtf.Name = {   % fault_catalogue.csv 'name' (-> HDF5 attr 'mechanism')
        'Compressor fouling (isentropic-efficiency loss)';  % F02
        'Compressor blade damage (isentropic-efficiency loss)';  % F03
        'Diffuser damage (pressure-ratio loss)';  % F05
        'Fuel pump degradation (fuel line-pressure loss)';  % F11
        'Combustor liner distress (combustor air-flow loss surrogate)';  % F16
        'Fuel nozzle clogging (combustor fuel-flow restriction)';  % F17
        'GG turbine fouling (efficiency loss)';  % F21
        'GG turbine blade damage (efficiency loss)';  % F22
        'GG nozzle blockage (hot-gas flow restriction)';  % F23
        'GG seal degradation (cooling-air leakage increase)';  % F24
        'PT fouling (efficiency loss)';  % F26
        'PT blade damage (efficiency loss)';  % F27
        'PT nozzle damage (hot-gas flow change)';  % F28
    };

    rtf.Folder = {   % RTF_<fault_id>_<code>
        'RTF_F02_CompressorFouling';
        'RTF_F03_CompressorBladeDamage';
        'RTF_F05_DiffuserDamage';
        'RTF_F11_FuelPumpDegradation';
        'RTF_F16_LinerDistress';
        'RTF_F17_NozzleClogging';
        'RTF_F21_GGTurbineFouling';
        'RTF_F22_GGBladeDamage';
        'RTF_F23_GGNozzleBlockage';
        'RTF_F24_GGSealDegradation';
        'RTF_F26_PTFouling';
        'RTF_F27_PTBladeDamage';
        'RTF_F28_PTNozzleDamage';
    };

    % delta_EOL, cross-checked against rtf_depth_max column.
    rtf.DeltaEOL = [0.133333; 0.133333; 0.266667; 0.266667; 0.088889; 0.5; ...
                    0.088889; 0.088889; 0.088889; 0.4; 0.133333; 0.133333; 0.133333];

    % delta_SEV1 table.
    rtf.DeltaSEV1 = [0.000637; 0.000637; 0.002272; 0.000090; 0.001033; 0.002560; ...
                     0.000234; 0.000237; 0.001013; 0.000737; 0.000310; 0.000316; 0.000401];

    % p = log(delta_SEV1/delta_EOL) / log(0.20), f_incipient = 0.20. Stored to the same
    % precision as the spec table; recompute and compare before trusting a hand-edit of the two
    % columns above.
    rtf.PExponent = [3.32; 3.32; 2.96; 4.97; 2.77; 3.28; 3.69; 3.68; 2.78; 3.91; 3.77; 3.76; 3.61];

    rtf.Count = numel(rtf.FaultID);

end
