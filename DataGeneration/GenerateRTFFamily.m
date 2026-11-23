function GenerateRTFFamily(mechanism_fault_ids, unit_range)
% GenerateRTFFamily - the run-to-failure family driver. Loops mechanisms
% x units, calling the real, unmodified RunRTFUnit.m, with per-unit resumability via
% RTFAlreadyDone.m.
%
% Inputs:
%   mechanism_fault_ids - (optional) subset of GetRTFMechanisms.FaultID to generate; default
%                         all 13
%   unit_range          - (optional) [lo hi] unit_id range; default 1:ScenarioConfig.UNITS_PER_MECHANISM
%
% Usage:
%   GenerateRTFFamily                  % all 13 mechanisms, all UNITS_PER_MECHANISM units
%   GenerateRTFFamily([2 3], [1 5])      % F02/F03 only, units 1-5 -- for testing
%
% Resumability: if interrupted, re-running the SAME call skips every unit RTFAlreadyDone.m
% already confirms complete and regenerates only what is missing or structurally incomplete --
% never resumes a partial unit mid-way.
%

    rtf = GetRTFMechanisms();
    if nargin < 1 || isempty(mechanism_fault_ids)
        mechanism_fault_ids = rtf.FaultID;
    end
    if nargin < 2 || isempty(unit_range)
        unit_range = [1, ScenarioConfig.UNITS_PER_MECHANISM];
    end

    n_done = 0; n_generated = 0; n_failed = 0;
    t0 = tic;

    for fi = 1:numel(mechanism_fault_ids)
        fault_id = mechanism_fault_ids(fi);
        mech_idx = find(rtf.FaultID == fault_id, 1);
        if isempty(mech_idx)
            error('GenerateRTFFamily:NotAMechanism', 'fault_id %d is not a run-to-failure mechanism.', fault_id);
        end
        folder_name = rtf.Folder{mech_idx};
        fprintf('\n########## Mechanism F%02d (%s) ##########\n', fault_id, folder_name);

        for unit_id = unit_range(1):unit_range(2)
            [done, output_file] = RTFAlreadyDone(fault_id, unit_id);
            if done
                fprintf('  unit %04d: already done (%s) -- skipping\n', unit_id, output_file);
                n_done = n_done + 1;
                continue;
            end

            fprintf('  unit %04d: generating...\n', unit_id);
            tU = tic;
            try
                ok = RunRTFUnit(fault_id, unit_id);
                if ok
                    fprintf('  unit %04d: done in %.1f s\n', unit_id, toc(tU));
                    n_generated = n_generated + 1;
                else
                    fprintf(2, '  unit %04d: RunRTFUnit returned false\n', unit_id);
                    n_failed = n_failed + 1;
                end
            catch ME
                fprintf(2, '  unit %04d: FAILED -- %s\n', unit_id, ME.message);
                n_failed = n_failed + 1;
            end
        end
    end

    fprintf('\n=== GenerateRTFFamily: %d already done, %d generated, %d failed (%.1f min total) ===\n', ...
        n_done, n_generated, n_failed, toc(t0)/60);
end
