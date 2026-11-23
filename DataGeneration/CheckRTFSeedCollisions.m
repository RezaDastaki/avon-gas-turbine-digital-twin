function summary = CheckRTFSeedCollisions(max_cycles, verbose)
% CheckRTFSeedCollisions - Prove, by enumeration, that no two run-to-failure random draws share a
% seed (P6R, R4). Errors on any violation; silent on success unless verbose.
%
% WHY. Two draws that share a seed are the same numbers, so two units (or two cycles of one unit)
% would silently see the same ambient sequence or the same sensor noise. The original per-cycle
% epoch, unit_id*1000 + c, repeats from cycle 1000 (unit u, cycle 1000+j equals unit u+1, cycle j);
% cycles that long exist since the cycle cap was lifted from 600 to 10,000, so cycles >= 1000 use
% ScenarioConfig.RTFCycleEpoch's separate block while cycles <= 999 keep the original formula
% (which leaves every unit already generated bit-identical).
%
% WHAT IT ENUMERATES, for all 13 mechanisms x UNITS_PER_MECHANISM units x cycles 1..max_cycles:
%   ENV    the ambient draw, SampleEnvironmentMC's seed
%            ENV_MC_SEED + hash + 131*epoch + 99991*attempt,  epoch = RTFCycleEpoch(unit, c),
%          attempts 1-3 (attempt >= 4 has mildness 1, i.e. EXACTLY the nominal condition whatever
%          the seed -- asserted below -- so its seed carries no randomness to collide)
%   NOISE  the measurement-noise seed NOISE_BASE_SEED + hash + 41*unit + 104729*c, which also
%          drives the damage increment (RTFGammaIncrement.m)
%   UNIT   the once-per-unit seeds: accumulator (RTF_ACCUM_SEED_BASE + hash + 613*unit), bias
%          (+61*unit) and calibration age (+71*unit)
%          (the hold seed is passed to ApplyMeasurementModel but only F37, never an RTF
%          mechanism, consumes it)
% and requires, within each family, NO two draws with the same seed among cycles >= 1000 and none
% between a cycle >= 1000 and any cycle <= 999 (the "new" seeds are the ones this change added).
% Collisions among cycles <= 999 predate the change, cannot be altered without changing existing
% units, and are REPORTED (summary.low_low) rather than failed on. Also checked: every seed is a
% valid MATLAB rng seed (0 <= seed < 2^32); the unit-level seeds of one unit differ from each
% other and from that unit's noise seeds; and the high-range ENV seeds do not meet the diagnosis
% family's own ENV seeds (it shares the RTF single-fault hash).
%
% Usage:  CheckRTFSeedCollisions            % cycles 1..1100 (fast; what ValidatePipelineConfig runs)
%         CheckRTFSeedCollisions(10000, true)   % the full proof, to the cycle cap, with a printout
%

    if nargin < 1 || isempty(max_cycles), max_cycles = 1100; end
    if nargin < 2, verbose = false; end

    rtf = GetRTFMechanisms();
    n_units = ScenarioConfig.UNITS_PER_MECHANISM;
    A = ScenarioConfig.AmbientConfig();
    MAX_ATTEMPT_WITH_RANDOMNESS = 3;
    assert(min(1, (MAX_ATTEMPT_WITH_RANDOMNESS) * A.mildness_step) >= 1 - 1e-12, ...
        'Attempt 4 must be the all-nominal attempt (mildness 1) for it to be excluded from the ENV enumeration.');
    assert(min(1, (MAX_ATTEMPT_WITH_RANDOMNESS - 1) * A.mildness_step) < 1, ...
        'Attempt 3 must still carry randomness (mildness < 1).');

    u = (1:n_units)';                 % [units x 1]
    c = 1:max_cycles;                 % [1 x cycles]
    is_high = repmat(c > ScenarioConfig.RTF_EPOCH_LOW_MAX_C, n_units, 1);   % [units x cycles]

    %% Per-mechanism seed matrices, packed as uint64 keys (seed*2 + is_high) so one sort finds
    % duplicates AND tells low from high, without carrying an index array
    env_keys = cell(rtf.Count, 1);
    noise_keys = cell(rtf.Count, 1);
    unit_seed_all = struct('accum', [], 'bias', [], 'calib', []);
    max_seed = 0; min_seed = Inf;
    for m = 1:rtf.Count
        hash = ScenarioConfig.ScenarioHash('single', rtf.FaultID(m));
        epoch = ScenarioConfig.RTFCycleEpoch(u, c);                         % [units x cycles]

        env = zeros(n_units * max_cycles, MAX_ATTEMPT_WITH_RANDOMNESS);
        for a = 1:MAX_ATTEMPT_WITH_RANDOMNESS
            seed = ScenarioConfig.ENV_MC_SEED + hash + epoch * 131 + a * 99991;
            env(:, a) = seed(:);
        end
        env_keys{m} = local_pack(env(:), repmat(is_high(:), MAX_ATTEMPT_WITH_RANDOMNESS, 1));
        [lo, hi] = bounds(env(:)); max_seed = max(max_seed, hi); min_seed = min(min_seed, lo);

        noise = ScenarioConfig.NOISE_BASE_SEED + hash + u * 41 + c * 104729;   % [units x cycles]
        noise_keys{m} = local_pack(noise(:), is_high(:));
        [lo, hi] = bounds(noise(:)); max_seed = max(max_seed, hi); min_seed = min(min_seed, lo);

        unit_seed_all.accum = [unit_seed_all.accum; ScenarioConfig.RTF_ACCUM_SEED_BASE + hash + u * 613]; %#ok<AGROW>
        unit_seed_all.bias  = [unit_seed_all.bias;  ScenarioConfig.BIAS_BASE_SEED      + hash + u * 61];  %#ok<AGROW>
        unit_seed_all.calib = [unit_seed_all.calib; ScenarioConfig.CALIB_AGE_BASE_SEED + hash + u * 71];  %#ok<AGROW>
    end

    summary = struct('max_cycles', max_cycles, 'units', n_units, 'mechanisms', rtf.Count);
    summary.env   = local_count(vertcat(env_keys{:}));    clear env_keys;
    summary.noise = local_count(vertcat(noise_keys{:}));  clear noise_keys;
    summary.unit_level = struct();
    for nm = {'accum', 'bias', 'calib'}
        key = nm{1};
        v = unit_seed_all.(key);
        summary.unit_level.(key) = numel(v) - numel(unique(v));   % duplicates within the family
        max_seed = max(max_seed, max(v)); min_seed = min(min_seed, min(v));
    end

    %% Cross-checks
    % (a) one unit's own seeds must be pairwise distinct, and distinct from its noise seeds
    cross = 0;
    for m = 1:rtf.Count
        hash = ScenarioConfig.ScenarioHash('single', rtf.FaultID(m));
        a_s = ScenarioConfig.RTF_ACCUM_SEED_BASE + hash + u * 613;
        b_s = ScenarioConfig.BIAS_BASE_SEED      + hash + u * 61;
        k_s = ScenarioConfig.CALIB_AGE_BASE_SEED + hash + u * 71;
        cross = cross + nnz(a_s == b_s) + nnz(a_s == k_s) + nnz(b_s == k_s);
        noise = ScenarioConfig.NOISE_BASE_SEED + hash + u * 41 + c * 104729;   % [units x cycles]
        for s_cell = {a_s, b_s, k_s}
            own = s_cell{1};
            cross = cross + nnz(noise == own);   % implicit expansion: own unit's value against every noise seed
        end
    end
    summary.unit_seed_cross_collisions = cross;

    % (b) high-range ENV seeds against the diagnosis family's own ENV seeds (same hash for the
    % single-fault scenarios): main-family epochs 1..1500 and turndown epochs 100001..100200
    diag_epochs = [1:1500, 100001:100200];
    diag_high_hits = 0; diag_low_hits = 0;
    for m = 1:rtf.Count
        hash = ScenarioConfig.ScenarioHash('single', rtf.FaultID(m));
        diag_seed = ScenarioConfig.ENV_MC_SEED + hash + diag_epochs * 131 + (1:MAX_ATTEMPT_WITH_RANDOMNESS)' * 99991;
        epoch = ScenarioConfig.RTFCycleEpoch(u, c);
        for a = 1:MAX_ATTEMPT_WITH_RANDOMNESS
            seed = ScenarioConfig.ENV_MC_SEED + hash + epoch * 131 + a * 99991;
            hit = ismember(seed, diag_seed(:));
            diag_high_hits = diag_high_hits + nnz(hit & is_high);
            diag_low_hits  = diag_low_hits  + nnz(hit & ~is_high);
        end
    end
    summary.env_vs_diagnosis_high = diag_high_hits;
    summary.env_vs_diagnosis_low = diag_low_hits;   % pre-existing overlap, reported not failed

    summary.min_seed = min_seed;
    summary.max_seed = max_seed;

    %% Verdict
    problems = {};
    if summary.env.high_high ~= 0 || summary.env.low_high ~= 0
        problems{end+1} = sprintf('ENV seeds: %d high-high and %d low-high collisions', summary.env.high_high, summary.env.low_high);
    end
    if summary.noise.high_high ~= 0 || summary.noise.low_high ~= 0 || summary.noise.low_low ~= 0
        problems{end+1} = sprintf('NOISE seeds: %d high-high, %d low-high, %d low-low collisions', ...
            summary.noise.high_high, summary.noise.low_high, summary.noise.low_low);
    end
    if any(structfun(@(x) x ~= 0, summary.unit_level))
        problems{end+1} = 'once-per-unit seeds repeat within a family';
    end
    if summary.unit_seed_cross_collisions ~= 0
        problems{end+1} = sprintf('%d collisions between one unit''s own seeds / its noise seeds', summary.unit_seed_cross_collisions);
    end
    if summary.env_vs_diagnosis_high ~= 0
        problems{end+1} = sprintf('%d high-range ENV seeds equal a diagnosis-family ENV seed', summary.env_vs_diagnosis_high);
    end
    if summary.min_seed < 0 || summary.max_seed >= 2^32
        problems{end+1} = sprintf('seed outside the rng range [0, 2^32): min %g, max %g', summary.min_seed, summary.max_seed);
    end

    if verbose
        fprintf('CheckRTFSeedCollisions: %d mechanisms x %d units x %d cycles\n', rtf.Count, n_units, max_cycles);
        fprintf('  ENV   seeds (attempts 1-3): %d total | high-high %d, low-high %d | low-low (predates change) %d\n', ...
            summary.env.total, summary.env.high_high, summary.env.low_high, summary.env.low_low);
        fprintf('  NOISE seeds:                %d total | high-high %d, low-high %d, low-low %d\n', ...
            summary.noise.total, summary.noise.high_high, summary.noise.low_high, summary.noise.low_low);
        fprintf('  per-unit seeds (accum/bias/calib) repeated within family: %d/%d/%d; own-seed cross collisions: %d\n', ...
            summary.unit_level.accum, summary.unit_level.bias, summary.unit_level.calib, summary.unit_seed_cross_collisions);
        fprintf('  high-range ENV seeds equal to a diagnosis ENV seed: %d (low-range, predating: %d)\n', ...
            summary.env_vs_diagnosis_high, summary.env_vs_diagnosis_low);
        fprintf('  seed range: [%g, %g] (limit 2^32 = %g)\n', summary.min_seed, summary.max_seed, 2^32);
    end
    if ~isempty(problems)
        error('CheckRTFSeedCollisions:Collision', 'Seed collisions: %s', strjoin(problems, '; '));
    end
    if verbose
        fprintf('  PASS: no run-to-failure seed collision up to cycle %d.\n', max_cycles);
    end
end

function keys = local_pack(seed, is_high)
% seed (non-negative integer-valued doubles) and a high/low flag -> uint64 key seed*2 + flag.
    keys = uint64(seed) * 2 + uint64(is_high);
end

function r = local_count(keys)
% Sort the keys and count equal-seed neighbours by class. Equal keys share seed AND class, so the
% seed is key>>1 and the class is its low bit.
    keys = sort(keys);
    seed = bitshift(keys, -1);
    cls = bitand(keys, uint64(1));        % 1 = cycle >= 1000
    same = seed(1:end-1) == seed(2:end);
    a = cls(1:end-1); b = cls(2:end);
    r.total = numel(keys);
    r.high_high = nnz(same & a == 1 & b == 1);
    r.low_low   = nnz(same & a == 0 & b == 0);
    r.low_high  = nnz(same & a ~= b);
end
