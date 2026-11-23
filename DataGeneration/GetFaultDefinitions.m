function fault_defs = GetFaultDefinitions()
% GetFaultDefinitions - Returns all 42 fault definitions for dataset generation
%
% Returns struct with:
%   Count              - 42 (all faults active, no remapping)
%   Names              - {42×1} fault names (F01-F42 = dataset labels = Simulink IDs)
%   Codes              - {42×1} CamelCase folder-name tokens (fault_catalogue.csv 'code')
%   Group              - {42×1} group labels
%   ProfileType        - {42×1} 'step', 'linear_ramp', or 'oscillate'
%   Factor             - [42×1] degradation/enhancement factor
%   DriftStartTime     - [42×1] default start time (s) — overridden per epoch
%   DriftDuration      - [42×1] ramp duration (s); 0 for step/oscillate
%   OscillationFrequency - [42×1] Hz; non-zero only for oscillate faults
%   IsEnhancement      - [42×1] logical; true = multiplier > 1.0
%   DualCombos         - [21×2]  dual-fault combinations (rebuild)
%   TripleCombos       - [14×3]  triple-fault combinations
%   QuadCombos         - [11×4]  quad-fault combinations
%
% NOTE: F01-F42 directly match Simulink workspace variables FAULT_01-FAULT_42.
%       No DatasetID remapping needed — Simulink ID = dataset column label.
%
% NOTE: F37 (GG temp sensor freeze) uses Switch+Memory pattern in Simulink.
%       ProfileType = 'freeze'; Factor = 1.0 (placeholder — not used in multiplier calc).
%       GetFaultMultiplier returns 0.0 directly for F37 (< 0.5 threshold triggers freeze).
%       GenerateFaultMultiplierArray handles 'freeze' as a dedicated profile case.
%
% Date: 2026-03-14 — Complete rebuild for unified F01-F42 system

fault_defs.Count = 42;

%% Fault Names
%% Source of truth: FaultReference/fault_catalogue.csv (columns fault_id, code, name); CheckNamingConsistency.m
%% asserts this table, Codes and GetRTFMechanisms.m equal the CSV exactly. 'name' is the human-readable
%% fault name written to the HDF5 attribute fault_name; 'code' is the CamelCase token used in folder names.
fault_defs.Names = {
    'Air intake filter fouling (intake pressure-loss increase)';  % F01
    'Compressor fouling (isentropic-efficiency loss)';  % F02
    'Compressor blade damage (isentropic-efficiency loss)';  % F03
    'Compressor air-flow step loss (stall surrogate)';  % F04
    'Diffuser damage (pressure-ratio loss)';  % F05
    'Inlet guide vane stuck (IGV opening offset from demand)';  % F06
    'Fuel gas pressure regulator stuck (line-pressure error)';  % F07
    'Fuel valve leakage (fuel-flow loss)';  % F08
    'Fuel contamination (fuel-flow error)';  % F09
    'Fuel line blockage (fuel-flow restriction)';  % F10
    'Fuel pump degradation (fuel line-pressure loss)';  % F11
    'Fuel gas regulated-pressure loss';  % F12
    'Fuel gas regulated-pressure oscillation (0.05 Hz)';  % F13
    'Fuel gas valve partial opening (valve-position loss)';  % F14
    'Fuel gas valve actuator gain loss';  % F15
    'Combustor liner distress (combustor air-flow loss surrogate)';  % F16
    'Fuel nozzle clogging (combustor fuel-flow restriction)';  % F17
    'Low-frequency heat-release oscillation, 0.30 Hz (combustor exit-temperature surrogate)';  % F18
    'Low-frequency combustion oscillation, 0.10 Hz (combustor exit-temperature surrogate)';  % F19
    'Hot gas path temperature increase';  % F20
    'GG turbine fouling (efficiency loss)';  % F21
    'GG turbine blade damage (efficiency loss)';  % F22
    'GG nozzle blockage (hot-gas flow restriction)';  % F23
    'GG seal degradation (cooling-air leakage increase)';  % F24
    'GG turbine inlet pressure loss';  % F25
    'PT fouling (efficiency loss)';  % F26
    'PT blade damage (efficiency loss)';  % F27
    'PT nozzle damage (hot-gas flow change)';  % F28
    'PT inlet temperature perturbation';  % F29
    'PT mechanical-loss increase (bearing-wear surrogate)';  % F30
    'PT delivered power loss';  % F31
    'Exhaust stack blockage (back-pressure increase)';  % F32
    'GG temperature sensor drift (+)';  % F33
    'GG temperature sensor drift (-)';  % F34
    'GG temperature sensor bias (+)';  % F35
    'GG temperature sensor bias (-)';  % F36
    'GG temperature sensor freezing';  % F37
    'GG speed sensor gain error';  % F38
    'PT speed sensor gain error';  % F39
    'Fuel gas flowmeter offset';  % F40
    'Fuel gas flowmeter drift';  % F41
    'Power-control loop oscillation (0.2 Hz on PID4 output)';  % F42
};

