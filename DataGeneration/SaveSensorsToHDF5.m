function SaveSensorsToHDF5(sensor_array_39, sensor_info, output_filename, metadata, fault_label, severity_label, record_attrs)
% SaveSensorsToHDF5 - writer: two channel datasets (sensors, /internal), chunked +
% compressed, int8 labels, no /time array, the new per-record attribute set.
%
% REPLACES the earlier writer (single /sensors [N x 34] + /time + int32 labels). Channel split and row
% order are fixed by the channel-split design (26 /sensors + 13 /internal = 39, exactly covering S01-S39 once
% each). MATLAB writes [time, channel] (h5create(..., [N, C], ...)); the well-documented MATLAB/
% h5py storage-order flip then makes h5py see (C, N) -- i.e. [channel, time] -- without any
% explicit transpose, exactly like the draft data's own /sensors convention.
%
% Inputs:
%   sensor_array_39 - [N x 39] post-measurement-model channel array, S01..S39 columns (the array
%                     ExtractSensorsFromWorkspace.m / ApplyMeasurementModel.m already produce)
%   sensor_info     - struct from ExtractSensorsFromWorkspace.m (Duration, SamplingRate, ...)
%   output_filename - output HDF5 path
%   metadata        - struct: epoch, attempt, environmental_id, environment_mode, env_conditions,
%                     fault_count, fault_ids, fault_names, severities, severity_deviations,
%                     fault_start_times
%   fault_label     - [N x 42] 0/1 (written as int8, not int32:
%                     "int8 labels save nothing" was about the DRAFT's already-gzipped labels;
%                     here it is simply the smallest exact type for a {0,1}/{0..5} range, free size
%                     with no precision loss)
%   severity_label  - [N x 42] 0-5
%   record_attrs    - struct from ComputeLayer1RecordAttributes.m, PLUS preroll_discarded_s,
%                     t_since_cal, f37_frozen_fraction_target/achieved, attempt_used
%                     (RunScenario.m Step 8 adds these three before calling this function)
%

%% Channel split (fixed design)
SENSORS_IDX = [1,2,3,4,5,6,7,8,10,11,17,19,20,21,24,25,26,27,28,29,31,35,36,37,38,39];   % 26
INTERNAL_IDX = [9,12,13,14,15,16,18,22,23,30,32,33,34];                                  % 13
assert(numel(SENSORS_IDX) == 26 && numel(INTERNAL_IDX) == 13, 'Channel split index count changed unexpectedly');
assert(isequal(sort([SENSORS_IDX, INTERNAL_IDX]), 1:39), 'Channel split does not cover S01-S39 exactly once');

if size(sensor_array_39, 2) ~= 39
    error('sensor_array_39 must have exactly 39 columns, got %d', size(sensor_array_39, 2));
end
N_samples = size(sensor_array_39, 1);
if N_samples ~= ScenarioConfig.STORED_SAMPLES
    error('sensor_array_39 has %d rows, expected STORED_SAMPLES=%d', N_samples, ScenarioConfig.STORED_SAMPLES);
end
if ~isequal(size(fault_label), [N_samples, 42]) || ~isequal(size(severity_label), [N_samples, 42])
    error('fault_label/severity_label must be [%d x 42]', N_samples);
end

%% Output directory / overwrite
[output_dir, ~, ~] = fileparts(output_filename);
if ~isempty(output_dir) && ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
if exist(output_filename, 'file')
    delete(output_filename);
end

SensorDef = GetSensorDefinitions();

%% /sensors (26 channels) and /internal (13 channels)
sensors_data  = single(sensor_array_39(:, SENSORS_IDX));
internal_data = single(sensor_array_39(:, INTERNAL_IDX));

