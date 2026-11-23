% FindMissingSensors.m
% Helper script to locate missing sensor outputs in Simulink model
% Searches for efficiency outputs and PT temperature sensors
%
% This script helps locate:
%   - S11: HP compressor efficiency (in comp_temp1 subsystem)
%   - S19: PT efficiency (in PT_Pwr subsystem)
%   - S20: Overall thermal efficiency (in PT_Pwr or calculated)
%   - Clarify S15/S18: PT inlet vs outlet temperature
%
% Usage:
%   Run this script after opening AvonGasTurbineDgTwin model
%   It will search the model and provide guidance
%
% Date: 2025-12-28

clc;
fprintf('\n========================================\n');
fprintf('  Missing Sensor Locator\n');
fprintf('========================================\n\n');

%% Check if model is loaded
model_name = 'AvonGasTurbineDgTwin';

try
    % Try to load the model
    load_system('Core/Models/AvonGasTurbineDgTwin');
    fprintf('✓ Model loaded: %s\n\n', model_name);
catch
    error('Cannot load model. Ensure you are in the repository root and Core/Models/AvonGasTurbineDgTwin.slx exists.');
end

%% Search for efficiency-related blocks
fprintf('=== Searching for Efficiency Blocks ===\n');

% Search for blocks with "efficiency" or "eta" in the name
eff_blocks = find_system(model_name, 'Type', 'Block', 'Name', 'eff');
eta_blocks = find_system(model_name, 'Type', 'Block', 'Name', 'eta');

fprintf('Blocks containing "eff": %d found\n', length(eff_blocks));
if ~isempty(eff_blocks)
    for i = 1:length(eff_blocks)
        fprintf('  %d. %s\n', i, eff_blocks{i});
    end
end

fprintf('\nBlocks containing "eta": %d found\n', length(eta_blocks));
if ~isempty(eta_blocks)
    for i = 1:length(eta_blocks)
        fprintf('  %d. %s\n', i, eta_blocks{i});
    end
end

%% Search for compressor subsystem
fprintf('\n=== Compressor Subsystem (comp_temp1) ===\n');

comp_subsys = find_system(model_name, 'Name', 'comp_temp1');
if ~isempty(comp_subsys)
    fprintf('✓ Found compressor subsystem: %s\n', comp_subsys{1});

    % Look for outport blocks in compressor
    comp_outports = find_system(comp_subsys{1}, 'SearchDepth', 1, 'BlockType', 'Outport');
    fprintf('  Output ports in comp_temp1: %d\n', length(comp_outports));

    if ~isempty(comp_outports)
        for i = 1:length(comp_outports)
            port_name = get_param(comp_outports{i}, 'Name');
            fprintf('    %d. %s\n', i, port_name);
        end
    end

    % Look for To Workspace blocks
    comp_toworkspace = find_system(comp_subsys{1}, 'BlockType', 'ToWorkspace');
    fprintf('  "To Workspace" blocks in comp_temp1: %d\n', length(comp_toworkspace));

    if ~isempty(comp_toworkspace)
        for i = 1:length(comp_toworkspace)
            var_name = get_param(comp_toworkspace{i}, 'VariableName');
            fprintf('    %d. Variable: %s\n', i, var_name);
        end
    else
        fprintf('  ⚠ No "To Workspace" blocks found\n');
        fprintf('  → You may need to add one for efficiency output\n');
    end
else
    fprintf('✗ Compressor subsystem "comp_temp1" not found\n');
end

%% Search for Power Turbine subsystem
fprintf('\n=== Power Turbine Subsystem (PT_Pwr) ===\n');