%% Fault Codes (folder-name tokens: DIAG_Fxx_<code>, RTF_Fxx_<code>)
fault_defs.Codes = {
    'AirIntakeFilterFouling';  % F01
    'CompressorFouling';  % F02
    'CompressorBladeDamage';  % F03
    'CompressorFlowLoss';  % F04
    'DiffuserDamage';  % F05
    'IGVStuck';  % F06
    'FuelRegulatorStuck';  % F07
    'FuelValveLeakage';  % F08
    'FuelContamination';  % F09
    'FuelLineBlockage';  % F10
    'FuelPumpDegradation';  % F11
    'FGRegulatedPressureLoss';  % F12
    'FGPressureOscillation';  % F13
    'FGValvePartialOpening';  % F14
    'FGValveActuatorGainLoss';  % F15
    'LinerDistress';  % F16
    'NozzleClogging';  % F17
    'HeatReleaseOscillation';  % F18
    'CombustionOscillation';  % F19
    'HotGasPathOvertemperature';  % F20
    'GGTurbineFouling';  % F21
    'GGBladeDamage';  % F22
    'GGNozzleBlockage';  % F23
    'GGSealDegradation';  % F24
    'GGInletPressureLoss';  % F25
    'PTFouling';  % F26
    'PTBladeDamage';  % F27
    'PTNozzleDamage';  % F28
    'PTInletTempPerturbation';  % F29
    'PTMechanicalLoss';  % F30
    'PTPowerLoss';  % F31
    'StackBlockage';  % F32
    'GGTempSensorDriftPos';  % F33
    'GGTempSensorDriftNeg';  % F34
    'GGTempSensorBiasPos';  % F35
    'GGTempSensorBiasNeg';  % F36
    'GGTempSensorFreeze';  % F37
    'GGSpeedSensorGainError';  % F38
    'PTSpeedSensorGainError';  % F39
    'FuelFlowmeterOffset';  % F40
    'FuelFlowmeterDrift';  % F41
    'ControlLoopOscillation';  % F42
};

%% Group Labels
fault_defs.Group = {
    'Air Intake';   % F01
    'Compressor';   % F02
    'Compressor';   % F03
    'Compressor';   % F04
    'Compressor';   % F05
    'Compressor';   % F06
    'Fuel System';  % F07
    'Fuel System';  % F08
    'Fuel System';  % F09
    'Fuel System';  % F10
    'Fuel System';  % F11
    'Fuel System';  % F12
    'Fuel System';  % F13
    'Fuel System';  % F14
    'Fuel System';  % F15
    'Combustor';    % F16
    'Combustor';    % F17
    'Combustor';    % F18
    'Combustor';    % F19
    'Combustor';    % F20
    'GG Turbine';   % F21
    'GG Turbine';   % F22
    'GG Turbine';   % F23
    'GG Turbine';   % F24
    'GG Turbine';   % F25
    'PT Turbine';   % F26
    'PT Turbine';   % F27
    'PT Turbine';   % F28
    'PT Turbine';   % F29
    'PT Turbine';   % F30
    'PT Turbine';   % F31
    'Exhaust';      % F32
    'Sensor';       % F33
    'Sensor';       % F34
    'Sensor';       % F35
    'Sensor';       % F36
    'Sensor';       % F37
    'Sensor';       % F38
    'Sensor';       % F39
    'Sensor';       % F40
    'Sensor';       % F41
    'Controller';   % F42
};

