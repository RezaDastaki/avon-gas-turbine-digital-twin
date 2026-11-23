% ExtractSensorsFromWorkspace.m
% Extract all 34 sensor measurements from AvonGasTurbineDgTwin simulation
% Handles multi-column arrays, timeseries objects, and resampling
%
% Usage:
%   [sensor_array, time_vector, sensor_info] = ExtractSensorsFromWorkspace(target_dt, target_duration)
%
% Inputs:
%   target_dt       - Target sampling interval in seconds (default: 1.0 for 1 Hz)
%   target_duration - Target simulation duration in seconds (default: 4800)
%
% Outputs:
%   sensor_array - [N × 34] matrix of sensor measurements (columns = S01-S34)
%   time_vector  - [N × 1] time vector at target sampling rate
%   sensor_info  - Struct with sensor metadata and extraction status
%
% Date: 2025 | Updated: 2026-02-21 (expanded to 34 sensors)

function [sensor_array, time_vector, sensor_info] = ExtractSensorsFromWorkspace(target_dt, target_duration)

    %% Input validation
    if nargin < 1 || isempty(target_dt)
        target_dt = 1.0;
    end
    if nargin < 2 || isempty(target_duration)
        target_duration = 4800;
    end

    fprintf('\n========================================\n');
    fprintf('  Sensor Extraction from Workspace\n');
    fprintf('  39-channel configuration (34 physical + 5 context)\n');
    fprintf('========================================\n\n');
    fprintf('Target sampling rate: %.2f Hz (dt = %.3f s)\n', 1/target_dt, target_dt);
    fprintf('Target duration: %.1f seconds\n\n', target_duration);

    %% Create target time vector
    time_vector = (0:target_dt:target_duration)';
    N = length(time_vector);
    fprintf('Target samples: %d\n\n', N);

    %% Initialize output (39 channels: 34 physical + 5 ambient context)
    SensorDef = GetSensorDefinitions();
    sensor_array = zeros(N, SensorDef.Count);

    %% Get Simulink time vector (used by SECF/PDT variables)
    sim_time = [];
    if evalin('base', 'exist(''time'', ''var'')')
        sim_time = evalin('base', 'time');
        sim_time = squeeze(sim_time(:));
        fprintf('✓ Simulink time vector: %d samples [%.1f, %.1f] s\n\n', ...
            length(sim_time), sim_time(1), sim_time(end));
    else
        fprintf('⚠ ''time'' variable not found — using index-based resampling for SECF/PDT vars\n\n');
    end

    fprintf('=== Extracting Sensors ===\n');

    % -------------------------------------------------------------------------
    % LOCAL HELPER: extract a zz_data_* or similar workspace variable.
    % These are stored as NxM arrays (M=1 or 2). If M=2, column 2 is the value.
    % Time axis is assumed uniform over [0, target_duration].
    % -------------------------------------------------------------------------
    function val = extract_zz(var_name, col_idx)
        data = evalin('base', var_name);
        if isa(data, 'timeseries')
            t_src = data.Time(:);
            d = squeeze(data.Data);
            d = d(:);
            val = interp1(t_src, d, time_vector, 'linear', 'extrap');
            return;
        end
        data = squeeze(data);
        if isvector(data)
            data = data(:);
        end
        t_src = linspace(0, target_duration, size(data, 1))';
        if nargin < 2
            col_idx = [];
        end
        if size(data, 2) > 1
            % Use specified column, or auto-select col 2 (data), or last col
            if ~isempty(col_idx)
                d = data(:, col_idx);
            else
                d = data(:, 2);
            end
        else
            d = data(:, 1);
        end
        val = interp1(t_src, d, time_vector, 'linear', 'extrap');
    end

    % -------------------------------------------------------------------------
    % LOCAL HELPER: extract a timed variable (uses Simulink time vector).
    % Used for Prss_*, PDT_*, SECF* variables.
    % -------------------------------------------------------------------------
    function val = extract_timed(var_name)
        data = evalin('base', var_name);
        data = squeeze(data);
        data = data(:);
        % Use sim_time only when lengths match; otherwise fall back to linspace.
        % Mismatch occurs when the signal uses variable-step logging (11223 pts)
        % while sim_time was logged at a different rate (10000 pts).
        if ~isempty(sim_time) && length(sim_time) == length(data)
            val = interp1(sim_time, data, time_vector, 'linear', 'extrap');
        else
            val = interp1(linspace(0, target_duration, length(data))', data, time_vector, 'linear', 'extrap');
        end
    end

    % =========================================================================
    % GROUP 1: FUEL GAS LINE  (S01–S05)
    % =========================================================================

    %% S01: FG supply pressure before MCV (kPa)
    try
        if evalin('base', 'exist(''Prss_FG_Bfr_MCV_PT203_kPa'', ''var'')')
            sensor_array(:, 1) = extract_timed('Prss_FG_Bfr_MCV_PT203_kPa');
            fprintf('✓ S01: FG supply pressure          [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,1)), max(sensor_array(:,1)));
        else; warning('S01: Prss_FG_Bfr_MCV_PT203_kPa not found'); end
    catch ME; warning('S01 extraction failed: %s', ME.message); end

    %% S02: FG MCV downstream pressure (kPa)
    try
        if evalin('base', 'exist(''Prss_FG_Aftr_MCV_PT204_kPa'', ''var'')')
            sensor_array(:, 2) = extract_timed('Prss_FG_Aftr_MCV_PT204_kPa');
            fprintf('✓ S02: FG MCV downstream pressure  [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,2)), max(sensor_array(:,2)));
        else; warning('S02: Prss_FG_Aftr_MCV_PT204_kPa not found'); end
    catch ME; warning('S02 extraction failed: %s', ME.message); end

    %% S03: FG MCV stem position (%)
    try
        if evalin('base', 'exist(''zz_data_FGvalpos'', ''var'')')
            sensor_array(:, 3) = extract_zz('zz_data_FGvalpos');
            fprintf('✓ S03: FG MCV stem position        [%.2f, %.2f] %%\n', ...
                min(sensor_array(:,3)), max(sensor_array(:,3)));
        else; warning('S03: zz_data_FGvalpos not found'); end
    catch ME; warning('S03 extraction failed: %s', ME.message); end

    %% S04: Fuel mass flow rate (kg/s)
    try
        if evalin('base', 'exist(''zz_data_fuel'', ''var'')')
            sensor_array(:, 4) = extract_zz('zz_data_fuel');
            fprintf('✓ S04: Fuel mass flow              [%.3f, %.3f] kg/s\n', ...
                min(sensor_array(:,4)), max(sensor_array(:,4)));
        else; warning('S04: zz_data_fuel not found'); end
    catch ME; warning('S04 extraction failed: %s', ME.message); end

    %% S05: FG combustor inlet temperature (degC)
    try
        if evalin('base', 'exist(''zz_data_FG_temp'', ''var'')')
            sensor_array(:, 5) = extract_zz('zz_data_FG_temp');
            fprintf('✓ S05: FG combustor inlet temp     [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,5)), max(sensor_array(:,5)));
        else; warning('S05: zz_data_FG_temp not found'); end
    catch ME; warning('S05 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 2: AIR INTAKE  (S06–S08)
    % =========================================================================

    %% S06: Air filter differential pressure (kPa)
    try
        if evalin('base', 'exist(''PDT_139'', ''var'')')
            sensor_array(:, 6) = extract_timed('PDT_139');
            fprintf('✓ S06: Air filter dP               [%.3f, %.3f] kPa\n', ...
                min(sensor_array(:,6)), max(sensor_array(:,6)));
        else; warning('S06: PDT_139 not found'); end
    catch ME; warning('S06 extraction failed: %s', ME.message); end

    %% S07: Air mass flow rate (kg/s)
    try
        if evalin('base', 'exist(''zz_data_trbAirflow'', ''var'')')
            sensor_array(:, 7) = extract_zz('zz_data_trbAirflow');
            fprintf('✓ S07: Air mass flow               [%.2f, %.2f] kg/s\n', ...
                min(sensor_array(:,7)), max(sensor_array(:,7)));
        else; warning('S07: zz_data_trbAirflow not found'); end
    catch ME; warning('S07 extraction failed: %s', ME.message); end

    %% S08: IGV opening angle (deg)
    try
        if evalin('base', 'exist(''zz_data_IGVpos'', ''var'')')
            sensor_array(:, 8) = extract_zz('zz_data_IGVpos');
            fprintf('✓ S08: IGV opening angle           [%.2f, %.2f] deg\n', ...
                min(sensor_array(:,8)), max(sensor_array(:,8)));
        else; warning('S08: zz_data_IGVpos not found'); end
    catch ME; warning('S08 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 3: HP COMPRESSOR  (S09–S15)
    % =========================================================================

    %% S09: HP compressor pressure ratio
    try
        if evalin('base', 'exist(''zz_data_cpr'', ''var'')')
            sensor_array(:, 9) = extract_zz('zz_data_cpr');
            fprintf('✓ S09: Compressor pressure ratio   [%.2f, %.2f]\n', ...
                min(sensor_array(:,9)), max(sensor_array(:,9)));
        else; warning('S09: zz_data_cpr not found'); end
    catch ME; warning('S09 extraction failed: %s', ME.message); end

    %% S10: HP compressor discharge pressure (kPa)
    try
        if evalin('base', 'exist(''zz_data_CmpdisPress'', ''var'')')
            sensor_array(:, 10) = extract_zz('zz_data_CmpdisPress');
            fprintf('✓ S10: Compressor discharge press  [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,10)), max(sensor_array(:,10)));
        else; warning('S10: zz_data_CmpdisPress not found'); end
    catch ME; warning('S10 extraction failed: %s', ME.message); end

    %% S11: HP compressor discharge temperature (degC)
    try
        if evalin('base', 'exist(''zz_data_CmpdisTemp'', ''var'')')
            sensor_array(:, 11) = extract_zz('zz_data_CmpdisTemp');
            fprintf('✓ S11: Compressor discharge temp   [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,11)), max(sensor_array(:,11)));
        else; warning('S11: zz_data_CmpdisTemp not found'); end
    catch ME; warning('S11 extraction failed: %s', ME.message); end

    %% S12: HP compressor isentropic efficiency (%)
    try
        if evalin('base', 'exist(''zz_data_CompEff'', ''var'')')
            sensor_array(:, 12) = extract_zz('zz_data_CompEff');
            fprintf('✓ S12: Compressor efficiency       [%.3f, %.3f]\n', ...
                min(sensor_array(:,12)), max(sensor_array(:,12)));
        else; warning('S12: zz_data_CompEff not found'); end
    catch ME; warning('S12 extraction failed: %s', ME.message); end

    %% S13: HP compressor shaft power (MW)
    try
        if evalin('base', 'exist(''zz_data_comp_outPower'', ''var'')')
            sensor_array(:, 13) = extract_zz('zz_data_comp_outPower');
            fprintf('✓ S13: Compressor shaft power      [%.3f, %.3f] MW\n', ...
                min(sensor_array(:,13)), max(sensor_array(:,13)));
        else; warning('S13: zz_data_comp_outPower not found'); end
    catch ME; warning('S13 extraction failed: %s', ME.message); end

    %% S14: Rotor cooling air flow (kg/s)
    try
        if evalin('base', 'exist(''zz_data_comp_rotorCooling_flow'', ''var'')')
            sensor_array(:, 14) = extract_zz('zz_data_comp_rotorCooling_flow');
            fprintf('✓ S14: Rotor cooling flow          [%.3f, %.3f] kg/s\n', ...
                min(sensor_array(:,14)), max(sensor_array(:,14)));
        else; warning('S14: zz_data_comp_rotorCooling_flow not found'); end
    catch ME; warning('S14 extraction failed: %s', ME.message); end

    %% S15: Stator cooling air flow (kg/s)
    try
        if evalin('base', 'exist(''zz_data_comp_statorCooling_flow'', ''var'')')
            sensor_array(:, 15) = extract_zz('zz_data_comp_statorCooling_flow');
            fprintf('✓ S15: Stator cooling flow         [%.3f, %.3f] kg/s\n', ...
                min(sensor_array(:,15)), max(sensor_array(:,15)));
        else; warning('S15: zz_data_comp_statorCooling_flow not found'); end
    catch ME; warning('S15 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 4: COMBUSTOR  (S16–S18)
    % =========================================================================

    %% S16: Combustor exit temperature / TIT (degC)
    try
        if evalin('base', 'exist(''zz_data_combustorChamber_temp'', ''var'')')
            sensor_array(:, 16) = extract_zz('zz_data_combustorChamber_temp');
            fprintf('✓ S16: Combustor exit temp (TIT)   [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,16)), max(sensor_array(:,16)));
        else; warning('S16: zz_data_combustorChamber_temp not found'); end
    catch ME; warning('S16 extraction failed: %s', ME.message); end

    %% S17: Combustor exit pressure (kPa)
    try
        if evalin('base', 'exist(''zz_data_combustorChamber_press'', ''var'')')
            sensor_array(:, 17) = extract_zz('zz_data_combustorChamber_press');
            fprintf('✓ S17: Combustor exit pressure     [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,17)), max(sensor_array(:,17)));
        else; warning('S17: zz_data_combustorChamber_press not found'); end
    catch ME; warning('S17 extraction failed: %s', ME.message); end

    %% S18: Combustor exit mass flow (kg/s)
    try
        if evalin('base', 'exist(''zz_data_combustorChamber_flowrate'', ''var'')')
            sensor_array(:, 18) = extract_zz('zz_data_combustorChamber_flowrate');
            fprintf('✓ S18: Combustor exit flow rate    [%.2f, %.2f] kg/s\n', ...
                min(sensor_array(:,18)), max(sensor_array(:,18)));
        else; warning('S18: zz_data_combustorChamber_flowrate not found'); end
    catch ME; warning('S18 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 5: GAS GENERATOR TURBINE  (S19–S24)
    % =========================================================================

    %% S19: GG turbine inlet temperature (degC) — after stator cooling mix
    try
        if evalin('base', 'exist(''zz_data_ggTrbInletTemp'', ''var'')')
            sensor_array(:, 19) = extract_zz('zz_data_ggTrbInletTemp');
            fprintf('✓ S19: GG turbine inlet temp       [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,19)), max(sensor_array(:,19)));
        else; warning('S19: zz_data_ggTrbInletTemp not found'); end
    catch ME; warning('S19 extraction failed: %s', ME.message); end

    %% S20: GG turbine exhaust temperature (degC) — before rotor cooling mix
    try
        if evalin('base', 'exist(''zz_data_ggTrbExeTemp'', ''var'')')
            sensor_array(:, 20) = extract_zz('zz_data_ggTrbExeTemp');
            fprintf('✓ S20: GG turbine exhaust temp     [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,20)), max(sensor_array(:,20)));
        else; warning('S20: zz_data_ggTrbExeTemp not found'); end
    catch ME; warning('S20 extraction failed: %s', ME.message); end

    %% S21: GG rotor cooling exhaust temperature (degC)
    try
        if evalin('base', 'exist(''zz_data_ggTrbRotorCoolingExeTemp'', ''var'')')
            sensor_array(:, 21) = extract_zz('zz_data_ggTrbRotorCoolingExeTemp');
            fprintf('✓ S21: GG rotor cooling exit temp  [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,21)), max(sensor_array(:,21)));
        else; warning('S21: zz_data_ggTrbRotorCoolingExeTemp not found'); end
    catch ME; warning('S21 extraction failed: %s', ME.message); end

    %% S22: GG turbine generated power (MW)
    try
        if evalin('base', 'exist(''zz_data_ggTrbGenPwr'', ''var'')')
            sensor_array(:, 22) = extract_zz('zz_data_ggTrbGenPwr');
            fprintf('✓ S22: GG turbine power            [%.3f, %.3f] MW\n', ...
                min(sensor_array(:,22)), max(sensor_array(:,22)));
        else; warning('S22: zz_data_ggTrbGenPwr not found'); end
    catch ME; warning('S22 extraction failed: %s', ME.message); end

    %% S23: GG exhaust mass flow rate (kg/s)
    try
        if evalin('base', 'exist(''zz_data_ggExitFlow'', ''var'')')
            sensor_array(:, 23) = extract_zz('zz_data_ggExitFlow');
            fprintf('✓ S23: GG exhaust flow rate        [%.2f, %.2f] kg/s\n', ...
                min(sensor_array(:,23)), max(sensor_array(:,23)));
        else; warning('S23: zz_data_ggExitFlow not found'); end
    catch ME; warning('S23 extraction failed: %s', ME.message); end

    %% S24: GG rotor speed (rpm)
    try
        if evalin('base', 'exist(''GasGen_Speed_SECF210_rpm'', ''var'')')
            sensor_array(:, 24) = extract_timed('GasGen_Speed_SECF210_rpm');
            fprintf('✓ S24: GG rotor speed              [%.0f, %.0f] rpm\n', ...
                min(sensor_array(:,24)), max(sensor_array(:,24)));
        else; warning('S24: GasGen_Speed_SECF210_rpm not found'); end
    catch ME; warning('S24 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 6: POWER TURBINE  (S25–S31)
    % =========================================================================

    %% S25: PT inlet pressure (kPa) — = GG discharge pressure
    try
        if evalin('base', 'exist(''zz_data_ggdisPres'', ''var'')')
            sensor_array(:, 25) = extract_zz('zz_data_ggdisPres');
            fprintf('✓ S25: PT inlet pressure           [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,25)), max(sensor_array(:,25)));
        else; warning('S25: zz_data_ggdisPres not found'); end
    catch ME; warning('S25 extraction failed: %s', ME.message); end

    %% S26: PT inlet temperature (degC)
    try
        if evalin('base', 'exist(''zz_data_ptInletTemp'', ''var'')')
            sensor_array(:, 26) = extract_zz('zz_data_ptInletTemp');
            fprintf('✓ S26: PT inlet temperature        [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,26)), max(sensor_array(:,26)));
        else; warning('S26: zz_data_ptInletTemp not found'); end
    catch ME; warning('S26 extraction failed: %s', ME.message); end

    %% S27: PT rotor speed (rpm)
    try
        if evalin('base', 'exist(''PwrTrb_Speed_SECF243_rpm'', ''var'')')
            sensor_array(:, 27) = extract_timed('PwrTrb_Speed_SECF243_rpm');
            fprintf('✓ S27: PT rotor speed              [%.0f, %.0f] rpm\n', ...
                min(sensor_array(:,27)), max(sensor_array(:,27)));
        else; warning('S27: PwrTrb_Speed_SECF243_rpm not found'); end
    catch ME; warning('S27 extraction failed: %s', ME.message); end

    %% S28: PT generated power (MW)
    try
        if evalin('base', 'exist(''zz_data_ptGenPw'', ''var'')')
            sensor_array(:, 28) = extract_zz('zz_data_ptGenPw');
            fprintf('✓ S28: PT generated power          [%.3f, %.3f] MW\n', ...
                min(sensor_array(:,28)), max(sensor_array(:,28)));
        else; warning('S28: zz_data_ptGenPw not found'); end
    catch ME; warning('S28 extraction failed: %s', ME.message); end

    %% S29: PT outlet temperature (degC)
    try
        if evalin('base', 'exist(''zz_data_ptOutletTemp'', ''var'')')
            sensor_array(:, 29) = extract_zz('zz_data_ptOutletTemp');
            fprintf('✓ S29: PT outlet temperature       [%.2f, %.2f] degC\n', ...
                min(sensor_array(:,29)), max(sensor_array(:,29)));
        else; warning('S29: zz_data_ptOutletTemp not found'); end
    catch ME; warning('S29 extraction failed: %s', ME.message); end

    %% S30: PT isentropic efficiency (%)
    try
        if evalin('base', 'exist(''zz_data_PTEff'', ''var'')')
            sensor_array(:, 30) = extract_zz('zz_data_PTEff');
            fprintf('✓ S30: PT efficiency               [%.3f, %.3f]\n', ...
                min(sensor_array(:,30)), max(sensor_array(:,30)));
        else; warning('S30: zz_data_PTEff not found'); end
    catch ME; warning('S30 extraction failed: %s', ME.message); end

    %% S31: PT outlet pressure / exhaust back-pressure (kPa)
    try
        if evalin('base', 'exist(''zz_data_ptOutletPress'', ''var'')')
            sensor_array(:, 31) = extract_zz('zz_data_ptOutletPress');
            fprintf('✓ S31: PT outlet pressure          [%.2f, %.2f] kPa\n', ...
                min(sensor_array(:,31)), max(sensor_array(:,31)));
        else; warning('S31: zz_data_ptOutletPress not found'); end
    catch ME; warning('S31 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 7: CONTROLLER  (S32–S34)
    % =========================================================================

    %% S32: PID1 output — power demand signal to FG MCV
    try
        if evalin('base', 'exist(''zz_data_valveController1'', ''var'')')
            sensor_array(:, 32) = extract_zz('zz_data_valveController1');
            fprintf('✓ S32: Controller power demand     [%.3f, %.3f]\n', ...
                min(sensor_array(:,32)), max(sensor_array(:,32)));
        else; warning('S32: zz_data_valveController1 not found'); end
    catch ME; warning('S32 extraction failed: %s', ME.message); end

    %% S33: PID2 output — temperature limit signal to FG MCV
    try
        if evalin('base', 'exist(''zz_data_valveController2'', ''var'')')
            sensor_array(:, 33) = extract_zz('zz_data_valveController2');
            fprintf('✓ S33: Controller temp limit       [%.3f, %.3f]\n', ...
                min(sensor_array(:,33)), max(sensor_array(:,33)));
        else; warning('S33: zz_data_valveController2 not found'); end
    catch ME; warning('S33 extraction failed: %s', ME.message); end

    %% S34: PID3 output — IGV position demand
    try
        if evalin('base', 'exist(''zz_data_valveController3'', ''var'')')
            sensor_array(:, 34) = extract_zz('zz_data_valveController3');
            fprintf('✓ S34: Controller IGV demand       [%.3f, %.3f]\n', ...
                min(sensor_array(:,34)), max(sensor_array(:,34)));
        else; warning('S34: zz_data_valveController3 not found'); end
    catch ME; warning('S34 extraction failed: %s', ME.message); end

    % =========================================================================
    % GROUP 8: AMBIENT / OPERATING-CONDITION CONTEXT  (S35–S39)
    % =========================================================================
    % These are the (measured) ambient conditions for this epoch, taken from
    % the ENV_* base-workspace variables set by LoadScenarioToWorkspace. They
    % are quasi-constant over the run (static context broadcast across time).
    % Measurement noise is added later, in AddGaussianNoise, like any sensor.

    % RE-ATTEMPT, 2026-10-20: the within-record ambient
    % trend is re-added (withdrew the first attempt's
    % failure -- it was severed wire, not model pathology). S37 (compressor inlet
    % temperature) is now the REALISED commanded trend series, read back from
    % ENV_comp_inlet_temp_trend (the same [t,T(t)] array LoadScenarioToWorkspace.m / Get
    % AmbientTrendAmplitude.m built and fed to the model's From Workspace block --
    % P4_57_add_ambient_trend_input_both_branches.m), interpolated onto THIS function's own
    % (full, pre-preroll-trim) time_vector -- exactly the signal the plant was commanded, sampled
    % at the same points as every other channel. The other four context channels stay plain
    % per-record constant broadcasts, as before.
    ctx_vars = { ...
        'ENV_FG_pressure_kPa', ...      % S35
        'ENV_FG_temp_C', ...            % S36
        'ENV_comp_inlet_temp_C', ...    % S37 (fallback only -- see has_trend below)
        'ENV_comp_inlet_press_kPa', ... % S38
        'ENV_ambient_moisture_pct'};    % S39
    has_trend = false;
    try
        has_trend = logical(evalin('base', 'exist(''ENV_comp_inlet_temp_trend'', ''var'')'));
    catch
        has_trend = false;
    end
    for k = 1:numel(ctx_vars)
        col = 34 + k;
        try
            if col == 37 && has_trend
                trend_arr = evalin('base', 'ENV_comp_inlet_temp_trend');
                S37_series = interp1(trend_arr(:,1), trend_arr(:,2), time_vector, 'linear', 'extrap');
                sensor_array(:, col) = S37_series;
                fprintf('✓ S%02d: %-28s trend [%.3f, %.3f]\n', col, 'ENV_comp_inlet_temp_trend', ...
                    min(S37_series), max(S37_series));
            elseif evalin('base', sprintf('exist(''%s'', ''var'')', ctx_vars{k}))
                v = evalin('base', ctx_vars{k});
                sensor_array(:, col) = double(v(1)) * ones(N, 1);
                fprintf('✓ S%02d: %-28s constant %.3f\n', col, ctx_vars{k}, double(v(1)));
            else
                warning('S%02d: %s not found in base workspace', col, ctx_vars{k});
            end
        catch ME
            warning('S%02d (%s) extraction failed: %s', col, ctx_vars{k}, ME.message);
        end
    end

    % =========================================================================
    % GROUP 9 : TRUE-VALUE TAPS for the drifting sensors, where present.
    % =========================================================================
    % Added by P1b_01_add_true_value_taps.m on AvonGasTurbineDgTwin_fixed: pre-fault-injection
    % values of S19 (GG turbine inlet temp), S24 (GG rotor speed), S27 (PT rotor speed), S04
    % (fuel mass flow), and S26 (PT inlet / GG exhaust temp, the 846 degC limiter's own
    % feedback). NOT part of /sensors (channel count stays 39) -- kept as a separate,
    % optional group so a model without the taps (or an older session) extracts unchanged.
    true_value_vars = {'S19_true', 'S24_true', 'S27_true', 'S04_true', 'S26_true'};
    true_value_data = NaN(N, numel(true_value_vars));
    true_value_present = false(1, numel(true_value_vars));
    for k = 1:numel(true_value_vars)
        vn = true_value_vars{k};
        try
            if evalin('base', sprintf('exist(''%s'', ''var'')', vn))
                true_value_data(:, k) = extract_zz(vn);
                % S19_true is tapped upstream of the F33-37 cascade's own "Sum (+ Kelvin
                % constant = 273.15)" conversion block, so it is in the cascade's internal
                % Kelvin-offset units while the logged S19 is in degC. Apply the SAME
                % conversion here so S19_true is directly comparable to S19 (confirmed exact
                % on a Healthy run, 2026-10-09: true - 273.15 == indicated to float precision).
                % Every other tap (S24/S27/S04/S26_true) already matches its indicated channel
                % with zero offset -- this correction is S19-specific.
                if strcmp(vn, 'S19_true')
                    true_value_data(:, k) = true_value_data(:, k) - 273.15;
                end
                true_value_present(k) = true;
            end
        catch
            % leave as NaN -- not present in this run (taps not added, or an older model)
        end
    end
    if any(true_value_present)
        fprintf('\n✓ True-value taps present: %s\n', strjoin(true_value_vars(true_value_present), ', '));
    end

    % =========================================================================
    % BUILD sensor_info OUTPUT STRUCT
    % =========================================================================

    sensor_info = struct();
    sensor_info.TrueValueTapNames    = true_value_vars;
    sensor_info.TrueValueTapPresent  = true_value_present;
    sensor_info.TrueValueTapData     = true_value_data;   % [N x 5], NaN columns where absent
    sensor_info.Names       = SensorDef.Names;
    sensor_info.ShortNames  = SensorDef.ShortNames;
    sensor_info.Units       = SensorDef.Units;
    sensor_info.Subsystems  = SensorDef.Subsystems;
    sensor_info.ChannelType = SensorDef.ChannelType;
    sensor_info.Count       = SensorDef.Count;          % 39
    sensor_info.PhysicalCount = SensorDef.PhysicalCount; % 34
    sensor_info.ContextCount  = SensorDef.ContextCount;  % 5
    sensor_info.SamplingRate = 1/target_dt;
    sensor_info.Duration    = target_duration;
    sensor_info.TotalSamples = N;

    % Count extracted vs missing over the PHYSICAL sensors only (context
    % channels are constants and are always present).
    n_phys = SensorDef.PhysicalCount;
    extracted_flags = any(sensor_array(:, 1:n_phys) ~= 0, 1);
    sensor_info.ExtractedSensors = sum(extracted_flags);
    sensor_info.MissingSensors   = n_phys - sensor_info.ExtractedSensors;

    % Compatibility fields for RunScenario / GenerateHDF5
    sensor_info.num_sensors   = SensorDef.Count;         % 39
    sensor_info.num_samples   = N;
    sensor_info.num_extracted = sensor_info.ExtractedSensors;
    sensor_info.num_missing   = sensor_info.MissingSensors;

    % =========================================================================
    % SUMMARY
    % =========================================================================

    fprintf('\n========================================\n');
    fprintf('  Extraction Summary\n');
    fprintf('========================================\n');
    fprintf('Total channels:   %d (%d physical + %d context)\n', ...
        SensorDef.Count, SensorDef.PhysicalCount, SensorDef.ContextCount);
    fprintf('Physical extracted: %d\n', sensor_info.ExtractedSensors);
    fprintf('Physical missing:   %d\n', sensor_info.MissingSensors);

    if sensor_info.MissingSensors > 0
        fprintf('\nMissing physical sensors (all-zero columns):\n');
        for i = 1:n_phys
            if ~extracted_flags(i)
                fprintf('  - S%02d: %s\n', i, SensorDef.Names{i});
            end
        end
    end

    fprintf('\nOutput dimensions:\n');
    fprintf('  sensor_array: [%d × %d]\n', size(sensor_array, 1), size(sensor_array, 2));
    fprintf('  time_vector:  [%d × 1]\n', length(time_vector));
    fprintf('========================================\n\n');

end
