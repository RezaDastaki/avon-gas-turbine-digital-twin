# Avon Gas Turbine Digital Twin: a fault-diagnosis and prognostics data generator

A physics-based Simulink digital twin of a **Rolls-Royce Avon Mk1535 two-shaft industrial gas
turbine**, together with the complete, resumable pipeline that turns it into labelled
benchmark data for **fault diagnosis** and **remaining-useful-life (RUL) prognostics**.

This repository is the generator behind the public dataset
*Rolls-Royce Avon Mk1535 Gas Turbine Digital-Twin Dataset for Fault Diagnosis and Prognostics*
(Zenodo: `[DOI to be added]`). Every file in that release can be regenerated from this code
**bit for bit**: same seeds, same arrays, same attributes.

> **What you can do with it**
> - Benchmark fault detection, isolation and severity estimation on 42 physically injected faults.
> - Train and test RUL models on 7,150 units run to a model-internal end of life.
> - Generate *new* data: other ambient conditions, another fixed duty, more epochs, more units,
>   or new fault combinations, with the same validated physics and QA gates.
> - Use the governing equations and the clean "true value" channels for physics-informed learning.

---

## Highlights

| | |
|---|---|
| **Plant** | Two-shaft industrial gas turbine (gas generator + free power turbine) driving a centrifugal compressor load |
| **Faults** | 42 single faults: gas path, fuel system, combustor, turbines, sensors and control. Each has five severity levels and a step, ramp, oscillation or freeze profile. |
| **Families in the release** | Diagnosis: 110,000 records. Run-to-failure: 7,150 units across 13 degradation mechanisms. Turndown at a second fixed duty: 17,800 records. |
| **Signals** | 39 channels at 1 Hz (26 instrument channels + 13 model states), plus 5 clean "true value" channels behind the sensor-fault taps |
| **Operating envelope** | Compressor-inlet temperature 10–50 °C, drawn per record by Monte Carlo along with four other ambient variables |
| **Labels** | Per-sample fault and severity labels. A *measured* operating regime: `duty_tracking`, `temperature_limited` or `fault_limited`. RUL and health index per cycle. |
| **Quality gates** | Per-record physical QA, a drawn-versus-realised ambient check, a pipeline pre-flight validator, and resumability tested at record and unit level |
| **Hardware** | Generated in full on a single laptop (10-core CPU, 64 GB RAM) |

---

## Quick start

Requirements:
- **MATLAB R2024b with Simulink** and the **Statistics and Machine Learning Toolbox**.
- The **Parallel Computing Toolbox** for the parallel drivers.

Run from the repository root.

```matlab
% 1. Set up paths and load the turbine parameters
run('setup_paths.m')

% 2. Pre-flight: 13 structural and configuration checks (no long simulation)
ValidatePipelineConfig(ScenarioConfig.GetActiveConfig(), ScenarioConfig.SIMULINK_MODEL)

% 3. Generate one record of each kind
RunScenario('healthy', 1, 1)        % Healthy, epoch 1
RunScenario('single', 1, 1, 7)      % fault F07, epoch 1
RunRTFUnit(27, 352)                 % one run-to-failure unit (mechanism F27, unit 352)
```

Output goes to `Data/` inside the repository. Set the environment variable `AVON_DATA_ROOT`
to write somewhere else. To check reproducibility, compare a generated file with the same file
from the Zenodo release: every array is identical.

The `launch/` folder has one-line Windows wrappers for the same commands.

### Generating whole families

```matlab
GenerateDiagnosisParallel()   % 89 scenarios: Healthy + 42 single + 46 multi-fault combinations
GenerateRTFParallel()         % 13 mechanisms x 550 units, each run to end of life
GenerateTurndownParallel()    % the 89 scenarios at a second fixed duty
AvonProgress                  % read-only progress report for all three families
```

All three drivers are **resumable**:
- If a run stops, run the same command again. Finished work is detected and skipped.
- Diagnosis resumes per record.
- Run-to-failure resumes per unit. A partially written unit is regenerated whole, because its
  RUL labels are defined against its own end of life.

The worker count comes from the `AVON_WORKERS` environment variable, then `config.txt`.
**Memory, not cores, is the usual limit.** Measured: RAM ≈ 0.87 + 3.22 × workers GB.

---

## How the generator works

```
 ambient draw (Monte Carlo, seeded)            fault draw (ID, severity, profile, onset)
            │                                                │
            ▼                                                ▼
  warm start from a measured operating-point library ──► Simulink twin (variable step)
            │                                                │
            │                                  pre-roll discarded, 4,200 s stored at 1 Hz
            ▼                                                ▼
  clean plant signals ──► QA Layer 1 (regime, settling, ambient check) ──► measurement model
            │                       │ fail → retry with a new draw              │
            ▼                       ▼                                           ▼
     /true_values             labels + attributes                    HDF5 record (/sensors, /internal, ...)
```

