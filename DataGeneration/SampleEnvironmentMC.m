function env = SampleEnvironmentMC(scenario_hash, epoch, attempt)
% SampleEnvironmentMC - Draw a continuous, solver-safe ambient/operating
% condition for one epoch (replaces the 5 fixed environments).
%
% The environment is Monte-Carlo sampled per epoch rather than being a
% fixed folder dimension. Each ambient parameter is drawn (seeded, reproducible)
% from a bounded range chosen to stay inside the Simulink solver-stable region
% — in particular the compressor inlet pressure is floored well above the
% 90 kPa "High Altitude" corner that historically caused singularity/collapse
% at high severity, so mixing severity + ambient can never hit that corner.
%
% RETRY / MILDNESS: if a simulation fails (singularity, NaN, non-convergence),
% the driver re-runs the SAME epoch with an incremented `attempt`. Higher
% attempts pull every ambient parameter linearly toward the known-safe nominal
% design point (ENV001), so within a few attempts the draw converges to a
% guaranteed-runnable condition — keeping epoch numbering gap-free.
%
% Inputs:
%   scenario_hash - integer identifying the fault/combo scenario (see
%                   ScenarioConfig.ScenarioHash) — decorrelates draws between
%                   scenarios so different faults don't share ambient sequences.
%   epoch         - epoch number (>=1)
%   attempt       - 1 for the first try; increment on failure (>=1)
%
% Output:
%   env - struct with the same fields as GetEnvironmentalCondition:
%         .FG_pressure_kPa .FG_temp_C .compressor_inlet_temp_C
%         .compressor_inlet_press_kPa .ambient_moisture_percent
%         .name .description .id (id = 0 => MC-sampled) .attempt .mildness
%
% Date: 2026-07-26

    if nargin < 3 || isempty(attempt), attempt = 1; end
    if attempt < 1, attempt = 1; end

    A = ScenarioConfig.AmbientConfig();   % ranges + nominal design point

    % Mildness in [0,1]: 0 on first attempt (full range), ->1 after a few
    % retries (collapses to nominal, guaranteed safe).
    mildness = min(1, (attempt - 1) * A.mildness_step);

    seed = ScenarioConfig.ENV_MC_SEED + scenario_hash + epoch * 131 + attempt * 99991;
    rng(seed, 'twister');

    env = struct();
    env.FG_pressure_kPa            = draw_(A.FG_pressure_kPa,            A.nom.FG_pressure_kPa,            mildness);
    env.FG_temp_C                  = draw_(A.FG_temp_C,                  A.nom.FG_temp_C,                  mildness);
    env.compressor_inlet_temp_C    = draw_(A.compressor_inlet_temp_C,    A.nom.compressor_inlet_temp_C,    mildness);
    env.compressor_inlet_press_kPa = draw_(A.compressor_inlet_press_kPa, A.nom.compressor_inlet_press_kPa, mildness);
    env.ambient_moisture_percent   = draw_(A.ambient_moisture_percent,   A.nom.ambient_moisture_percent,   mildness);

    env.id          = 0;                 % 0 => MC-sampled (no fixed environment)
    env.name        = 'MC-sampled';
    env.description  = sprintf('MC-sampled ambient (attempt %d, mildness %.2f)', attempt, mildness);
    env.attempt     = attempt;
    env.mildness    = mildness;

    % TEST-ONLY HOOK (global TASK9_FORCE_ENV): used ONLY B2 grid-completion probe
    % to exercise the real, unmodified
    % RunScenario.m pipeline at exact ambient grid points instead of this function's own random
    % draw. Overrides individual env fields when set (struct with any subset of this function's
    % field names); unset (empty) on every production call. Grep TASK9_FORCE_ENV to find the one
    % test script that sets it.
    global TASK9_FORCE_ENV
    if ~isempty(TASK9_FORCE_ENV)
        fn = fieldnames(TASK9_FORCE_ENV);
        for fi = 1:numel(fn)
            env.(fn{fi}) = TASK9_FORCE_ENV.(fn{fi});
        end
    end
end

% -------------------------------------------------------------------------
function v = draw_(range, nominal, mildness)
% Uniform draw within [range(1), range(2)], then linearly pulled toward the
% nominal design point by `mildness` (0 = full random range, 1 = exactly nominal).
    u = range(1) + (range(2) - range(1)) * rand();
    v = u * (1 - mildness) + nominal * mildness;
end