%% Profile Types
% 'step'        - Instant activation at fault_start_time
% 'linear_ramp' - Linear degradation over DriftDuration seconds
% 'oscillate'   - Sinusoidal variation at OscillationFrequency Hz
fault_defs.ProfileType = {
    'linear_ramp';  % F01: Filter fouling (gradual, 40 min)
    'linear_ramp';  % F02: Blade fouling (gradual, 40 min)
    'step';         % F03: Blade damage (sudden)
    'step';         % F04: Surge/stall (instant)
    'step';         % F05: Diffuser damage (sudden)
    'step';         % F06: IGV stuck (instant)
    'step';         % F07: Regulator stuck (instant)
    'linear_ramp';  % F08: Valve leakage (gradual, 30 min)
    'step';         % F09: Contamination (sudden)
    'linear_ramp';  % F10: Line blockage (gradual, 20 min)
    'linear_ramp';  % F11: Pump degradation (gradual, 40 min)
    'step';         % F12: Pressure drop (instant)
    'oscillate';    % F13: Pressure oscillation (0.05 Hz)
    'step';         % F14: Valve partial open (stuck)
    'step';         % F15: Actuator delay (constant lag)
    'step';         % F16: Liner damage (sudden)
    'linear_ramp';  % F17: Nozzle clogging (gradual, 30 min)
    'oscillate';    % F18: Flame oscillation (1.0 Hz)
    'oscillate';    % F19: Combustion instability (0.5 Hz)
    'linear_ramp';  % F20: Hot gas temp increase (gradual, 40 min)
    'linear_ramp';  % F21: GG fouling (gradual, 60 min)
    'linear_ramp';  % F22: GG blade damage (progressive fatigue/erosion, 30 min)
    'linear_ramp';  % F23: GG nozzle blockage (gradual, 30 min)
    'linear_ramp';  % F24: GG seal degradation (gradual, 40 min)
    'linear_ramp';  % F25: GG bearing wear (gradual, 60 min)
    'linear_ramp';  % F26: PT fouling (gradual, 60 min)
    'step';         % F27: PT blade damage (sudden)
    'step';         % F28: PT nozzle damage (sudden)
    'linear_ramp';  % F29: PT seal degradation (gradual, 40 min)
    'linear_ramp';  % F30: PT bearing wear (gradual, 60 min)
    'step';         % F31: PT power loss (instant)
    'linear_ramp';  % F32: Stack blockage (gradual, 40 min)
    'linear_ramp';  % F33: GG temp drift + (gradual, 20 min)
    'linear_ramp';  % F34: GG temp drift - (gradual, 20 min)
    'step';         % F35: GG temp bias + (constant offset)
    'step';         % F36: GG temp bias - (constant offset)
    'freeze';       % F37: GG temp freeze (Switch+Memory; see faults_configuration.md)
    'step';         % F38: GG speed sensor (bias/stuck)
    'step';         % F39: PT speed sensor (bias/stuck)
    'step';         % F40: Flowmeter offset/failure (step)
    'linear_ramp';  % F41: Flowmeter drift (gradual, 20 min)
    'oscillate';    % F42: Control instability (0.2 Hz)
};

%% SEV1 deviation — the noise-referenced detection threshold
% delta at which z(delta) = k*sigma_window on the fault's target_channel_observable, k=12,
% calibrated on the four instrument-uncertainty anchors (F38/F39 ISO 2314, F40/F41 Coriolis),
%. Interpolated only (never extrapolated
% obligation 2) from the measured delta-grid (38 untouched
% faults) (F15/F16/F30/F42, re-measured aftera
% model corrections) (the 16 faults whose z already exceeded
% k at the old Factor/100 floor). Full derivation and per-fault notes,
%a sections. F37 (freeze) has no depth axis; placeholder 0.0, unused —
% GetFaultMultiplier.m returns 0.0 directly for any active F37 severity.
fault_defs.Sev1Deviation = [
    0.000761;  % F01
    0.000637;  % F02
    0.000637;  % F03
    0.001024;  % F04
    0.002272;  % F05
    0.002135;  % F06
    0.000088;  % F07
    0.007391;  % F08
    0.007383;  % F09
    0.007387;  % F10
    0.000090;  % F11
    0.000090;  % F12
    0.000092;  % F13
    0.002962;  % F14
    0.002974;  % F15 -- re-derived post-split (a); new target channel S03
    0.001033;  % F16 -- re-derived post-split (a); new target channel S10
    0.002560;  % F17
    0.002000;  % F18 -- RE-MEASURED after moved F18 to 0.30 Hz: self-resolved
               % exactly as predicted -- z already >=12 at the grid floor on the re-derived target
               % channel S10 (z=14.82), not the old 1.00 Hz carrier's max z=1.432. No longer
               % low_dynamic_range_flag. See.
    0.008542;  % F19
    0.001732;  % F20
    0.000234;  % F21
    0.000237;  % F22
    0.001013;  % F23
    0.000737;  % F24
    0.000197;  % F25
    0.000310;  % F26
    0.000316;  % F27
    0.000401;  % F28
    0.000640;  % F29
    0.150000;  % F30 -- flagged placeholder: z never reaches k=12 anywhere even aftera
               % Loss-gain rewire (max z=0.002 at Factor) for the torque-balance
               % diagnostic (Sum7, not Sum9, is the term that nulls at equilibrium).
    0.000353;  % F31
    0.005247;  % F32
    0.001102;  % F33
    0.001102;  % F34
    0.001102;  % F35
    0.001102;  % F36
    0.000000;  % F37 -- unused placeholder (freeze special-case in GetFaultMultiplier)
    0.001097;  % F38
    0.001097;  % F39
    0.001917;  % F40
    0.001917;  % F41
    0.028040;  % F42 -- re-derived post-rewire (a); new target channel S10, duty_tracking
               % reference condition (regime-conditional: masked in temperature_limited records)
];

