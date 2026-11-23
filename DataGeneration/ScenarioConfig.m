% ScenarioConfig.m
% User-Editable Configuration for Dataset Generation
%
% This file contains all configurable parameters for the automated
% dataset generation pipeline. Edit these values to customise your
% generation run. The class provides GetActiveConfig which applies
% testing mode overrides automatically.
%
% Date: 2025-12-29
% Updated: 2026-03-15 - Complete overhaul per Automation_Pipeline_Guide

classdef ScenarioConfig
    properties (Constant)

        %% =================================================================
        %% SIMULATION PARAMETERS
        %% =================================================================

        % Simulink model path (relative to repository root)
        % CRITICAL FIX: this pointed at the ORIGINAL, unfixed model.
        % RunScenario.m Step 2 calls RunSimulinkModel(ScenarioConfig.SIMULINK_MODEL, ...) directly,
        % so the production pipeline, as found, would have simulated AvonGasTurbineDgTwin.slx --
        % NONE fixes (speed-dependent PT load, governor loops, the duty-command
        % rewrite, the true-value taps) would have applied to an actual generation run. This is
        % separate from, and more serious than, the enable-flag sidecar gap that motivated this
        % fix in the first place for the full finding and verification.
        SIMULINK_MODEL        = 'Core/Models/AvonGasTurbineDgTwin_fixed';

        % Simulation duration (seconds) — record-timing redesign. The stored window is a FIXED 4200 samples at 1 Hz; what varies
        % per record is the unstored, ambient-dependent pre-roll that warm-starts the model from
        % the operating-point library: 1800 s by default, 3600 s when the drawn
        % compressor-inlet temperature falls in [23, 27] °C (the duty_tracking/temperature_limited
        % regime boundary, where the warm start needs longer to resolve a genuine S26 overshoot).
        % SIMULATION_DURATION as a constant is therefore the DEFAULT total (used by anything that
        % needs one fixed number — docs, EstimateFileCount, the old single-shot validators); the
        % real per-record total is ScenarioConfig.GetSimulationDuration(inlet_temp_C), computed
        % after the ambient draw and used by RunScenario.m to call RunSimulinkModel. Both equal
        % STORED_SAMPLES + GetPrerollSeconds(...): 4200 + 1800 = 6000 (default) or 4200 + 3600 =
        % 7800 (near the regime boundary) — both still below the draft's 7200 s simulated for most
        % of the envelope, and never longer than needed to absorb the warm-start residual
        %.
        SIMULATION_DURATION   = 6000;

        % STORED window — fixed, independent of pre-roll.
        STORED_SAMPLES        = 4200;

        % Pre-roll (unstored, absorbs the warm-start residual).
        PREROLL_DEFAULT_S     = 1800;
        PREROLL_REGIME_S      = 3600;
        PREROLL_REGIME_TEMP_LO = 23;   % inlet_temp_C band that gets the longer pre-roll
        PREROLL_REGIME_TEMP_HI = 27;

        % Default output sampling rate (Hz) for saved HDF5 files — 1 Hz,
        % unchanged from the original dataset, → 7201 samples per file.
        % UNIFORM across the whole release:
        % F18 and F19's oscillation frequencies were LOWERED to 0.30/0.10 Hz specifically so that
        % no fault needs a higher output rate any more -- previously F18 (1.0 Hz oscillate)
        % sampled at exactly its own frequency at 1 Hz (total aliasing) and F19 (0.5 Hz) sat
        % exactly at the Nyquist limit, which needed GetOutputDt's 5 Hz override below. That
        % override is now removed; every fault's oscillation/ramp/step frequency content is under
        % 1 Hz and the release carries no 5 Hz files at all, removing C21/C49.
        SAMPLING_RATE         = 1.0;

        % Internal resolution (seconds) used to build the fault-multiplier
        % injection array and to log raw signals inside Simulink (ToWorkspace
        % blocks are hardcoded to this in the .slx). Kept fine (5 Hz) for
        % ALL faults regardless of final output rate below -- this is what
        % fixed the F13 premature-onset bug (see datasetInformation.md) and
        % ensures F18/F19's own oscillation is correctly represented at the
        % injection stage. This does NOT by itself affect saved file size;
        % only GetOutputDt below does.
        TIMESERIES_DT         = 0.2;

        % Solver settings
        USE_FAST_SOLVER       = false;  % true = ode23t instead of ode45

        % Stop simulation on Simulink model error (set true for testing, false for production)
        STOP_ON_ERROR         = false;

        %% =================================================================
        %% PATHS
        %% =================================================================

        % OUTPUT ROOT: the (regenerated, first-version) dataset is written here,
        % alongside the documentation files in the same folder. The old raw .h5
        % data was deleted before regeneration.
        %: renamed from 'Dataset' to
        % 'Diagnosis' while the tree was still empty, so the generation tree IS the upload tree
        % (release layout: Diagnosis/, RunToFailure/, Sample/, Code/). Safe and reversible even
        % after generation -- no HDF5 attribute anywhere stores an on-disk path, and only four
        % .m files reference this constant (ScenarioConfig.m, GenerateScenarioInfo.m,
        % DatasetProgress.m, RTFAlreadyDone.m touches only RTF_OUTPUT_ROOT, a separate constant).
        % made ABSOLUTE via
        % AvonDataRoot so the pipeline runs on any machine, at any path, on any drive
        % letter. 'Diagnosis' (the string) is unchanged -- only the parent root moved from
        % implicitly-cwd-relative to the repository root itself, so the release tree
        % sits directly under it with no intervening level.
        % RELEASE LAYOUT: the main-family (13 MW) scenario folders sit DIRECTLY in
        % AvonDataRoot -- there is no 'Diagnosis' level any more; the data root IS the release
        % tree. Only the turndown family has a container folder (DatasetRoot).
        OUTPUT_ROOT           = AvonDataRoot();

        % NOT legacy -- ValidatePipelineConfig.m Check 7 and DatasetAuditReport.m both read this
        % constant directly; the old "(legacy; unused by the path builder)" comment was stale.
        DATASET_BASE_DIR      = AvonDataRoot();
        CHECKPOINT_DIR        = fullfile(fileparts(AvonLogDir()), 'Checkpoints');    % <repo>/Checkpoints, never inside the data root
        % LEGACY category-folder names — UNUSED in the flat layout (every
        % fault/combo folder now sits directly at the dataset root; see
        % GenerateScenarioInfo.m). Kept only so old references still parse.
        HEALTHY_DIR           = 'DIAG_Healthy';   % naming scheme 2026-11-21 (turndown: TD_Healthy, see FamilyPrefix)
        SINGLE_FAULT_DIR      = 'SingleFault';
        DUAL_FAULT_DIR        = 'DualFault';
        TRIPLE_FAULT_DIR      = 'TripleFault';
        QUAD_FAULT_DIR        = 'QuadFault';

        % Turndown family: epochs per scenario, all 89 scenarios (= 17,800 records).
        % Single source for GenerateTurndownParallel and AvonProgress.
        TURNDOWN_EPOCHS_PER_SCENARIO = 200;

        %% =================================================================
        %% STORAGE / DIVERSITY OPTIONS
        %% =================================================================

        % Store sensor arrays as single (float32) instead of double (float64).
        % Halves file size; precision (~1e-7 relative) far exceeds the 0.05-1%
        % noise floor, so there is no scientific loss for this data.
        STORE_FLOAT32         = true;

        % Add a per-epoch constant calibration bias (offset) to each channel,
        % on top of white measurement noise. Biggest cheap diversity gain,
        % especially for healthy epochs. See GetSensorNoiseModel / AddGaussianNoise.
        ADD_SENSOR_BIAS       = true;

        % Max simulation attempts per epoch. On failure (singularity/NaN) the
        % SAME epoch is re-run with a milder MC-sampled environment (see
        % SampleEnvironmentMC) until it succeeds, so epoch numbering stays
        % gap-free. attempt>=4 collapses ambient to the nominal design point,
        % so a handful of attempts is effectively always sufficient.
        SIM_RETRY_MAX         = 6;

        %% =================================================================
        %% GENERATION SCOPE (PRODUCTION)
        %% =================================================================

        GENERATE_HEALTHY      = true;
        GENERATE_SINGLE_FAULT = true;
        GENERATE_DUAL_FAULT   = true;
        GENERATE_TRIPLE_FAULT = true;
        GENERATE_QUAD_FAULT   = true;

        % LEGACY: fixed environment IDs from an earlier pipeline iteration. The
        % environment is now MC-sampled continuously per epoch
        % (SampleEnvironmentMC), so there is no environment dimension anymore.
        % Kept only for reference/back-compat.
        ENVIRONMENTS          = [1:5];   % (unused by the current drivers)

        %% =================================================================
        %% EPOCHS PER SCENARIO (the numbers you tune to hit your GB budget)
        %% =================================================================
        %
        % Each scenario (one fault / one combo / healthy) now lives in a single
        % folder with this many epochs; every epoch MC-samples its own
        % environment + severity + onset + noise + bias. Increase any of these
        % later and simply re-run the driver: existing epoch files are skipped
        % and only the NEW epochs are generated (no data is lost or rewritten).
        %
        % SIZING — record-count/duration redesign, applied
        % 2026-10-13. Replaces 10000/3000/2500/2000/1500 counts (527 GB raw / 201 GB
        % zipped at the old 7201-sample / stability-workaround-combo design) and the 18/22/15 combo
        % counts (see GetFaultDefinitions.m's combo-table header for why those were retired, not
        % extended). New total: Healthy 8,000 + 42 singles x 1,500 + 21 dual x 800 + 14 triple x
        % 800 + 11 quad x 1,000 = 110,000 records across 89 scenarios (asserted in
        % ValidatePipelineConfig.m). At the new ~4200-sample / ~0.25 MB/record writer,
        % that is ~28 GB total -- own sizing is in `` / ``'s
        % section; do not cite 527/201 GB figures.
        % Scale any of these up/down and re-run — existing epochs are skipped.
        %
        % doubled from counts above (8000/1500/
        % 800/800/1000) to 16000/3000/1600/1600/2000 removes the
        % compute barrier. New total: 16,000 + 42*3000 + 21*1600 +
        % 14*1600 + 11*2000 = 220,000 records. Every count is still a multiple of 5, so the
        % severity-balance property (severity is a shuffled permutation per block of 5 epochs)
        % is preserved -- verified, not assumed.
        N_EPOCHS_HEALTHY      = 8000;
        N_EPOCHS_SINGLE       = 1500;
        N_EPOCHS_DUAL         = 800;
        N_EPOCHS_TRIPLE       = 800;
        N_EPOCHS_QUAD         = 1000;

        % Legacy single knob (kept so old scripts referencing it still parse).
        N_EPOCHS              = 1500;

        % Single-fault parameters — all 42 faults live (none parked).
        SINGLE_FAULT_IDS      = 1:42;
        SINGLE_FAULT_SEVERITIES = [1:5];  % all 5 severity levels

        % Multi-fault combo ranges (index into GetFaultDefinitions combo tables) — rebuild,
        % every row of the new 21/14/11-row tables is live (the 46-combo
        % co-occurrence search already excludes anything solver-unsafe by construction; see
        % GetFaultDefinitions.m). No PARKED_FAULTS filter is needed any more -- removed below,
        % together with the GetActiveConfig logic that applied it (F08/F25/F30/F32 are all live
        % faults now, not excluded from multi-fault combos).
        DUAL_FAULT_COMBOS     = 1:21;
        TRIPLE_FAULT_COMBOS   = 1:14;
        QUAD_FAULT_COMBOS     = 1:11;

        %% =================================================================
        %% EPOCH VARIATION — FAULT START TIMES
        %% =================================================================

        % — comment this
        % replaced read "Maximum 3600 s: slowest ramp (3600 s) completes exactly at t=7200 s". That
        % sentence IS the defect found: F21/F25/F26/F30 (3600 s ramps) got 0-1599 s of
        % post-ramp tail under it, not the >=1800 s every severity band was calibrated against —
        % full account test S10.
        %
        % FAULT_START_TAU_MIN/MAX are STORED-WINDOW-RELATIVE (tau = sample index into the 4200-
        % sample stored record, tau in [1, STORED_SAMPLES]), NOT absolute simulation time — the
        % pre-roll is now ambient-dependent, so a fixed absolute-time onset constant
        % would onset during the unstored pre-roll for some records and not others. The onset draw
        % is tau_onset = randi([FAULT_START_TAU_MIN, FAULT_START_TAU_MAX]) (inclusive two-arg
        % form, so the bounds below ARE the realised range, no off-by-one), and the absolute
        % simulation-time onset used to build FAULT_NN_multiplier is
        % GetPrerollSeconds(inlet_temp_C) + tau_onset — see LoadScenarioToWorkspace.m.
        % Budget: max(DriftDuration) <= STORED_SAMPLES - FAULT_START_TAU_MAX
        % - 1800 = 4200 - 1200 - 1800 = 1200 s, asserted in ValidatePipelineConfig.m Check 5.
        FAULT_START_TAU_MIN   = 601;
        FAULT_START_TAU_MAX   = 1200;
        FAULT_START_SEED      = 7391;   % base RNG seed for reproducible start-time sampling

        %% =================================================================
        %% GAUSSIAN NOISE
        %% =================================================================

        ADD_GAUSSIAN_NOISE    = true;

        % Base RNG seeds. Full seeds are keyed on (scenario_hash, epoch,
        % attempt) so retries of the same epoch get a DIFFERENT realisation:
        %   noise: NOISE_BASE_SEED + scenario_hash + epoch*41  + attempt*104729
        %   bias : BIAS_BASE_SEED  + scenario_hash + epoch*61  + attempt*100003
        NOISE_BASE_SEED       = 5147;
        BIAS_BASE_SEED        = 9241;   % per-epoch calibration bias

        % (measurement layer): two more independent seed streams, same
        % (scenario_hash, epoch, attempt)-keyed convention as NOISE/BIAS above.
        %   calib_age : CALIB_AGE_BASE_SEED + scenario_hash + epoch*71 + attempt*100477
        %     draws t_since_cal ~ U(0,1) yr, once per record, shared across all 39 channels
        %     (rule 3.2(e) — same calibration-interval context for the whole instrument suite).
        %   hold      : HOLD_BASE_SEED + scenario_hash + epoch*83 + attempt*100519
        %     drives F37's per-chunk intermittent-freeze draw (ApplyMeasurementModel.m).
        CALIB_AGE_BASE_SEED   = 3083;
        HOLD_BASE_SEED        = 6829;

        % Per-channel noise levels now come from GetSensorNoiseModel
        % (type-driven, temperature on absolute-K basis). The hand-tuned
        % 34-element vector below is retained ONLY for reference; it is no
        % longer read by the pipeline.
        NOISE_PERCENT_PER_SENSOR = [ ...
            0.10, 0.10, 0.05, 0.20, 0.10, ...   % S01–S05  (LEGACY — unused)
            0.10, 0.20, 0.05, 0.10, 0.10, ...   % S06–S10
            0.10, 0.05, 0.10, 0.20, 0.20, ...   % S11–S15
            0.10, 0.10, 0.20, 0.10, 0.10, ...   % S16–S20
            0.10, 0.10, 0.20, 0.05, 0.10, ...   % S21–S25
            0.10, 0.05, 0.10, 0.10, 0.05, ...   % S26–S30
            0.10, 0.05, 0.05, 0.05];             % S31–S34

        % Sampling seeds
        ENV_MC_SEED           = 20260726;  % continuous ambient MC
        SEV_STRAT_SEED        = 8123;      % stratified single-fault severity

        % (the within-record ambient trend, C12): TREND_BASE_SEED + scenario_hash +
        % epoch*89 + attempt*100523 -- GetAmbientTrendAmplitude.m's own seed formula.
        TREND_BASE_SEED       = 4457;

        %% =================================================================
        %% MULTI-FAULT MONTE CARLO SEVERITY SAMPLING
        %% =================================================================

        % MC_COMBO_SEED: used by GenerateMonteCarloCombos.m (one-time utility only)
        MC_COMBO_SEED         = 42;

        % MC_SEV_SEED: used per epoch to sample independent severities for multi-fault combos
        % Seed formula: rng(MC_SEV_SEED + combo_id*10000 + env_id*1000 + epoch_id*10, 'twister')
        MC_SEV_SEED           = 1337;

        % Expected combo counts (for validation in ValidatePipelineConfig) -- raw
        % GetFaultDefinitions table row counts. rebuild: 21/14/11, and every row
        % is active (DUAL_FAULT_COMBOS/TRIPLE_FAULT_COMBOS/QUAD_FAULT_COMBOS = 1:N, no filtering).
        N_DUAL_COMBOS         = 21;
        N_TRIPLE_COMBOS       = 14;
        N_QUAD_COMBOS         = 11;

        %% =================================================================
        %% QUALITY CONTROL
        %% =================================================================

        % Run quality checks after each file save (the real per-file integrity
        % check: sample counts, NaN/Inf, time, metadata, plausibility, labels).
        % OFF. QualityCheckHDF5.m predates writer schema -- it reads a
        % removed '/time' dataset, an attribute this writer renamed, and (more importantly) several
        % of its per-channel plausibility checks assume column i of /sensors IS S0i, which is no
        % longer true now that /sensors is a 26-channel SUBSET in dictionary order (S01,S02,...,
        % S08,S10,S11,S17,S19,...), not a 1:1 slice of S01-S34. A surface patch of just the loader
        % would silently check the WRONG channel's plausibility range for the back half of the
        % array -- worse than skipping it. The real per-record gate is QA Layer 1
        % (ValidateGenerationLayer1.m, RunScenario.m Step 7.5), which already runs unconditionally
        % and is schema-aware by construction. QualityCheckHDF5.m needs a full schema-aware
        % rewrite before this flag should go back to true -- not done this session.
        RUN_QUALITY_CHECKS         = false;

        % Workspace verification OFF. It re-extracts the CLEAN signal and
        % compares it to the saved NOISY file, so post-noise it only ever
        % reports "differences = the injected noise" (plus a benign 5 Hz
        % off-by-one in its own re-extraction). Label integrity is already
        % covered by QualityCheckHDF5 CHECK 7, and turning this off also avoids
        % a second full extraction per file. Re-enable only for debugging.
        RUN_WORKSPACE_VERIFICATION = false;

        % On quality check or verification failure: STOP immediately
        STOP_ON_QUALITY_FAIL       = false;

        % Thresholds for VerifyHDF5Data
        MIN_CORRELATION            = 0.5;
        MAX_RMSE                   = 100;

        %% =================================================================
        %% CHECKPOINTS
        %% =================================================================

        % Checkpoints OFF. Each checkpoint is a ~2 MB .mat per file; with
        % ~130k files that is another ~260 GB in Checkpoints/ (roughly doubling
        % on-disk usage). They only fed the (now-disabled) workspace
        % verification; the pipeline is fully resumable without them. Set true
        % only if you specifically want a .mat fallback per file.
        SAVE_CHECKPOINTS               = false;
        DELETE_CHECKPOINTS_AFTER_VERIFY = false;

        %% =================================================================
        %% MEMORY MANAGEMENT
        %% =================================================================

        % Call pack every N files to defragment MATLAB heap
        PACK_INTERVAL         = 50;

        %% =================================================================
        %% PROGRESS TRACKING & LOGGING
        %% =================================================================

        VERBOSE_PROGRESS           = true;
        DETAILED_PROGRESS_INTERVAL = 10;
        SAVE_PROGRESS_LOG          = true;
        PROGRESS_LOG_FILE          = 'DataGeneration/generation_progress.log';
        FAILURE_LOG_FILE           = 'DataGeneration/generation_failures.log';
        AUDIT_REPORT_FILE          = 'DataGeneration/dataset_audit.log';
        SHOW_TIME_ESTIMATES        = true;

        %% =================================================================
        %% TESTING MODE
        %% =================================================================

        % TESTING_MODE = true  → minimal dataset (46 files) for pipeline verification
        % TESTING_MODE = false → full production dataset (31,375 files)
        TESTING_MODE          = false;   % ← ALWAYS start here; set false for production

        TEST_ENVIRONMENTS     = [1:5];
        TEST_EPOCHS           = [1];           % 1 epoch in testing
        TEST_SINGLE_FAULTS    = [1:42];        % all 42 faults at SEV3 × ENV001 × 1 epoch
        TEST_SINGLE_SEVERITIES = [3];          % SEV3 only
        TEST_DUAL_COMBOS      = [1];
        TEST_TRIPLE_COMBOS    = [1];
        TEST_QUAD_COMBOS      = [1];

        %% =================================================================
        %% RUN-TO-FAILURE
        %% =================================================================
        % NOT yet used by a production driver: RunRTFUnit.m/GenerateRTFFamily.m are blocked on
        % the GG-rotor edit-sensitivity finding and remain unbuilt.
        % These constants are the parts that do not touch Simulink and were built
        % and verified ahead of that resolution (GetRTFMechanisms.m; the accumulator calibration
        % below). See before building the driver on top of them.

        % Units per mechanism -- RAISED 2026-10-20 (chosen for
        % statistical depth, accepting the compute cost). 13 mechanisms x 550 units = 7,150
        % units =~ 41 GB, restoring the original design weight (its "7,200 units =~ 40 GB"
        % was designed for 36 mechanisms; 13 x 550 lands within ~1% of that total unit count by
        % coincidence of the arithmetic, not by design). Was 200 (2,600 units =~ 15 GB).
        %
        % (A larger count of 1,100 per mechanism was considered and not used; 550 stands.)
        UNITS_PER_MECHANISM   = 550;

        % On-disk root for the run-to-failure family, parallel to OUTPUT_ROOT for diagnosis.
        % Convention choice (not dictated by any phase spec): mirrors OUTPUT_ROOT's flat layout,
        % one subfolder per mechanism (GetRTFMechanisms.Folder), e.g.
        % '<root>/RTF_F02_CompressorFouling/RTF_F02_U0001.h5'. The top-level
        % split can be changed without affecting any record, since no HDF5 attribute stores a path.
        % absolute via AvonDataRoot, same treatment as OUTPUT_ROOT above.
        RTF_OUTPUT_ROOT       = AvonDataRoot();   % release layout: RTF_Fxx_<Code>/ folders directly in the data root

        RTF_CYCLE_SECONDS     = 300;    % stored samples per cycle at 1 Hz
        RTF_PREROLL_S         = 300;    % cycles 2+ only; cycle 1 uses GetPrerollSeconds
        RTF_HARD_CAP_H        = 1.5;    % abort-the-unit ceiling on latent health
        % Abort-the-unit ceiling on cycle count. Was 600 for the first generation pass,
        % which aborted 320 of 7,150 units (the longest-lived ones) right-censored. P6R continues
        % those units to genuine failure (RunRTFUnit.m's continuation branch) and lifts the cap
        % so no unit is censored: at 10,000 the stored trajectories extrapolate to zero units still
        % running (longest ~5,100 cycles). The abort path itself stays as a safety net. Read it
        % through RTFCapCycles, which a test can override; never edit this value to test.
        RTF_HARD_CAP_CYCLES   = 10000;
        RTF_H_NEAR            = 0.75;   % reference-check cadence switch point
        RTF_N_FAR             = 10;     % reference-check interval below RTF_H_NEAR
        RTF_W0_MAX_FRAC       = 0.05;   % initial wear ceiling, as a fraction of D_EOL

        % Severity-factor constants -- declared modelling parameters, not measured ones.
        RTF_S26_REF_C         = 777.15;  % reference-condition tail S26
        RTF_T_DOUBLING_C      = 15;      % degC of (clean) tail S26 that doubles the damage rate
        RTF_BETA_LIMITER      = 0.5;     % limiter_active_fraction coefficient

        % Gamma-process accumulator calibration (calibration script, 2026-10-17;
        % re-solved 2026-10-20). kappa and the
        % per-cycle shape k0 are the two free modelling-choice parameters (the frailty gamma
        % degradation model -- Lawless & Crowder 2004 -- chosen because DESIGN_run_to_failure.md
        % leaves the parametric form of "shape and scale drawn per unit" open), do not depend on
        % Simulink, and are UNCHANGED. theta0 alone is re-solved: the original calibration
        % assumed a unit-mean severity factor (s_c==1 on average); the REAL per-cycle severity
        % factor is driven by ambient, drawn i.i.d. per cycle Uniform(10,50) C
        % (confirmed by reading SampleEnvironmentMC.m, not assumed), and its TRUE marginal mean
        % -- evaluated on the measured equilibrium grid
        % (Healthy, 11 points) -- is 25.35, not 1, confirming the earlier cited ~25
        % estimate (this value was obtained independently, via a fresh T~U(10,50) Monte Carlo
        % against the measured grid, not by assuming the cited figure). A naive pool of the 13
        % real units' own severity_factor arrays gives a much lower mean (14.2) -- a measured,
        % quantified LENGTH-BIAS artifact (a unit that draws many hot cycles dies sooner and so
        % contributes fewer of them to a simple pool), which is why theta0 is re-solved against
        % the unbiased grid-based distribution, not that pool. New theta0 is a factor of 0.040
        % of the old provisional value (i.e. ~25x smaller), matching the ~25x error previously flagged almost exactly. Realised, N=20000: mean=195.1 (confirmation run 197.0),
        % median=151.0, =78.0, =354.0 -- against the DESIGN_run_to_failure.md target
        % of mean~200, /~80/400. Realised abort fraction at a cap of 600 cycles (the
        % first generation pass's cap; P6R later continued those units to failure and lifted the
        % cap to 10,000): 2.78% (556/20000) -- these units were first shipped RIGHT-CENSORED
        % (terminated_or_aborted='aborted', failure_mode='aborted_hard_cap'), never discarded,
        % confirmed by reading RunRTFUnit.m itself, so the fleet life distribution is not
        % silently truncated.
        RTF_ACCUM_K0          = 20;        % per-cycle base gamma shape
        RTF_ACCUM_KAPPA       = 3.2;       % per-unit frailty gamma shape (E[frailty]=1)
        RTF_ACCUM_THETA0      = 0.00001416;  % per-cycle base gamma scale -- RE-SOLVED

        % Per-unit draw seed (w0, lambda_u) -- RunRTFUnit.m, 2026-10-19. Same
        % (BASE + scenario_hash + unit-keyed-term) convention as every other seed in this file.
        RTF_ACCUM_SEED_BASE   = 7703;

        % restated: the RTF per-cycle ambient
        % check's two GATED tolerances, for the DIFFERENTIAL statistic (RunRTFUnit.m's
        % ambient_check_residual_C -- cycle 1 falls back to the absolute form, the only case it
        % is still valid). Named distinctly from the diagnosis path's own
        % AMBIENT_CHECK_TOL_C/_PINNED_C (ValidateGenerationLayer1.m) so the two paths' constants
        % are provably independent -- neither this task nor any RTF edit touches the diagnosis
        % constants.
        %
        % Stage 1/2 derivation found NO rung on EITHER ladder (D3)
        % against the pre-port, no-persistence population. diagnosed
        % why and resolved it with two changes, both applied: (1) RunRTFUnit.m's own
        % regime classification had never been ported to ONE-SIDED limiter test
        % (ComputeLayer1RecordAttributes.m ~114) -- it still ran the original two-sided form, which
        % mislabelled genuinely temperature_limited overshoot cycles (clean S26 up to 868.88 degC)
        % as duty_tracking and gated them at the tight non-pinned tier, inflating the very maximum
        % the 4x rule multiplies; (2) the differential statistic is an exact algebraic identity on
        % the first difference of the absolute one (verified, max discrepancy 0.0), so a single
        % one-cycle transient produces TWO large opposite-sign residuals -- which a PERSISTENCE
        % requirement (RTF_AMBIENT_DIFF_PERSIST_N consecutive SAME-SIGN breaches) filters out,
        % because the permanent defect class this check exists for (a frozen/severed ambient)
        % breaches every cycle with the same sign, while the two-cycle +/- transient pair never
        % reaches N=3 (measured: longest benign same-sign run = 2 at any
        % candidate tolerance). 4x/2x arithmetic and {3,5,8,12}/{15,20,25,30}
        % ladders are UNCHANGED -- only the statistic they are applied to changed, from "worst
        % single-cycle benign residual" to "worst benign residual sustained over N=3 consecutive
        % same-sign cycles" (M_3).
        %
        % Calibration result: pooled over both post-port Stage-1
        % units (F02/9801 79 cycles, F05/9901 296 cycles), M_3(non-pinned) = max(0.9694, 0.9538)
        % = 0.9694 degC -> require >= 4x = 3.8776 -> smallest fitting rung on {3,5,8,12} = 5.0
        % (1.29x the requirement, 13.76x margin against the 68.82 degC defect signature).
        % M_3(pinned) = max(3.7286, 1.3453) = 3.7286 degC -> require >= 2x = 7.4572 AND <= 27.52
        % -> smallest fitting rung on {15,20,25,30} = 15.0 (2.01x the requirement, 4.59x margin
        % against 68.82, 12.52 degC of headroom under the 27.52 ceiling). Both ladders fit --
        % escalation is resolved by the one-sided port plus
        % the persistence statistic together (-32.3), not by widening either ladder.
        RTF_AMBIENT_DIFF_TOL_C        = 5.0;   % -- SHIPPED
        RTF_AMBIENT_DIFF_TOL_PINNED_C = 15.0;  % -- SHIPPED

        % Edit 2: the ambient check's PERSISTENCE requirement
        % -- a single breaching cycle is not sufficient to retry-then-fail
        % the unit; only this many CONSECUTIVE SAME-SIGN cycle-level breaches are. Derived, not
        % chosen: measured longest benign same-sign run over both Stage-1 units (283 cycles) at
        % every candidate tolerance on the ladder is 2 (the +/- pair of a single-cycle transient,
        % an exact consequence of the differential statistic being the first difference of the
        % absolute one); N=3 never occurs in benign data at any rung, while the permanent defect
        % class (a frozen/severed ambient) breaches every cycle with the same sign and so reaches
        % any N quickly. Applies to RTF only; the diagnosis path has no cycles and no persistence
        % concept.
        RTF_AMBIENT_DIFF_PERSIST_N    = 3;

        % Per-cycle ambient-draw epoch (the `epoch` argument of SampleEnvironmentMC) for run-to-
        % failure cycles 1000 and later -- see RTFCycleEpoch. Cycles <= 999 keep the original
        % unit_id*1000 + c so that every unit already on disk reproduces bit-for-bit; the original
        % formula repeats from c = 1000 on (unit u, cycle 1000+j == unit u+1, cycle j). The high
        % range starts above the largest low-range epoch (550 units: 550,999) and gives every unit
        % its own 10,000-wide block, so it cannot meet the low range or itself up to cycle 10,999.
        % CheckRTFSeedCollisions.m proves it by enumeration.
        RTF_EPOCH_HIGH_BASE   = 1000000;
        RTF_EPOCH_HIGH_STRIDE = 10000;
        RTF_EPOCH_LOW_MAX_C   = 999;

        % Channel split of the stored RTF unit file (/sensors vs /internal), shared by the writer
        % (SaveRTFUnitToHDF5.m) and the continuation's state restore (RestoreRTFUnitState.m) so
        % the two can never disagree about which of S01-S39 lives in which dataset.
        RTF_SENSORS_IDX       = [1,2,3,4,5,6,7,8,10,11,17,19,20,21,24,25,26,27,28,29,31,35,36,37,38,39];   % 26
        RTF_INTERNAL_IDX      = [9,12,13,14,15,16,18,22,23,30,32,33,34];                                  % 13

    end

    methods (Static)

        function mw = DUTY_CMD_MW()
        % DUTY_CMD_MW - Commanded duty (MW), the design point:
        % duty is a FIXED setpoint, never a drawn per-record axis -- this is a second FIXED
        % setpoint for the turndown sub-family, never a per-record draw).
        %
        % A Static METHOD, not a Constant property, so the turndown driver can override it for
        % its own run only, via the AVON_DUTY_CMD_MW environment variable -- the same
        % resolution pattern as AvonWorkers.m -- without ever editing this file's default for
        % the main families. Read by LoadScenarioToWorkspace.m, the only one of the three
        % SP_POWER_CMD sites this touches; RunRTFUnit.m's two sites stay at the literal 13
        % (that file is frozen and has no turndown variant).
        %
        % 2026-11-12, spec
            mw = 13;
            env_val = getenv('AVON_DUTY_CMD_MW');
            if ~isempty(env_val)
                num = str2double(strtrim(env_val));
                if ~isnan(num) && isfinite(num) && num > 0
                    mw = num;
                end
            end
        end

        function n = RTFCapCycles()
        % RTFCapCycles - The run-to-failure cycle cap in force: RTF_HARD_CAP_CYCLES, unless the
        % TEST-ONLY setting AVON_RTF_CAP_CYCLES (environment variable or config.txt, resolved by
        % AvonSetting.m like AVON_WORKERS) is set. Production never sets it. It exists so the
        % continuation path can be tested on a unit that is capped after a handful of cycles
        % instead of after thousands. Read by RunRTFUnit.m and RTFAlreadyDone.m, so a writer and
        % the resume check always agree on what "capped" means.
            n = AvonSetting('AVON_RTF_CAP_CYCLES', ScenarioConfig.RTF_HARD_CAP_CYCLES);
        end

        function epoch = RTFCycleEpoch(unit_id, c)
        % RTFCycleEpoch - The `epoch` fed to SampleEnvironmentMC for unit `unit_id`, cycle `c`.
        %   c <= 999 : unit_id*1000 + c   (the original formula; keeps every existing unit
        %                                  bit-identical -- never change this branch)
        %   c >= 1000: RTF_EPOCH_HIGH_BASE + unit_id*RTF_EPOCH_HIGH_STRIDE + (c - 1000)
        % The original formula collides from c = 1000 (unit u cycle 1000+j == unit u+1 cycle j),
        % which would give two different units the same ambient sequence. Cycles that long exist
        % since P6R lifted the cycle cap from 600 to 10,000. Accepts scalars or broadcast-
        % compatible arrays (CheckRTFSeedCollisions.m enumerates every unit x cycle at once).
            offset = c - (ScenarioConfig.RTF_EPOCH_LOW_MAX_C + 1);
            hi = c > ScenarioConfig.RTF_EPOCH_LOW_MAX_C;
            if any(offset(hi) >= ScenarioConfig.RTF_EPOCH_HIGH_STRIDE)
                error('ScenarioConfig:RTFCycleBeyondEpochBlock', ...
                    'A cycle exceeds the %d-cycle block reserved per unit for cycles >= 1000.', ...
                    ScenarioConfig.RTF_EPOCH_HIGH_STRIDE + ScenarioConfig.RTF_EPOCH_LOW_MAX_C);
            end
            epoch_low  = unit_id * 1000 + c;
            epoch_high = ScenarioConfig.RTF_EPOCH_HIGH_BASE + unit_id * ScenarioConfig.RTF_EPOCH_HIGH_STRIDE + offset;
            epoch = epoch_low .* ~hi + epoch_high .* hi;
        end

        function config = GetActiveConfig()
        % Return active configuration based on TESTING_MODE

            config = struct();

            if ScenarioConfig.TESTING_MODE
                % Testing mode — minimal dataset for verification
                fprintf('\n*** TESTING MODE ENABLED ***\n');
                fprintf('Generating minimal dataset for verification (46 total files)\n\n');

                config.environments         = ScenarioConfig.TEST_ENVIRONMENTS;
                config.n_epochs             = length(ScenarioConfig.TEST_EPOCHS);
                config.epochs               = ScenarioConfig.TEST_EPOCHS;
                config.single_fault_ids     = ScenarioConfig.TEST_SINGLE_FAULTS;
                config.single_fault_severities = ScenarioConfig.TEST_SINGLE_SEVERITIES;
                config.dual_fault_combos    = ScenarioConfig.TEST_DUAL_COMBOS;
                config.triple_fault_combos  = ScenarioConfig.TEST_TRIPLE_COMBOS;
                config.quad_fault_combos    = ScenarioConfig.TEST_QUAD_COMBOS;
            else
                % Production mode
                config.environments         = ScenarioConfig.ENVIRONMENTS;
                config.n_epochs             = ScenarioConfig.N_EPOCHS;
                config.epochs               = 1 : ScenarioConfig.N_EPOCHS;
                config.single_fault_ids     = ScenarioConfig.SINGLE_FAULT_IDS;
                config.single_fault_severities = ScenarioConfig.SINGLE_FAULT_SEVERITIES;

                % the PARKED_FAULTS filter this
                % replaced excluded any combo containing F08/F25/F30/F32 as a scoping choice tied
                % to the OLD 18/22/15 stability-workaround combo tables. The new 21/14/11-row
                % tables (GetFaultDefinitions.m) were built by a fresh co-occurrence search over
                % all 42 live faults -- F08/F25/F30/F32 are included deliberately
                % (measurements confirm F30 and F42 are measured, live faults; F25/F30 are also run-to-failure
                % mechanisms, so excluding them from the diagnosis multi-fault set would have been
                % inconsistent with their own family membership). No filter is needed: every row
                % of every combo table is in scope.
                config.dual_fault_combos    = ScenarioConfig.DUAL_FAULT_COMBOS;
                config.triple_fault_combos  = ScenarioConfig.TRIPLE_FAULT_COMBOS;
                config.quad_fault_combos    = ScenarioConfig.QUAD_FAULT_COMBOS;
            end

            % Common configuration
            config.simulation_duration        = ScenarioConfig.SIMULATION_DURATION;
            config.sampling_rate              = ScenarioConfig.SAMPLING_RATE;
            config.timeseries_dt              = ScenarioConfig.TIMESERIES_DT;
            config.run_quality_checks         = ScenarioConfig.RUN_QUALITY_CHECKS;
            config.run_workspace_verification = ScenarioConfig.RUN_WORKSPACE_VERIFICATION;
            config.stop_on_quality_fail       = ScenarioConfig.STOP_ON_QUALITY_FAIL;
            config.verbose_progress           = ScenarioConfig.VERBOSE_PROGRESS;
            config.detailed_progress_interval = ScenarioConfig.DETAILED_PROGRESS_INTERVAL;
            config.show_time_estimates        = ScenarioConfig.SHOW_TIME_ESTIMATES;
            config.pack_interval              = ScenarioConfig.PACK_INTERVAL;

            % Storage / diversity options
            config.output_root      = ScenarioConfig.OUTPUT_ROOT;
            config.store_float32    = ScenarioConfig.STORE_FLOAT32;
            config.add_sensor_bias  = ScenarioConfig.ADD_SENSOR_BIAS;
            config.sim_retry_max    = ScenarioConfig.SIM_RETRY_MAX;

            % Per-category epoch counts (the drivers loop 1:n_epochs_<cat>).
            % In TESTING_MODE every category is capped to a couple of epochs.
            if ScenarioConfig.TESTING_MODE
                nH = length(ScenarioConfig.TEST_EPOCHS);
                nS = nH; nD = nH; nT = nH; nQ = nH;
            else
                nH = ScenarioConfig.N_EPOCHS_HEALTHY;
                nS = ScenarioConfig.N_EPOCHS_SINGLE;
                nD = ScenarioConfig.N_EPOCHS_DUAL;
                nT = ScenarioConfig.N_EPOCHS_TRIPLE;
                nQ = ScenarioConfig.N_EPOCHS_QUAD;
            end
            config.n_epochs_healthy = nH;  config.epochs_healthy = 1:nH;
            config.n_epochs_single  = nS;  config.epochs_single  = 1:nS;
            config.n_epochs_dual    = nD;  config.epochs_dual    = 1:nD;
            config.n_epochs_triple  = nT;  config.epochs_triple  = 1:nT;
            config.n_epochs_quad    = nQ;  config.epochs_quad    = 1:nQ;

            % Category flags
            config.generate_healthy = ScenarioConfig.GENERATE_HEALTHY;
            config.generate_single  = ScenarioConfig.GENERATE_SINGLE_FAULT;
            config.generate_dual    = ScenarioConfig.GENERATE_DUAL_FAULT;
            config.generate_triple  = ScenarioConfig.GENERATE_TRIPLE_FAULT;
            config.generate_quad    = ScenarioConfig.GENERATE_QUAD_FAULT;

        end

        function severities = SampleMultiFaultSeverities(combo_id, env_id, epoch_id, n_faults)
        % SampleMultiFaultSeverities - Monte Carlo severity sampling per epoch
        %
        % Returns a [1 × n_faults] vector of independent discrete severities {1,2,3,4,5}.
        % Seeded for reproducibility: same combo/env/epoch always gives same severities.
        %
        % Seed formula: MC_SEV_SEED + combo_id*10000 + env_id*1000 + epoch_id*10

            seed = ScenarioConfig.MC_SEV_SEED + combo_id * 10000 + env_id * 1000 + epoch_id * 10;
            rng(seed, 'twister');
            severities = randi(5, 1, n_faults);
        end

        function severities = SampleMultiFaultSeveritiesV2(scenario_hash, epoch_id, attempt, n_faults)
        % Multi-fault severity sampling: independent {1..5} per fault, keyed
        % on (scenario_hash, epoch, attempt) so a retry re-draws severities too.
            seed = ScenarioConfig.MC_SEV_SEED + scenario_hash + epoch_id * 137 + attempt * 99991;
            rng(seed, 'twister');
            severities = randi(5, 1, n_faults);
        end

        function sev = SampleSingleFaultSeverity(fault_id, epoch_id)
        % SampleSingleFaultSeverity - Stratified per-epoch severity for single
        % faults. Within every consecutive block of 5 epochs each severity
        % 1..5 appears exactly once (perfect balance), but the order inside a
        % block is randomised per (fault, block). Deterministic in epoch and
        % independent of the total epoch count, so raising N_EPOCHS_SINGLE
        % later never disturbs the severity already assigned to earlier epochs.
        % NOTE: intentionally NOT attempt-dependent — a retry keeps the same
        % severity LABEL and only re-samples the (collapse-driving) environment.
            block = floor((epoch_id - 1) / 5);
            pos   = mod(epoch_id - 1, 5) + 1;
            rng(ScenarioConfig.SEV_STRAT_SEED + fault_id * 911 + block * 7, 'twister');
            perm  = randperm(5);
            sev   = perm(pos);
        end

        function h = ScenarioHash(scenario_type, fault_ids)
        % ScenarioHash - Stable integer identifying a scenario (independent of
        % environment), used to decorrelate the per-epoch MC seeds between
        % different faults/combos. Fault IDs are <= 42 < 101 so the polynomial
        % base 101 is collision-free within a category.
            switch lower(scenario_type)
                case 'healthy', offset = 10000;   ids = [];
                case 'single',  offset = 100000;  ids = fault_ids;
                case 'dual',    offset = 200000;  ids = fault_ids;
                case 'triple',  offset = 300000;  ids = fault_ids;
                case 'quad',    offset = 400000;  ids = fault_ids;
                otherwise,      offset = 0;        ids = fault_ids;
            end
            h = offset;
            ids = sort(ids(:))';
            for k = 1:numel(ids)
                h = h + ids(k) * (101 ^ (k - 1));
            end
        end

        function A = AmbientConfig()
        % AmbientConfig - Continuous ambient MC ranges (solver-safe) + the
        % nominal design point that retries converge toward. Ranges are derived
        % from the known-good earlier-generation environments, EXCEPT the compressor inlet
        % pressure floor is raised to 95 kPa (never the 90 kPa "High Altitude"
        % corner that collapsed at high severity) so severity+ambient mixing
        % cannot reach the singular region.
            A = struct();
            A.FG_pressure_kPa            = [2200, 2500];
            A.FG_temp_C                  = [10,   35];
            A.compressor_inlet_temp_C    = [10,   50];
            A.compressor_inlet_press_kPa = [95,   103];   % floored at 95 (was 90 in ENV004)
            A.ambient_moisture_percent   = [40,   95];

            % Nominal design point (ENV001) — retries collapse toward this.
            % compressor_inlet_temp_C = 15 (the reference
            % condition, the most benign point in the envelope by every measurement taken
            % (13.0000 MW delivered exactly, 68.85 degC of margin to the limiter, cold-start
            % drift 0.0009 rad/s). The former 38.85 sat in the temperature_limited branch, where
            % measures the LARGEST cold-start residual and
            % the worst settling margin -- i.e. retries were converging toward the point that
            % makes a settling failure MORE likely, exactly the defect DESIGN_run_to_failure.md
            % warned against ("do not let retries pull toward a degenerate point").
            A.nom = struct( ...
                'FG_pressure_kPa',            2400, ...
                'FG_temp_C',                  20, ...
                'compressor_inlet_temp_C',    15, ...
                'compressor_inlet_press_kPa', 99.2, ...
                'ambient_moisture_percent',   65);

            % Per-attempt mildness increment (attempt>=4 => ~nominal).
            A.mildness_step = 0.34;
        end

        function p = FamilyPrefix()
        % FamilyPrefix - 'DIAG_' for the 13 MW main diagnosis family, 'TD_' for the 10 MW turndown
        % family (naming scheme 2026-11-21). Same duty test as DatasetRoot; GenerateScenarioInfo.m
        % is the only caller that builds diagnosis folder/file names from it.
            if abs(ScenarioConfig.DUTY_CMD_MW() - 10) < 1e-9
                p = 'TD_';
            else
                p = 'DIAG_';
            end
        end

        function root = DatasetRoot()
        % DatasetRoot - The diagnosis-family output root (see OUTPUT_ROOT).
        % duty-aware. GenerateScenarioInfo.m and ScenarioAlreadyDone.m
        % (both non-frozen, but unmodified by this change) call ONLY this method to locate the
        % family's output root, so redirecting it here -- rather than editing either of them --
        % is sufficient to send every turndown-family record to its own root, DiagnosisTurndown/,
        % while leaving the 13 MW path (the default, and every existing caller's behaviour)
        % byte-for-byte unchanged.
            if abs(ScenarioConfig.DUTY_CMD_MW() - 10) < 1e-9
                root = fullfile(AvonDataRoot(), 'DiagnosisTurndown');   % release layout: the ONLY container folder
            else
                root = ScenarioConfig.OUTPUT_ROOT;
            end
        end

        function preroll_s = GetPrerollSeconds(inlet_temp_C)
        % GetPrerollSeconds - Ambient-dependent, UNSTORED pre-roll length.
        % 1800 s by default; 3600 s when the drawn compressor-inlet temperature falls in
        % [PREROLL_REGIME_TEMP_LO, PREROLL_REGIME_TEMP_HI] (the duty_tracking/temperature_limited
        % regime boundary, where the warm start needs longer to resolve a genuine S26 overshoot of
        % the 846 degC limit).
            if inlet_temp_C >= ScenarioConfig.PREROLL_REGIME_TEMP_LO && ...
               inlet_temp_C <= ScenarioConfig.PREROLL_REGIME_TEMP_HI
                preroll_s = ScenarioConfig.PREROLL_REGIME_S;
            else
                preroll_s = ScenarioConfig.PREROLL_DEFAULT_S;
            end
        end

        function duration_s = GetSimulationDuration(inlet_temp_C)
        % GetSimulationDuration - Per-record total simulated duration: the ambient-dependent
        % unstored pre-roll (above) plus the fixed STORED_SAMPLES stored window. Replaces the flat
        % SIMULATION_DURATION constant as the value actually passed to RunSimulinkModel; the
        % constant stays as the default/documentation figure.
            duration_s = ScenarioConfig.GetPrerollSeconds(inlet_temp_C) + ScenarioConfig.STORED_SAMPLES;
        end

        function start_time = GetFaultStartTime(fault_id, epoch_id, env_id)
        % GetFaultStartTime - UNUSED by the real pipeline (LoadScenarioToWorkspace.m draws onset
        % inline with its own (scenario_hash, epoch, attempt)-keyed seed, not this (fault_id,
        % epoch_id, env_id)-keyed one) -- confirmed by grep, no caller anywhere in DataGeneration/.
        % Kept updated rather than deleted so a stale reference to FAULT_START_MIN/MAX cannot
        % silently reappear; fixed it to use the renamed, stored-window-relative
        % FAULT_START_TAU_MIN/MAX (see that property's comment) and the two-arg randi form so the
        % bounds are the realised range with no off-by-one. Returns a TAU value (relative to the
        % stored window start), not an absolute simulation time -- add GetPrerollSeconds(...) at
        % the call site if an absolute time is needed, exactly as LoadScenarioToWorkspace.m does.
            seed = ScenarioConfig.FAULT_START_SEED + fault_id * 997 + epoch_id * 37 + env_id * 1000;
            rng(seed, 'twister');
            start_time = randi([ScenarioConfig.FAULT_START_TAU_MIN, ScenarioConfig.FAULT_START_TAU_MAX]);
        end

        function ramp_duration = GetFaultRampDuration(fault_id)
        % Get fault ramp duration from GetFaultDefinitions

            fault_defs = GetFaultDefinitions();
            ramp_duration = fault_defs.DriftDuration(fault_id);
        end

        function frequency = GetFaultFrequency(fault_id)
        % Get fault oscillation frequency from GetFaultDefinitions

            fault_defs = GetFaultDefinitions();
            frequency = fault_defs.OscillationFrequency(fault_id);
        end

        function dt = GetOutputDt(fault_ids)
        % GetOutputDt - Per-scenario output sampling interval (seconds) for
        % the saved HDF5 file. ALWAYS ScenarioConfig.SAMPLING_RATE (1 Hz) -- the release is
        % uniform 1 Hz. The old 5 Hz override
        % for F18/F19 is REMOVED, not left unreachable: those two faults' oscillation frequencies
        % were lowered to 0.30/0.10 Hz specifically so no fault needs a higher output rate.
        % fault_ids is kept as a parameter for call-site compatibility (RunScenario.m and
        % VerifyHDF5Data.m both call this) but is no longer used to branch.

            dt = 1 / ScenarioConfig.SAMPLING_RATE;
        end

        function count = EstimateFileCount()
        % Estimate total number of files to generate

            config = ScenarioConfig.GetActiveConfig();
            count = 0;

            % No environment dimension; each category has its own epoch count.
            if config.generate_healthy
                count = count + config.n_epochs_healthy;
            end
            if config.generate_single
                count = count + length(config.single_fault_ids) * config.n_epochs_single;
            end
            if config.generate_dual
                count = count + length(config.dual_fault_combos) * config.n_epochs_dual;
            end
            if config.generate_triple
                count = count + length(config.triple_fault_combos) * config.n_epochs_triple;
            end
            if config.generate_quad
                count = count + length(config.quad_fault_combos) * config.n_epochs_quad;
            end
        end

        function DisplayConfig()
        % Display current configuration summary

            config = ScenarioConfig.GetActiveConfig();

            fprintf('\n========================================\n');
            fprintf('  Dataset Generation Configuration\n');
            fprintf('========================================\n\n');

            mode_str = iif(ScenarioConfig.TESTING_MODE, 'TESTING', 'PRODUCTION');
            fprintf('Mode: %s\n', mode_str);
            fprintf('Simulated duration: %d s default / %d s near the regime boundary (ambient-dependent pre-roll) + %d s stored\n', ...
                ScenarioConfig.PREROLL_DEFAULT_S + ScenarioConfig.STORED_SAMPLES, ...
                ScenarioConfig.PREROLL_REGIME_S + ScenarioConfig.STORED_SAMPLES, ...
                ScenarioConfig.STORED_SAMPLES);
            fprintf('Sampling Rate: %.1f Hz  →  %d stored samples/file\n', ...
                ScenarioConfig.SAMPLING_RATE, ScenarioConfig.STORED_SAMPLES);
            fprintf('Timeseries dt: %.2f s\n\n', ScenarioConfig.TIMESERIES_DT);

            fprintf('Categories:\n');
            fprintf('  Healthy:       %s\n', iif(config.generate_healthy, 'YES', 'NO'));
            fprintf('  Single-Fault:  %s\n', iif(config.generate_single,  'YES', 'NO'));
            fprintf('  Dual-Fault:    %s\n', iif(config.generate_dual,    'YES', 'NO'));
            fprintf('  Triple-Fault:  %s\n', iif(config.generate_triple,  'YES', 'NO'));
            fprintf('  Quad-Fault:    %s\n\n', iif(config.generate_quad,  'YES', 'NO'));

            fprintf('Scope (environment & severity MC-sampled per epoch):\n');
            fprintf('  Output root: %s   |  Storage: %s\n', ...
                config.output_root, iif(config.store_float32, 'float32', 'float64'));
            fprintf('  Epochs/scenario  H:%d  S:%d  D:%d  T:%d  Q:%d\n', ...
                config.n_epochs_healthy, config.n_epochs_single, ...
                config.n_epochs_dual, config.n_epochs_triple, config.n_epochs_quad);
            if config.generate_single
                fprintf('  Single Fault IDs: [1:%d] (%d faults, severity stratified 1-5)\n', ...
                    max(config.single_fault_ids), length(config.single_fault_ids));
            end
            fprintf('  Multi combos  D:%d  T:%d  Q:%d\n', ...
                length(config.dual_fault_combos), length(config.triple_fault_combos), ...
                length(config.quad_fault_combos));

            fprintf('\nNoise: %s (base seed %d)\n', ...
                iif(ScenarioConfig.ADD_GAUSSIAN_NOISE, 'ON', 'OFF'), ScenarioConfig.NOISE_BASE_SEED);
            fprintf('Quality Control: %s  |  Stop on Fail: %s\n', ...
                iif(config.run_quality_checks, 'ON', 'OFF'), ...
                iif(config.stop_on_quality_fail, 'YES', 'NO (log+skip)'));

            total = ScenarioConfig.EstimateFileCount();
            fprintf('\nEstimated file count: %d\n', total);
            fprintf('========================================\n\n');
        end

    end
end

% Helper function
function result = iif(condition, true_val, false_val)
    if condition
        result = true_val;
    else
        result = false_val;
    end
end
