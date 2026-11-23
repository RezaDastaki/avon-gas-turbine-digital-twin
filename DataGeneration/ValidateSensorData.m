function [is_valid, failed_columns, reason] = ValidateSensorData(sensor_data, sensor_data_clean)
% ValidateSensorData - Validate extracted sensor data before HDF5 save
%
% Runs per-column checks on the [N × 34] sensor matrix. Called as Step 6 in
% RunScenario, after AddGaussianNoise, before SaveWorkspaceToHDF5.
%
% Checks per column (fails on first failing check for that column):
%   1. All-NaN:        all(isnan(col))
%   2. All-zero:       all(col == 0)
%   3. Constant:       std(col) < 1e-9  (sensor not logging)
%   4. NaN fraction:   sum(isnan(col))/N > 0.05  (>5% missing)
%   5. Infinite:       any(isinf(col))
%
% Inputs:
%   sensor_data - [N × 34] double — sensor matrix (post-noise)
%
% Outputs:
%   is_valid       - logical — true if all columns pass all checks
%   failed_columns - [1 × k] integer — column indices that failed (empty if is_valid)
%   reason         - cell array of strings — failure reason per failed column
%
% On failure in the pipeline:
%   - Log column index, fault type, and reason to generation_failures.log
%   - Skip HDF5 save for this scenario
%   - Keep .mat checkpoint for re-extraction
%
% Date: 2026-03-15

%% Input validation

[N, n_sensors] = size(sensor_data);

% Input may be 34 (physical only) or 39 (physical + context). Context
% channels S35-S39 are quasi-constant ambient values by design, so only the
% physical sensors are validated here.
SensorDef_v = GetSensorDefinitions();
n_phys = SensorDef_v.PhysicalCount;   % 34
if n_sensors < n_phys
    error('ValidateSensorData:InvalidInput', ...
          'sensor_data must have at least %d columns (got %d)', n_phys, n_sensors);
end

%% Run checks (physical sensors only)

% found by running the real post-pipeline end-to-end (a genuine integration
% bug between measurement model and this pre-existing check, not a -introduced defect).
% a verification run found 3 of 39 channels --
% S05, S32, S34 -- are QUANTISATION-DOMINATED: their measurement-noise sigma_noise sits below half
% the ADC quantisation step, so ApplyMeasurementModel.m's quantisation stage (step 5) can
% legitimately round an entire record's worth of samples for these three channels onto a single
% quantised level, especially in mild/Healthy conditions where the underlying physical signal
% barely moves. That is NOT the same failure mode as check 3's original target (a sensor that
% never logs at all, e.g. a broken wire) -- confirmed on the very first real smoke-test record
% this session, where S32 was exactly constant to float precision after quantisation on a
% Healthy/10.6 degC record. These three channels are exempted from the hard constant-check below;
% every other channel keeps it unchanged.
QUANTISATION_DOMINATED_COLS = [5, 32, 34];

%/14: the exemption above is now CONDITIONAL, not blanket. Exempting
% these three channels outright also silences the check's original target -- a channel that
% genuinely never logs -- for three of the 39 channels. With the clean, pre-quantisation array
% in hand the two cases separate exactly, PROVIDED the test is the right way round. The test is
% NOT "does the clean column vary": a settled, constant-ambient, fault-free record has clean
% columns that are constant to machine precision by construction, so that test false-fails every
% Healthy record (measured: 7 of 9 real records in P4_audit_04 failed on S32 under it). The
% correct test is whether QUANTISATION EXPLAINS the flatness: if the clean column's whole-record
% range is within about one ADC step, a single stored level is exactly what the quantiser should
% produce and the record is fine; if the clean column swung much further than a step and the
% stored column is still flat, something downstream of the plant has broken and the record must
% fail. Called with one argument the old blanket behaviour is kept, so no existing caller breaks.
have_clean = nargin >= 2 && ~isempty(sensor_data_clean) && ...
             size(sensor_data_clean, 1) == N && size(sensor_data_clean, 2) >= n_phys;
if have_clean
    nm_vsd = GetSensorNoiseModel();
    quant_step_vsd = (nm_vsd.span_max - nm_vsd.span_min) ./ (2 .^ nm_vsd.quant_bits);
end

failed_columns = [];
reason         = {};

for c = 1 : n_phys
    col = sensor_data(:, c);

    % Check 1: All-NaN
    if all(isnan(col))
        failed_columns(end+1) = c;          %#ok<AGROW>
        reason{end+1} = sprintf('Column %d (S%02d): all NaN', c, c);  %#ok<AGROW>
        continue;
    end

    % Check 2: All-zero -- same quantisation-dominated exemption as Check 3 below. Found on a real
    % F37 record (17.3 degC): S32 (a channel that legitimately crosses zero) read
    % real, varying values [-3.455, 3.476] over the FULL pre-trim extraction, but after
    % quantisation (step 0.0488, sigma_noise 0.0019 -- the same quantisation-dominated channel
    % Check 3 already exempts) the whole STORED window happened to land in the zero bucket. The
    % underlying cause is identical to Check 3's; "stuck at zero" is not a different failure mode
    % from "stuck at some other constant" for these three channels, just a different bucket value.
    exempt = ismember(c, QUANTISATION_DOMINATED_COLS);
    if exempt && have_clean
        % exempt only if quantisation explains the flatness (see the note above)
        clean_range = max(sensor_data_clean(:, c)) - min(sensor_data_clean(:, c));
        exempt = clean_range <= 1.5 * quant_step_vsd(c);
    end

    if all(col == 0) && ~exempt
        failed_columns(end+1) = c;          %#ok<AGROW>
        reason{end+1} = sprintf('Column %d (S%02d): all zero', c, c);  %#ok<AGROW>
        continue;
    end

    % Check 3: Constant (std < 1e-9) -- not applied to the known quantisation-dominated channels
    if std(col, 'omitnan') < 1e-9 && ~exempt
        failed_columns(end+1) = c;          %#ok<AGROW>
        reason{end+1} = sprintf('Column %d (S%02d): constant (std < 1e-9)', c, c);  %#ok<AGROW>
        continue;
    end

    % Check 4: NaN fraction > 5%
    nan_frac = sum(isnan(col)) / N;
    if nan_frac > 0.05
        failed_columns(end+1) = c;          %#ok<AGROW>
        reason{end+1} = sprintf('Column %d (S%02d): %.1f%% NaN (limit 5%%)', c, c, nan_frac*100);  %#ok<AGROW>
        continue;
    end

    % Check 5: Infinite values
    if any(isinf(col))
        failed_columns(end+1) = c;          %#ok<AGROW>
        reason{end+1} = sprintf('Column %d (S%02d): contains Inf/-Inf', c, c);  %#ok<AGROW>
        continue;
    end
end

is_valid = isempty(failed_columns);

end