%% SEV5 deviation — the model's own top severity; replaces the old
%% linear Factor array. Same cutoff/literature anchoring rule as before:
%% cutoff-anchored where S26 is monotone to 846C within the measured grid, literature-
%% anchored otherwise, both clamped to the deepest delta the model completes cleanly. Formula now:
%%   delta_k = Sev1Deviation * (Sev5Deviation/Sev1Deviation)^((k-1)/4),  k=1..5  (geometric)
%%   multiplier = 1 - delta_k (degradation) | 1 + delta_k (enhancement)
% Enhancement: +   Degradation:
% F37: unused (special freeze — GetFaultMultiplier returns 0.0 directly)
fault_defs.Sev5Deviation = [
    0.25;  % F01: Enh — filter ΔP rises to 1.250 at SEV5
    0.10;  % F02: Deg — compressor eff drops to 0.900 at SEV5. Reduced from
            % 0.15: 0.15 caused a solver singularity at
            % SEV4/SEV5 in ENV004 and SEV5 in ENV005. 0.10 verified to
            % survive in all 5 environments at all 5 severities.
    0.10;  % F03: Deg — compressor eff drops to 0.900 at SEV5. Reduced from 0.25
            % 0.25 caused a solver singularity (non-finite state
            % derivative) in 4/5 environments at SEV5. 0.10 survives in
            % ENV001/002/003/005; ENV004 still collapses at SEV5 even at 0.10
            % (genuine physical limit, not fixable by further reduction without
            % making the fault trivially weak elsewhere -- see datasetInformation.md 2.4).
    0.07;  % F04: Deg — mass flow drops to 0.930 at SEV5. Reduced from 0.25
            % 0.25 collapsed the engine in 5/5 environments at
            % SEV5. 0.07 survives in ENV001/002/003/005; ENV004 still collapses
            % (same environment-wide limit as F03/F22/F23 -- see datasetInformation.md 2.4).
    0.13;  % F05: Deg — pressure ratio drops to 0.870 at SEV5. Reduced from
            % 0.20: 0.20 caused a solver singularity at SEV5
            % in ENV004. 0.13 verified to survive in all 5 environments at
            % all 5 severities.
    0.20;  % F06: Deg — IGV position drops to 0.800 at SEV5
    0.15;  % F07: Deg — gas pressure drops to 0.850 at SEV5
    0.10;  % F08: Deg — fuel flow drops to 0.900 at SEV5. Re-wired and confirmed fixed
            % 2026-07-16 (previously parked since 2026-07-09 for zero effect on any
            % sensor at any severity -- see datasetInformation.md 2.5/2.7). Re-verified
            % SEV5/ENV001 (largest deviation: S33 +73.5%) and SEV5/ENV004 (no collapse,
            % S24/S27 ratio ~1.0) this session. No factor change needed.
    0.20;  % F09: Deg — fuel flow drops to 0.800 at SEV5
    0.30;  % F10: Deg — fuel flow drops to 0.700 at SEV5
    0.20;  % F11: Deg — gas pressure drops to 0.800 at SEV5
    0.20;  % F12: Deg — gas pressure drops to 0.800 at SEV5
    0.10;  % F13: Deg — oscillation amplitude ±10% at SEV5
    0.10;  % F14: Deg — valve position drops to 0.900 at SEV5. Reduced from
            % 0.15: 0.15 caused a solver singularity at SEV5
            % in ENV004. 0.10 verified to survive in all 5 environments at
            % all 5 severities.
    0.07;  % F15: Deg — valve position drops to 0.930 at SEV5. Reduced from
            % 0.10: 0.10 caused a solver singularity at SEV5
            % in ENV004. 0.07 verified to survive in all 5 environments at
            % all 5 severities.
    0.08;  % F16: Deg — air flow drops to 0.920 at SEV5. Reduced from 0.15
            % 0.15 caused a solver singularity starting at
            % SEV3 in ENV004/005, extending to SEV4 in ENV002 and SEV5 in
            % ENV001/002/004/005. 0.08 survives everywhere except SEV5 x
            % ENV004, which remains a permanent, physically-justified gap
            % (same ENV004="High Altitude" margin limit as F03/F04/F22/F23
            % -- see datasetInformation.md 2.4). Verified across all other
            % 24 of 25 severity x environment cells.
    0.15;  % F17: Deg — nozzle flow drops to 0.850 at SEV5
    0.20;  % F18: Deg — RE-MEASURED after moved F18 to 0.30 Hz: the
           % literature-anchor fallback (no citable figure for this fault) keeps SEV5 at the
           % model's own current Factor (0.20, unchanged from the original design value) -- no
           % degenerate-progression bump needed this time, because z(SEV5)=1481 is now far above
           % the 10k=120 guardrail (was flagged low_dynamic_range at the old 1.00 Hz carrier,
           % max z=1.432; self-resolved, no longer flagged). S26 moves only 0.42C across the
           % grid, well under the 1C cutoff-branch threshold, so literature (not cutoff) applies.
    0.20;  % F19: Deg — oscillation amplitude ±20% at SEV5
    0.10;  % F20: Enh — combustor temp rises to 1.100 at SEV5
    0.08;  % F21: Deg — GG eff drops to 0.920 at SEV5. Reduced from 0.15
            % 0.15 caused a solver singularity starting at
            % SEV3 in ENV004/005, extending to SEV4 in ENV002/004/005 and
            % SEV5 in ENV002/004/005. 0.08 survives everywhere except SEV4
            % and SEV5 x ENV004, which remain a permanent, physically-
            % justified gap (same ENV004="High Altitude" margin limit as
            % F03/F04/F22/F23/F16 -- see datasetInformation.md 2.4).
            % Verified across all other 23 of 25 severity x environment cells.
    0.07;  % F22: Deg — GG eff drops to 0.930 at SEV5. Reduced from 0.25
            % 0.25 collapsed the engine in 5/5 environments at
            % SEV5. 0.07 survives in ENV001/002/003/005; ENV004 still collapses
            % (same environment-wide limit as F03/F04/F23 -- see datasetInformation.md 2.4).
    0.10;  % F23: Deg — hot gas flow drops to 0.900 at SEV5. Reduced from 0.20
            % 0.20 collapsed the engine in 4/5 environments at
            % SEV5. 0.10 survives in ENV001/002/003/005; ENV004 still collapses
            % (same environment-wide limit as F03/F04/F22 -- see datasetInformation.md 2.4).
    0.10;  % F24: Enh — cooling air flow rises to 1.100 at SEV5
    0.10;  % F25: Deg — GG turbine inlet pressure drops to 0.900 at SEV5. Re-wired
            % 2026-07-16 (see datasetInformation.md 2.5/2.7): original "net power
            % wire" injection point never propagated (zero effect at any factor,
            % any placement, incl. bypassing the suspected ManualSwitch gate).
            % Fault re-targeted to GasGenerator Inport 4 (turb_inlet_press, fed
            % from Combustor1), same simple point-to-point pattern as F23/F24 --
            % confirmed working with strong, correlated cascading effect across
            % fuel/compressor/combustor/GG/PT sensors. Factor reduced from 0.15
            % to 0.10 after ENV004 SEV5 collapse at 0.15 (S24/S27 solver failure);
            % 0.10 survives ENV004 with S24/S27 ratio ~1.0 (no collapse) while
            % still producing a large, clearly detectable downstream signature.
    0.15;  % F26: Deg — PT eff drops to 0.850 at SEV5
    0.129487;  % F27: Deg — LOWERED from 0.25: cutoff-anchored -- tail S26
           % reaches the 846C exhaust-temperature limiter at this shallower delta within the
           % measured grid clamp caps SEV5 there rather than at the old Factor
           % (which the companion-paper-anchors fork separately flagged as exceeding even the
           % 2-20% general erosion-literature band). See.
    0.20;  % F28: Deg — hot gas flow drops to 0.800 at SEV5
    0.10;  % F29: Enh — PT inlet temp rises to 1.100 at SEV5
    0.225;  % F30: Deg — RAISED from 0.15: the fault's injection point
            % moved onto the Loss friction gain this session, but z still
            % never reaches k=12 anywhere in the measured band (max z=0.002 at the old Factor,
            % WORSE than the pre-rewire injection's 0.087 torque-balance
            % diagnostic: Sum7, not Sum9, is the term that nulls at equilibrium, and Loss's own
            % magnitude [~0.04] is too small relative to Sum8 [~2] to move the equilibrium speed
            % detectably). SEV1's placeholder landed at the old Factor and the degenerate-
            % progression floor raised SEV5 to 1.5x SEV1. Flagged
            % low_dynamic_range_flag=True; reported step 6, not patched further.
    0.25;  % F31: Deg — PT output power drops to 0.750 at SEV5
    0.20;  % F32: Enh — exhaust back-pressure rises to 1.200 at SEV5. Re-wired and confirmed
            % fixed 2026-07-16 (previously parked since 2026-07-09 -- see datasetInformation.md
            % 2.5/2.7). Re-verified SEV5/ENV001 (largest deviation: S27 +2.6% borderline
            % near the 3% detectability floor -- worth a closer look post-production) and
            % SEV5/ENV004 (no collapse, S24/S27 ratio ~1.0) this session. No factor change needed.
    0.05;  % F33: Enh — GG temp reads +5% at SEV5 (ramp)
    0.05;  % F34: Deg — GG temp reads -5% at SEV5 (ramp)
    0.05;  % F35: Enh — GG temp bias +5% at SEV5 (step)
    0.05;  % F36: Deg — GG temp bias -5% at SEV5 (step)
    1.00;  % F37: freeze (placeholder — GetFaultMultiplier returns 0.0 directly for F37)
    0.05;  % F38: Deg — GG speed sensor reads -5% at SEV5. literature
           % in_service_max for F38 (0.2%) is numerically IDENTICAL to its own detection_threshold
           % (also one of the four k=12 calibration anchors) -- using it as SEV5 would collapse
           % SEV1~SEV5, so the literature branch is rejected as degenerate and SEV5 falls back to
           % the current Factor, same remedy as "no citable figure". See;
           % flag: F38/F39's in_service_max column should likely read
           % UNKNOWN rather than copying detection_threshold.
    0.05;  % F39: Deg — PT speed sensor reads -5% at SEV5. Same degenerate-anchor finding as F38.
    0.01;  % F40: Deg — LOWERED from 0.05: literature-anchored to the
           % Coriolis custody-transfer accuracy range's upper end (in_service_max=1.0% 
           %) rather than the old placeholder Factor. z(SEV5)=62.8, below
           % the 10*k=120 guardrail -- flagged low_dynamic_range_flag=True (a genuine, reported
           % finding: this sensor fault's own literature range is itself narrow, not a bug).
    0.01;  % F41: Deg — same literature anchor and flag as F40.
    0.15;  % F42: Deg — oscillation amplitude ±15% at SEV5. Regime-conditional:
           % live in duty_tracking records (z=44.1 on S10 at the 15C
           % reference condition), masked in temperature_limited records (z=0.0003 on the same
           % channel at 35C) -- must be declared in the Usage Notes.
];

