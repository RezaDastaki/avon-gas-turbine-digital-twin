function metadata = CreateMetadata(scenario_type, varargin)
% CreateMetadata - Helper function to create metadata structure for HDF5 dataset
%
% Simplifies metadata creation for different scenarios (healthy, faulty)
%
% Syntax:
%   metadata = CreateMetadata('healthy', env_id, env_conditions)
%   metadata = CreateMetadata('fault', env_id, env_conditions, fault_id, fault_name, severity)
%
% Inputs:
%   scenario_type    - 'healthy' or 'fault'
%   env_id           - Environmental condition ID (1, 2, 3, ...)
%   env_conditions   - Struct with environmental parameters:
%       .FG_pressure_kPa
%       .FG_temp_C
%       .compressor_inlet_temp_C
%       .compressor_inlet_press_kPa
%       .ambient_moisture_percent
%   fault_id         - (Fault only) Fault number 1-32
%   fault_name       - (Fault only) Fault name string
%   severity         - (Fault only) Severity level 1-4 (25% 50% 75% 100%)
%
% Outputs:
%   metadata - Complete metadata structure ready for SaveSensorsToHDF5
%
% Examples:
%   % Nominal environmental conditions
%   env = struct('FG_pressure_kPa', 2400, 'FG_temp_C', 20, ...
%                'compressor_inlet_temp_C', 38.85, ...
%                'compressor_inlet_press_kPa', 99.2, ...
%                'ambient_moisture_percent', 65);
%
%   % Healthy scenario
%   metadata = CreateMetadata('healthy', 1, env);
%
%   % Fault scenario
%   metadata = CreateMetadata('fault', 1, env, 1, 'Fuel pressure regulator stuck', 2);
%   % Creates: ENV001, Fault #1, Severity 2 (50%)
%
% Date: 2025-12-29

%% Validate inputs
if ~ismember(lower(scenario_type), {'healthy', 'fault'})
    error('scenario_type must be ''healthy'' or ''fault''');
end

if strcmpi(scenario_type, 'healthy')
    if nargin ~= 3
        error('Healthy scenario requires: CreateMetadata(''healthy'', env_id, env_conditions)');
    end
    env_id = varargin{1};
    env_conditions = varargin{2};

elseif strcmpi(scenario_type, 'fault')
    if nargin ~= 6
        error('Fault scenario requires: CreateMetadata(''fault'', env_id, env_conditions, fault_id, fault_name, severity)');
    end
    env_id = varargin{1};
    env_conditions = varargin{2};
    fault_id = varargin{3};
    fault_name = varargin{4};
    severity = varargin{5};

    % Validate fault parameters
    if fault_id < 1 || fault_id > 32
        error('fault_id must be between 1 and 32');
    end
    if severity < 1 || severity > 4
        error('severity must be between 1 (25%%) and 4 (100%%)');
    end
end

%% Validate environmental conditions struct
required_fields = {'FG_pressure_kPa', 'FG_temp_C', 'compressor_inlet_temp_C', ...
                   'compressor_inlet_press_kPa', 'ambient_moisture_percent'};

for i = 1:length(required_fields)
    if ~isfield(env_conditions, required_fields{i})
        error('env_conditions missing field: %s', required_fields{i});
    end
end

%% Create metadata structure
metadata = struct();

if strcmpi(scenario_type, 'healthy')
    % Healthy scenario
    metadata.fault_id = 0;
    metadata.fault_name = 'Healthy';
    metadata.severity = 0;
    metadata.severity_percent = 0;

else
    % Fault scenario
    metadata.fault_id = fault_id;
    metadata.fault_name = fault_name;
    metadata.severity = severity;

    % Convert severity level to percentage
    severity_map = [25, 50, 75, 100];
    metadata.severity_percent = severity_map(severity);
end

% Environmental information
metadata.environmental_id = env_id;
metadata.env_conditions = env_conditions;

end
