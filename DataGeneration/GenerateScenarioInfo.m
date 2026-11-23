function [fault_info, output_file] = GenerateScenarioInfo(scenario_type, epoch, varargin)
% GenerateScenarioInfo - Fault metadata + output filename for a scenario.
%
% STRUCTURE:
%   - No environment in the path (environment is MC-sampled per epoch and mixed
%     within one folder per fault/combo).
%   - FLAT layout: every scenario folder sits directly at the family root
%     (naming scheme 2026-11-21): DIAG_Healthy/, DIAG_F01_AirIntakeFilterFouling/ ...,
%     DIAG_DualFault_F01F21/, DIAG_TripleFault_F02F07F26/, DIAG_QuadFault_F02F06F07F29/.
%     The turndown family (10 MW, DatasetRoot=DiagnosisTurndown) uses the TD_ prefix instead
%     of DIAG_ (ScenarioConfig.FamilyPrefix). This function is the only builder of these names.
%   - Uniform epoch naming for ALL scenarios: <DIAG_|TD_><IDs>_E####.h5 (4-digit epoch),
%     e.g. DIAG_F01_E0001.h5, DIAG_F01F05_E0001.h5, DIAG_Healthy_E0001.h5.
%     Severity is NOT in the name (it is MC-sampled per epoch; stored in attrs).
%   - Output root comes from ScenarioConfig.DatasetRoot (the data root; <data root>/DiagnosisTurndown for turndown).
%
% The exact same path logic is reused by ScenarioAlreadyDone.m (resumability),
% so the two can never disagree about where a scenario is written.
%
% Usage:
%   GenerateScenarioInfo('healthy', epoch)
%   GenerateScenarioInfo('single',  epoch, fault_id, severity)
%   GenerateScenarioInfo('dual',    epoch, combo_id, severity_levels)
%   GenerateScenarioInfo('triple',  epoch, combo_id, severity_levels)
%   GenerateScenarioInfo('quad',    epoch, combo_id, severity_levels)
%
% (severity / severity_levels feed the returned fault_info metadata only; the
%  output path does not depend on them, so ScenarioAlreadyDone may pass dummies.)
%
% Date: 2026-07-26

fault_defs = GetFaultDefinitions();
root = ScenarioConfig.DatasetRoot();
pfx  = ScenarioConfig.FamilyPrefix();   % 'DIAG_' (13 MW) or 'TD_' (10 MW turndown)

