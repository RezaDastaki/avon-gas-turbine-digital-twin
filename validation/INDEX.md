# validation/

One-off scripts that were used to modify the Simulink model, to build the measured lookup libraries
that the generation pipeline loads, and to inspect or spot-check generated output. **None of them is
called by the generation pipeline** (`DataGeneration/`); the pipeline only loads the two library files
they produced (`Core/Models/P4_operating_point_library*.mat`) and, for the ambient check, a surface
stored in the same files.

The model-patch scripts (`P1b_01`, `P1b_02`, `P4_21`, `P4_22`, `P4_25`, `P4_45`, `P4_47`, `P4_57`, `P4_58`)
edit a Simulink model in place. Their effects are already contained in
`Core/Models/AvonGasTurbineDgTwin_fixed.slx`; they are kept as a record of what was changed, and
should not be re-run against that file. Each takes a model name argument; read its header first.

`validation/` is on the MATLAB path after `setup_paths`.

| Script | What it does |
|---|---|
| `P1b_01_add_true_value_taps.m` | Adds To Workspace taps for the unperturbed (pre-fault-injection) value of five drifting sensors (`S19_true`, `S24_true`, `S27_true`, `S04_true`, `S26_true`). These feed the `/true_values` dataset. |
| `P1b_02_fix_duty_command.m` | Replaces the model's hard-coded two-step power-setpoint ramp with a constant workspace variable `SP_POWER_CMD` (default 13 MW). |
| `P4_20_build_operating_point_library.m` | Builds the warm-start library: measured PT and GG rotor-speed equilibrium against compressor-inlet temperature (10 to 50 degC, 2 degC grid) at the fixed 13 MW duty, Healthy. Writes `Core/Models/P4_operating_point_library.mat`. |
| `P4_21_add_ambient_trend_input.m` | First attempt at replacing the `ENV_comp_inlet_temp_C` constant with a From Workspace block, so the inlet temperature can carry a within-record trend. Fed only one of the constant's two destinations; superseded. |
| `P4_22_revert_ambient_trend_input.m` | Reverts `P4_21` after its identity regression (flat trend against the constant-ambient baseline) failed. |
| `P4_25_repair_ambient_line.m` | Restores the compressor-inlet-temperature line that had been left connected to only one of its two destinations. |
| `P4_34_build_ambient_check_surface.m` | Builds the two-dimensional (inlet temperature by inlet pressure) measured surface of clean baseline `S26` used by the per-record drawn-versus-realised ambient check. |
| `P4_45_add_gg_restoring_term.m` | Adds a restoring term to the gas-generator rotor torque balance. Built and measured on a scratch copy; it did not meet its tolerance and is not part of the shipped model. |
| `P4_47_apply_g2_freeze_gg_rotor.m` | Freezes the gas-generator rotor speed at the library equilibrium (the variant that is in the shipped model). |
| `P4_57_add_ambient_trend_input_both_branches.m` | Second attempt at the within-record ambient trend input, feeding both original destinations of the ambient constant. |
| `P4_58_revert_ambient_trend_input_both_branches.m` | Reverts `P4_57`, with the same both-destinations check. |
| `CheckSensorQuality.m` | Run after a simulation: checks that the sensor variables exist in the workspace, have the expected length, contain no NaN or Inf and lie in expected ranges. |
| `DebugSimulationOutput.m` | Run after a simulation: prints the structure of the `SimulationOutput` object. |
| `FindMissingSensors.m` | Searches the Simulink model for the blocks that carry efficiency and power-turbine temperature signals. |
| `TestCandidateComboStability.m` | Runs each candidate multi-fault combination at maximum severity in all five environments to check that it completes. |
| `TestFaultMultipliers.m` | Tests the fault definition loading, multiplier calculation, array generation and workspace loading. |
| `VerifyLabelAccuracy.m` | Read-only check that `fault_label` and `severity_label` in sample records match the documented fault-activation timing and severity behaviour. Uses `AVON_DATA_ROOT` or the default data root. |

Not every script has been re-run since the files were moved here; the scripts that ran in the
fresh-copy tests are the pipeline entry points, not the files in this folder.