%% Default Drift Start Time (seconds)
% Overridden per epoch in LoadScenarioToWorkspace via seeded RNG
% tau ∈ [FAULT_START_TAU_MIN, FAULT_START_TAU_MAX] = [601, 1200], a sample index relative to the
% 4200-sample STORED window (not simulation time) -- see ScenarioConfig.m
%.
fault_defs.DriftStartTime = zeros(42, 1);

%% Drift Duration (seconds) — ramp faults only; 0 for step/oscillate
%
% RESCALED 2026-10-13 — the whole ladder divided by 3. The 19 linear_ramp faults
% previously carried 1200/1800/2400/3600 s ramps, sized for the draft run's 7200 s record by the
% rule "slowest ramp completes exactly at t = 7200 s" -- i.e. by design the 3600 s group had
% ZERO settled post-ramp tail in the latest onset draw, so its multiplier never reached the
% commanded SEV delta and its own severity_label never reached the record's severity attribute.
% The shortened 4800 s / 4200-stored-sample record makes that worse, not better.
%
% The release's rule instead: every ramp must COMPLETE inside the stored window and then hold
% the commanded severity for at least 1800 s, because 1800 s is the quasi-static hold
% calibrated every severity band against (P2_08_severity_delta_grid.m, DUR = 1800, tail
% statistic over the last 180 s; 296/296 non-oscillating cells settled to
% |dS26/dt| <= 0.0133 K/s there). That makes the binding constraint
%
%     max(DriftDuration) <= STORED_SAMPLES - FAULT_START_TAU_MAX - 1800 = 4200 - 1200 - 1800
%                        =  1200 s
%
% A uniform /3 satisfies it exactly at the ceiling while preserving every pairwise drift-rate
% ratio (the 3x spread 1200..3600 becomes the 3x spread 400..1200), so ramp-rate diversity --
% which the onset-detection and prognostic tasks use -- survives intact. Severity MAGNITUDE is
% untouched: bands were calibrated from held multipliers, not from ramp rates.
% ValidatePipelineConfig.m asserts the inequality above test S10 checks it per record.
%
%   old -> new :  3600 -> 1200 (F21 F25 F26 F30)   2400 -> 800 (F01 F02 F11 F20 F24 F29 F32)
%                 1800 ->  600 (F08 F17 F22 F23)   1200 -> 400 (F10 F33 F34 F41)
fault_defs.DriftDuration = [
     800;  % F01: 13.3 min ramp (was 2400 s / 40 min)
     800;  % F02: 13.3 min ramp (was 2400 s / 40 min)
       0;  % F03: step
       0;  % F04: step
       0;  % F05: step
       0;  % F06: step
       0;  % F07: step
     600;  % F08: 10 min ramp (was 1800 s / 30 min)
       0;  % F09: step
     400;  % F10: 6.7 min ramp (was 1200 s / 20 min)
     800;  % F11: 13.3 min ramp (was 2400 s / 40 min)
       0;  % F12: step
       0;  % F13: oscillate (instant start)
       0;  % F14: step
       0;  % F15: step
       0;  % F16: step
     600;  % F17: 10 min ramp (was 1800 s / 30 min)
       0;  % F18: oscillate (instant start)
       0;  % F19: oscillate (instant start)
     800;  % F20: 13.3 min ramp (was 2400 s / 40 min)
    1200;  % F21: 20 min ramp (was 3600 s / 60 min)
     600;  % F22: 10 min ramp (was 1800 s / 30 min)
     600;  % F23: 10 min ramp (was 1800 s / 30 min)
     800;  % F24: 13.3 min ramp (was 2400 s / 40 min)
    1200;  % F25: 20 min ramp (was 3600 s / 60 min)
    1200;  % F26: 20 min ramp (was 3600 s / 60 min)
       0;  % F27: step
       0;  % F28: step
     800;  % F29: 13.3 min ramp (was 2400 s / 40 min)
    1200;  % F30: 20 min ramp (was 3600 s / 60 min)
       0;  % F31: step
     800;  % F32: 13.3 min ramp (was 2400 s / 40 min)
     400;  % F33: 6.7 min ramp (was 1200 s / 20 min)
     400;  % F34: 6.7 min ramp (was 1200 s / 20 min)
       0;  % F35: step
       0;  % F36: step
       0;  % F37: step (freeze)
       0;  % F38: step
       0;  % F39: step
       0;  % F40: step
     400;  % F41: 6.7 min ramp (was 1200 s / 20 min)
       0;  % F42: oscillate (instant start)
];

