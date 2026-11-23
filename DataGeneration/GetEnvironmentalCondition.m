function env = GetEnvironmentalCondition(env_id)
% GetEnvironmentalCondition - Returns environmental parameters for given ID
%
% Inputs:
%   env_id - Environment ID (1-5)
%
% Outputs:
%   env - Struct with environmental parameters:
%         .FG_pressure_kPa - Fuel gas supply pressure (kPa)
%         .FG_temp_C - Fuel gas temperature (°C)
%         .compressor_inlet_temp_C - Compressor inlet temperature (°C)
%         .compressor_inlet_press_kPa - Compressor inlet pressure (kPa)
%         .ambient_moisture_percent - Ambient relative humidity (%)
%         .name - Environment name
%         .description - Environment description
%
% Environmental Conditions:
%   ENV001: Nominal - Design point baseline
%   ENV002: Hot Day - High ambient temperature
%   ENV003: Cold Day - Low ambient temperature
%   ENV004: High Altitude - Reduced ambient pressure
%   ENV005: Humid Tropical - High temperature + humidity
%
% Date: 2025-12-29

    if nargin < 1 || env_id < 1 || env_id > 5
        error('env_id must be between 1 and 5');
    end

    switch env_id
        case 1
            % ENV001: Nominal conditions (Design point)
            env.FG_pressure_kPa = 2400;
            env.FG_temp_C = 20;
            env.compressor_inlet_temp_C = 38.85;
            env.compressor_inlet_press_kPa = 99.2;
            env.ambient_moisture_percent = 65;
            env.name = 'Nominal';
            env.description = 'Design point baseline - standard ISA conditions';

        case 2
            % ENV002: Hot Day
            env.FG_pressure_kPa = 2300;
            env.FG_temp_C = 30;
            env.compressor_inlet_temp_C = 45;
            env.compressor_inlet_press_kPa = 97;
            env.ambient_moisture_percent = 80;
            env.name = 'Hot Day';
            env.description = 'High ambient temperature - summer peak load';

        case 3
            % ENV003: Cold Day
            env.FG_pressure_kPa = 2500;
            env.FG_temp_C = 10;
            env.compressor_inlet_temp_C = 25;
            env.compressor_inlet_press_kPa = 102;
            env.ambient_moisture_percent = 40;
            env.name = 'Cold Day';
            env.description = 'Low ambient temperature - winter operation';

        case 4
            % ENV004: High Altitude
            env.FG_pressure_kPa = 2200;
            env.FG_temp_C = 15;
            env.compressor_inlet_temp_C = 35;
            env.compressor_inlet_press_kPa = 90;
            env.ambient_moisture_percent = 50;
            env.name = 'High Altitude';
            env.description = 'Reduced ambient pressure - mountain/elevated operation';

        case 5
            % ENV005: Humid Tropical
            env.FG_pressure_kPa = 2400;
            env.FG_temp_C = 35;
            env.compressor_inlet_temp_C = 50;
            env.compressor_inlet_press_kPa = 99;
            env.ambient_moisture_percent = 95;
            env.name = 'Humid Tropical';
            env.description = 'High temperature + humidity - coastal/tropical climate';

        otherwise
            error('Invalid env_id: %d. Must be 1-5.', env_id);
    end

    % Add ID to struct
    env.id = env_id;

end
