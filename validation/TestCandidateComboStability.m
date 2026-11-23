function TestCandidateComboStability()
% TestCandidateComboStability - Worst-case stability test for the 8
% candidate multi-fault combos added 2026-07-19 to replace the F02+F21 /
% F04+F16 pairings that hit a 62-71% completion ceiling under the original
% combo definitions.
%
% Method: run each candidate combo at maximum severity (SEV5 on every
% active fault) in all 5 environments, epoch 1. If max severity in the
% harshest environments survives, the combo is very likely stable across
% the full MC severity distribution used in production (same logic as the
% bisection testing already used for F02/F05/F14/F15/F16/F21). A real,
% valid HDF5 file is produced by each passing run, so passes also count
% as real epoch-1 production progress once the combo is promoted to the
% active list.
%
% IMPORTANT: this must be a FUNCTION, not a script. RunScenario ->
% LoadScenarioToWorkspace calls `evalin('base', 'clearvars -except ...')`
% on every invocation, which wipes any base-workspace variable not on its
% whitelist (documented gotcha, see GENERATION_PROGRESS.md). A function's
% local workspace is untouched by evalin('base', ...), so loop state
% (n_pass, n_fail, results_log) survives here. Results are also written
% to disk after every single run (not just at the end) as a safety net.
%
% Date: 2026-07-19

clc;
fprintf('\n');
fprintf('================================================================\n');
fprintf('   CANDIDATE COMBO STABILITY TEST (worst-case SEV5, all 5 envs)\n');
fprintf('================================================================\n\n');

candidates = struct( ...
    'type',     {'dual',   'triple', 'triple', 'triple', 'triple', 'quad',   'quad',   'quad'}, ...
    'combo_id', {19,       23,       24,       25,       26,       16,       17,       18}, ...
    'n_faults', {2,        3,        3,        3,        3,        4,        4,        4}, ...
    'label',    {'F02+F24 (repl. F02+F21)', 'F01+F02+F24 (repl. F01+F02+F21)', ...
                 'F02+F17+F24 (repl. F02+F17+F21)', 'F02+F24+F26 (repl. F02+F21+F26)', ...
                 'F04+F18+F38 (repl. F04+F16+F38)', 'F01+F02+F24+F26 (repl. F01+F02+F21+F26)', ...
                 'F02+F24+F26+F29 (repl. F02+F21+F26+F29)', 'F04+F18+F33+F38 (repl. F04+F16+F33+F38)'});

environments = 1:5;
epoch = 1;

results_file = 'CandidateComboStability_results.txt';
fid = fopen(results_file, 'w');
fprintf(fid, 'Candidate combo stability test -- started %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fclose(fid);

n_pass = 0;
n_fail = 0;
start_time = tic;

for c = 1:length(candidates)
    cand = candidates(c);
    severities = 5 * ones(1, cand.n_faults);

    for env_id = environments
        fprintf('\n----------------------------------------------------------------\n');
        fprintf('Testing: %s | %s combo %d | ENV%03d | SEV%s\n', ...
            cand.label, upper(cand.type), cand.combo_id, env_id, mat2str(severities));
        fprintf('----------------------------------------------------------------\n');

        try
            success = RunScenario(cand.type, epoch, env_id, cand.combo_id, severities);
        catch ME
            success = false;
            fprintf('EXCEPTION: %s\n', ME.message);
        end

        if success
            n_pass = n_pass + 1;
            status = 'PASS';
        else
            n_fail = n_fail + 1;
            status = 'FAIL';
        end

        line = sprintf('%-45s | %-6s | ENV%03d | %s', cand.label, upper(cand.type), env_id, status);

        % Write immediately -- do not rely on in-memory accumulation surviving
        % to the end of the loop.
        fid = fopen(results_file, 'a');
        fprintf(fid, '%s\n', line);
        fclose(fid);

        fprintf('RESULT: %s\n', line);
    end
end

elapsed = toc(start_time);

fid = fopen(results_file, 'a');
fprintf(fid, '\nTotal: %d passed, %d failed (%d runs, %.1f minutes)\n', ...
    n_pass, n_fail, n_pass + n_fail, elapsed/60);
fclose(fid);

fprintf('\n\n================================================================\n');
fprintf('   STABILITY TEST SUMMARY: %d passed, %d failed (%.1f minutes)\n', ...
    n_pass, n_fail, elapsed/60);
fprintf('================================================================\n\n');
fprintf('Results written to %s\n', results_file);

end
