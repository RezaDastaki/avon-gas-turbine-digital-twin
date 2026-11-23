function DatasetAuditReport(config, report_file)
% DatasetAuditReport - Post-generation audit of the complete dataset directory
%
% Scans all Dataset/ subdirectories, counts .h5 files per category, and
% reports expected vs actual file counts, missing combinations, and label
% dataset presence.  Writes a text report to report_file.
%
% Inputs:
%   config      - struct from ScenarioConfig.GetActiveConfig
%   report_file - path to write the text audit report (appended if exists)
%
% Date: 2026-03-15

if nargin < 2 || isempty(report_file)
    report_file = ScenarioConfig.AUDIT_REPORT_FILE;
end

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║              DATASET AUDIT REPORT                           ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% Open report file
fid_report = fopen(report_file, 'a');
if fid_report == -1
    warning('DatasetAuditReport: cannot open report file %s — printing to console only', report_file);
    fid_report = 1;  % stdout fallback
    close_report = false;
else
    close_report = true;
end

ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
plog(fid_report, '================================================\n');
plog(fid_report, 'DATASET AUDIT REPORT — %s\n', ts);
plog(fid_report, '================================================\n\n');

%% Directories
base_dir     = ScenarioConfig.DATASET_BASE_DIR;
healthy_dir  = fullfile(base_dir, ScenarioConfig.HEALTHY_DIR);
single_dir   = fullfile(base_dir, ScenarioConfig.SINGLE_FAULT_DIR);
% Release layout: multi-fault folders sit under DIAG_<N>Fault group folders.
dual_dir     = fullfile(base_dir, 'DIAG_DualFault');
triple_dir   = fullfile(base_dir, 'DIAG_TripleFault');
quad_dir     = fullfile(base_dir, 'DIAG_QuadFault');

environments = config.environments;
epochs       = config.epochs;
n_env        = length(environments);
n_ep         = length(epochs);

%% ---- HEALTHY -------------------------------------------------------
plog(fid_report, '--- HEALTHY ---\n');
expected_healthy = n_env * n_ep;
actual_healthy   = count_h5(healthy_dir);
plog(fid_report, '  Expected : %d\n', expected_healthy);
plog(fid_report, '  Found    : %d\n', actual_healthy);
plog(fid_report, '  Missing  : %d\n\n', max(0, expected_healthy - actual_healthy));

fprintf('Healthy:     %d / %d files\n', actual_healthy, expected_healthy);

%% ---- SINGLE-FAULT --------------------------------------------------
% NOTE: single-fault files live under Dataset/{FaultID}/
% {FaultID}_{ENV}/... (one folder per fault, no common 'SingleFault'
% parent) since the folder-structure fix -- ScenarioConfig.SINGLE_FAULT_DIR
% ('SingleFault') is stale and points at the old, pre-fix structure.
% Count directly from each active fault's own folder instead.
plog(fid_report, '--- SINGLE-FAULT ---\n');
fault_ids    = config.single_fault_ids;
fdefs_codes  = getfield(GetFaultDefinitions(), 'Codes');
severities   = config.single_fault_severities;
expected_sf  = length(fault_ids) * length(severities) * n_env * n_ep;
actual_sf = 0;
single_sample_dir = '';
for fi = 1:length(fault_ids)
    fdir = fullfile(base_dir, sprintf('%sF%02d_%s', ScenarioConfig.FamilyPrefix(), fault_ids(fi), fdefs_codes{fault_ids(fi)}));   % naming scheme 2026-11-21
    actual_sf = actual_sf + count_h5(fdir);
    if isempty(single_sample_dir) && exist(fdir, 'dir')
        single_sample_dir = fdir;
    end
end
plog(fid_report, '  Expected : %d  (%d faults × %d sev × %d env × %d ep)\n', ...
    expected_sf, length(fault_ids), length(severities), n_env, n_ep);
plog(fid_report, '  Found    : %d\n', actual_sf);
plog(fid_report, '  Missing  : %d\n\n', max(0, expected_sf - actual_sf));

fprintf('Single-fault: %d / %d files\n', actual_sf, expected_sf);

%% ---- DUAL-FAULT ----------------------------------------------------
% Expected count uses config.dual_fault_combos (already excludes combos
% containing parked faults -- see ScenarioConfig.GetActiveConfig), not the
% raw ScenarioConfig.N_DUAL_COMBOS which counts all combos regardless.
plog(fid_report, '--- DUAL-FAULT ---\n');
n_dual       = length(config.dual_fault_combos);
expected_dual = n_dual * n_env * n_ep;
actual_dual   = count_h5(dual_dir);
plog(fid_report, '  Expected : %d  (%d valid combos × %d env × %d ep)\n', ...
    expected_dual, n_dual, n_env, n_ep);