%% Oscillation Frequency (Hz) — non-zero only for 'oscillate' profile faults
% F18/F19 LOWERED from 1.00/0.50 Hz to 0.30/0.10 Hz (2026-10-13
%) -- closes C18/C21/C49. At the old frequencies, F18 (1.0 Hz) sampled at exactly its
% own frequency at a 1 Hz output rate (total aliasing) and F19 (0.5 Hz) sat exactly on the
% Nyquist limit; both needed a 5 Hz output-rate override (ScenarioConfig.GetOutputDt), which is
% now removed -- the whole release is uniform 1 Hz. F13 (0.05 Hz) and F42 (0.20 Hz) are already
% well inside the 1 Hz Nyquist and do NOT change.
fault_defs.OscillationFrequency = zeros(42, 1);
fault_defs.OscillationFrequency(13) = 0.05;  % F13: FG pressure oscillation (20 s period)
fault_defs.OscillationFrequency(18) = 0.30;  % F18: low-frequency heat-release oscillation (3.33 s period)
fault_defs.OscillationFrequency(19) = 0.10;  % F19: low-frequency fuel-air ratio oscillation (10 s period)
fault_defs.OscillationFrequency(42) = 0.20;  % F42: Control loop instability (5 s period)

%% Enhancement Faults (multiplier > 1.0)
% F01: air intake filter fouling — raises filter differential pressure
% F20: hot gas path temperature increase — raises combustor outlet temperature
% F24: GG seal degradation — increases rotor cooling air leakage flow
% F29: PT seal degradation — raises PT inlet gas temperature
% F32: stack blockage — raises PT outlet back-pressure
% F33: GG temp sensor drift (+) — sensor reads high (ramp)
% F35: GG temp sensor bias (+) — sensor reads high (step)
fault_defs.IsEnhancement = false(42, 1);
fault_defs.IsEnhancement([1, 20, 24, 29, 32, 33, 35]) = true;

