% setup_paths.m - Environment setup for the Avon Gas Turbine Digital Twin
% Run this at the start of each MATLAB session
%
% Usage:
%   run('setup_paths.m')
%
% Date: 2025-12-28
clc;close all;clear;
fprintf('\n========================================\n');
fprintf('  Avon Gas Turbine Digital Twin\n');
fprintf('  Environment Setup\n');
fprintf('========================================\n\n');

% Navigate to the repository root (this script lives there)
script_path = fileparts(mfilename('fullpath'));
cd(script_path);
fprintf('Working directory: %s\n\n', pwd);

% Add all necessary paths
fprintf('Adding paths...\n');
addpath(script_path);          % repository root: AvonProgress/AvonSetupCheck
addpath('Core/Models');
addpath('Core/Scripts');
addpath('DataGeneration');
addpath('validation');
fprintf('  ✓ Core/Models\n');
fprintf('  ✓ Core/Scripts\n');
fprintf('  ✓ DataGeneration\n\n');

% Load initialization data
fprintf('Loading gas turbine parameters (this may take 10-30 seconds)...\n');
tic;
run('Core/Scripts/DataGasTurbineAvon.m');
load_time = toc;
fprintf('  ✓ Parameters loaded (%.1f seconds)\n\n', load_time);

% Display workspace variables
vars = whos;
fprintf('Workspace variables: %d loaded\n', length(vars));

% Display available models
fprintf('\nAvailable Simulink Models:\n');
fprintf('  1. AvonGasTurbine.slx          - Baseline reference model\n');
fprintf('  2. AvonGasTurbineDgTwin.slx    - Main digital twin (for fault injection)\n');
fprintf('  3. AvonGasTurbineController.slx - Controller subsystem\n');

fprintf('\nAvailable Scripts:\n');
fprintf('  DataGeneration/InitializeFaultConfig.m   - Configure faults\n');
fprintf('  DataGeneration/SaveToHDF5.m              - Export data to HDF5\n');
fprintf('  DataGeneration/Example_SingleFaultSimulation.m - Demo script\n');
fprintf('  DataGeneration/GenerateCompleteDataset.m - Batch generation\n');

fprintf('\n========================================\n');
fprintf('  Setup Complete!\n');
fprintf('========================================\n');
fprintf('\nQuick Commands:\n');
fprintf('  open_system(''Core/Models/AvonGasTurbineDgTwin'')\n');
fprintf('  sim(''Core/Models/AvonGasTurbineDgTwin'', ''StopTime'', ''100'')\n');
fprintf('  cd(''DataGeneration''); Example_SingleFaultSimulation\n');
fprintf('\n');
