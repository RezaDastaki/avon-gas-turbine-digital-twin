function result = AvonScenarioAssignment(shard, n_shards)
% AvonScenarioAssignment - The deterministic, no-coordination shard/scenario assignment
%. Single source of truth for BOTH parallel drivers,
% AvonProgress.m, SuperSetupCheck.m's disk check and 1_SETUP.bat's startup print -- nobody
% else re-derives the assignment, so it cannot drift between call sites.
%
% Algorithm (spec, verbatim):
%   1. Canonical order: healthy, then single F01..F42 (ascending fault_id), then dual,
%      triple, quad (by combo index) -- i.e. exactly GenerateDiagnosisParallel's own
%      local_build_dispatch loop order, which is also zip_release.py's SCENARIO_FOLDERS
%      order (Healthy + 42 singles + 21 dual + 14 triple + 11 quad = 89). Separately, the 13
%      RTF mechanisms in GetRTFMechanisms order.
%   2. Weight: diagnosis = epoch count for that scenario's kind (cfg.n_epochs_*); RTF = units
%      per mechanism (UNITS_PER_MECHANISM, EQUAL for every mechanism, since per-mechanism
%      mean life is not known in advance -- spec's own declared imbalance).
%   3. Sort by weight DESCENDING; ties broken by canonical index ascending (MATLAB's sort is
%      stable, so this falls out of sorting the already-canonically-ordered list -- no
%      separate tie-break key is needed).
%   4. Assign each item, in that sorted order, to the CURRENTLY LEAST-LOADED shard, ties
%      broken by lowest shard index (MATLAB's min returns the first/lowest index on a tie).
%
% No randomness, no communication, no state read from disk: given the same (shard, n_shards)
% and the same ScenarioConfig/GetRTFMechanisms (both frozen production constants once a run
% starts), every machine computes the identical assignment -- this is what W4 tests.
%
% Inputs:
%   shard, n_shards - OPTIONAL. [] or omitted for either -> AvonShard resolves both. Both
%                     accepted explicitly so acceptance tests (W2/W3/W4/W5) can probe
%                     hypothetical shard counts without touching config.txt/env.
%
% Returns a struct:
%   .shard, .n_shards
%   .diag_items   - [89x1] struct array, canonical order, fields: kind, arg, weight,
%                   canonical_idx, folder, owner_shard
%   .rtf_items    - [13x1] struct array, canonical order, fields: fault_id, folder, weight,
%                   canonical_idx, owner_shard
%   .diag_owned   - diag_items filtered to owner_shard == shard
%   .rtf_owned    - rtf_items filtered to owner_shard == shard
%   .diag_records_owned - sum of .weight over diag_owned (this shard's diagnosis record count)
%   .diag_records_total - sum of .weight over diag_items (the whole family's record count)
%

    if nargin < 1 || isempty(shard) || nargin < 2 || isempty(n_shards)
        [resolved_shard, resolved_n_shards] = AvonShard();
        if nargin < 1 || isempty(shard), shard = resolved_shard; end
        if nargin < 2 || isempty(n_shards), n_shards = resolved_n_shards; end
    end

    cfg = ScenarioConfig.GetActiveConfig();
    diag_items = local_build_diag_items(cfg);
    diag_owner = local_greedy_lpt([diag_items.weight], n_shards);
    for i = 1:numel(diag_items)
        diag_items(i).owner_shard = diag_owner(i);
    end

    rtf = GetRTFMechanisms();
    rtf_items = local_build_rtf_items(rtf);
    rtf_owner = local_greedy_lpt([rtf_items.weight], n_shards);
    for i = 1:numel(rtf_items)
        rtf_items(i).owner_shard = rtf_owner(i);
    end

    result.shard = shard;
    result.n_shards = n_shards;
    result.diag_items = diag_items;
    result.rtf_items = rtf_items;
    result.diag_owned = diag_items(diag_owner == shard);
    result.rtf_owned = rtf_items(rtf_owner == shard);
    result.diag_records_owned = sum([result.diag_owned.weight]);
    result.diag_records_total = sum([diag_items.weight]);
    result.rtf_units_owned = sum([result.rtf_owned.weight]);
    result.rtf_units_total = sum([rtf_items.weight]);
end

%% ===================== canonical item builders =====================

function items = local_build_diag_items(cfg)
    items = struct('kind', {}, 'arg', {}, 'weight', {}, 'canonical_idx', {}, 'folder', {});
    idx = 0;

    idx = idx + 1;
    [~, out_file] = GenerateScenarioInfo('healthy', 1);
    items(idx) = struct('kind', 'healthy', 'arg', [], 'weight', cfg.n_epochs_healthy, ...
        'canonical_idx', idx, 'folder', local_folder_of(out_file));

    for fault_id = cfg.single_fault_ids
        idx = idx + 1;
        [~, out_file] = GenerateScenarioInfo('single', 1, fault_id, 0);
        items(idx) = struct('kind', 'single', 'arg', fault_id, 'weight', cfg.n_epochs_single, ...
            'canonical_idx', idx, 'folder', local_folder_of(out_file));
    end

    for combo_id = cfg.dual_fault_combos
        idx = idx + 1;
        [~, out_file] = GenerateScenarioInfo('dual', 1, combo_id, [1 1]);
        items(idx) = struct('kind', 'dual', 'arg', combo_id, 'weight', cfg.n_epochs_dual, ...
            'canonical_idx', idx, 'folder', local_folder_of(out_file));
    end

    for combo_id = cfg.triple_fault_combos
        idx = idx + 1;
        [~, out_file] = GenerateScenarioInfo('triple', 1, combo_id, [1 1 1]);
        items(idx) = struct('kind', 'triple', 'arg', combo_id, 'weight', cfg.n_epochs_triple, ...
            'canonical_idx', idx, 'folder', local_folder_of(out_file));
    end

    for combo_id = cfg.quad_fault_combos
        idx = idx + 1;
        [~, out_file] = GenerateScenarioInfo('quad', 1, combo_id, [1 1 1 1]);
        items(idx) = struct('kind', 'quad', 'arg', combo_id, 'weight', cfg.n_epochs_quad, ...
            'canonical_idx', idx, 'folder', local_folder_of(out_file));
    end
end

function folder_name = local_folder_of(out_file)
    [parent_dir, ~, ~] = fileparts(out_file);
    [~, folder_name, ~] = fileparts(parent_dir);
end

function items = local_build_rtf_items(rtf)
    items = struct('fault_id', {}, 'folder', {}, 'weight', {}, 'canonical_idx', {});
    weight = ScenarioConfig.UNITS_PER_MECHANISM;  % EQUAL weight for every mechanism
    for i = 1:rtf.Count
        items(i) = struct('fault_id', rtf.FaultID(i), 'folder', rtf.Folder{i}, ...
            'weight', weight, 'canonical_idx', i);
    end
end

%% ===================== greedy longest-processing-time bin packing =====================

function owner = local_greedy_lpt(weights, n_shards)
% Deterministic greedy LPT: sort items by weight descending (MATLAB's sort is stable, so ties
% keep their original -- canonical -- relative order, which IS the tie-break the spec asks
% for); walk the sorted list, assigning each item to the currently least-loaded shard (min
% returns the FIRST/lowest index among ties, which is exactly "ties broken by lowest shard
% index").
    n = numel(weights);
    [~, order] = sort(weights, 'descend');
    loads = zeros(1, n_shards);
    owner = zeros(1, n);
    for k = 1:n
        item_idx = order(k);
        [~, s] = min(loads);
        owner(item_idx) = s;
        loads(s) = loads(s) + weights(item_idx);
    end
end