h5create(output_filename, '/sensors', [N_samples, 26], 'Datatype', 'single', ...
    'ChunkSize', [N_samples, 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/sensors', sensors_data);
h5writeatt(output_filename, '/sensors', 'Description', ...
    'The headline, directly-instrumented channel suite. 21 measured + 5 ambient-context channels. [channel, time] on disk (h5py); row order given by channel_names.');
h5writeatt(output_filename, '/sensors', 'channel_names', strjoin(arrayfun(@(i) SensorDef.ShortNames{i}, SENSORS_IDX, 'UniformOutput', false), ','));
h5writeatt(output_filename, '/sensors', 'dtype', 'single');

h5create(output_filename, '/internal', [N_samples, 13], 'Datatype', 'single', ...
    'ChunkSize', [N_samples, 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/internal', internal_data);
h5writeatt(output_filename, '/internal', 'Description', ...
    'Model-internal / controller-demand channels: 10 derived quantities a real historian would compute, plus 3 controller PID states. No real instrument exists for any of these -- an oracle ceiling, not a headline-benchmark channel suite (P3_channel_split.md Sec3). [channel, time] on disk.');
h5writeatt(output_filename, '/internal', 'channel_names', strjoin(arrayfun(@(i) SensorDef.ShortNames{i}, INTERNAL_IDX, 'UniformOutput', false), ','));
h5writeatt(output_filename, '/internal', 'dtype', 'single');

%% /true_values (5 channels) /
% Ground truth for the nine logger_only sensor faults (F33-F41): the
% unperturbed internal value of each channel a sensor fault can perturb. Identical treatment to
% /sensors. A tap that is absent comes through as an all-NaN column (checked against
% TrueValueTapPresent by ValidateGenerationLayer1.m, not here).
TRUE_VALUE_NAMES = {'S19_true', 'S24_true', 'S27_true', 'S04_true', 'S26_true'};
if isfield(sensor_info, 'TrueValueTapData')
    true_values_data = single(sensor_info.TrueValueTapData);
else
    true_values_data = single(NaN(N_samples, numel(TRUE_VALUE_NAMES)));
end
if ~isequal(size(true_values_data), [N_samples, numel(TRUE_VALUE_NAMES)])
    error('TrueValueTapData must be [%d x %d], got [%d x %d]', ...
        N_samples, numel(TRUE_VALUE_NAMES), size(true_values_data,1), size(true_values_data,2));
end
h5create(output_filename, '/true_values', [N_samples, numel(TRUE_VALUE_NAMES)], 'Datatype', 'single', ...
    'ChunkSize', [N_samples, 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/true_values', true_values_data);
h5writeatt(output_filename, '/true_values', 'Description', ...
    'The unperturbed internal value of each channel that a sensor fault (F33-F41) can perturb, provided as ground truth for sensor-fault recovery tasks. No real instrument produces this signal. NaN where the tap is absent (see root attribute true_value_tap_present).');
h5writeatt(output_filename, '/true_values', 'channel_names', strjoin(TRUE_VALUE_NAMES, ','));
h5writeatt(output_filename, '/true_values', 'dtype', 'single');

%% Labels -- int8 (smallest exact type for {0,1} / {0..5}), chunked + compressed
h5create(output_filename, '/fault_label', [N_samples, 42], ...
    'Datatype', 'int8', 'Deflate', 4, 'ChunkSize', [N_samples, 1]);
h5write(output_filename, '/fault_label', int8(fault_label));
h5writeatt(output_filename, '/fault_label', 'Description', ...
    'Per-timestep fault activity. Column i = fault F(i) (dataset ID 1-42). 0=inactive, 1=active.');
h5writeatt(output_filename, '/fault_label', 'Column_order', 'F01, F02, ..., F42');

h5create(output_filename, '/severity_label', [N_samples, 42], ...
    'Datatype', 'int8', 'Deflate', 4, 'ChunkSize', [N_samples, 1]);
h5write(output_filename, '/severity_label', int8(severity_label));
h5writeatt(output_filename, '/severity_label', 'Description', ...
    'Per-timestep fault severity. Column i = fault F(i). 0=inactive, 1-5=severity level. Ramp faults interpolate 1->S during the drift period.');
h5writeatt(output_filename, '/severity_label', 'Column_order', 'F01, F02, ..., F42');

%% Metadata
h5writeatt(output_filename, '/', 'fault_count', int32(metadata.fault_count));
if metadata.fault_count == 0
    h5writeatt(output_filename, '/', 'fault_name', 'Healthy');
else
    % Naming scheme 2026-11-21: single-fault records use the SAME layout as multi-fault ones
    % (fault_01_id / fault_01_severity / fault_01_severity_deviation); the old single-fault
    % fault_id / severity / severity_deviation attributes are no longer written.
    % severity_deviation = the real fractional deviation applied to the perturbed quantity
    % not severity*20 restated as a percentage.
    h5writeatt(output_filename, '/', 'fault_name', metadata.fault_names);
    for i = 1:metadata.fault_count
        h5writeatt(output_filename, '/', sprintf('fault_%02d_id',                i), int32(metadata.fault_ids(i)));
        h5writeatt(output_filename, '/', sprintf('fault_%02d_severity',          i), int32(metadata.severities(i)));
        h5writeatt(output_filename, '/', sprintf('fault_%02d_severity_deviation',i), double(metadata.severity_deviations(i)));
    end
end

if isfield(metadata, 'scenario_id') && ~isempty(metadata.scenario_id)
    h5writeatt(output_filename, '/', 'scenario_id', metadata.scenario_id);   % folder name minus DIAG_/TD_
end
h5writeatt(output_filename, '/', 'epoch', int32(metadata.epoch));
h5writeatt(output_filename, '/', 'attempt', int32(metadata.attempt));
h5writeatt(output_filename, '/', 'environmental_id', int32(metadata.environmental_id));
h5writeatt(output_filename, '/', 'environment_mode', metadata.environment_mode);
h5writeatt(output_filename, '/', 'FG_pressure_kPa', metadata.env_conditions.FG_pressure_kPa);
h5writeatt(output_filename, '/', 'FG_temp_C', metadata.env_conditions.FG_temp_C);
h5writeatt(output_filename, '/', 'compressor_inlet_temp_C', metadata.env_conditions.compressor_inlet_temp_C);
h5writeatt(output_filename, '/', 'compressor_inlet_press_kPa', metadata.env_conditions.compressor_inlet_press_kPa);
h5writeatt(output_filename, '/', 'ambient_moisture_percent', metadata.env_conditions.ambient_moisture_percent);

h5writeatt(output_filename, '/', 'num_samples', int32(N_samples));
h5writeatt(output_filename, '/', 'num_sensors_channels', int32(26));
h5writeatt(output_filename, '/', 'num_internal_channels', int32(13));
h5writeatt(output_filename, '/', 'num_true_value_channels', int32(numel(TRUE_VALUE_NAMES)));
if isfield(sensor_info, 'TrueValueTapPresent')
    h5writeatt(output_filename, '/', 'true_value_tap_present', int8(sensor_info.TrueValueTapPresent));
else
    h5writeatt(output_filename, '/', 'true_value_tap_present', int8(zeros(1, numel(TRUE_VALUE_NAMES))));
end
h5writeatt(output_filename, '/', 'sampling_rate_hz', sensor_info.SamplingRate);
h5writeatt(output_filename, '/', 'duration_sec', double(ScenarioConfig.STORED_SAMPLES));

if isfield(metadata, 'fault_start_times') && ~isempty(metadata.fault_start_times)
    h5writeatt(output_filename, '/', 'fault_start_times', metadata.fault_start_times);
else
    h5writeatt(output_filename, '/', 'fault_start_times', double([]));
end

%% -- the new per-record operating-point / QA attributes (ComputeLayer1RecordAttributes.m)
h5writeatt(output_filename, '/', 'duty_achieved_MW', double(record_attrs.duty_achieved_MW));
h5writeatt(output_filename, '/', 'operating_regime', record_attrs.operating_regime);
h5writeatt(output_filename, '/', 'limiter_active_fraction', double(record_attrs.limiter_active_fraction));
h5writeatt(output_filename, '/', 'controller_saturated', int32(record_attrs.controller_saturated));
h5writeatt(output_filename, '/', 'controller_saturated_hi', int32(record_attrs.controller_saturated_hi));
h5writeatt(output_filename, '/', 'controller_saturated_lo', int32(record_attrs.controller_saturated_lo));
h5writeatt(output_filename, '/', 'pt_speed_settled', int32(record_attrs.pt_speed_settled));
if isnan(record_attrs.steady_state_start_s)
    h5writeatt(output_filename, '/', 'steady_state_start_s', double(-1));   % -1 sentinel: never settled
else
    h5writeatt(output_filename, '/', 'steady_state_start_s', double(record_attrs.steady_state_start_s));
end
h5writeatt(output_filename, '/', 'in_calibration_envelope', int32(record_attrs.in_calibration_envelope));
h5writeatt(output_filename, '/', 'preroll_discarded_s', double(record_attrs.preroll_discarded_s));
h5writeatt(output_filename, '/', 't_since_cal_years', double(record_attrs.t_since_cal));
if ~isnan(record_attrs.f37_frozen_fraction_target)
    h5writeatt(output_filename, '/', 'f37_frozen_fraction_target', double(record_attrs.f37_frozen_fraction_target));
    h5writeatt(output_filename, '/', 'f37_frozen_fraction_achieved', double(record_attrs.f37_frozen_fraction_achieved));
end
h5writeatt(output_filename, '/', 'retry_attempts_used', int32(record_attrs.attempt_used));
% Seed provenance: scenario_hash is an input to every seed formula in the pipeline, so without it
% a record cannot be regenerated from its own file (S4 cross-cutting
% requirement 2). Added.
h5writeatt(output_filename, '/', 'scenario_hash', int32(record_attrs.scenario_hash));
% S4: which initial condition this record actually started from.
h5writeatt(output_filename, '/', 'warm_start_route', record_attrs.warm_start_route);
if isnan(record_attrs.warm_start_temp_C)
    h5writeatt(output_filename, '/', 'warm_start_temp_C', double(-1));   % -1 sentinel: cold start
else
    h5writeatt(output_filename, '/', 'warm_start_temp_C', double(record_attrs.warm_start_temp_C));
end
% the realised (signed) within-record ambient trend amplitude, degC.
if isfield(record_attrs, 'ambient_trend_amplitude_C')
    h5writeatt(output_filename, '/', 'ambient_trend_amplitude_C', double(record_attrs.ambient_trend_amplitude_C));
end
% the drawn-vs-realised ambient check's own statistic,
% GATED at +/-15 degC in ValidateGenerationLayer1.m, plus the realised window length. The S24
% half is informational only -- see that function's header for why it cannot be a
% gate yet (the GG rotor has no equilibrium until G3 lands).
h5writeatt(output_filename, '/', 'ambient_check_residual_C', double(record_attrs.ambient_check_residual_C));
h5writeatt(output_filename, '/', 'ambient_check_window_n', int32(record_attrs.ambient_check_window_n));
h5writeatt(output_filename, '/', 's24_library_offset_radps', double(record_attrs.s24_library_offset_radps));

% the FIXED commanded duty this record was generated at, sourced
% directly from ScenarioConfig (not from record_attrs, which RunScenario.m -- frozen -- builds
% without knowledge of the turndown family) so every diagnosis-family record, 13 MW or 10 MW,
% self-identifies its duty even after the DiagnosisTurndown/ and Diagnosis/ folders are merged.
h5writeatt(output_filename, '/', 'duty_cmd_MW', double(ScenarioConfig.DUTY_CMD_MW()));

%% Generation provenance
h5writeatt(output_filename, '/', 'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
h5writeatt(output_filename, '/', 'matlab_version', version);
% Generator identity, as a released-dataset-facing string: no internal phase name and no
% version language about the dataset itself (Terminology). owns the final
% wording; this is the neutral placeholder it replaces.
h5writeatt(output_filename, '/', 'writer_version', 'avon-generation-pipeline 2026-10');

file_info = dir(output_filename);
fprintf('  HDF5 saved: %s (%.3f MB)\n', output_filename, file_info.bytes/1024/1024);

end