switch lower(scenario_type)
    case 'healthy'
        fault_info.fault_count = 0;
        fault_info.fault_ids = [];
        fault_info.fault_names = 'Healthy';
        fault_info.severities = [];
        fault_info.severity_deviations = [];
        fault_info.description = 'Healthy (No Faults)';

        scen_id    = 'Healthy';
        filename   = sprintf('%s%s_E%04d.h5', pfx, scen_id, epoch);
        output_dir = fullfile(root, [pfx 'Healthy']);

    case 'single'
        fault_id = varargin{1};
        if nargin >= 4, severity = varargin{2}; else, severity = 0; end

        if fault_id < 1 || fault_id > 42
            error('fault_id must be between 1 and 42. Got: %d', fault_id);
        end

        fault_info.fault_count = 1;
        fault_info.fault_ids = fault_id;
        fault_info.fault_names = fault_defs.Names{fault_id};
        fault_info.severities = severity;
        fault_info.severity_deviations = compute_severity_deviation(fault_id, severity);
        fault_info.description = sprintf('F%02d: %s (SEV%d, deviation=%.4g)', ...
            fault_id, fault_defs.Names{fault_id}, severity, fault_info.severity_deviations);

        % Layout: <root>/DIAG_F07_<Code>/DIAG_F07_E0001.h5   (TD_ for the turndown family)
        scen_id    = sprintf('F%02d_%s', fault_id, fault_defs.Codes{fault_id});
        filename   = sprintf('%sF%02d_E%04d.h5', pfx, fault_id, epoch);
        output_dir = fullfile(root, [pfx scen_id]);

    case 'dual'
        combo_id        = varargin{1};
        severity_levels = varargin{2};

        combo = fault_defs.DualCombos(combo_id, :);
        f1 = combo(1);  f2 = combo(2);

        fault_info.fault_count       = 2;
        fault_info.fault_ids         = [f1, f2];
        fault_info.fault_names       = sprintf('%s + %s', fault_defs.Names{f1}, fault_defs.Names{f2});
        fault_info.severities        = severity_levels;
        fault_info.severity_deviations = compute_severity_deviation([f1, f2], severity_levels);
        fault_info.description       = sprintf('F%02d+F%02d: %s', f1, f2, fault_info.fault_names);

        % Layout: <root>/DIAG_DualFault_F01F21/DIAG_F01F21_E0001.h5
        % The FOLDER leads with the fault count so dual/triple/quad folders sort together; the FILE
        % name and the scenario_id attribute keep the combo-first form (F01F21_DualFault) already on
        % disk -- only folders were renamed. scenario_id is therefore NOT the
        % folder name minus its prefix for multi-fault records.
        combo_tok  = sprintf('F%02dF%02d', f1, f2);
        scen_id    = [combo_tok '_DualFault'];
        filename   = sprintf('%s%s_E%04d.h5', pfx, combo_tok, epoch);
        output_dir = multifault_dir(root, pfx, 'Dual', combo_tok);

    case 'triple'
        combo_id        = varargin{1};
        severity_levels = varargin{2};

        combo = fault_defs.TripleCombos(combo_id, :);
        f1 = combo(1);  f2 = combo(2);  f3 = combo(3);

        fault_info.fault_count       = 3;
        fault_info.fault_ids         = [f1, f2, f3];
        fault_info.fault_names       = sprintf('%s + %s + %s', ...
            fault_defs.Names{f1}, fault_defs.Names{f2}, fault_defs.Names{f3});
        fault_info.severities        = severity_levels;
        fault_info.severity_deviations = compute_severity_deviation([f1, f2, f3], severity_levels);
        fault_info.description       = sprintf('F%02d+F%02d+F%02d: %s', f1, f2, f3, fault_info.fault_names);

        % Layout: <root>/DIAG_TripleFault_F02F07F26/DIAG_F02F07F26_E0001.h5
        % The FOLDER leads with the fault count so dual/triple/quad folders sort together; the FILE
        % name and the scenario_id attribute keep the combo-first form (F02F07F26_TripleFault) already on
        % disk -- only folders were renamed. scenario_id is therefore NOT the
        % folder name minus its prefix for multi-fault records.
        combo_tok  = sprintf('F%02dF%02dF%02d', f1, f2, f3);
        scen_id    = [combo_tok '_TripleFault'];
        filename   = sprintf('%s%s_E%04d.h5', pfx, combo_tok, epoch);
        output_dir = multifault_dir(root, pfx, 'Triple', combo_tok);

    case 'quad'
        combo_id        = varargin{1};
        severity_levels = varargin{2};

        combo = fault_defs.QuadCombos(combo_id, :);
        f1 = combo(1);  f2 = combo(2);  f3 = combo(3);  f4 = combo(4);

        fault_info.fault_count       = 4;
        fault_info.fault_ids         = [f1, f2, f3, f4];
        fault_info.fault_names       = sprintf('%s + %s + %s + %s', ...
            fault_defs.Names{f1}, fault_defs.Names{f2}, fault_defs.Names{f3}, fault_defs.Names{f4});
        fault_info.severities        = severity_levels;
        fault_info.severity_deviations = compute_severity_deviation([f1, f2, f3, f4], severity_levels);
        fault_info.description       = sprintf('F%02d+F%02d+F%02d+F%02d: %s', ...
            f1, f2, f3, f4, fault_info.fault_names);

        % Layout: <root>/DIAG_QuadFault_F02F06F07F29/DIAG_F02F06F07F29_E0001.h5
        % The FOLDER leads with the fault count so dual/triple/quad folders sort together; the FILE
        % name and the scenario_id attribute keep the combo-first form (F02F06F07F29_QuadFault) already on
        % disk -- only folders were renamed. scenario_id is therefore NOT the
        % folder name minus its prefix for multi-fault records.
        combo_tok  = sprintf('F%02dF%02dF%02dF%02d', f1, f2, f3, f4);
        scen_id    = [combo_tok '_QuadFault'];
        filename   = sprintf('%s%s_E%04d.h5', pfx, combo_tok, epoch);
        output_dir = multifault_dir(root, pfx, 'Quad', combo_tok);

    otherwise
        error('GenerateScenarioInfo: unknown scenario_type %s', scenario_type);
end

fault_info.scenario_id = scen_id;   % single/Healthy: folder name without prefix; multi: <combo>_<N>Fault -> HDF5 root attr 'scenario_id'
output_file = fullfile(output_dir, filename);

end

function d = multifault_dir(root, pfx, grp, combo_tok)
% Release layout: in the main family the multi-fault scenario folders sit under a
% group folder, <root>/DIAG_DualFault/DIAG_DualFault_F01F05/. The turndown family is NOT grouped:
% <root>/DiagnosisTurndown/TD_DualFault_F01F05/ (flat, as released).
    if strcmp(pfx, 'TD_')
        d = fullfile(root, [pfx grp 'Fault_' combo_tok]);
    else
        d = fullfile(root, [pfx grp 'Fault'], [pfx grp 'Fault_' combo_tok]);
    end
end

function dev = compute_severity_deviation(fault_ids, severity_levels)
% compute_severity_deviation: replaces the misleading
% severity_percents = severity*20 (a restatement of severity as a percentage, not a physical
% magnitude -- under the k=12 geometric bands, F01's actual deviation runs 0.076% at
% SEV1 to 25% at SEV5, nowhere near 20/40/60/80/100%). The real quantity: the exact fractional
% deviation GetFaultMultiplier.m built the injected multiplier from, |multiplier - 1|. F37's
% multiplier is 0 by construction (a Switch+Memory freeze trigger, not a deviation magnitude at
% all), so it gets NaN rather than the meaningless |0-1|=1.
    dev = arrayfun(@(k) local_deviation(fault_ids(k), severity_levels(k)), 1:numel(fault_ids));
end

function d = local_deviation(fault_id, severity_level)
    if fault_id == 37
        d = NaN;
    else
        d = abs(GetFaultMultiplier(fault_id, severity_level) - 1);
    end
end
