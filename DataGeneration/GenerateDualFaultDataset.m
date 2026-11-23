% GenerateDualFaultDataset.m
% Batch generation of the dual-fault dataset.
%
% One folder per combo (DualFault/F##F##/), N_EPOCHS_DUAL epochs.
% Every epoch MC-samples its own environment + noise + bias + per-fault onsets,
% and an INDEPENDENT per-fault severity vector (randi 1-5 each). Raise
% N_EPOCHS_DUAL to better cover the 5^2 = 25 severity-combination space.
% Filename (flat): <root>/F##F##/F##F##_E####.h5
%
% Resumable: existing epoch files are skipped.
%
% Date: 2026-07-26

clc;
fprintf('\n=== DUAL-FAULT DATASET GENERATION ===\n\n');

config = ScenarioConfig.GetActiveConfig();
if ~config.generate_dual
    fprintf('Dual-fault generation DISABLED (ScenarioConfig.GENERATE_DUAL_FAULT = false).\n');
    return;
end

combo_ids   = config.dual_fault_combos;
epochs      = config.epochs_dual;
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
        fprintf('\n--- DualCombo %d epoch %d (%d/%d) ---\n', combo_id, epoch, idx, total_files);

        if ScenarioAlreadyDone('dual', epoch, combo_id)
            files_completed = files_completed + 1;
            fprintf('  already exists -- skipped\n');
            continue;
        end

        done = false;
        for attempt = 1:retry_max
            success = RunScenario('dual', epoch, attempt, combo_id);
            if success, done = true; break; end
            fprintf('  combo %d epoch %d failed on attempt %d -- resampling milder conditions...\n', ...
                combo_id, epoch, attempt);
        end

        if done
            files_completed = files_completed + 1;
        else
            files_failed = files_failed + 1;
            failed_scenarios{end+1} = sprintf('DIAG_DualCombo%02d_E%04d', combo_id, epoch); %#ok<AGROW>
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

fprintf('\n=== DUAL-FAULT COMPLETE: %d ok, %d failed (%.1f%%) in %.1f h ===\n', ...
    files_completed, files_failed, 100*files_completed/max(1,total_files), toc(start_time)/3600);
fprintf('Next: >> GenerateTripleFaultDataset\n\n');