plog(fid_report, '  Found    : %d\n', actual_dual);
plog(fid_report, '  Missing  : %d\n\n', max(0, expected_dual - actual_dual));

fprintf('Dual-fault:   %d / %d files\n', actual_dual, expected_dual);

%% ---- TRIPLE-FAULT --------------------------------------------------
plog(fid_report, '--- TRIPLE-FAULT ---\n');
n_triple       = length(config.triple_fault_combos);
expected_triple = n_triple * n_env * n_ep;
actual_triple   = count_h5(triple_dir);
plog(fid_report, '  Expected : %d  (%d valid combos × %d env × %d ep)\n', ...
    expected_triple, n_triple, n_env, n_ep);
plog(fid_report, '  Found    : %d\n', actual_triple);
plog(fid_report, '  Missing  : %d\n\n', max(0, expected_triple - actual_triple));

fprintf('Triple-fault: %d / %d files\n', actual_triple, expected_triple);

%% ---- QUAD-FAULT ----------------------------------------------------
plog(fid_report, '--- QUAD-FAULT ---\n');
n_quad       = length(config.quad_fault_combos);
expected_quad = n_quad * n_env * n_ep;
actual_quad   = count_h5(quad_dir);
plog(fid_report, '  Expected : %d  (%d valid combos × %d env × %d ep)\n', ...
    expected_quad, n_quad, n_env, n_ep);
plog(fid_report, '  Found    : %d\n', actual_quad);
plog(fid_report, '  Missing  : %d\n\n', max(0, expected_quad - actual_quad));

fprintf('Quad-fault:   %d / %d files\n', actual_quad, expected_quad);

%% ---- TOTALS --------------------------------------------------------
expected_total = expected_healthy + expected_sf + expected_dual + expected_triple + expected_quad;
actual_total   = actual_healthy   + actual_sf   + actual_dual   + actual_triple   + actual_quad;
missing_total  = max(0, expected_total - actual_total);

plog(fid_report, '--- TOTALS ---\n');
plog(fid_report, '  Expected : %d\n', expected_total);
plog(fid_report, '  Found    : %d\n', actual_total);
plog(fid_report, '  Missing  : %d\n', missing_total);
plog(fid_report, '  Complete : %.1f%%\n\n', 100 * actual_total / max(1, expected_total));

fprintf('\nTotal: %d / %d files (%.1f%% complete)\n', ...
    actual_total, expected_total, 100 * actual_total / max(1, expected_total));

%% ---- LABEL SPOT CHECK (first file per category) --------------------
plog(fid_report, '--- LABEL SPOT CHECK ---\n');
spot_dirs = {healthy_dir, single_sample_dir, dual_dir, triple_dir, quad_dir};
spot_names = {'Healthy', 'SingleFault', 'DualFault', 'TripleFault', 'QuadFault'};

for si = 1:length(spot_dirs)
    h5s = rdir_h5(spot_dirs{si});
    if isempty(h5s)
        plog(fid_report, '  %s: no files found\n', spot_names{si});
        continue;
    end
    f = h5s{1};
    try
        fl = h5read(f, '/fault_label');
        sl = h5read(f, '/severity_label');
        [fr, fc] = size(fl);
        [sr, sc] = size(sl);
        if fc == 42 && sc == 42
            plog(fid_report, '  %s: /fault_label [%d×42] ✓  /severity_label [%d×42] ✓\n', ...
                spot_names{si}, fr, sr);
        else
            plog(fid_report, '  %s: unexpected shape — fl [%d×%d]  sl [%d×%d]\n', ...
                spot_names{si}, fr, fc, sr, sc);
        end
    catch ME
        plog(fid_report, '  %s: label read FAILED — %s\n', spot_names{si}, ME.message);
    end
end

plog(fid_report, '\n================================================\n\n');

fprintf('\nAudit report written to: %s\n', report_file);

if close_report
    fclose(fid_report);
end

fprintf('\n╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║           AUDIT COMPLETE                                    ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

end

%% ---- Helper: count .h5 files recursively in a directory -----------
function n = count_h5(dir_path)
    if ~exist(dir_path, 'dir')
        n = 0;
        return;
    end
    files = dir(fullfile(dir_path, '**', '*.h5'));
    n = length(files);
end

%% ---- Helper: return cell array of .h5 paths in a directory --------
function paths = rdir_h5(dir_path)
    paths = {};
    if ~exist(dir_path, 'dir')
        return;
    end
    files = dir(fullfile(dir_path, '**', '*.h5'));
    for i = 1:length(files)
        paths{end+1} = fullfile(files(i).folder, files(i).name); %#ok<AGROW>
    end
end

%% ---- Helper: printf to both console and file ----------------------
function plog(fid, fmt, varargin)
    msg = sprintf(fmt, varargin{:});
    fprintf('%s', msg);
    if fid ~= 1
        fprintf(fid, '%s', msg);
    end
end
