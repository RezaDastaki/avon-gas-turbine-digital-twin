function [unit_file, refcheck_file, folder_name] = RTFUnitPath(fault_id, unit_id)
% RTFUnitPath - The ONE builder of run-to-failure unit file names (naming scheme, 2026-11-21).
%   <RTF_OUTPUT_ROOT>/RTF_Fxx_<code>/RTF_Fxx_UNNNN.h5  [release layout 2026-11-23: RTF_OUTPUT_ROOT is the data root]   and   RTF_Fxx_UNNNN_refchecks.csv
% Used by RunRTFUnit.m (writer) and RTFAlreadyDone.m (resume check) so they can never disagree.
    rtf = GetRTFMechanisms();
    idx = find(rtf.FaultID == fault_id, 1);
    if isempty(idx)
        error('RTFUnitPath:NotAMechanism', 'fault_id %d is not a run-to-failure mechanism (see GetRTFMechanisms).', fault_id);
    end
    folder_name   = rtf.Folder{idx};
    stem          = sprintf('RTF_F%02d_U%04d', fault_id, unit_id);
    unit_file     = fullfile(ScenarioConfig.RTF_OUTPUT_ROOT, folder_name, [stem '.h5']);
    refcheck_file = fullfile(ScenarioConfig.RTF_OUTPUT_ROOT, folder_name, [stem '_refchecks.csv']);
end
