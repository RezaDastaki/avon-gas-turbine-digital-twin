function [ok, msg] = ValidateRecordSchema(h5_file)
% ValidateRecordSchema - Structural validation against the CURRENT diagnosis-family writer
% schema (sensors, /internal, /true_values), same rule family
% ScenarioAlreadyDone.m already trusts for resumability, plus a NaN/Inf sanity check on
% /sensors.
%
% Factored out of AvonSetupCheck.m's local_validate_current_schema so
% parallel-driver acceptance tests can reuse
% exactly the same check instead of duplicating it. NOT a replacement for QualityCheckHDF5.m's
% intent -- that function is stale against the current schema and is
% handled separately. Nothing calls QualityCheckHDF5 differently because of this file.
%
% Usage:
%   [ok, msg] = ValidateRecordSchema(h5_file)
%

    ok = false;
    try
        info = h5info(h5_file);
        dsets = {info.Datasets.Name};
        required = {'sensors', 'internal', 'true_values'};
        if ~all(ismember(required, dsets))
            msg = sprintf('missing required dataset(s): %s', strjoin(setdiff(required, dsets), ', '));
            return;
        end
        sensors_dset = info.Datasets(strcmp(dsets, 'sensors'));
        n_samples = sensors_dset.Dataspace.Size(1);
        if n_samples ~= ScenarioConfig.STORED_SAMPLES
            msg = sprintf('/sensors has %d rows, expected STORED_SAMPLES=%d', n_samples, ScenarioConfig.STORED_SAMPLES);
            return;
        end
        sensors = h5read(h5_file, '/sensors');
        if any(isnan(sensors(:))) || any(isinf(sensors(:)))
            msg = '/sensors contains NaN or Inf';
            return;
        end
        fault_count = h5readatt(h5_file, '/', 'fault_count'); %#ok<NASGU>
        regime = h5readatt(h5_file, '/', 'operating_regime');
        writer_version = h5readatt(h5_file, '/', 'writer_version'); %#ok<NASGU>
        msg = sprintf('/sensors [%d x %d], no NaN/Inf, operating_regime=%s, required attrs present', ...
            size(sensors,1), size(sensors,2), regime);
        ok = true;
    catch ME
        msg = sprintf('structural check threw: %s', ME.message);
        ok = false;
    end
end
