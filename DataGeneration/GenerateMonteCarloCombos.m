% GenerateMonteCarloCombos.m
% Run-once utility to display and verify all multi-fault combinations
%
% This script prints the dual/triple/quad fault combination tables with
% fault names, allowing visual verification that all combos are physically
% meaningful and cover the full fault space.
%
% Run from the <repo>/DataGeneration directory.
%
% Date: 2026-03-14

fault_defs = GetFaultDefinitions();

fprintf('\n========================================\n');
fprintf('  Multi-Fault Combination Tables\n');
fprintf('  Avon Mk1533 Digital Twin Dataset\n');
fprintf('========================================\n\n');

%% Dual-Fault Combinations
fprintf('DUAL-FAULT COMBINATIONS (%d total)\n', size(fault_defs.DualCombos, 1));
fprintf('%s\n', repmat('-', 1, 70));
for k = 1:size(fault_defs.DualCombos, 1)
    f1 = fault_defs.DualCombos(k, 1);
    f2 = fault_defs.DualCombos(k, 2);
    fprintf('  Combo %d: F%02d + F%02d\n', k, f1, f2);
    fprintf('           %s\n', fault_defs.Names{f1});
    fprintf('         + %s\n', fault_defs.Names{f2});
    fprintf('           Groups: %s + %s\n\n', fault_defs.Group{f1}, fault_defs.Group{f2});
end

%% Triple-Fault Combinations
fprintf('TRIPLE-FAULT COMBINATIONS (%d total)\n', size(fault_defs.TripleCombos, 1));
fprintf('%s\n', repmat('-', 1, 70));
for k = 1:size(fault_defs.TripleCombos, 1)
    f1 = fault_defs.TripleCombos(k, 1);
    f2 = fault_defs.TripleCombos(k, 2);
    f3 = fault_defs.TripleCombos(k, 3);
    fprintf('  Combo %d: F%02d + F%02d + F%02d\n', k, f1, f2, f3);
    fprintf('           %s\n', fault_defs.Names{f1});
    fprintf('         + %s\n', fault_defs.Names{f2});
    fprintf('         + %s\n', fault_defs.Names{f3});
    fprintf('           Groups: %s + %s + %s\n\n', ...
        fault_defs.Group{f1}, fault_defs.Group{f2}, fault_defs.Group{f3});
end

%% Quad-Fault Combinations
fprintf('QUAD-FAULT COMBINATIONS (%d total)\n', size(fault_defs.QuadCombos, 1));
fprintf('%s\n', repmat('-', 1, 70));
for k = 1:size(fault_defs.QuadCombos, 1)
    f1 = fault_defs.QuadCombos(k, 1);
    f2 = fault_defs.QuadCombos(k, 2);
    f3 = fault_defs.QuadCombos(k, 3);
    f4 = fault_defs.QuadCombos(k, 4);
    fprintf('  Combo %d: F%02d + F%02d + F%02d + F%02d\n', k, f1, f2, f3, f4);
    fprintf('           %s\n', fault_defs.Names{f1});
    fprintf('         + %s\n', fault_defs.Names{f2});
    fprintf('         + %s\n', fault_defs.Names{f3});
    fprintf('         + %s\n', fault_defs.Names{f4});
    fprintf('           Groups: %s + %s + %s + %s\n\n', ...
        fault_defs.Group{f1}, fault_defs.Group{f2}, ...
        fault_defs.Group{f3}, fault_defs.Group{f4});
end

%% Summary
fprintf('========================================\n');
fprintf('Summary:\n');
fprintf('  Total faults:      %d (F01-F42)\n', fault_defs.Count);
fprintf('  Dual combos:       %d\n', size(fault_defs.DualCombos, 1));
fprintf('  Triple combos:     %d\n', size(fault_defs.TripleCombos, 1));
fprintf('  Quad combos:       %d\n', size(fault_defs.QuadCombos, 1));
fprintf('  Total multi-fault: %d combinations\n', ...
    size(fault_defs.DualCombos,1) + size(fault_defs.TripleCombos,1) + size(fault_defs.QuadCombos,1));
fprintf('========================================\n\n');