- **Physics.** Component models for the inlet, compressor, combustor, gas-generator turbine and
  power turbine, coupled through rotor dynamics and a speed-dependent load (affinity law,
  exponent 3).
- **Control.** A power loop, an 846 °C turbine-inlet-temperature limiter, and overspeed
  protection.
- **Measurement.** The noise and bias model is applied after the simulation, so the
  ground-truth labels and every QA check use the clean signal.
- **Operating regimes are measured, not assumed.** Commanded duty is fixed (13 MW in the main
  families). Above roughly 23–25 °C the engine cannot deliver it and runs on its temperature
  limit. That regime is kept, measured and labelled in every record.
- **Run-to-failure.**
  - Degradation follows a gamma process with a per-unit frailty.
  - It is accelerated by the measured thermal state of each cycle, so hot cycles age a unit
    faster.
  - End of life is reached when the engine can no longer hold its duty within its temperature
    limit. This is a model-internal criterion, not a threshold chosen by hand.

---

## Repository layout

| Path | Contents |
|---|---|
| `setup_paths.m` | Run first. Adds the paths and loads the turbine parameters. |
| `Core/Models/` | The Simulink models (`AvonGasTurbineDgTwin_fixed.slx` generates the data), plus the warm-start operating-point libraries |
| `Core/Scripts/` | Turbine data and parameter loading |
| `DataGeneration/` | The pipeline: scenario grid (`ScenarioConfig.m`), fault definitions (`GetFaultDefinitions.m`), RTF mechanisms (`GetRTFMechanisms.m`), record and unit runners, QA, HDF5 writers, parallel drivers, pre-flight validator |
| `FaultReference/` | `fault_catalogue.csv`, the single naming source for all 42 faults |
| `validation/` | The measurement scripts behind the dataset's technical validation (see `validation/INDEX.md`) |
| `tools/release/` | Packaging helpers: per-folder zips and the sample subset. Not needed to generate data. |
| `launch/` | Windows command wrappers |

---

## Extending it

- **More data of the same kind.** Change the epoch or unit counts in `ScenarioConfig.m`.
  Seeds are a function of scenario, epoch and attempt, so the existing records stay identical
  and the new ones are simply appended.
- **A different fixed duty.** The turndown family shows the pattern: a second fixed setpoint
  with its own warm-start library, written to its own folder.
- **New fault combinations.** Add them to the combination tables used by `ScenarioConfig.m` and
  `GetFaultDefinitions.m`. `GenerateScenarioInfo.m` names them automatically.
- **New faults or mechanisms.** Add the injection point in the model and its definition in
  `GetFaultDefinitions.m` (or `GetRTFMechanisms.m`). Then run `ValidatePipelineConfig`, and do a
  one-epoch pass over every scenario before any long run.

Before any long run, the project's own rule is a **one-epoch smoke pass over every scenario**,
with every written file opened and validated. Defects that matter tend to be scenario-specific
and survive sampling.

---

## Known modelling choices (declared, not hidden)

- The power-turbine rotor's time constant is of order 10³ s, against about 1 s physically. The
  dataset's transients are therefore **not physically time-scaled**.
- The gas-generator rotor speed is held at its operating-point value within a record. Its speed
  feedback is decoupled in the original model, and freezing it isolates that defect without
  moving any other channel.
- The nine sensor faults (F33–F41) affect only the logged channel, not the controller. The clean
  value is provided in `/true_values`.
- In run-to-failure units, the per-cycle ambient is not uniform. Rejected cycles are redrawn
  milder, so use the empirical distribution stored in each file.

The dataset description and the accompanying paper document these choices and their measured
consequences.

---

## Citing

If you use the generator or the dataset, please cite the dataset and the paper:

```
[Dataset citation and DOI to be added]
[Data Descriptor citation to be added]
```

A `CITATION.cff` is included, so GitHub's "Cite this repository" button gives the reference.
The physical model builds on the high-order digital twin of Mostafavi & Chaibakhsh
`[full reference to be added]`.

## Contributing

Issues and pull requests are welcome, in particular:
- new fault mechanisms;
- ports of the measurement model;
- loaders for Python and other languages;
- faster generation;
- independent validation against plant data.

See `CONTRIBUTING.md`.

## Licence

`[Licence to be chosen by the author]`

## Trademark note

"Rolls-Royce" and "Avon" identify the engine type that the model represents. The industrial Avon
line has been owned by Siemens since 2014. This project is not affiliated with, endorsed by, or
sponsored by Rolls-Royce plc or Siemens Energy, and the model is not manufacturer data.

## Acknowledgements

<!-- TODO (author): confirm this wording before publishing. -->
We thank Fajr Jam Gas Refining Company, Iran, the operator of the engine on which the original
digital twin is based.
