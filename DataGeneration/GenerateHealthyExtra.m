% GenerateHealthyExtra.m  (DEPRECATED)
%
% An earlier pipeline iteration used this script to extend Healthy from 25 to
% 250 epochs per environment, using its own hardcoded epoch range so it
% wouldn't disturb the shared N_EPOCHS. The current pipeline has no
% environment folders and each category has its own editable epoch count
% (N_EPOCHS_HEALTHY) instead. To add more healthy epochs now, simply raise
% ScenarioConfig.N_EPOCHS_HEALTHY and re-run GenerateHealthyDataset
% -- existing epoch files are skipped and only the new epochs are generated.
%
% This script is intentionally a no-op to avoid running against the old
% (removed) RunScenario signature.
%
% Date: 2026-07-26

fprintf(['\nGenerateHealthyExtra is DEPRECATED.\n' ...
         'To add healthy epochs: raise ScenarioConfig.N_EPOCHS_HEALTHY and\n' ...
         'run >> GenerateHealthyDataset  (resumable — only new epochs generate).\n\n']);
