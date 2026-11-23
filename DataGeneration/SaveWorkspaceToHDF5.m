function output_file = SaveWorkspaceToHDF5(scenario_type, epoch, attempt, env_conditions, sensor_array, time_vector, sensor_info, fault_label, severity_label, fault_start_times, record_attrs, varargin)
% SaveWorkspaceToHDF5 - Save pre-extracted channel data and labels to HDF5 (writer).
%
% CHANGES vs the earlier writer:
%   - sensor_array is the full [N x 39] post-measurement-model array (S01..S39); the channel
%     split into /sensors (26) and /internal (13) happens inside SaveSensorsToHDF5.m, not here.
%   - record_attrs (from ComputeLayer1RecordAttributes.m, extended by RunScenario.m Step 8) is
%     threaded through and written as the new per-record attribute set.
%   - time_vector is accepted for a basic sanity check only -- it is NOT stored (no /time
%     dataset; "no unreclaimed free space / no time array").
%
% Usage:
%   SaveWorkspaceToHDF5('healthy', epoch, attempt, env, sensors, time, info, fl, sl, tstarts, attrs)
%   SaveWorkspaceToHDF5('single',  epoch, attempt, env, sensors, time, info, fl, sl, tstarts, attrs, fault_id, severity)
%   SaveWorkspaceToHDF5('dual',    epoch, attempt, env, sensors, time, info, fl, sl, tstarts, attrs, combo_id, severity_levels)
%

%% Validate basic inputs
if epoch < 1
    error('epoch must be >= 1');
end
if size(sensor_array, 2) ~= 39
    error('sensor_array must have 39 columns, got %d', size(sensor_array, 2));
end
if length(time_vector) ~= size(sensor_array, 1)
    error('time_vector length must match sensor_array rows');
end
if ~isequal(size(fault_label), [size(sensor_array,1), 42])
    error('fault_label must be [N x 42], got [%dx%d]', size(fault_label,1), size(fault_label,2));
end
if ~isequal(size(severity_label), [size(sensor_array,1), 42])
    error('severity_label must be [N x 42], got [%dx%d]', size(severity_label,1), size(severity_label,2));
end

%% Metadata + output path
metadata = struct();
metadata.epoch            = epoch;
metadata.attempt          = attempt;
metadata.environmental_id = 0;                 % 0 => MC-sampled (no fixed env)
metadata.environment_mode = 'MC-sampled';
metadata.env_conditions   = env_conditions;    % sampled true ambient values

[fault_info, output_file] = GenerateScenarioInfo(scenario_type, epoch, varargin{:});

metadata.fault_count         = fault_info.fault_count;
metadata.fault_ids           = fault_info.fault_ids;
metadata.fault_names         = fault_info.fault_names;
metadata.scenario_id         = fault_info.scenario_id;
metadata.severities          = fault_info.severities;
% severity_deviation (renamed from severity_percents) is the exact fractional
% deviation applied to the perturbed quantity (|GetFaultMultiplier - 1|), not severity*20.
metadata.severity_deviations = fault_info.severity_deviations;

if ~isempty(fault_start_times)
    metadata.fault_start_times = fault_start_times;
else
    metadata.fault_start_times = [];
end

%% Save
try
    SaveSensorsToHDF5(sensor_array, sensor_info, output_file, metadata, fault_label, severity_label, record_attrs);
catch ME
    fprintf('Save failed: %s\n', ME.message);
    rethrow(ME);
end

end