pt_subsys = find_system(model_name, 'Name', 'PT_Pwr');
if ~isempty(pt_subsys)
    fprintf('✓ Found PT subsystem: %s\n', pt_subsys{1});

    % Look for outport blocks in PT
    pt_outports = find_system(pt_subsys{1}, 'SearchDepth', 1, 'BlockType', 'Outport');
    fprintf('  Output ports in PT_Pwr: %d\n', length(pt_outports));

    if ~isempty(pt_outports)
        for i = 1:length(pt_outports)
            port_name = get_param(pt_outports{i}, 'Name');
            fprintf('    %d. %s\n', i, port_name);
        end
    end

    % Look for To Workspace blocks
    pt_toworkspace = find_system(pt_subsys{1}, 'BlockType', 'ToWorkspace');
    fprintf('  "To Workspace" blocks in PT_Pwr: %d\n', length(pt_toworkspace));

    if ~isempty(pt_toworkspace)
        for i = 1:length(pt_toworkspace)
            var_name = get_param(pt_toworkspace{i}, 'VariableName');
            fprintf('    %d. Variable: %s\n', i, var_name);
        end
    else
        fprintf('  ⚠ No "To Workspace" blocks found\n');
        fprintf('  → You may need to add one for efficiency output\n');
    end
else
    fprintf('✗ PT subsystem "PT_Pwr" not found\n');

    % Try alternative names
    fprintf('  Searching for alternative PT subsystem names...\n');
    pt_alt = find_system(model_name, 'Name', 'PT_Par');
    if ~isempty(pt_alt)
        fprintf('  ✓ Found: %s\n', pt_alt{1});
    else
        fprintf('  ✗ No PT_Par found either\n');
    end

    % Search for any subsystem with "PT" in name
    pt_all = find_system(model_name, 'BlockType', 'SubSystem', 'Name', 'PT');
    fprintf('  Subsystems containing "PT": %d\n', length(pt_all));
    if ~isempty(pt_all)
        for i = 1:length(pt_all)
            fprintf('    %d. %s\n', i, pt_all{i});
        end
    end
end

%% Search for PT temperature-related blocks
fprintf('\n=== PT Temperature Sensors ===\n');

% Search for zz_data_ptTemp related blocks
pt_temp_blocks = find_system(model_name, 'BlockType', 'ToWorkspace', 'VariableName', 'zz_data_ptTemp');
fprintf('Blocks saving to zz_data_ptTemp: %d\n', length(pt_temp_blocks));

if ~isempty(pt_temp_blocks)
    for i = 1:length(pt_temp_blocks)
        fprintf('  %d. %s\n', i, pt_temp_blocks{i});

        % Try to get more info about the signal
        try
            block_path = pt_temp_blocks{i};
            port_handles = get_param(block_path, 'PortHandles');
            fprintf('     Block type: %s\n', get_param(block_path, 'BlockType'));
        catch
        end
    end
else
    fprintf('  ⚠ No blocks found saving to zz_data_ptTemp\n');
end

% Check workspace for PT temperature data
fprintf('\n  Checking workspace for zz_data_ptTemp...\n');
if evalin('base', 'exist(''zz_data_ptTemp'', ''var'')')
    pt_temp_data = evalin('base', 'zz_data_ptTemp');
    fprintf('  ✓ Variable exists in workspace\n');
    fprintf('    Size: [%d × %d]\n', size(pt_temp_data, 1), size(pt_temp_data, 2));

    if size(pt_temp_data, 2) >= 2
        fprintf('    Column 1 range: [%.2f, %.2f]\n', min(pt_temp_data(:,1)), max(pt_temp_data(:,1)));
        fprintf('    Column 2 range: [%.2f, %.2f]\n', min(pt_temp_data(:,2)), max(pt_temp_data(:,2)));

        % Check if columns are different
        if std(pt_temp_data(:,1)) < 1.0
            fprintf('    → Column 1 appears CONSTANT (likely setpoint)\n');
        else
            fprintf('    → Column 1 appears VARYING (likely temperature)\n');
        end

        if std(pt_temp_data(:,2)) < 1.0
            fprintf('    → Column 2 appears CONSTANT\n');
        else
            fprintf('    → Column 2 appears VARYING (likely temperature)\n');
        end
    end
else
    fprintf('  ✗ Variable not found in workspace (run simulation first)\n');
end

%% Search for PT power-related blocks
fprintf('\n=== PT Power Measurement ===\n');

