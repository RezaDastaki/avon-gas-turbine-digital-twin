% DatasetProgress.m
% Track dataset generation progress and estimate completion time.
%
% Scans the (flat) dataset root and reports files generated per category,
% overall progress, current size, and an ETA. Expected counts are read live
% from ScenarioConfig, so this always matches your current N_EPOCHS_* settings.
%
% Category is inferred from each root folder's name:
%   Healthy/                      -> Healthy
%   F##        (e.g. F07)         -> Single
%   F##F##     (e.g. F01F21)      -> Dual
%   F##F##F##                     -> Triple
%   F##F##F##F##                  -> Quad
%
% Usage:  >> DatasetProgress
%
% Date: 2026-07-26 (flat structure; live expected counts)

function DatasetProgress()

    fprintf('\n========================================\n');
    fprintf('  Diagnosis Dataset Generation Progress\n');
    fprintf('========================================\n\n');

    base_dir = ScenarioConfig.DatasetRoot();
    if ~exist(base_dir, 'dir')
        fprintf('Diagnosis folder "%s" not found yet (nothing generated).\n\n', base_dir);
        return;
    end
    fprintf('Scanning "%s" ...\n\n', base_dir);

    cfg = ScenarioConfig.GetActiveConfig();

    %% Expected counts (live from config)
    exp = struct();
    exp.Healthy = cfg.n_epochs_healthy;
    exp.Single  = numel(cfg.single_fault_ids)   * cfg.n_epochs_single;
    exp.Dual    = numel(cfg.dual_fault_combos)  * cfg.n_epochs_dual;
    exp.Triple  = numel(cfg.triple_fault_combos)* cfg.n_epochs_triple;
    exp.Quad    = numel(cfg.quad_fault_combos)  * cfg.n_epochs_quad;
    exp.Total   = exp.Healthy + exp.Single + exp.Dual + exp.Triple + exp.Quad;

    %% Actual counts (scan flat root folders)
    act = struct('Healthy',0,'Single',0,'Dual',0,'Triple',0,'Quad',0);
    pfx = ScenarioConfig.FamilyPrefix();   % naming scheme 2026-11-21: DIAG_ / TD_
    act.Healthy = count_h5_files(fullfile(base_dir, [pfx 'Healthy']));

    % Release layout: in the main family the multi-fault folders sit one level down inside the
    % <pfx>DualFault/, <pfx>TripleFault/, <pfx>QuadFault/ group folders (turndown is flat).
    % scan_dirs collects every folder counted, so size/ETA exclude other families in the data root.
    scan_dirs = {fullfile(base_dir, [pfx 'Healthy'])};
    d = dir(base_dir);
    d = d([d.isdir]);
    cand = struct('name', {}, 'path', {});
    for i = 1:numel(d)
        nm = d(i).name;
        if strncmp(nm, '.', 1) || ~strncmp(nm, pfx, numel(pfx)), continue; end
        if ~isempty(regexp(nm, ['^' pfx '(Dual|Triple|Quad)Fault$'], 'once'))
            c = dir(fullfile(base_dir, nm));
            c = c([c.isdir]);
            for j = 1:numel(c)
                if strncmp(c(j).name, '.', 1), continue; end
                cand(end+1) = struct('name', c(j).name, 'path', fullfile(base_dir, nm, c(j).name)); %#ok<AGROW>
            end
        else
            cand(end+1) = struct('name', nm, 'path', fullfile(base_dir, nm)); %#ok<AGROW>
        end
    end
    for i = 1:numel(cand)
        name = cand(i).name;
        % Fault count by grammar, never by name length (single: DIAG_Fxx_<code>; multi:
        % DIAG_DualFault_<F..F..>/DIAG_TripleFault_..../DIAG_QuadFault_....).
        if ~isempty(regexp(name, '^(DIAG|TD)_F\d{2}_[A-Za-z]\w*$', 'once'))
            groups = 1;
        else
            tok = regexp(name, '^(?:DIAG|TD)_(?:Dual|Triple|Quad)Fault_((?:F\d{2}){2,4})$', 'tokens', 'once');
            if isempty(tok), continue; end   % skip Healthy, docs and other dirs
            groups = numel(tok{1}) / 3;
        end
        n = count_h5_files(cand(i).path);
        scan_dirs{end+1} = cand(i).path; %#ok<AGROW>
        switch groups
            case 1, act.Single = act.Single + n;
            case 2, act.Dual   = act.Dual   + n;
            case 3, act.Triple = act.Triple + n;
            case 4, act.Quad   = act.Quad   + n;
        end
    end
    act.Total = act.Healthy + act.Single + act.Dual + act.Triple + act.Quad;

    %% Display table
    fprintf('========================================================\n');
    fprintf('%-14s %10s %10s   %s\n', 'Category', 'Expected', 'Actual', 'Progress');
    fprintf('--------------------------------------------------------\n');
    print_row('Healthy',      exp.Healthy, act.Healthy);
    print_row('Single-Fault', exp.Single,  act.Single);
    print_row('Dual-Fault',   exp.Dual,    act.Dual);
    print_row('Triple-Fault', exp.Triple,  act.Triple);
    print_row('Quad-Fault',   exp.Quad,    act.Quad);
    fprintf('--------------------------------------------------------\n');
    print_row('TOTAL',        exp.Total,   act.Total);
    fprintf('========================================================\n\n');

    if exp.Total > 0
        fprintf('Overall: %.2f%% (%d / %d files)\n\n', ...
            100*act.Total/exp.Total, act.Total, exp.Total);
    end

    %% Size
    total_size = 0;
    for i = 1:numel(scan_dirs), total_size = total_size + get_folder_size(scan_dirs{i}); end
    fprintf('Current dataset size (raw .h5): %.2f GB\n', total_size);
    if act.Total > 0
        fprintf('Avg per file: %.2f MB  |  Projected full size: %.1f GB (raw)\n\n', ...
            total_size*1024/act.Total, total_size/act.Total*exp.Total);
    else
        fprintf('\n');
    end

    %% ETA (from first/last file timestamps)
    files = [];
    for i = 1:numel(scan_dirs)
        if isfolder(scan_dirs{i}), files = [files; dir(fullfile(scan_dirs{i}, '**', '*.h5'))]; end %#ok<AGROW>
    end
    if numel(files) > 1
        [~, idx] = sort([files.datenum]);
        files = files(idx);
        hours_elapsed = (files(end).datenum - files(1).datenum) * 24;
        remaining = max(0, exp.Total - act.Total);
        if act.Total > 1 && hours_elapsed > 0
            per_file = hours_elapsed / (act.Total - 1);   % hours
            eta = per_file * remaining;
            fprintf('Elapsed: %.1f h (%.1f d) | %.1f s/file | Remaining: %d files\n', ...
                hours_elapsed, hours_elapsed/24, per_file*3600, remaining);
            fprintf('Est. time left: %.1f h (%.1f d) | Est. completion: %s\n\n', ...
                eta, eta/24, datestr(now + eta/24, 'yyyy-mm-dd HH:MM'));
        end
    end

    if act.Total >= exp.Total && exp.Total > 0
        fprintf('Status: COMPLETE.\n\n');
    else
        fprintf('Status: IN PROGRESS. Re-run the driver(s) to continue (resumable).\n\n');
    end
end

%% ---- helpers ----
function print_row(label, expected, actual)
    fprintf('%-14s %10d %10d   %s\n', label, expected, actual, progress_bar(actual, expected));
end

function count = count_h5_files(folder_path)
    if ~exist(folder_path, 'dir'), count = 0; return; end
    files = dir(fullfile(folder_path, '**', '*.h5'));
    count = numel(files);
end

function size_gb = get_folder_size(folder_path)
    if ~exist(folder_path, 'dir'), size_gb = 0; return; end
    files = dir(fullfile(folder_path, '**', '*.h5'));
    if isempty(files), size_gb = 0; return; end
    size_gb = sum([files.bytes]) / (1024^3);
end

function bar_str = progress_bar(current, total)
    if total <= 0, bar_str = '[----------] n/a'; return; end
    percent = min(100, (current / total) * 100);
    filled = round(percent / 10);
    bar_str = sprintf('[%s%s] %.0f%%', repmat('=',1,filled), repmat('-',1,10-filled), percent);
end
