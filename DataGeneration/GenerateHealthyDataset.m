% GenerateHealthyDataset.m
% Batch generation of the healthy (baseline) dataset.
%
% One folder (Healthy/), N_EPOCHS_HEALTHY epochs. Every epoch MC-samples its
% own environment + noise + bias (no faults), so the healthy class is a
% realistic cloud rather than near-duplicate trajectories.
% Filename: <root>/DIAG_Healthy/DIAG_Healthy_E####.h5
%
% Resumable: existing epoch files are skipped. Raise N_EPOCHS_HEALTHY and re-run
% to add more epochs without touching existing ones.
%
% Date: 2026-07-26

clc;
fprintf('\n=== HEALTHY DATASET GENERATION ===\n\n');

config = ScenarioConfig.GetActiveConfig();
if ~config.generate_healthy
    fprintf('Healthy generation DISABLED (ScenarioConfig.GENERATE_HEALTHY = false).\n');
    return;
end

epochs      = config.epochs_healthy;
retry_max   = config.sim_retry_max;
total_files = numel(epochs);

fprintf('Epochs: %d  |  Output: %s  |  Retry max: %d\n', total_files, config.output_root, retry_max);

start_time      = tic;
files_completed = 0;
files_failed    = 0;
failed_scenarios = {};

for epoch = epochs
    idx = files_completed + files_failed + 1;
    fprintf('\n--- Healthy epoch %d/%d ---\n', epoch, total_files);

    if ScenarioAlreadyDone('healthy', epoch)
        files_completed = files_completed + 1;
        fprintf('  already exists -- skipped\n');
        continue;
    end

    done = false;
    for attempt = 1:retry_max
        success = RunScenario('healthy', epoch, attempt);
        if success, done = true; break; end
        fprintf('  epoch %d failed on attempt %d -- resampling milder environment...\n', epoch, attempt);
    end

    if done
        files_completed = files_completed + 1;
        fprintf('  OK (%d/%d)\n', idx, total_files);
    else
        files_failed = files_failed + 1;
        failed_scenarios{end+1} = sprintf('DIAG_Healthy_E%04d', epoch); %#ok<AGROW>
        fprintf('  *** epoch %d FAILED after %d attempts (leaves a gap) ***\n', epoch, retry_max);
    end

    if config.show_time_estimates && files_completed > 0 && mod(idx, config.detailed_progress_interval) == 0
        elapsed = toc(start_time);
        avg = elapsed / (files_completed + files_failed);
        eta = avg * (total_files - idx);
        fprintf('  elapsed %.1f h | avg %.1f min/file | ETA %.1f h\n', elapsed/3600, avg/60, eta/3600);
    end
end

fprintf('\n=== HEALTHY COMPLETE: %d ok, %d failed (%.1f%%) in %.1f h ===\n', ...
    files_completed, files_failed, 100*files_completed/max(1,total_files), toc(start_time)/3600);
if files_failed > 0
    fprintf('Failed (should be ~0 given retry): %s\n', strjoin(failed_scenarios, ', '));
end
fprintf('Next: >> GenerateSingleFaultDataset\n\n');
