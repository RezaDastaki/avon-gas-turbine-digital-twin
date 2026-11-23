function CheckNamingConsistency(verbose)
% CheckNamingConsistency - Assert the MATLAB name tables equal FaultReference/fault_catalogue.csv.
%
% The catalogue (columns fault_id, code, name, ...) is the single naming source of truth for the
% release (naming scheme 2026-11-21). This asserts, with an error on any mismatch:
%   GetFaultDefinitions.Names{i} == catalogue name   and  .Codes{i} == catalogue code (i=1..42)
%   GetRTFMechanisms.Name{j}     == catalogue name of FaultID(j)
%   GetRTFMechanisms.Folder{j}   == ['RTF_' fault_id '_' code]
%   the catalogue's rtf_member column == the set of GetRTFMechanisms.FaultID
%   the combo tables yield 21 / 14 / 11 distinct, well-formed scenario folder names
% Usage: CheckNamingConsistency            (silent on success)
%        CheckNamingConsistency(true)      (prints a summary)
    if nargin < 1, verbose = false; end
    here = fileparts(mfilename('fullpath'));
    csv  = fullfile(here, '..', 'FaultReference', 'fault_catalogue.csv');
    if ~isfile(csv)
        error('CheckNamingConsistency:NoCatalogue', 'Catalogue not found: %s', csv);
    end
    T = readtable(csv, 'Delimiter', ',', 'TextType', 'string', 'VariableNamingRule', 'preserve');
    if height(T) ~= 42
        error('CheckNamingConsistency:Rows', 'fault_catalogue.csv has %d rows, expected 42.', height(T));
    end
    fd  = GetFaultDefinitions();
    rtf = GetRTFMechanisms();
    for i = 1:42
        want_id = sprintf('F%02d', i);
        if string(T.fault_id(i)) ~= want_id
            error('CheckNamingConsistency:Order', 'Catalogue row %d is %s, expected %s.', i, T.fault_id(i), want_id);
        end
        if ~strcmp(fd.Names{i}, char(T.name(i)))
            error('CheckNamingConsistency:Name', 'GetFaultDefinitions Names{%d} = "%s" but catalogue says "%s".', i, fd.Names{i}, T.name(i));
        end
        if ~strcmp(fd.Codes{i}, char(T.code(i)))
            error('CheckNamingConsistency:Code', 'GetFaultDefinitions Codes{%d} = "%s" but catalogue says "%s".', i, fd.Codes{i}, T.code(i));
        end
    end
    cat_rtf = find(string(T.rtf_member) == "yes");
    if ~isequal(sort(cat_rtf(:)), sort(rtf.FaultID(:)))
        error('CheckNamingConsistency:RTFSet', 'rtf_member set in catalogue differs from GetRTFMechanisms().FaultID.');
    end
    for j = 1:rtf.Count
        id = rtf.FaultID(j);
        if ~strcmp(rtf.Name{j}, char(T.name(id)))
            error('CheckNamingConsistency:RTFName', 'RTF Name{%d} = "%s" but catalogue says "%s".', j, rtf.Name{j}, T.name(id));
        end
        want_folder = sprintf('RTF_F%02d_%s', id, char(T.code(id)));
        if ~strcmp(rtf.Folder{j}, want_folder)
            error('CheckNamingConsistency:RTFFolder', 'RTF Folder{%d} = "%s", expected "%s".', j, rtf.Folder{j}, want_folder);
        end
    end
    % Scenario folder names built by the real builder: 89 distinct, grammar-conforming.
    names = {};
    [~, f] = GenerateScenarioInfo('healthy', 1); names{end+1} = fileparts(f); %#ok<AGROW>
    for id = 1:42
        [~, f] = GenerateScenarioInfo('single', 1, id, 1); names{end+1} = fileparts(f); %#ok<AGROW>
    end
    kinds = {'dual', 2; 'triple', 3; 'quad', 4};
    tabs  = {fd.DualCombos, fd.TripleCombos, fd.QuadCombos};
    for k = 1:3
        for c = 1:size(tabs{k}, 1)
            [~, f] = GenerateScenarioInfo(kinds{k,1}, 1, c, ones(1, kinds{k,2})); names{end+1} = fileparts(f); %#ok<AGROW>
        end
    end
    leaf = cellfun(@(p) string(local_leaf(p)), names);
    if numel(unique(leaf)) ~= 89
        error('CheckNamingConsistency:Scenarios', 'Expected 89 distinct scenario folders, got %d.', numel(unique(leaf)));
    end
    pat = '^(DIAG|TD)_(Healthy|F\d{2}_[A-Za-z]\w*|DualFault_(F\d{2}){2}|TripleFault_(F\d{2}){3}|QuadFault_(F\d{2}){4})$';
    bad = leaf(cellfun(@isempty, regexp(leaf, pat, 'once')));
    if ~isempty(bad)
        error('CheckNamingConsistency:Grammar', 'Scenario folder "%s" does not fit the naming grammar.', bad(1));
    end
    if verbose
        fprintf('CheckNamingConsistency: 42 names/codes, %d RTF mechanisms and 89 scenario folders agree with fault_catalogue.csv\n', rtf.Count);
    end
end

function n = local_leaf(p)
    [~, n] = fileparts(p);
end
