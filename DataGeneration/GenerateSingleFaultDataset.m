% GenerateSingleFaultDataset.m
% Batch generation of the single-fault dataset.
%
% One folder per fault (SingleFault/F##/), N_EPOCHS_SINGLE epochs.
% Every epoch MC-samples its own environment + noise + bias + onset; severity
% is stratified 1-5 (each block of 5 epochs covers all severities once).
% Filename: <root>/SingleFault/F##/F##_E####.h5
%
% Resumable: existing epoch files are skipped. Raise N_EPOCHS_SINGLE and re-run
% to add more epochs without touching existing ones.
%
% Date: 2026-07-26

clc;
fprintf('\n=== SINGLE-FAULT DATASET GENERATION ===\n\n');

config = ScenarioConfig.GetActiveConfig();
if ~config.generate_single
    fprintf('Single-fault generation DISABLED (ScenarioConfig.GENERATE_SINGLE_FAULT = false).\n');
    return;
end

fault_ids   = config.single_fault_ids;
epochs      = config.epochs_single;
retry_max   = config.sim_retry_max;
total_files = numel(fault_ids) * numel(epochs);

fprintf('Faults: %d  |  Epochs/fault: %d  |  Total: %d  |  Output: %s\n', ...
    numel(fault_ids), numel(epochs), total_files, config.output_root);

start_time      = tic;
files_completed = 0;
files_failed    = 0;
failed_scenarios = {};

for fault_id = fault_ids
    for epoch = epochs
        idx = files_completed + files_failed + 1;
        fprintf('\n--- F%02d epoch %d (%d/%d) ---\n', fault_id, epoch, idx, total_files);

        if ScenarioAlreadyDone('single', epoch, fault_id)
            files_completed = files_completed + 1;
            fprintf('  already exists -- skipped\n');
            continue;
        end

        done = false;
        for attempt = 1:retry_max
            success = RunScenario('single', epoch, attempt, fault_id);
            if success, done = true; break; end
            fprintf('  F%02d epoch %d failed on attempt %d -- resampling milder environment...\n', ...
                fault_id, epoch, attempt);
        end

        if done
            files_completed = files_completed + 1;
        else
            files_failed = files_failed + 1;
            failed_scenarios{end+1} = sprintf('DIAG_F%02d_E%04d', fault_id, epoch); %#ok<AGROW>
            fprintf('  *** F%02d epoch %d FAILED after %d attempts (leaves a gap) ***\n', ...
                fault_id, epoch, retry_max);
        end

        if config.show_time_estimates && files_completed > 0 && mod(idx, config.detailed_progress_interval) == 0
            elapsed = toc(start_time);
            avg = elapsed / (files_completed + files_failed);
            eta = avg * (total_files - idx);
            fprintf('  elapsed %.1f h | avg %.1f min/file | ETA %.1f h (%.1f d)\n', ...
                elapsed/3600, avg/60, eta/3600, eta/86400);
        end
    end
end

fprintf('\n=== SINGLE-FAULT COMPLETE: %d ok, %d failed (%.1f%%) in %.1f h ===\n', ...
    files_completed, files_failed, 100*files_completed/max(1,total_files), toc(start_time)/3600);
if files_failed > 0
    n = min(20, numel(failed_scenarios));
    tail = '';
    if numel(failed_scenarios) > n, tail = ' ...'; end
    fprintf('Failed (%d): %s%s\n', numel(failed_scenarios), strjoin(failed_scenarios(1:n), ', '), tail);
end
fprintf('Next: >> GenerateDualFaultDataset\n\n');
