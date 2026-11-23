function SensorDef = GetSensorDefinitions()
% GetSensorDefinitions - Define all 39 channels (34 physical sensors + 5 ambient
% context channels) for the gas turbine dataset.
%
% Syntax:
%   SensorDef = GetSensorDefinitions
%
% Output:
%   SensorDef - Struct with channel information:
%               .Names        - Cell array of channel names
%               .ShortNames   - Cell array of short codes (S01-S39)
%               .Units        - Cell array of measurement units
%               .Subsystems   - Cell array of subsystem categories
%               .ChannelType  - Cell array 'physical' (S01-S34) | 'context' (S35-S39)
%               .Count        - Total number of channels (39)
%               .PhysicalCount- Number of physical sensors (34)
%               .ContextCount - Number of ambient context channels (5)
%               .TypicalRanges- Cell array of [min, max] validation ranges
%               .WorkspaceVars- Base-workspace variable names (context = ENV_* vars)
%               .SimulinkMapping - 1:34 (physical only; context appended post-sim)
%
% CHANGE: channels expanded from 34 -> 39.
%   S35-S39 are the (measured) ambient / operating-condition context channels.
%   The environment is Monte-Carlo sampled per epoch, so these ambient
%   values differ from file to file and are provided to the model as input
%   channels (they carry no fault semantics; fault labels stay 42-wide).
%   Context channels are quasi-constant within a run (static context repeated
%   across time). Their noise-free true values are also stored as file
%   attributes (FG_pressure_kPa, ... ambient_moisture_percent).
%
% Sensor List (sorted by component, thermodynamic flow order):
%   S01-S05: Fuel Gas Line
%   S06-S08: Air Intake
%   S09-S15: HP Compressor
%   S16-S18: Combustor
%   S19-S24: Gas Generator Turbine
%   S25-S31: Power Turbine
%   S32-S34: Controller
%   S35-S39: Ambient / operating-condition context (added 2026-07-26)
%
% Reference: Sensors_configuration.md
%
% Date: 2025 | Updated: 2026-07-26 (34 physical + 5 context = 39 channels)

    SensorDef = struct();

    %% Channel counts
    SensorDef.PhysicalCount = 34;
    SensorDef.ContextCount  = 5;
    SensorDef.Count         = 39;

    %% Short names (for HDF5 datasets and logging)
    SensorDef.ShortNames = {
        'S01', 'S02', 'S03', 'S04', 'S05', ...                         % Fuel Gas Line
        'S06', 'S07', 'S08', ...                                         % Air Intake
        'S09', 'S10', 'S11', 'S12', 'S13', 'S14', 'S15', ...           % HP Compressor
        'S16', 'S17', 'S18', ...                                         % Combustor
        'S19', 'S20', 'S21', 'S22', 'S23', 'S24', ...                   % GG Turbine
        'S25', 'S26', 'S27', 'S28', 'S29', 'S30', 'S31', ...           % Power Turbine
        'S32', 'S33', 'S34', ...                                         % Controller
        'S35', 'S36', 'S37', 'S38', 'S39'                              % Ambient context
    };

    %% Full descriptive names
    SensorDef.Names = {
        'FG_supply_pressure', ...                    % S01: FG pressure before MCV
        'FG_MCV_downstream_pressure', ...            % S02: FG pressure after MCV
        'FG_MCV_valve_position', ...                 % S03: MCV stem position
        'FG_mass_flow', ...                          % S04: Fuel mass flow rate
        'FG_combustor_inlet_temperature', ...        % S05: FG temp at combustor inlet
        'Air_filter_differential_pressure', ...      % S06: Filter dP
        'Air_mass_flow', ...                         % S07: Main compressor air flow
        'IGV_opening_angle', ...                     % S08: IGV position
        'HP_compressor_pressure_ratio', ...          % S09: Compressor PR
        'HP_compressor_discharge_pressure', ...      % S10: Compressor outlet pressure
        'HP_compressor_discharge_temperature', ...   % S11: Compressor outlet temp
        'HP_compressor_efficiency', ...              % S12: Compressor isentropic efficiency
        'HP_compressor_shaft_power', ...             % S13: Compressor consumed shaft power
        'HP_compressor_rotor_cooling_flow', ...      % S14: Rotor cooling air bleed
        'HP_compressor_stator_cooling_flow', ...     % S15: Stator cooling air bleed
        'Combustor_exit_temperature', ...            % S16: TIT - Turbine Inlet Temperature
        'Combustor_exit_pressure', ...               % S17: Hot gas pressure out of combustor
        'Combustor_exit_flow_rate', ...              % S18: Combustor exit mass flow
        'GG_turbine_inlet_temperature', ...          % S19: GG turbine inlet (after stator cooling mix)
        'GG_turbine_exhaust_temperature', ...        % S20: GG turbine exhaust (before rotor cooling mix)
        'GG_rotor_cooling_exhaust_temperature', ...  % S21: Rotor cooling circuit exhaust temp
        'GG_turbine_power', ...                      % S22: GG turbine generated power
        'GG_exhaust_flow_rate', ...                  % S23: GG exhaust mass flow
        'GG_rotor_speed', ...                        % S24: GG spool speed
        'PT_inlet_pressure', ...                     % S25: PT inlet (= GG discharge) pressure
        'PT_inlet_temperature', ...                  % S26: PT inlet temperature
        'PT_rotor_speed', ...                        % S27: PT spool speed
        'PT_generated_power', ...                    % S28: PT shaft power output
        'PT_outlet_temperature', ...                 % S29: PT exhaust temperature
        'PT_efficiency', ...                         % S30: PT isentropic efficiency
        'PT_outlet_pressure', ...                    % S31: PT exhaust back-pressure
        'Controller_power_demand', ...               % S32: PID1 output (power control -> FG MCV)
        'Controller_temperature_limit', ...          % S33: PID2 output (temp limit -> FG MCV)
        'Controller_IGV_demand', ...                 % S34: PID3 output (temp control -> IGV)
        'Ambient_FG_supply_pressure', ...            % S35: (context) sampled FG supply pressure
        'Ambient_FG_temperature', ...                % S36: (context) sampled FG temperature
        'Ambient_compressor_inlet_temperature', ...  % S37: (context) sampled inlet air temperature
        'Ambient_compressor_inlet_pressure', ...     % S38: (context) sampled inlet air pressure
        'Ambient_relative_humidity'                  % S39: (context) sampled ambient humidity
    };

    %% Measurement units
    % CHANGE (2026-10-13 known-error list, C23/C60):
    % S24/S27 corrected rpm -> rad/s (the model's native unit; values were never converted,
    % only mislabelled -- confirmed empirically, P3_02_healthy_baseline_and_units_check.m:
    % S24 tail-mean 749.2, S27 tail-mean 513.2, both plainly rad/s against a design point of
    % 513.4 rad/s, not rpm). Conversion factor to the alternate (rpm) unit, for the dictionary:
    % 60/(2*pi) = 9.5493 rpm per rad/s. Design points in both units: PT 513.4 rad/s = 4903 rpm;
    % GG 702.0 rad/s = 6704 rpm.
    % S12/S30 corrected % -> - (dimensionless): stored values are fractions (0-1), not percent
    % -- confirmed empirically (S12 tail-mean 0.8207, S30 tail-mean 0.8435). x100 gives percent.
    % S03 checked and CONFIRMED UNCHANGED: two independent measurements (a live-model reference
    % run, 43.0-46.0, and 200 real Healthy records from the released draft data, 35.1-60.8) both
    % land inside a 0-100 scale, consistent with the existing '%'/[0,100] assignment.
    SensorDef.Units = {
        'kPa', ...      % S01
        'kPa', ...      % S02
        '%', ...        % S03 -- confirmed by measurement, (c); no change
        'kg/s', ...     % S04
        'degC', ...     % S05
        'kPa', ...      % S06
        'kg/s', ...     % S07
        'deg', ...      % S08
        '-', ...        % S09
        'kPa', ...      % S10
        'degC', ...     % S11
        '-', ...        % S12 -- CORRECTED from '%' ((b)): stored as a fraction, not percent
        'MW', ...       % S13
        'kg/s', ...     % S14
        'kg/s', ...     % S15
        'degC', ...     % S16
        'kPa', ...      % S17
        'kg/s', ...     % S18
        'degC', ...     % S19
        'degC', ...     % S20
        'degC', ...     % S21
        'MW', ...       % S22
        'kg/s', ...     % S23
        'rad/s', ...    % S24 -- CORRECTED from 'rpm' ((a)): model's native unit, no conversion applied
        'kPa', ...      % S25
        'degC', ...     % S26
        'rad/s', ...    % S27 -- CORRECTED from 'rpm' ((a)), same basis as S24
        'MW', ...       % S28
        'degC', ...     % S29
        '-', ...        % S30 -- CORRECTED from '%' ((b)), same basis as S12
        'kPa', ...      % S31
        '-', ...        % S32
        '-', ...        % S33
        '-', ...        % S34
        'kPa', ...      % S35 (context) FG supply pressure
        'degC', ...     % S36 (context) FG temperature
        'degC', ...     % S37 (context) inlet air temperature
        'kPa', ...      % S38 (context) inlet air pressure
        '%RH'           % S39 (context) relative humidity
    };

    %% Subsystem categories
    SensorDef.Subsystems = {
        'FuelGas', 'FuelGas', 'FuelGas', 'FuelGas', 'FuelGas', ...          % S01-S05
        'AirIntake', 'AirIntake', 'AirIntake', ...                            % S06-S08
        'Compressor', 'Compressor', 'Compressor', 'Compressor', ...           % S09-S12
        'Compressor', 'Compressor', 'Compressor', ...                         % S13-S15
        'Combustor', 'Combustor', 'Combustor', ...                            % S16-S18
        'GasGenerator', 'GasGenerator', 'GasGenerator', ...                   % S19-S21
        'GasGenerator', 'GasGenerator', 'GasGenerator', ...                   % S22-S24
        'PowerTurbine', 'PowerTurbine', 'PowerTurbine', ...                   % S25-S27
        'PowerTurbine', 'PowerTurbine', 'PowerTurbine', 'PowerTurbine', ...   % S28-S31
        'Controller', 'Controller', 'Controller', ...                          % S32-S34
        'Context', 'Context', 'Context', 'Context', 'Context'                 % S35-S39
    };

    %% Channel type: 'physical' (S01-S34) or 'context' (S35-S39)
    SensorDef.ChannelType = [ ...
        repmat({'physical'}, 1, 34), ...
        repmat({'context'},  1, 5) ];

    %% Typical ranges (for validation / reference)
    SensorDef.TypicalRanges = {
        [2000, 3000], ...    % S01
        [2000, 3000], ...    % S02
        [0, 100], ...        % S03
        [0, 5], ...          % S04
        [0, 100], ...        % S05
        [0, 10], ...         % S06
        [0, 100], ...        % S07
        [0, 120], ...        % S08
        [1, 20], ...         % S09
        [300, 1100], ...     % S10
        [0, 600], ...        % S11
        [0, 1], ...          % S12 -- CORRECTED from [0,100] ((b)): fraction, not percent
        [0, 40], ...         % S13
        [0, 15], ...         % S14
        [0, 10], ...         % S15
        [600, 1400], ...     % S16
        [300, 1100], ...     % S17
        [20, 110], ...       % S18
        [700, 1400], ...     % S19
        [400, 1000], ...     % S20
        [400, 950], ...      % S21
        [10, 40], ...        % S22
        [0, 100], ...        % S23
        [0, 900], ...        % S24 -- CORRECTED from [0,20000] ((a)): rad/s (GG design point 702.0 rad/s = 6704 rpm)
        [0, 2000], ...       % S25
        [0, 1000], ...       % S26
        [0, 600], ...        % S27 -- CORRECTED from [0,10000] ((a)): rad/s (PT design point 513.4 rad/s = 4903 rpm)
        [0, 30], ...         % S28
        [0, 800], ...        % S29
        [0, 1], ...          % S30 -- CORRECTED from [0,100] ((b)): fraction, not percent
        [80, 250], ...       % S31
        [-50, 100], ...      % S32
        [-50, 100], ...      % S33
        [-50, 50], ...       % S34
        [2000, 2700], ...    % S35 (context) FG supply pressure (kPa)
        [0, 60], ...         % S36 (context) FG temperature (degC)
        [0, 60], ...         % S37 (context) inlet air temperature (degC)
        [80, 110], ...       % S38 (context) inlet air pressure (kPa)
        [0, 100]             % S39 (context) relative humidity (%RH)
    };

    %% Channel-to-workspace variable mapping (physical = Simulink logs;
    %% context = ENV_* base-workspace variables set by LoadScenarioToWorkspace)
    %% NOTE ((a)): 'GasGen_Speed_SECF210_rpm' (S24) and 'PwrTrb_Speed_SECF243_rpm'
    %% (S27) are Simulink-side workspace variable names only -- they do not ship, and despite
    %% the '_rpm' suffix both are logged and stored in rad/s (SensorDef.Units, above). Left
    %% unrenamed deliberately (a rename would touch the model for no user-visible benefit);
    %% flagged here and so a reader of the generation source is
    %% not misled by the variable name.
    SensorDef.WorkspaceVars = {
        'Prss_FG_Bfr_MCV_PT203_kPa', ...       % S01
        'Prss_FG_Aftr_MCV_PT204_kPa', ...       % S02
        'zz_data_FGvalpos', ...                  % S03
        'zz_data_fuel', ...                      % S04
        'zz_data_FG_temp', ...                   % S05
        'PDT_139', ...                           % S06
        'zz_data_trbAirflow', ...                % S07
        'zz_data_IGVpos', ...                    % S08
        'zz_data_cpr', ...                       % S09
        'zz_data_CmpdisPress', ...               % S10
        'zz_data_CmpdisTemp', ...                % S11
        'zz_data_CompEff', ...                   % S12
        'zz_data_comp_outPower', ...             % S13
        'zz_data_comp_rotorCooling_flow', ...    % S14
        'zz_data_comp_statorCooling_flow', ...   % S15
        'zz_data_combustorChamber_temp', ...     % S16
        'zz_data_combustorChamber_press', ...    % S17
        'zz_data_combustorChamber_flowrate', ... % S18
        'zz_data_ggTrbInletTemp', ...            % S19
        'zz_data_ggTrbExeTemp', ...              % S20
        'zz_data_ggTrbRotorCoolingExeTemp', ...  % S21
        'zz_data_ggTrbGenPwr', ...               % S22
        'zz_data_ggExitFlow', ...                % S23
        'GasGen_Speed_SECF210_rpm', ...          % S24
        'zz_data_ggdisPres', ...                 % S25
        'zz_data_ptInletTemp', ...               % S26
        'PwrTrb_Speed_SECF243_rpm', ...          % S27
        'zz_data_ptGenPw', ...                   % S28
        'zz_data_ptOutletTemp', ...              % S29
        'zz_data_PTEff', ...                     % S30
        'zz_data_ptOutletPress', ...             % S31
        'zz_data_valveController1', ...          % S32
        'zz_data_valveController2', ...          % S33
        'zz_data_valveController3', ...          % S34
        'ENV_FG_pressure_kPa', ...               % S35 (context)
        'ENV_FG_temp_C', ...                     % S36 (context)
        'ENV_comp_inlet_temp_C', ...             % S37 (context)
        'ENV_comp_inlet_press_kPa', ...          % S38 (context)
        'ENV_ambient_moisture_pct'               % S39 (context)
    };

    %% Simulink output mapping (physical channels only; context appended post-sim)
    SensorDef.SimulinkMapping = 1:34;

    fprintf('\n=== Sensor Definitions Loaded ===\n');
    fprintf('Total Channels: %d (%d physical + %d context)\n', ...
        SensorDef.Count, SensorDef.PhysicalCount, SensorDef.ContextCount);
    fprintf('Groups: FuelGas(5), AirIntake(3), Compressor(7), Combustor(3),\n');
    fprintf('        GasGenerator(6), PowerTurbine(7), Controller(3), Context(5)\n');
    fprintf('=================================\n\n');
end
