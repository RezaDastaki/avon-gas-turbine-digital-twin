function AvonProgress()
% AvonProgress - Read-only progress across all three families.
%
% Reports, for Diagnosis, RunToFailure and DiagnosisTurndown (if present): per-category
% counts against target, GB on disk, overall percentage, and an ETA computed from the
% dispatch manifests' own timestamps -- NOT from DatasetAuditReport's stale formula
% (that function prints "0.0% complete" and must not be
% used). Safe to run during generation (read-only, never writes).
%
% The ETA source is <repo>/Logs/diag_parallel_manifest.csv / rtf_parallel_manifest.csv,
% written by the parallel drivers -- not yet built as of this work
% package. Until a manifest exists, this prints file-system timestamp-based
% progress (the same method DatasetProgress.m already used) instead of failing.
%
% P6R: the run-to-failure table also reports, per mechanism, how many units have
% FAILED (run to genuine end of life) and how many are CAPPED (right-censored at the old cycle cap
% and still waiting to be continued), so progress of the continuation is visible.
%

    fprintf('\n======================================================================\n');
    fprintf('  AvonProgress -- Diagnosis / RunToFailure / DiagnosisTurndown\n');
    fprintf('======================================================================\n\n');

    data_root = AvonDataRoot();
    fprintf('Data root: %s\n\n', data_root);

    %% report THIS MACHINE'S SHARD against its own target, and the
    % shard's share of the whole release, so 100% on one machine is never mistaken for 100%
    % overall.
    [shard, n_shards] = AvonShard();
    assignment = AvonScenarioAssignment(shard, n_shards);
    diag_pct_of_release = 100 * assignment.diag_records_owned / max(assignment.diag_records_total, 1);
    rtf_pct_of_release  = 100 * assignment.rtf_units_owned / max(assignment.rtf_units_total, 1);
    fprintf('Shard: %d of %d\n', shard, n_shards);
    fprintf('  Diagnosis: owns %d/%d scenarios, %d/%d records (%.1f%% of the diagnosis family)\n', ...
        numel(assignment.diag_owned), numel(assignment.diag_items), ...
        assignment.diag_records_owned, assignment.diag_records_total, diag_pct_of_release);
    fprintf('  RunToFailure: owns %d/%d mechanisms, %d/%d units (%.1f%% of the run-to-failure family)\n\n', ...
        numel(assignment.rtf_owned), numel(assignment.rtf_items), ...
        assignment.rtf_units_owned, assignment.rtf_units_total, rtf_pct_of_release);
    if n_shards > 1
        fprintf('  (figures below are THIS SHARD''s target, not the whole release -- 100%% here means\n');
        fprintf('   this shard is done, not that the release is done.)\n\n');
    end

    % the main two families are sharded by whole scenario folder, so
    % restrict their "Expected" and "Actual" to THIS shard's own owned folders. The turndown
    % family is not scope -- no sharding interface was specified for
    % GenerateTurndownParallel -- so it is reported against the WHOLE 89-scenario target,
    % unfiltered, same as before.
    diag_owned_folders = {assignment.diag_owned.folder};
    rtf_owned_folders  = {assignment.rtf_owned.folder};

    total_gb = 0;
    total_gb = total_gb + report_diagnosis(data_root, 'Diagnosis', ...
        'diag_parallel_manifest.csv', data_root, diag_owned_folders);
    total_gb = total_gb + report_rtf(data_root, data_root, rtf_owned_folders);
    total_gb = total_gb + report_diagnosis(fullfile(data_root, 'DiagnosisTurndown'), ...
        'DiagnosisTurndown', 'turndown_parallel_manifest.csv', data_root, []);

    fprintf('----------------------------------------------------------------------\n');
    fprintf('Total on disk (all families): %.2f GB\n', total_gb);
    fprintf('----------------------------------------------------------------------\n\n');
end

