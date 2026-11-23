function done = ScenarioAlreadyDone(scenario_type, epoch, varargin)
% ScenarioAlreadyDone - Resumability check: has this exact scenario+epoch
% already been generated (and does the file look structurally intact)?
%
% Uses the same path logic as SaveWorkspaceToHDF5 (via GenerateScenarioInfo),
% so it can never disagree with where a scenario actually gets written. The
% pipeline mixes environment and (single-fault) severity within one folder per
% fault/combo, the file path depends only on (scenario_type, epoch, id) — NOT
% on environment or severity — so this check runs BEFORE any per-epoch sampling.
%
% This is what makes epoch counts safely editable: raise N_EPOCHS_* and re-run;
% existing epoch files are detected here and skipped, only new epochs generate.
%
% Usage:
%   ScenarioAlreadyDone('healthy', epoch)
%   ScenarioAlreadyDone('single',  epoch, fault_id)
%   ScenarioAlreadyDone('dual',    epoch, combo_id)
%   ScenarioAlreadyDone('triple',  epoch, combo_id)
%   ScenarioAlreadyDone('quad',    epoch, combo_id)
%
% A file counts as "done" only if it exists AND has a readable /sensors dataset
% with a non-zero row count AND a fault_count attribute — this catches
% partially-written files left by a crash mid-write.
%
% Date: 2026-07-26

    done = false;

    switch lower(scenario_type)
        case 'healthy'
            [~, output_file] = GenerateScenarioInfo('healthy', epoch);
        case 'single'
            fault_id = varargin{1};
            [~, output_file] = GenerateScenarioInfo('single', epoch, fault_id, 0);
        case {'dual', 'triple', 'quad'}
            combo_id = varargin{1};
            % Path does not depend on severities; pass a dummy vector sized to
            % the category so GenerateScenarioInfo can index the combo table.
            switch lower(scenario_type)
                case 'dual',   k = 2;
                case 'triple', k = 3;
                case 'quad',   k = 4;
            end
            [~, output_file] = GenerateScenarioInfo(scenario_type, epoch, combo_id, ones(1, k));
        otherwise
            error('ScenarioAlreadyDone: unknown scenario_type %s', scenario_type);
    end

    if ~exist(output_file, 'file')
        return;
    end

    try
        info = h5info(output_file);
        dsets = {info.Datasets.Name};
        % the writer now splits channels into /sensors (26) + /internal (13),
        % not one flat /sensors (34). Both must be present and the right length, or the file is
        % from a partial/crashed write (or, during transition, a pre-file) and must be
        % regenerated -- never resumed onto a different schema.
        % /true_values (5) joined the schema in the same sitting as --
        % same presence test, same reasoning.
        if ~ismember('sensors', dsets) || ~ismember('internal', dsets) || ~ismember('true_values', dsets)
            return;  % structurally incomplete -- treat as not done
        end
        sensors_dset     = info.Datasets(strcmp(dsets, 'sensors'));
        internal_dset    = info.Datasets(strcmp(dsets, 'internal'));
        true_values_dset = info.Datasets(strcmp(dsets, 'true_values'));
        if sensors_dset.Dataspace.Size(1) ~= ScenarioConfig.STORED_SAMPLES || ...
           internal_dset.Dataspace.Size(1) ~= ScenarioConfig.STORED_SAMPLES || ...
           true_values_dset.Dataspace.Size(1) ~= ScenarioConfig.STORED_SAMPLES
            return;
        end
        h5readatt(output_file, '/', 'fault_count');       % confirms metadata write completed
        h5readatt(output_file, '/', 'operating_regime');  % confirms attribute set is present
        % Read the LAST attribute the writer writes, not a middle one: HDF5 attribute writes are
        % not atomic as a group, so a crash between operating_regime and the provenance block
        % would otherwise leave a file that passes this check but is missing provenance
        %. Keep this in step with SaveSensorsToHDF5.m's final write.
        h5readatt(output_file, '/', 'writer_version');
        done = true;
    catch
        done = false;  % unreadable/corrupt -- regenerate
    end

end