pt_power_blocks = find_system(model_name, 'BlockType', 'ToWorkspace', 'VariableName', 'zz_data_ptGenPw');
fprintf('Blocks saving to zz_data_ptGenPw: %d\n', length(pt_power_blocks));

if ~isempty(pt_power_blocks)
    for i = 1:length(pt_power_blocks)
        fprintf('  %d. %s\n', i, pt_power_blocks{i});
    end
end

% Check workspace
fprintf('\n  Checking workspace for zz_data_ptGenPw...\n');
if evalin('base', 'exist(''zz_data_ptGenPw'', ''var'')')
    pt_power_data = evalin('base', 'zz_data_ptGenPw');
    fprintf('  ✓ Variable exists in workspace\n');
    fprintf('    Size: [%d × %d]\n', size(pt_power_data, 1), size(pt_power_data, 2));

    for col = 1:size(pt_power_data, 2)
        fprintf('    Column %d range: [%.2f, %.2f]\n', col, min(pt_power_data(:,col)), max(pt_power_data(:,col)));
    end

    if size(pt_power_data, 2) == 3
        fprintf('  → Likely: Col1=?, Col2=?, Col3=Actual Power (verify!)\n');
    end
else
    fprintf('  ✗ Variable not found in workspace (run simulation first)\n');
end

%% Summary and recommendations
fprintf('\n========================================\n');
fprintf('  Recommendations\n');
fprintf('========================================\n\n');

fprintf('1. For S11 (Compressor Efficiency):\n');
if ~isempty(comp_subsys)
    fprintf('   - Open subsystem: %s\n', comp_subsys{1});
    fprintf('   - Look for efficiency calculation blocks\n');
    fprintf('   - Add "To Workspace" block if efficiency is calculated but not logged\n');
    fprintf('   - Variable name suggestion: zz_data_CompEff\n');
else
    fprintf('   - Locate the compressor subsystem first\n');
end

fprintf('\n2. For S19 (PT Efficiency):\n');
if ~isempty(pt_subsys)
    fprintf('   - Open subsystem: %s\n', pt_subsys{1});
    fprintf('   - Look for efficiency calculation blocks\n');
    fprintf('   - Add "To Workspace" block if efficiency is calculated but not logged\n');
    fprintf('   - Variable name suggestion: zz_data_PTEff\n');
else
    fprintf('   - Locate the PT subsystem first (check screenshot 172434.png)\n');
    fprintf('   - It may be named PT_Par instead of PT_Pwr\n');
end

fprintf('\n3. For S15 vs S18 (PT inlet vs outlet temperature):\n');
fprintf('   - Check if zz_data_ptTemp has one or two temperature measurements\n');
fprintf('   - If only one column varies, you may need separate inlet/outlet variables\n');
fprintf('   - Verify in PT subsystem which temperature is being logged\n');

fprintf('\n4. For S20 (Overall Thermal Efficiency):\n');
fprintf('   - Option A: Find calculated efficiency in PT_Pwr subsystem\n');
fprintf('   - Option B: Calculate from: efficiency = Power_out / (Fuel_flow × LHV)\n');
fprintf('   - LHV for natural gas ≈ 50,000 kJ/kg\n');

fprintf('\n========================================\n');
fprintf('  Next Steps\n');
fprintf('========================================\n\n');

fprintf('1. Screenshot the interior of subsystems:\n');
if ~isempty(comp_subsys)
    fprintf('   >> open_system(''%s'')\n', comp_subsys{1});
end
if ~isempty(pt_subsys)
    fprintf('   >> open_system(''%s'')\n', pt_subsys{1});
end

fprintf('\n2. Check current workspace variables:\n');
fprintf('   >> whos zz_data*\n');

fprintf('\n3. Run a test simulation:\n');
fprintf('   >> sim(''Core/Models/AvonGasTurbineDgTwin'', ''StopTime'', ''100'')\n');

fprintf('\n4. After simulation, check if new variables appeared:\n');
fprintf('   >> whos\n');

fprintf('\n========================================\n\n');