%% ---- Diagnosis-shaped family (DIAG_* folders in the data root; DiagnosisTurndown/TD_*) ----
function gb = report_diagnosis(base_dir, label, manifest_name, data_root, owned_folders)
% owned_folders: [] -> no shard filter (report the whole family, as before -- used for
% DiagnosisTurndown, which does not shard). A cellstr -> only folders in that list count
% toward "Expected" and "Actual" (this shard's own target).
    fprintf('--- %s ---\n', label);
    if ~isfolder(base_dir)
        fprintf('  (folder not found -- nothing generated yet)\n\n');
        gb = 0;
        return;
    end
    sharded = ~isempty(owned_folders);

    cfg = ScenarioConfig.GetActiveConfig();
    if strcmp(label, 'DiagnosisTurndown')
        % The turndown family pins ONE epoch count for every scenario (89 x 200 =
        % 17,800), independent of the main family's per-category production counts that
        % GetActiveConfig returns -- so override them here, from the shared constant.
        n_td = ScenarioConfig.TURNDOWN_EPOCHS_PER_SCENARIO;
        cfg.n_epochs_healthy = n_td; cfg.n_epochs_single = n_td; cfg.n_epochs_dual = n_td;
        cfg.n_epochs_triple  = n_td; cfg.n_epochs_quad   = n_td;
    end
    if sharded
        own = @(name) any(strcmp(name, owned_folders));
    else
        own = @(name) true;
    end
    % Naming scheme 2026-11-21: folders are DIAG_Healthy, DIAG_Fxx_<code>, DIAG_DualFault_<combo> ...
    % (TD_ prefix in DiagnosisTurndown). Single-fault folder names carry the catalogue code.
    if strcmp(label, 'DiagnosisTurndown'), pfx = 'TD_'; else, pfx = 'DIAG_'; end
    fdefs = GetFaultDefinitions();
    healthy_dir = [pfx 'Healthy'];
    exp_healthy = cfg.n_epochs_healthy * own(healthy_dir);
    exp_single  = numel(cfg.single_fault_ids(arrayfun(@(f) own(sprintf('%sF%02d_%s', pfx, f, fdefs.Codes{f})), cfg.single_fault_ids))) * cfg.n_epochs_single;
    % Dual/triple/quad folder names depend on which fault_ids a combo_id maps to, which this
    % file does not re-derive -- count them from owned_folders directly by group-size instead.
    n_owned_multi = struct('dual', 0, 'triple', 0, 'quad', 0);
    if sharded
        for i = 1:numel(owned_folders)
            name = owned_folders{i};
            groups = scenario_group_count(name);   % 2/3/4 for multi-fault folders, else 0/1
            switch groups
                case 2, n_owned_multi.dual   = n_owned_multi.dual + 1;
                case 3, n_owned_multi.triple = n_owned_multi.triple + 1;
                case 4, n_owned_multi.quad   = n_owned_multi.quad + 1;
            end
        end
        exp_dual   = n_owned_multi.dual   * cfg.n_epochs_dual;
        exp_triple = n_owned_multi.triple * cfg.n_epochs_triple;
        exp_quad   = n_owned_multi.quad   * cfg.n_epochs_quad;
    else
        exp_dual    = numel(cfg.dual_fault_combos)   * cfg.n_epochs_dual;
        exp_triple  = numel(cfg.triple_fault_combos) * cfg.n_epochs_triple;
        exp_quad    = numel(cfg.quad_fault_combos)   * cfg.n_epochs_quad;
    end
    exp_total   = exp_healthy + exp_single + exp_dual + exp_triple + exp_quad;

    act_healthy = own(healthy_dir) * count_h5(fullfile(base_dir, healthy_dir));
    act_single = 0; act_dual = 0; act_triple = 0; act_quad = 0;
    % Release layout: scenario folders are listed by list_scenario_dirs (descends the
    % DIAG_Dual/Triple/QuadFault group folders in the main family; turndown is flat).
    sdirs = list_scenario_dirs(base_dir, pfx);
    gb_sum = count_gb(fullfile(base_dir, healthy_dir));
    for i = 1:numel(sdirs)
        name = sdirs(i).name;
        groups = scenario_group_count(name);   % number of faults in the folder; 0 = not a fault scenario folder
        if groups == 0, continue; end
        if ~own(name), continue; end  % skip folders not owned by this shard
        n = count_h5(sdirs(i).path);
        gb_sum = gb_sum + count_gb(sdirs(i).path);
        switch groups
            case 1, act_single = act_single + n;
            case 2, act_dual   = act_dual   + n;
            case 3, act_triple = act_triple + n;
            case 4, act_quad   = act_quad   + n;
        end
    end
    act_total = act_healthy + act_single + act_triple + act_dual + act_quad;

    fprintf('  %-10s %10s %10s\n', 'Category', 'Expected', 'Actual');
    fprintf('  %-10s %10d %10d\n', 'Healthy', exp_healthy, act_healthy);
    fprintf('  %-10s %10d %10d\n', 'Single',  exp_single,  act_single);
    fprintf('  %-10s %10d %10d\n', 'Dual',    exp_dual,    act_dual);
    fprintf('  %-10s %10d %10d\n', 'Triple',  exp_triple,  act_triple);
    fprintf('  %-10s %10d %10d\n', 'Quad',    exp_quad,    act_quad);
    if exp_total > 0
        fprintf('  TOTAL: %d / %d (%.2f%%)\n', act_total, exp_total, 100*act_total/exp_total);
    else
        fprintf('  TOTAL: %d / %d\n', act_total, exp_total);
    end

    gb = gb_sum;
    fprintf('  Size on disk: %.2f GB%s\n', gb, local_unfiltered_note(sharded));

    report_eta(manifest_name, base_dir, act_total, exp_total);
    fprintf('\n');
end

%% ---- scenario folder lister (release layout) ----
function sd = list_scenario_dirs(base_dir, pfx)
% Struct array (name, path) of every scenario folder of the family. In the main family the
% multi-fault folders live one level down, inside <pfx>DualFault/, <pfx>TripleFault/, <pfx>QuadFault/.
    sd = struct('name', {}, 'path', {});
    d = dir(base_dir);
    d = d([d.isdir]);
    for i = 1:numel(d)
        nm = d(i).name;
        if strncmp(nm, '.', 1) || ~strncmp(nm, pfx, numel(pfx)), continue; end
        if ~isempty(regexp(nm, ['^' pfx '(Dual|Triple|Quad)Fault$'], 'once'))
            c = dir(fullfile(base_dir, nm));
            c = c([c.isdir]);
            for j = 1:numel(c)
                if strncmp(c(j).name, '.', 1), continue; end
                sd(end+1) = struct('name', c(j).name, 'path', fullfile(base_dir, nm, c(j).name)); %#ok<AGROW>
            end
        else
            sd(end+1) = struct('name', nm, 'path', fullfile(base_dir, nm)); %#ok<AGROW>
        end
    end
end

%% ---- folder-name parser (naming scheme 2026-11-21) ----
function n = scenario_group_count(name)
% Number of faults in a diagnosis-shaped scenario folder name, by grammar (never by name length):
%   DIAG_Fxx_<code> / TD_Fxx_<code>                       -> 1
%   DIAG_DualFault_<F..F..> / TripleFault_.. / QuadFault_..   -> 2 / 3 / 4
% DIAG_Healthy / TD_Healthy and anything else -> 0 (Healthy is counted separately).
    n = 0;
    if ~isempty(regexp(name, '^(DIAG|TD)_F\d{2}_[A-Za-z]\w*$', 'once'))
        n = 1;
        return;
    end
    tok = regexp(name, '^(?:DIAG|TD)_(?:Dual|Triple|Quad)Fault_((?:F\d{2}){2,4})$', 'tokens', 'once');
    if ~isempty(tok)
        n = numel(tok{1}) / 3;
    end
end

%% ---- RunToFailure family ----
function gb = report_rtf(base_dir, data_root, owned_folders)
% owned_folders: cellstr of mechanism folders owned by this shard -- only
% these contribute to "Expected"/"Actual".
    fprintf('--- RunToFailure ---\n');
    if ~isfolder(base_dir)
        fprintf('  (folder not found -- nothing generated yet)\n\n');
        gb = 0;
        return;
    end

    rtf = GetRTFMechanisms();
    exp_per_mech = ScenarioConfig.UNITS_PER_MECHANISM;
    act_total = 0;
    exp_total = 0;
    failed_total = 0; capped_total = 0; other_total = 0; rtf_gb = 0;

    % P6R: every unit is classified from two root attributes of its own file (one cheap read each,
    % about a minute for the whole family). A unit that ended on its own (the EOL check tripped) is
    % FAILED, i.e. finished; one stored as aborted at the cycle cap below the cap now in force is
    % CAPPED -- right-censored, still to be continued by GenerateRTFParallel (RTFAlreadyDone.m's
    % 'capped_pending'). Anything else (aborted on the health ceiling, unreadable) is OTHER.
    fprintf('  %-32s %10s %10s %10s %10s\n', 'Mechanism', 'Expected', 'Actual', 'Failed', 'Capped');
    for i = 1:rtf.Count
        if ~any(strcmp(rtf.Folder{i}, owned_folders))
            continue;  % not this shard's mechanism -- excluded from this shard's target
        end
        mech_dir = fullfile(base_dir, rtf.Folder{i});
        rtf_gb = rtf_gb + count_gb(mech_dir);
        files = dir(fullfile(mech_dir, 'RTF_F*_U*.h5'));
        n = numel(files);
        n_failed = 0; n_capped = 0;
        for k = 1:n
            f = fullfile(files(k).folder, files(k).name);
            try
                fm = char(h5readatt(f, '/', 'failure_mode'));
                ctf = double(h5readatt(f, '/', 'cycles_to_failure'));
                if ~strncmp(fm, 'aborted', 7)
                    n_failed = n_failed + 1;
                elseif strcmp(fm, 'aborted_hard_cap') && ctf < ScenarioConfig.RTFCapCycles()
                    n_capped = n_capped + 1;
                end
            catch
                % unreadable: counted in Actual only, so Actual - Failed - Capped shows it
            end
        end
        act_total = act_total + n;
        exp_total = exp_total + exp_per_mech;
        failed_total = failed_total + n_failed;
        capped_total = capped_total + n_capped;
        other_total = other_total + (n - n_failed - n_capped);
        fprintf('  %-32s %10d %10d %10d %10d\n', rtf.Folder{i}, exp_per_mech, n, n_failed, n_capped);
    end
    if exp_total > 0
        fprintf('  TOTAL: %d / %d (%.2f%%)\n', act_total, exp_total, 100*act_total/exp_total);
    else
        fprintf('  TOTAL: %d / %d\n', act_total, exp_total);
    end
    fprintf('  Run to failure: %d | capped, pending continuation: %d | other (stopped at the cap now in force or at the health ceiling, or unreadable): %d | not yet generated: %d\n', ...
        failed_total, capped_total, other_total, max(0, exp_total - act_total));

    gb = rtf_gb;
    fprintf('  Size on disk: %.2f GB (all RTF_ folders -- not shard-filtered; other shards'' mechanisms should not be on this disk)\n', gb);

    if capped_total > 0
        % The manifest's mean seconds-per-unit describes whole units; a continuation's cost depends
        % on how far from failure the stored unit is, so that ETA would mislead. GenerateRTFParallel
        % prints its own work-weighted ETA while it runs (and mirrors it to rtf_extend_progress.log).
        fprintf('  Status: %d capped unit(s) still to continue -- run GenerateRTFParallel (progress and ETA are printed as it runs).\n', capped_total);
    else
        report_eta('rtf_parallel_manifest.csv', base_dir, act_total, exp_total);
    end
    fprintf('\n');
end

%% ---- small helper for the diagnosis-family size note ----
function note = local_unfiltered_note(sharded)
    if sharded
        note = ' (whole folder -- not shard-filtered; other shards'' scenarios should not be on this disk)';
    else
        note = '';
    end
end

%% ---- ETA, from the dispatch manifest's own timestamps when one exists ----
function report_eta(manifest_name, base_dir, act_total, exp_total)
    manifest_path = fullfile(AvonLogDir(), manifest_name);
    remaining = max(0, exp_total - act_total);
    if remaining <= 0
        fprintf('  Status: COMPLETE.\n');
        return;
    end

    if isfile(manifest_path)
        try
            T = readtable(manifest_path);
            if ismember('seconds', T.Properties.VariableNames) && height(T) > 0
                mean_s = mean(T.seconds);
                workers = AvonWorkers();
                eta_h = (mean_s * remaining) / max(1, workers) / 3600;
                fprintf('  ETA (from %s, mean %.1f s/record, %d workers): %.1f h (%.1f d)\n', ...
                    manifest_name, mean_s, workers, eta_h, eta_h/24);
                return;
            end
        catch
            % fall through to the file-timestamp fallback
        end
    end

    % Fallback: file-modification-time spread across the folder, same method
    % DatasetProgress.m used, since no manifest exists yet (not built / not yet run).
    files = dir(fullfile(base_dir, '**', '*.h5'));
    if numel(files) > 1
        [~, idx] = sort([files.datenum]);
        files = files(idx);
        hours_elapsed = (files(end).datenum - files(1).datenum) * 24;
        if act_total > 1 && hours_elapsed > 0
            per_file = hours_elapsed / (act_total - 1);
            eta_h = per_file * remaining;
            fprintf('  ETA (file-timestamp fallback, no manifest found): %.1f h (%.1f d)\n', eta_h, eta_h/24);
        else
            fprintf('  ETA: not enough elapsed time yet to estimate.\n');
        end
    else
        fprintf('  ETA: not enough files yet to estimate (no manifest, <2 files).\n');
    end
end

%% ---- helpers ----
function n = count_h5(folder_path)
    if ~isfolder(folder_path), n = 0; return; end
    files = dir(fullfile(folder_path, '**', '*.h5'));
    n = numel(files);
end

function gb = count_gb(folder_path)
    if ~isfolder(folder_path), gb = 0; return; end
    files = dir(fullfile(folder_path, '**', '*.h5'));
    if isempty(files), gb = 0; return; end
    gb = sum([files.bytes]) / (1024^3);
end