%% Multi-Fault Combinations
% All IDs use unified F01-F42 numbering (= Simulink FAULT_XX_multiplier variable IDs)
% Generated via Monte Carlo with forbidden-pair constraints and group diversity score >= 2.
% 2026-10-13: the draft's 18/22/15 stability-workaround combo
% tables are RETIRED, not extended. Those tables existed to route around the three faults
% (F08, F25, F30, F32) a 2026-07 session had parked for solver-stability reasons -- all three are
% live now (F30's injection point moved and measured run-to-failure sweep
% ran F25/F30 at depths far beyond anything a diagnosis-severity combo would reach). The
% replacement is `multifault_design_output.txt`'s fully re-run co-occurrence search: 21 dual + 14
% triple + 11 quad = 46 combinations (not 40), covering all 42 faults (min 3, max 4 appearances --
% F16 and F20 each appear 4 times "every fault appears 3 times" is an
% oversimplification of that file's own "distribution={3:40, 4:2}" line, corrected here for).
% No forbidden-pair table is needed any more -- the new search already excludes same-subsystem
% mutually-exclusive pairs (the old (2,3),(7,11),... list) by construction; see that file's own
% rationale tags ([CC]/[IC]/[CS]/[CL]/[SM]/[MI]).

% Dual-Fault Combinations (21) -- multifault_design_output.txt, "--- DUAL (21) ---"
fault_defs.DualCombos = [
     1,  5;   % Combo 01 [CC]: Air intake filter fouling + Diffuser damage
     2, 26;   % Combo 02 [CC]: Compressor blade fouling + PT fouling
     3, 32;   % Combo 03 [IC]: Compressor blade damage + Stack blockage
     4, 19;   % Combo 04 [CS]: Compressor surge/stall + Low-freq combustion instability
     6, 42;   % Combo 05 [MI]: IGV stuck + Control loop instability
     7, 40;   % Combo 06 [SM]: Fuel pressure regulator stuck + FG flowmeter offset
     8, 16;   % Combo 07 [CC]: Fuel valve leakage + Combustion liner damage
     9, 25;   % Combo 08 [IC]: Fuel contamination + GG mechanical-loss increase
    10, 41;   % Combo 09 [SM]: Fuel line blockage + FG flowmeter drift
    11, 17;   % Combo 10 [CS]: Fuel pump degradation + Fuel nozzle clogging
    12, 30;   % Combo 11 [IC]: FG regulator/downstream press loss + PT mechanical-loss increase
    13, 18;   % Combo 12 [CS]: FG supply pressure oscillation + Low-freq fuel/heat-release oscill.
    14, 22;   % Combo 13 [IC]: FG valve partial opening + GG turbine blade damage
    15, 21;   % Combo 14 [IC]: FG valve actuator gain loss + GG turbine fouling
    20, 37;   % Combo 15 [SM]: Hot gas path temperature increase + GG temp sensor freeze
    23, 36;   % Combo 16 [SM]: GG nozzle blockage + GG temp sensor bias (-)
    24, 38;   % Combo 17 [SM]: GG seal degradation + GG speed sensor fault
    27, 33;   % Combo 18 [IC]: PT blade damage + GG temp sensor drift (+)
    28, 35;   % Combo 19 [IC]: PT nozzle damage + GG temp sensor bias (+)
    29, 39;   % Combo 20 [SM]: PT seal degradation + PT speed sensor fault
    31, 34;   % Combo 21 [IC]: PT power loss + GG temp sensor drift (-)
];

% Triple-Fault Combinations (14) -- multifault_design_output.txt, "--- TRIPLE (14) ---"
fault_defs.TripleCombos = [
     1, 20, 36;   % Combo 01 [SM]: Air intake filter fouling + Hot gas path temp increase + GG temp sensor bias (-)
     2, 32, 37;   % Combo 02 [MI]: Compressor blade fouling + Stack blockage + GG temp sensor freeze
     3, 22, 34;   % Combo 03 [SM]: Compressor blade damage + GG turbine blade damage + GG temp sensor drift (-)
     4, 19, 38;   % Combo 04 [SM]: Compressor surge/stall + Low-freq combustion instability + GG speed sensor fault
     5, 10, 41;   % Combo 05 [SM]: Diffuser damage + Fuel line blockage + FG flowmeter drift
     6, 27, 29;   % Combo 06 [CL]: IGV stuck + PT blade damage + PT seal degradation
     7, 17, 39;   % Combo 07 [CS]: Fuel pressure regulator stuck + Fuel nozzle clogging + PT speed sensor fault
     8, 16, 28;   % Combo 08 [CC]: Fuel valve leakage + Combustion liner damage + PT nozzle damage
     9, 25, 40;   % Combo 09 [SM]: Fuel contamination + GG mechanical-loss increase + FG flowmeter offset
    11, 15, 23;   % Combo 10 [CL]: Fuel pump degradation + FG valve actuator gain loss + GG nozzle blockage
    12, 14, 30;   % Combo 11 [CL]: FG regulator/downstream press loss + FG valve partial opening + PT mechanical-loss increase
    13, 18, 42;   % Combo 12 [SM]: FG supply pressure oscillation + Low-freq fuel/heat-release oscill. + Control loop instability
    21, 24, 35;   % Combo 13 [SM]: GG turbine fouling + GG seal degradation + GG temp sensor bias (+)
    26, 31, 33;   % Combo 14 [CS]: PT fouling + PT power loss + GG temp sensor drift (+)
];

% Quad-Fault Combinations (11) -- multifault_design_output.txt, "--- QUAD (11) ---"
fault_defs.QuadCombos = [
     1,  6, 20, 34;   % Combo 01 [SM]: Air intake filter fouling + IGV stuck + Hot gas path temp increase + GG temp sensor drift (-)
     2,  5, 20, 37;   % Combo 02 [SM]: Compressor blade fouling + Diffuser damage + Hot gas path temp increase + GG temp sensor freeze
     3, 10, 32, 41;   % Combo 03 [SM]: Compressor blade damage + Fuel line blockage + Stack blockage + FG flowmeter drift
     4,  7, 16, 17;   % Combo 04 [CS]: Compressor surge/stall + Fuel pressure regulator stuck + Combustion liner damage + Fuel nozzle clogging
     8, 12, 14, 28;   % Combo 05 [CL]: Fuel valve leakage + FG regulator/downstream press loss + FG valve partial opening + PT nozzle damage
     9, 16, 33, 40;   % Combo 06 [SM]: Fuel contamination + Combustion liner damage + GG temp sensor drift (+) + FG flowmeter offset
    11, 15, 21, 35;   % Combo 07 [SM]: Fuel pump degradation + FG valve actuator gain loss + GG turbine fouling + GG temp sensor bias (+)
    13, 19, 30, 39;   % Combo 08 [SM]: FG supply pressure oscillation + Low-freq combustion instability + PT mechanical-loss increase + PT speed sensor fault
    18, 27, 31, 42;   % Combo 09 [SM]: Low-freq fuel/heat-release oscill. + PT blade damage + PT power loss + Control loop instability
    22, 23, 25, 36;   % Combo 10 [SM]: GG turbine blade damage + GG nozzle blockage + GG mechanical-loss increase + GG temp sensor bias (-)
    24, 26, 29, 38;   % Combo 11 [SM]: GG seal degradation + PT fouling + PT seal degradation + GG speed sensor fault
];

end
