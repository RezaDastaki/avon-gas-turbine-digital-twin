function [fault_label, severity_label] = GenerateFaultLabels(time_vector, fault_ids, severity_levels, fault_start_times, fault_defs)
% GenerateFaultLabels - Generate per-timestep label arrays for one scenario
%
% Produces two [N × 42] integer arrays for ML training:
%   fault_label    — binary (0/1): is fault F(i) active at this timestep?
%   severity_label — 0 or 1-5: instantaneous severity of fault F(i) at this timestep
%
% Inputs:
%   time_vector       [N×1] double  — time in seconds (from ExtractSensorsFromWorkspace)
%   fault_ids         [1×k] int     — active fault IDs (1-42); pass [] for healthy
%   severity_levels   [1×k] int     — prescribed severity (1-5) per fault; pass [] for healthy
%   fault_start_times [1×k] double  — fault activation time in seconds per fault; pass [] for healthy
%   fault_defs        struct        — from GetFaultDefinitions
%
% Outputs:
%   fault_label       [N×42] int32 — 0=inactive, 1=active; column i = fault F(i)
%   severity_label    [N×42] int32 — 0=inactive, 1-5=instantaneous severity; column i = fault F(i)
%
% NOTE: Fault IDs (1-42) map directly to column indices — no DatasetID remapping.
%       fault_ids(k) = fid  →  output column index = fid
%
% Severity label rules per profile type:
%   step / oscillate / freeze:
%     fault_label(:,fid)    = 0 before fault_start_time, 1 at and after
%     severity_label(:,fid) = 0 before fault_start_time, S (fixed) at and after
%
%   linear_ramp (DriftDuration D > 0):
%     fault_label(:,fid)    = 0 before fault_start_time, 1 at and after
%     severity_label(:,fid) = 0 before fault_start_time
%                             During ramp [t_start, t_start+D]:
%                               max(1, round(1 + (S-1) * progress)) where progress = (t-t_start)/D
%                               → starts at 1 (fault just activated), ends at S (fully developed)
%                             After ramp end: S (constant)
%
% Date: 2026-03-15 — Rebuilt for unified F01-F42 system (no DatasetID remapping)

N = length(time_vector);
fault_label    = zeros(N, 42, 'int32');
severity_label = zeros(N, 42, 'int32');

if isempty(fault_ids)
    return;   % healthy scenario — all-zero labels
end

for k = 1 : length(fault_ids)
    fid     = fault_ids(k);           % fault ID (1-42) = output column index directly
    S       = severity_levels(k);     % prescribed severity (1-5)
    t_start = fault_start_times(k);   % fault activation time (seconds)
    profile = fault_defs.ProfileType{fid};
    D       = fault_defs.DriftDuration(fid);  % ramp duration (0 for step/oscillate/freeze)

    active_mask = time_vector >= t_start;

    % Binary fault label: 1 from fault_start_time onwards
    fault_label(active_mask, fid) = int32(1);

    % Severity label — depends on profile
    if strcmp(profile, 'linear_ramp') && D > 0
        ramp_end  = t_start + D;
        t_active  = time_vector(active_mask);

        in_ramp   = t_active < ramp_end;
        post_ramp = ~in_ramp;

        sev_vec = zeros(sum(active_mask), 1, 'int32');
        sev_vec(post_ramp) = int32(S);

        if any(in_ramp)
            progress         = (t_active(in_ramp) - t_start) / D;   % ∈ [0, 1)
            sev_vec(in_ramp) = int32(max(1, round(1 + (S - 1) .* progress)));
        end

        severity_label(active_mask, fid) = sev_vec;
    else
        % step, oscillate, freeze: fixed severity from fault_start_time
        severity_label(active_mask, fid) = int32(S);
    end
end

end
