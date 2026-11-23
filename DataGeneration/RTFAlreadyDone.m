function [done, output_file, status] = RTFAlreadyDone(fault_id, unit_id)
% RTFAlreadyDone - Per-unit resumability check for the run-to-failure family
%: a unit resumes per UNIT,
% never mid-unit, because rul_cycles/health_index are defined against the unit's own
% termination cycle and a half-written unit would desynchronise them silently.
%
% Modelled directly on ScenarioAlreadyDone.m's pattern (same style of structural checks, same
% "read the LAST attribute the writer writes" discipline), extended to per-unit rules:
% a unit counts as done only if its file exists, carries /sensors, /internal, /true_values and
% every per-cycle label dataset, every per-cycle dataset has exactly cycles_to_failure rows,
% /cycle_index's maximum equals cycles_to_failure, /sensors has exactly
% 300*cycles_to_failure rows, and the last attribute the writer writes is readable.
%
% Wired to the real writer as, 2026-10-19 (RunRTFUnit.m / SaveRTFUnitToHDF5.m).
% FIXED, same date: the original required_percycle_dsets loop checked `cycle_index`'s row count
% against `cycles_to_failure`, but /cycle_index is SAMPLE-level ([300*C x 1]), not
% per-cycle ([C x 1]) -- the two checks contradicted each other for any C>0 and would have
% rejected every correctly-written file. Found by running this function against a real unit
% (P4_41_test_rtf_unit.m). /cycle_index is checked separately, by its own correct rule, below.
%
% P6R: a structurally valid unit that was ABORTED AT THE CYCLE CAP below the cap now
% in force (failure_mode 'aborted_hard_cap' and cycles_to_failure < ScenarioConfig.RTFCapCycles)
% is NOT done -- it is a right-censored unit that RunRTFUnit.m continues to genuine failure. The
% two units that terminated naturally at exactly the old cap (failure_mode 'temperature_limit')
% stay done. A unit aborted on the health ceiling carries the different failure_mode
% 'aborted_health_cap' and stays done, so a unit that can never fail is not re-queued forever.
%
% Usage:
%   [done, path, status] = RTFAlreadyDone(fault_id, unit_id)
% status is one of 'missing' (no file), 'invalid' (unreadable or incomplete -- regenerate from
% scratch), 'capped_pending' (valid but censored at the cap -- continue it) or 'complete'.
% `done` is true only for 'complete'.
%

    done = false;
    status = 'missing';

    % RTFUnitPath is the single builder of the unit file name, shared with RunRTFUnit.m.
    output_file = RTFUnitPath(fault_id, unit_id);

    if ~exist(output_file, 'file')
        return;
    end

    status = 'invalid';
    try
        info = h5info(output_file);
        dsets = {info.Datasets.Name};

        required_channel_dsets = {'sensors', 'internal', 'true_values'};
        required_persample_dsets = {'cycle_index'};
        required_percycle_dsets = {'rul_cycles', 'rul_seconds', 'health_index', 'delta', ...
                                    'severity_factor', 'duty_achieved_MW', 'limiter_active_fraction', ...
                                    'operating_regime_code', 'ambient'};
        required_all = [required_channel_dsets, required_persample_dsets, required_percycle_dsets];
        if ~all(ismember(required_all, dsets))
            return;  % structurally incomplete -- treat as not done
        end

        cycles_to_failure = h5readatt(output_file, '/', 'cycles_to_failure');
        expected_samples = ScenarioConfig.RTF_CYCLE_SECONDS * double(cycles_to_failure);

        sensors_dset = info.Datasets(strcmp(dsets, 'sensors'));
        if sensors_dset.Dataspace.Size(1) ~= expected_samples
            return;
        end

        % /cycle_index is SAMPLE-level, [300*C x 1] -- same row count as /sensors, not cycles_to_failure.
        cindex_dset = info.Datasets(strcmp(dsets, 'cycle_index'));
        if cindex_dset.Dataspace.Size(1) ~= expected_samples
            return;
        end

        for k = 1:numel(required_percycle_dsets)
            d = info.Datasets(strcmp(dsets, required_percycle_dsets{k}));
            if d.Dataspace.Size(1) ~= double(cycles_to_failure)
                return;
            end
        end

        cycle_index = h5read(output_file, '/cycle_index');
        if max(cycle_index) ~= double(cycles_to_failure)
            return;
        end

        % Confirms metadata write completed; read the LAST attribute the writer writes (the
        % root-attribute list ends with unit_id, master_seed, scenario_hash, warm_start_route,
        % writer_version), not a middle one -- HDF5 attribute writes are not atomic as a group.
        h5readatt(output_file, '/', 'writer_version');

        failure_mode = char(h5readatt(output_file, '/', 'failure_mode'));
        if strcmp(failure_mode, 'aborted_hard_cap') && double(cycles_to_failure) < ScenarioConfig.RTFCapCycles()
            status = 'capped_pending';
            return;
        end

        done = true;
        status = 'complete';
    catch
        done = false;  % unreadable/corrupt -- regenerate the whole unit
        status = 'invalid';
    end

end
