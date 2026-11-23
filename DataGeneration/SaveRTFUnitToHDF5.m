function SaveRTFUnitToHDF5(sensors_noisy_all, true_values_all, output_filename, unit_attrs, ...
    cycle_index, labels, duty_achieved_MW_hist, limiter_active_fraction_hist, operating_regime_code_hist, ambient_hist, ...
    ambient_check_residual_C_hist, ambient_check_absolute_C_hist)
% SaveRTFUnitToHDF5 - writer for ONE run-to-failure unit file.
% Same channel-split, chunking, compression and channel_names conventions as SaveSensorsToHDF5.m
% (the diagnosis family's writer) -- deliberately, so a user reading both families sees the same
% /sensors, /internal, /true_values schema; only the per-sample row count (300*C instead of 4200)
% and the per-cycle label arrays differ.
%
% Inputs:
%   sensors_noisy_all - [300*C x 39] post-measurement-model channel array, cycles concatenated
%   true_values_all    - [300*C x 5] clean true-value taps, cycles concatenated
%   output_filename    - output HDF5 path
%   unit_attrs         - struct: mechanism, fault_id, cycles_to_failure, failure_mode,
%                        initial_wear, gamma_shape, gamma_scale, delta_EOL, p_exponent,
%                        h_at_termination, S26_ref, T_DOUBLING, BETA_LIMITER, unit_id,
%                        master_seed, scenario_hash, warm_start_route, gg_warm_start_mode,
%                        pt_warm_start_mode, terminated_or_aborted, true_value_tap_present
%   cycle_index        - [300*C x 1] int, which cycle each STORED SAMPLE belongs to (1..C)
%   labels             - struct from ComputeRTFUnitLabels.m: severity_factor, delta, rul_cycles,
%                        rul_seconds, cycles_to_failure, h_at_termination (all [C x 1] except the
%                        two scalars) -- health_index is NOT in this struct, passed separately
%                        below via the accumulator's own h_hist (RunRTFUnit.m keeps it, not this
%                        function, since ComputeRTFUnitLabels.m takes health_index as an INPUT,
%                        not an output)
%   duty_achieved_MW_hist, limiter_active_fraction_hist, operating_regime_code_hist, ambient_hist
%                      - [C x 1] / [C x 5] per-cycle measured arrays (RunRTFUnit.m's own history)
%   ambient_check_residual_C_hist
%                      - [C x 1] per-cycle drawn-vs-realised ambient check residual. Made DIFFERENTIAL
% this is now the GATED statistic (cycle 1 holds the
%                        absolute value, since cycle 1 has no predecessor to difference against).
%                        Gating itself became a PERSISTENCE rule (RTF_AMBIENT_DIFF_PERSIST_N
%                        consecutive same-sign breaches) -- see the
%                        '/ambient_check_residual_C' dataset's own Description attribute below.
%   ambient_check_absolute_C_hist
%                      - [C x 1] the ORIGINAL absolute-form ambient
%                        check residual (this cycle's clean tail S26 minus the Healthy library's
%                        prediction at this cycle's own drawn ambient). Stored as an
%                        informational, UNGATED fault-progression signal -- not used to retry or
%                        fail a cycle on.
%
%         pt_warm_start_mode added, 2026-10-21; ambient_check_residual_C_hist
%         made DIFFERENTIAL and ambient_check_absolute_C_hist added, 2026-10-21;
%         ambient_check_residual_C_hist's gate made PERSISTENCE-based and limiter_active_fraction_hist's
%         one-sided-limiter ported, 2026-10-21

SENSORS_IDX  = ScenarioConfig.RTF_SENSORS_IDX;    % 26 -- shared with RestoreRTFUnitState.m
INTERNAL_IDX = ScenarioConfig.RTF_INTERNAL_IDX;   % 13
TRUE_VALUE_NAMES = {'S19_true', 'S24_true', 'S27_true', 'S04_true', 'S26_true'};

N_samples = size(sensors_noisy_all, 1);
C = unit_attrs.cycles_to_failure;
if N_samples ~= ScenarioConfig.RTF_CYCLE_SECONDS * C
    error('SaveRTFUnitToHDF5:SampleCountMismatch', 'Got %d samples, expected %d (= %d cycles x %d s).', ...
        N_samples, ScenarioConfig.RTF_CYCLE_SECONDS*C, C, ScenarioConfig.RTF_CYCLE_SECONDS);
end
if numel(cycle_index) ~= N_samples
    error('SaveRTFUnitToHDF5:CycleIndexMismatch', 'cycle_index has %d entries, expected %d.', numel(cycle_index), N_samples);
end

[output_dir, ~, ~] = fileparts(output_filename);
if ~isempty(output_dir) && ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
if exist(output_filename, 'file')
    delete(output_filename);
end

SensorDef = GetSensorDefinitions();

%% /sensors, /internal -- identical convention to the diagnosis family's writer
sensors_data  = single(sensors_noisy_all(:, SENSORS_IDX));
internal_data = single(sensors_noisy_all(:, INTERNAL_IDX));

h5create(output_filename, '/sensors', [N_samples, 26], 'Datatype', 'single', ...
    'ChunkSize', [min(N_samples,ScenarioConfig.RTF_CYCLE_SECONDS), 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/sensors', sensors_data);
h5writeatt(output_filename, '/sensors', 'Description', ...
    'The headline, directly-instrumented channel suite. 21 measured + 5 ambient-context channels. [channel, time] on disk (h5py); row order given by channel_names. Cycles concatenated in order -- use /cycle_index to slice.');
h5writeatt(output_filename, '/sensors', 'channel_names', strjoin(arrayfun(@(i) SensorDef.ShortNames{i}, SENSORS_IDX, 'UniformOutput', false), ','));
h5writeatt(output_filename, '/sensors', 'dtype', 'single');

h5create(output_filename, '/internal', [N_samples, 13], 'Datatype', 'single', ...
    'ChunkSize', [min(N_samples,ScenarioConfig.RTF_CYCLE_SECONDS), 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/internal', internal_data);
h5writeatt(output_filename, '/internal', 'Description', ...
    'Model-internal / controller-demand channels. No real instrument exists for any of these. [channel, time] on disk.');
h5writeatt(output_filename, '/internal', 'channel_names', strjoin(arrayfun(@(i) SensorDef.ShortNames{i}, INTERNAL_IDX, 'UniformOutput', false), ','));
h5writeatt(output_filename, '/internal', 'dtype', 'single');

%% /true_values
true_values_data = single(true_values_all);
if ~isequal(size(true_values_data), [N_samples, numel(TRUE_VALUE_NAMES)])
    error('SaveRTFUnitToHDF5:TrueValuesShape', 'true_values_all must be [%d x %d], got [%d x %d]', ...
        N_samples, numel(TRUE_VALUE_NAMES), size(true_values_data,1), size(true_values_data,2));
end
h5create(output_filename, '/true_values', [N_samples, numel(TRUE_VALUE_NAMES)], 'Datatype', 'single', ...
    'ChunkSize', [min(N_samples,ScenarioConfig.RTF_CYCLE_SECONDS), 1], 'Deflate', 4, 'Shuffle', true);
h5write(output_filename, '/true_values', true_values_data);
h5writeatt(output_filename, '/true_values', 'Description', ...
    'The unperturbed internal value of each channel that a sensor fault (F33-F41) can perturb. Not applicable to this family''s own mechanism (none of the 13 are sensor faults); provided for schema parity with the diagnosis family. NaN where the tap is absent.');
h5writeatt(output_filename, '/true_values', 'channel_names', strjoin(TRUE_VALUE_NAMES, ','));
h5writeatt(output_filename, '/true_values', 'dtype', 'single');

%% /cycle_index -- sample-level, int32
h5create(output_filename, '/cycle_index', [N_samples, 1], 'Datatype', 'int32', ...
    'ChunkSize', [min(N_samples,ScenarioConfig.RTF_CYCLE_SECONDS), 1], 'Deflate', 4);
h5write(output_filename, '/cycle_index', int32(cycle_index(:)));
h5writeatt(output_filename, '/cycle_index', 'Description', ...
    'Which cycle (1..cycles_to_failure) each stored sample belongs to -- the only way to slice this file without assuming 300 samples/cycle.');

%% Per-cycle datasets -- [C x 1] (or [C x 5] for /ambient)
h5create(output_filename, '/rul_cycles', [C, 1], 'Datatype', 'int32');
h5write(output_filename, '/rul_cycles', int32(labels.rul_cycles));
h5writeatt(output_filename, '/rul_cycles', 'Description', 'cycles_to_failure - cycle, per cycle.');

h5create(output_filename, '/rul_seconds', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/rul_seconds', double(labels.rul_seconds));
h5writeatt(output_filename, '/rul_seconds', 'Description', 'rul_cycles * RTF_CYCLE_SECONDS.');

h5create(output_filename, '/health_index', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/health_index', double(unit_attrs.health_index_hist));
h5writeatt(output_filename, '/health_index', 'Description', ...
    'Latent damage variable h(c), accumulated by the gamma process, AFTER cycle c''s own increment. Published alongside delta so the generating process is fully reconstructable (Sec5.3).');

h5create(output_filename, '/delta', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/delta', double(unit_attrs.delta_hist));
h5writeatt(output_filename, '/delta', 'Description', ...
    'delta(c) = delta_EOL * h(c)^p_exponent -- the deviation actually commanded this cycle (same axis as the diagnosis family''s severity deviation).');

h5create(output_filename, '/severity_factor', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/severity_factor', double(labels.severity_factor));
h5writeatt(output_filename, '/severity_factor', 'Description', ...
    's_c = 2^((S26_tail_c-S26_ref)/T_DOUBLING) * (1 + BETA_LIMITER*limiter_active_fraction_c). Scales this cycle''s gamma increment.');

h5create(output_filename, '/duty_achieved_MW', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/duty_achieved_MW', double(duty_achieved_MW_hist));
h5writeatt(output_filename, '/duty_achieved_MW', 'Description', 'Tail-window mean S28, per cycle.');

h5create(output_filename, '/limiter_active_fraction', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/limiter_active_fraction', double(limiter_active_fraction_hist));
h5writeatt(output_filename, '/limiter_active_fraction', 'Description', 'Fraction of this cycle''s tail window with S26 >= 845 degC (one-sided, decision 59, ported to this family by P4 Task 21/decision 63 -- counts OVER-limit time too, not only the [845,846] approach band).');

h5create(output_filename, '/operating_regime_code', [C, 1], 'Datatype', 'int8');
h5write(output_filename, '/operating_regime_code', int8(operating_regime_code_hist));
h5writeatt(output_filename, '/operating_regime_code', 'Description', ...
    '1=duty_tracking, 2=temperature_limited, 3=fault_limited, 0=indeterminate (rare -- a cycle whose depth sits exactly at the duty_tracking/temperature_limited boundary and did not resolve after retry; RunRTFUnit.m retries an indeterminate cycle with mildness before accepting it, unlike the diagnosis family where this value is never shipped).');

h5create(output_filename, '/ambient', [C, 5], 'Datatype', 'double');
h5write(output_filename, '/ambient', double(ambient_hist));
h5writeatt(output_filename, '/ambient', 'Description', 'Per-cycle realised ambient draw: FG_pressure_kPa, FG_temp_C, compressor_inlet_temp_C, compressor_inlet_press_kPa, ambient_moisture_percent.');
h5writeatt(output_filename, '/ambient', 'channel_names', 'FG_pressure_kPa,FG_temp_C,compressor_inlet_temp_C,compressor_inlet_press_kPa,ambient_moisture_percent');

h5create(output_filename, '/ambient_check_residual_C', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/ambient_check_residual_C', double(ambient_check_residual_C_hist));
h5writeatt(output_filename, '/ambient_check_residual_C', 'Description', ...
    'P4 Task 20 (decision 62), persistence rule added Task 21 (decision 63): the GATED per-cycle ambient check, DIFFERENTIAL form. For cycle c>1: (this cycle''s clean tail S26 minus the PREVIOUS accepted cycle''s clean tail S26) minus (the warm-start library''s 2-D surface-predicted S26 at this cycle''s drawn ambient minus the same surface at the previous accepted cycle''s drawn ambient) -- cancels the unit''s own accumulating fault offset to first order, unlike the diagnosis family''s absolute check, because an RTF cycle has no fault-free pre-onset window for an absolute Healthy-library comparison to be valid against (P4_results.md Sec30). Cycle 1 has no predecessor and holds the ABSOLUTE value instead (valid there: h<=0.05). A single cycle''s |value| exceeding +/-RTF_AMBIENT_DIFF_TOL_C degC (ScenarioConfig.m), or +/-RTF_AMBIENT_DIFF_TOL_PINNED_C degC when THIS cycle''s OR the PREVIOUS cycle''s measured operating_regime_code is 2 (temperature_limited), is NOT by itself sufficient to fail the unit -- the differential statistic is an exact first difference of the absolute one, so a single-cycle transient produces a benign same-sign-then-opposite-sign PAIR of large residuals (P4_results.md Sec32.1/32.3). The gate fires, and retries the cycle, only at RTF_AMBIENT_DIFF_PERSIST_N consecutive SAME-SIGN breaches (reset on any non-breach or sign change); a gate still firing after the last retry attempt fails the unit rather than writing it. A NaN (broken library lookup) is exempt from the persistence counter and is always unconditional/single-cycle. Superseded Task 18''s absolute form, which is preserved separately as /ambient_check_absolute_C.');

h5create(output_filename, '/ambient_check_absolute_C', [C, 1], 'Datatype', 'double');
h5write(output_filename, '/ambient_check_absolute_C', double(ambient_check_absolute_C_hist));
h5writeatt(output_filename, '/ambient_check_absolute_C', 'Description', ...
    'P4 Task 20 (decision 62): the ORIGINAL (Task 18) absolute-form ambient check residual -- this cycle''s own tail-window clean S26 minus the warm-start library''s 2-D (temperature x pressure) surface prediction at this cycle''s own drawn ambient. INFORMATIONAL ONLY from Task 20 on: it grows with the unit''s own accumulating fault depth (it is, in effect, a free fault-progression signal) and is NOT gated -- gating moved to /ambient_check_residual_C''s differential form (P4_results.md Sec30).');

%% Root attributes
h5writeatt(output_filename, '/', 'mechanism', unit_attrs.mechanism);
if isfield(unit_attrs, 'scenario_id'), h5writeatt(output_filename, '/', 'scenario_id', unit_attrs.scenario_id); end
h5writeatt(output_filename, '/', 'fault_id', int32(unit_attrs.fault_id));
h5writeatt(output_filename, '/', 'cycles_to_failure', int32(unit_attrs.cycles_to_failure));
h5writeatt(output_filename, '/', 'failure_mode', unit_attrs.failure_mode);
h5writeatt(output_filename, '/', 'initial_wear', double(unit_attrs.initial_wear));
h5writeatt(output_filename, '/', 'gamma_shape', double(unit_attrs.gamma_shape));
h5writeatt(output_filename, '/', 'gamma_scale', double(unit_attrs.gamma_scale));
h5writeatt(output_filename, '/', 'delta_EOL', double(unit_attrs.delta_EOL));
h5writeatt(output_filename, '/', 'p_exponent', double(unit_attrs.p_exponent));
h5writeatt(output_filename, '/', 'h_at_termination', double(unit_attrs.h_at_termination));
h5writeatt(output_filename, '/', 'S26_ref', double(unit_attrs.S26_ref));
h5writeatt(output_filename, '/', 'T_DOUBLING', double(unit_attrs.T_DOUBLING));
h5writeatt(output_filename, '/', 'BETA_LIMITER', double(unit_attrs.BETA_LIMITER));
h5writeatt(output_filename, '/', 'unit_id', int32(unit_attrs.unit_id));
h5writeatt(output_filename, '/', 'master_seed', int32(unit_attrs.master_seed));
h5writeatt(output_filename, '/', 'scenario_hash', int32(unit_attrs.scenario_hash));
h5writeatt(output_filename, '/', 'warm_start_route', unit_attrs.warm_start_route);
h5writeatt(output_filename, '/', 'gg_warm_start_mode', unit_attrs.gg_warm_start_mode);
h5writeatt(output_filename, '/', 'pt_warm_start_mode', unit_attrs.pt_warm_start_mode);
h5writeatt(output_filename, '/', 'terminated_or_aborted', unit_attrs.terminated_or_aborted);
h5writeatt(output_filename, '/', 'true_value_tap_present', int8(unit_attrs.true_value_tap_present));
h5writeatt(output_filename, '/', 'num_samples', int32(N_samples));
h5writeatt(output_filename, '/', 'samples_per_cycle', int32(ScenarioConfig.RTF_CYCLE_SECONDS));

h5writeatt(output_filename, '/', 'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
h5writeatt(output_filename, '/', 'matlab_version', version);
h5writeatt(output_filename, '/', 'writer_version', 'avon-generation-pipeline 2026-10');

file_info = dir(output_filename);
fprintf('  RTF unit HDF5 saved: %s (%.3f MB)\n', output_filename, file_info.bytes/1024/1024);

end
