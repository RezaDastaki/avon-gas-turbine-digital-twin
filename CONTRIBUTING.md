# Contributing

Thank you for considering a contribution. The generator is used to produce a published
benchmark, so the bar is reproducibility: a change must never alter existing records silently.

## Before you open a pull request

1. **Run the pre-flight validator.** All checks must pass:
   ```matlab
   run('setup_paths.m')
   ValidatePipelineConfig(ScenarioConfig.GetActiveConfig(), ScenarioConfig.SIMULINK_MODEL)
   ```
2. **Show that existing records are unchanged**, unless changing them is the point of the PR.
   Regenerate a few records into a temporary `AVON_DATA_ROOT`, for example:
   - Healthy epoch 1;
   - one single fault;
   - one multi-fault combination;
   - one run-to-failure unit.

   Compare them with the released files. The arrays must be identical, and so must every
   attribute except `timestamp`.
3. **If you change the model or the pipeline**, run one epoch of every diagnosis scenario and
   open and validate every written file. Report the pass and fail counts in the PR.
4. **Keep runs resumable.** Diagnosis resumes per record. Run-to-failure resumes per unit, and a
   partial unit must be regenerated whole.

## Good first contributions

- Python or Julia loaders for the HDF5 records.
- Plots and notebooks that use the sample subset.
- Documentation of a component model, with equations traced to the Simulink blocks.
- Performance profiling of a single record.

## Style

- Put new parameters in `ScenarioConfig.m`, never as literals scattered through the code.
- Derive every path from the code's location or from `AVON_DATA_ROOT`. Never hard-code a drive
  or user path.
- Comments should explain *why*, in a form that stands on its own.

## Reporting a problem

Open an issue with:
- the MATLAB version;
- the exact command;
- the scenario, epoch or unit;
- the error text or log excerpt.

For a physics question, say which channel and which record you looked at.
