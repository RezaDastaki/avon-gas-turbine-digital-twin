% DebugSimulationOutput.m
% Debug script to inspect the SimulationOutput object structure
%
% Run this AFTER running a simulation to see what's in 'ans'
%
% Date: 2025-12-30

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║         SIMULATION OUTPUT INSPECTOR                         ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% Check if ans exists and is SimulationOutput
if ~exist('ans', 'var')
    fprintf('✗ Variable "ans" not found in workspace.\n');
    fprintf('  Run a simulation first using sim() command.\n\n');
    return;
end

if ~isobject(ans)
    fprintf('✗ Variable "ans" is not an object.\n');
    fprintf('  Type: %s\n\n', class(ans));
    return;
end

fprintf('✓ Found SimulationOutput object in "ans"\n');
fprintf('  Class: %s\n\n', class(ans));

%% Display all properties
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('Properties of SimulationOutput:\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

props = properties(ans);
fprintf('Total properties: %d\n\n', length(props));

for i = 1:length(props)
    prop_name = props{i};

    try
        prop_value = ans.(prop_name);

        % Display property info
        fprintf('  [%2d] %-30s: ', i, prop_name);

        if isempty(prop_value)
            fprintf('(empty)\n');
        elseif isobject(prop_value)
            fprintf('Object (%s)', class(prop_value));

            % If it's logsout, show number of signals
            if strcmp(class(prop_value), 'Simulink.SimulationData.Dataset')
                fprintf(' with %d elements\n', prop_value.numElements);
            else
                fprintf('\n');
            end
        elseif isnumeric(prop_value)
            fprintf('[%d × %d] numeric\n', size(prop_value, 1), size(prop_value, 2));
        else
            fprintf('%s\n', class(prop_value));
        end
    catch ME
        fprintf('  [%2d] %-30s: Cannot access (%s)\n', i, prop_name, ME.message);
    end
end

%% Check for logsout specifically
fprintf('\n');
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('Checking for logsout (logged signals):\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

if isprop(ans, 'logsout') && ~isempty(ans.logsout)
    logsout = ans.logsout;

    fprintf('✓ logsout found!\n');
    fprintf('  Type: %s\n', class(logsout));
    fprintf('  Number of signals: %d\n\n', logsout.numElements);

    fprintf('Logged signals:\n');
    fprintf('───────────────────────────────────────────────────────────────\n\n');

    for i = 1:logsout.numElements
        element = logsout.getElement(i);

        fprintf('  [%2d] Name: %-35s', i, element.Name);

        % Get data info
        data = element.Values;

        if isa(data, 'timeseries')
            fprintf('  [%d samples]\n', length(data.Data));
        else
            fprintf('  [%s]\n', class(data));
        end
    end

    fprintf('\n');

else
    fprintf('✗ logsout not found or empty\n');
    fprintf('  This means no signals were logged via Signal Logging.\n');
    fprintf('  You need to configure Signal Logging in Simulink.\n\n');
end

%% Check for other common fields
fprintf('═══════════════════════════════════════════════════════════════\n');
fprintf('Checking for other data fields:\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

% Check for time
if isprop(ans, 'time') && ~isempty(ans.time)
    fprintf('✓ time: [%d samples]\n', length(ans.time));
elseif isprop(ans, 'tout') && ~isempty(ans.tout)
    fprintf('✓ tout: [%d samples]\n', length(ans.tout));
else
    fprintf('✗ No time vector found\n');
end

% Check for yout
if isprop(ans, 'yout') && ~isempty(ans.yout)
    fprintf('✓ yout: [%d × %d]\n', size(ans.yout, 1), size(ans.yout, 2));
else
    fprintf('✗ No yout found\n');
end

% Check for xout (states)
if isprop(ans, 'xout') && ~isempty(ans.xout)
    fprintf('✓ xout: [%d × %d]\n', size(ans.xout, 1), size(ans.xout, 2));
else
    fprintf('✗ No xout found\n');
end

fprintf('\n');
fprintf('═══════════════════════════════════════════════════════════════\n\n');

fprintf('Summary:\n');
fprintf('  Your simulation data is stored in the SimulationOutput object.\n');
fprintf('  The updated RunSimulinkModel.m should now extract this data.\n\n');

fprintf('Next steps:\n');
fprintf('  1. Run TestSimulinkConfig again to verify extraction works\n');
fprintf('  2. If still failing, check Simulink Signal Logging settings\n\n');

fprintf('═══════════════════════════════════════════════════════════════\n\n');
