function [ok, msg] = QualityCheckHDF5(h5_file)
% QualityCheckHDF5 - REWRITTEN against the CURRENT writer schema
% (SaveSensorsToHDF5.m / SaveRTFUnitToHDF5.m).
%
% STATUS: an OFFLINE AUDITING TOOL, not a production gate. ScenarioConfig.RUN_QUALITY_CHECKS
% stays false, deliberately -- QA Layer 1 (ValidateGenerationLayer1.m /
% ComputeLayer1RecordAttributes.m) is the real per-record/per-cycle gate, and turning a
% newly-written per-record check on for every record risks hard-failing valid records on a
% tolerance that sits inside the benign range. This function is meant to be run by hand over
% a finished family, or by AvonProgress.m / the release packaging step -- never inline from
% RunScenario.m / RunRTFUnit.m.
%
% WHAT IT REPLACES: an earlier QualityCheckHDF5.m that read /time, /fault_label,
% /severity_label and an `environmental_id` attribute against the pre-split schema and threw
% "object 'time' doesn't exist" on every record written by the current pipeline. RunScenario.m's
% Step 9 call is wrapped in try/catch and ScenarioConfig.RUN_QUALITY_CHECKS=false, so that
% error was silently swallowed; this version reads the current /sensors + /internal +
% /true_values schema.
%
% FAMILY, auto-detected from dataset presence (never guessed from the file path or name):
%   diagnosis record - has /fault_label, /severity_label        (SaveSensorsToHDF5.m)
%   RTF unit         - has /rul_cycles, /cycle_index, ...        (SaveRTFUnitToHDF5.m)
%
% CHECKS, both families: required datasets present; /sensors [N x 26], /internal [N x 13],
% /true_values [N x 5] (true_values MAY legitimately be NaN where a sensor-fault tap is absent
% -- both writers document this explicitly -- so only Inf is flagged there, never NaN); no
% NaN/Inf in /sensors or /internal; required root attributes present and spot-checked for type;
% label-array/per-cycle-array lengths consistent with /sensors' own row count.
%
% CHECKS, diagnosis only: /fault_label, /severity_label shaped [N x 42]; values in {0,1} /
% {0..5}; required scalar attributes (fault_count, epoch, attempt, environmental_id,
% operating_regime, duty_achieved_MW) present.
%
% CHECKS, RTF only: /cycle_index length == N and N == 300*C where C = max(cycle_index); every
% per-cycle dataset (/rul_cycles, /rul_seconds, /health_index, /delta, /severity_factor,
% /duty_achieved_MW, /limiter_active_fraction, /operating_regime_code,
% /ambient_check_residual_C, /ambient_check_absolute_C) has exactly C rows; /ambient is [C x 5];
% required scalar attributes (mechanism, fault_id, cycles_to_failure, failure_mode, unit_id,
% h_at_termination, terminated_or_aborted) present. /ambient_check_residual_C and
% /ambient_check_absolute_C MAY legitimately contain NaN (SaveRTFUnitToHDF5.m's own Description:
% "A NaN (broken library lookup) is exempt from the persistence counter") -- only Inf is an
% error there.
%
% A checker that has never been shown to fail is not a checker (spec(a)) --
% QualityCheckHDF5_test.m (scratch, run once and discarded per the task instructions) generated
% real records of several kinds, confirmed this function passes every one of them, then
% deliberately corrupted copies (NaN-poisoned /sensors; a required attribute deleted via the
% low-level H5A API; a required dataset unlinked via H5L.delete) and confirmed FAIL on every one.
% See.
%
% Usage:
%   QualityCheckHDF5(h5_file)             % prints a report; a non-capturing caller (the old
%                                          % RunScenario.m Step 9 call site, left untouched --
%                                          % that file is frozen) still works unchanged
%   [ok, msg] = QualityCheckHDF5(h5_file) % ok=false + msg lists every failure found, '|'-joined
%

    errs = {};
    N = NaN; %#ok<NASGU>

    fprintf('\n=== QualityCheckHDF5: %s ===\n', h5_file);

    if ~isfile(h5_file)
        ok = false;
        msg = sprintf('file not found: %s', h5_file);
        fprintf('FAIL: %s\n', msg);
        return;
    end

    try
        info = h5info(h5_file);
    catch ME
        ok = false;
        msg = sprintf('h5info threw: %s', ME.message);
        fprintf('FAIL: %s\n', msg);
        return;
    end

    dset_names = {info.Datasets.Name};
    if isempty(info.Attributes)
        attr_names = {};
    else
        attr_names = {info.Attributes.Name};
    end

    is_rtf  = ismember('rul_cycles', dset_names);
    is_diag = ismember('fault_label', dset_names);

    if ~is_rtf && ~is_diag
        errs{end+1} = 'cannot determine family: neither /fault_label (diagnosis) nor /rul_cycles (RTF) present';
    elseif is_rtf && is_diag
        errs{end+1} = 'ambiguous family: BOTH /fault_label and /rul_cycles present';
    end

    %% --- shared: /sensors, /internal, /true_values ---
    N = NaN;
    required_common = {'sensors', 'internal', 'true_values'};
    missing_common = setdiff(required_common, dset_names);
    if ~isempty(missing_common)
        errs{end+1} = sprintf('missing required dataset(s): %s', strjoin(missing_common, ', '));
    else
        sz_sensors = local_dset_size(info, 'sensors');
        N = sz_sensors(1);
        if numel(sz_sensors) ~= 2 || sz_sensors(2) ~= 26
            errs{end+1} = sprintf('/sensors shape %s, expected [N x 26]', mat2str(sz_sensors));
        end
        sz_internal = local_dset_size(info, 'internal');
        if numel(sz_internal) ~= 2 || sz_internal(2) ~= 13 || sz_internal(1) ~= N
            errs{end+1} = sprintf('/internal shape %s, expected [%d x 13]', mat2str(sz_internal), N);
        end
        sz_tv = local_dset_size(info, 'true_values');
        if numel(sz_tv) ~= 2 || sz_tv(2) ~= 5 || sz_tv(1) ~= N
            errs{end+1} = sprintf('/true_values shape %s, expected [%d x 5]', mat2str(sz_tv), N);
        end

        try
            sensors = h5read(h5_file, '/sensors');
            if any(isnan(sensors(:))) || any(isinf(sensors(:)))
                errs{end+1} = '/sensors contains NaN or Inf';
            end
        catch ME
            errs{end+1} = sprintf('/sensors unreadable: %s', ME.message);
        end
        try
            internal = h5read(h5_file, '/internal');
            if any(isnan(internal(:))) || any(isinf(internal(:)))
                errs{end+1} = '/internal contains NaN or Inf';
            end
        catch ME
            errs{end+1} = sprintf('/internal unreadable: %s', ME.message);
        end
        try
            tv = h5read(h5_file, '/true_values');
            % NaN is EXPECTED here where a sensor-fault tap is absent -- both writers' own
            % Description attribute says so explicitly. Only Inf is an error.
            if any(isinf(tv(:)))
                errs{end+1} = '/true_values contains Inf';
            end
        catch ME
            errs{end+1} = sprintf('/true_values unreadable: %s', ME.message);
        end
    end

    %% --- required root attributes, both families ---
    required_attrs_common = {'num_samples', 'timestamp', 'matlab_version', 'writer_version'};
    missing_attrs = setdiff(required_attrs_common, attr_names);
    if ~isempty(missing_attrs)
        errs{end+1} = sprintf('missing required root attribute(s): %s', strjoin(missing_attrs, ', '));
    elseif ismember('writer_version', attr_names)
        try
            wv = h5readatt(h5_file, '/', 'writer_version');
            if ~(ischar(wv) || isstring(wv))
                errs{end+1} = 'writer_version attribute is not a string';
            end
        catch ME
            errs{end+1} = sprintf('writer_version unreadable: %s', ME.message);
        end
    end

    %% --- diagnosis-family-specific ---
    if is_diag
        required_diag_dsets = {'fault_label', 'severity_label'};
        missing = setdiff(required_diag_dsets, dset_names);
        if ~isempty(missing)
            errs{end+1} = sprintf('diagnosis record missing dataset(s): %s', strjoin(missing, ', '));
        else
            sz_fl = local_dset_size(info, 'fault_label');
            sz_sl = local_dset_size(info, 'severity_label');
            if isnan(N) || ~isequal(sz_fl, [N, 42])
                errs{end+1} = sprintf('/fault_label shape %s, expected [%d x 42]', mat2str(sz_fl), N);
            end
            if isnan(N) || ~isequal(sz_sl, [N, 42])
                errs{end+1} = sprintf('/severity_label shape %s, expected [%d x 42]', mat2str(sz_sl), N);
            end
            try
                fl = h5read(h5_file, '/fault_label');
                sl = h5read(h5_file, '/severity_label');
                if any(isnan(double(fl(:)))) || any(isinf(double(fl(:))))
                    errs{end+1} = '/fault_label contains NaN or Inf';
                end
                if any(isnan(double(sl(:)))) || any(isinf(double(sl(:))))
                    errs{end+1} = '/severity_label contains NaN or Inf';
                end
                if ~all(ismember(unique(double(fl(:))), [0 1]))
                    errs{end+1} = '/fault_label has values outside {0,1}';
                end
                if ~all(ismember(unique(double(sl(:))), 0:5))
                    errs{end+1} = '/severity_label has values outside {0..5}';
                end
            catch ME
                errs{end+1} = sprintf('fault_label/severity_label unreadable: %s', ME.message);
            end
        end
        required_diag_attrs = {'fault_count', 'epoch', 'attempt', 'environmental_id', ...
            'operating_regime', 'duty_achieved_MW'};
        missing_attrs_d = setdiff(required_diag_attrs, attr_names);
        if ~isempty(missing_attrs_d)
            errs{end+1} = sprintf('diagnosis record missing attribute(s): %s', strjoin(missing_attrs_d, ', '));
        end
    end

    %% --- RTF-family-specific ---
    if is_rtf
        required_rtf_dsets = {'cycle_index', 'rul_cycles', 'rul_seconds', 'health_index', ...
            'delta', 'severity_factor', 'duty_achieved_MW', 'limiter_active_fraction', ...
            'operating_regime_code', 'ambient', 'ambient_check_residual_C', 'ambient_check_absolute_C'};
        missing = setdiff(required_rtf_dsets, dset_names);
        if ~isempty(missing)
            errs{end+1} = sprintf('RTF unit missing dataset(s): %s', strjoin(missing, ', '));
        else
            try
                cyc_idx = double(h5read(h5_file, '/cycle_index'));
                if isnan(N) || numel(cyc_idx) ~= N
                    errs{end+1} = sprintf('/cycle_index has %d entries, expected %d (= /sensors rows)', numel(cyc_idx), N);
                end
                C = max(cyc_idx);
                if ~isnan(N) && N ~= 300 * C
                    errs{end+1} = sprintf('/sensors has %d rows, expected 300*C = %d (C=%d)', N, 300*C, C);
                end
                percycle = {'rul_cycles', 'rul_seconds', 'health_index', 'delta', 'severity_factor', ...
                    'duty_achieved_MW', 'limiter_active_fraction', 'operating_regime_code', ...
                    'ambient_check_residual_C', 'ambient_check_absolute_C'};
                for i = 1:numel(percycle)
                    sz = local_dset_size(info, percycle{i});
                    if isempty(sz) || sz(1) ~= C
                        errs{end+1} = sprintf('/%s has %s rows, expected C=%d', percycle{i}, mat2str(sz), C); %#ok<AGROW>
                    end
                end
                sz_amb = local_dset_size(info, 'ambient');
                if ~isequal(sz_amb, [C, 5])
                    errs{end+1} = sprintf('/ambient shape %s, expected [%d x 5]', mat2str(sz_amb), C);
                end
                for i = 1:numel(percycle)
                    try
                        v = double(h5read(h5_file, ['/' percycle{i}]));
                    catch
                        continue;  % already reported as a shape/missing issue above
                    end
                    if startsWith(percycle{i}, 'ambient_check')
                        % NaN permitted here (broken library lookup, documented) -- only Inf.
                        if any(isinf(v(:)))
                            errs{end+1} = sprintf('/%s contains Inf', percycle{i}); %#ok<AGROW>
                        end
                    else
                        if any(isnan(v(:))) || any(isinf(v(:)))
                            errs{end+1} = sprintf('/%s contains NaN or Inf', percycle{i}); %#ok<AGROW>
                        end
                    end
                end
            catch ME
                errs{end+1} = sprintf('RTF per-cycle datasets unreadable: %s', ME.message);
            end
        end
        required_rtf_attrs = {'mechanism', 'fault_id', 'cycles_to_failure', 'failure_mode', ...
            'unit_id', 'h_at_termination', 'terminated_or_aborted'};
        missing_attrs_r = setdiff(required_rtf_attrs, attr_names);
        if ~isempty(missing_attrs_r)
            errs{end+1} = sprintf('RTF unit missing attribute(s): %s', strjoin(missing_attrs_r, ', '));
        end
    end

    ok = isempty(errs);
    if ok
        fam_str = 'diagnosis';
        if is_rtf, fam_str = 'RTF'; end
        msg = sprintf('PASS (%s record, N=%d stored samples)', fam_str, N);
        fprintf('PASS: %s\n', msg);
    else
        msg = strjoin(errs, ' | ');
        fprintf('FAIL (%d issue(s)):\n', numel(errs));
        for i = 1:numel(errs)
            fprintf('  - %s\n', errs{i});
        end
    end
end

function sz = local_dset_size(info, name)
    idx = find(strcmp({info.Datasets.Name}, name), 1);
    if isempty(idx)
        sz = [];
    else
        sz = info.Datasets(idx).Dataspace.Size;
    end
end
