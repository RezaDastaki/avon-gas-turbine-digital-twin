% GenerateTripleFaultDataset.m
% Batch generation of the triple-fault dataset.
%
% One folder per combo (TripleFault/F##F##F##/), N_EPOCHS_TRIPLE
% epochs. Every epoch MC-samples environment + noise + bias + per-fault onsets
% and an INDEPENDENT per-fault severity vector (randi 1-5 each). Triple faults
% have 5^3 = 125 severity combinations, so raise N_EPOCHS_TRIPLE for coverage.
% Filename (flat): <root>/F##F##F##/F##F##F##_E####.h5
%
% Resumable: existing epoch files are skipped.
%
% Date: 2026-07-26

clc;
fprintf('\n=== TRIPLE-FAULT DATASET GENERATION ===\n\n');

config = ScenarioConfig.GetActiveConfig();
if ~config.generate_triple
    fprintf('Triple-fault generation DISABLED (ScenarioConfig.GENERATE_TRIPLE_FAULT = false).\n');
    return;
end

combo_ids   = config.triple_fault_combos;
epochs      = config.epochs_triple;
retry_max   = config.sim_retry_max;
total_files = numel(combo_ids) * numel(epochs);

fprintf('Combos: %d  |  Epochs/combo: %d  |  Total: %d  |  Output: %s\n', ...
    numel(combo_ids), numel(epochs), total_files, config.output_root);

start_time      = tic;
files_completed = 0;
files_failed    = 0;
failed_scenarios = {};

for combo_id = combo_ids
    for epoch = epochs
        idx = files_completed + files_failed + 1;
        fprintf('\n--- TripleCombo %d epoch %d (%d/%d) ---\n', combo_id, epoch, idx, total_files);

        if ScenarioAlreadyDone('triple', epoch, combo_id)
            files_completed = files_completed + 1;
            fprintf('  already exists -- skipped\n');
            continue;
        end

        done = false;
        for attempt = 1:retry_max
            success = RunScenario('triple', epoch, attempt, combo_id);
            if success, done = true; break; end
            fprintf('  combo %d epoch %d failed on attempt %d -- resampling milder conditions...\n', ...
                combo_id, epoch, attempt);
        end

        if done
            files_completed = files_completed + 1;
        else
            files_failed = files_failed + 1;
            failed_scenarios{end+1} = sprintf('DIAG_TripleCombo%02d_E%04d', combo_id, epoch); %#ok<AGROW>
            fprintf('  *** combo %d epoch %d FAILED after %d attempts (leaves a gap) ***\n', ...
                combo_id, epoch, retry_max);
        end

        if config.show_time_estimates && files_completed > 0 && mod(idx, config.detailed_progress_interval) == 0
            elapsed = toc(start_time);
            avg = elapsed / (files_completed + files_failed);
            eta = avg * (total_files - idx);
            fprintf('  elapsed %.1f h | avg %.1f min/file | ETA %.1f h\n', elapsed/3600, avg/60, eta/3600);
        end
    end
end

fprintf('\n=== TRIPLE-FAULT COMPLETE: %d ok, %d failed (%.1f%%) in %.1f h ===\n', ...
    files_completed, files_failed, 100*files_completed/max(1,total_files), toc(start_time)/3600);
fprintf('Next: >> GenerateQuadFaultDataset\n\n');
