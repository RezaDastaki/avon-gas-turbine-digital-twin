function VerifyLabelAccuracy()
% Read-only spot check: does fault_label/severity_label match the documented
% fault-activation timing and severity ramp behavior for a sample of files
% spanning each profile type (step, ramp, oscillate, freeze) plus one
% multi-fault file. Does NOT modify any dataset file.

base = AvonDataRoot();   % release layout: <root>/DIAG_F07_<Code>/DIAG_F07_E0001.h5 ...

files = {
    fullfile(base,'DIAG_F07_FuelRegulatorStuck/DIAG_F07_E0001.h5'),        'F07 (step)',      7,  [];
    fullfile(base,'DIAG_F21_GGTurbineFouling/DIAG_F21_E0001.h5'),          'F21 (ramp)',      21, [];
    fullfile(base,'DIAG_F18_HeatReleaseOscillation/DIAG_F18_E0001.h5'),    'F18 (oscillate)', 18, [];
    fullfile(base,'DIAG_F37_GGTempSensorFreeze/DIAG_F37_E0001.h5'),        'F37 (freeze)',    37, [];
    fullfile(base,'DIAG_F13_FGPressureOscillation/DIAG_F13_E0001.h5'),     'F13 (oscillate)', 13, [];
    fullfile(base,'DIAG_DualFault/DIAG_DualFault_F02F26/DIAG_F02F26_E0001.h5'), 'F02+F26 (dual, ramp+ramp)', [2 26], []
};

for k = 1:size(files,1)
    f = files{k,1};
    label = files{k,2};
    fault_ids = files{k,3};

    fprintf('\n================ %s ================\n', label);
    fprintf('File: %s\n', f);

    t   = h5read(f, '/time');
    fl  = h5read(f, '/fault_label');
    sl  = h5read(f, '/severity_label');
    fst = h5readatt(f, '/', 'fault_start_times');
    dt  = t(2) - t(1);

    for i = 1:length(fault_ids)
        fid = fault_ids(i);
        col = fid; % column i (1-based in MATLAB) = fault F(i)
        declared_t_start = fst(i);

        active_idx = find(fl(:,col) == 1, 1, 'first');
        actual_t_start = t(active_idx);

        pre_mask  = fl(:,col) == 0;
        post_mask = fl(:,col) == 1;

        final_sev = sl(end, col);
        declared_sev_attr = '';
        try
            if length(fault_ids) == 1
                declared_sev_attr = h5readatt(f,'/','severity');
            else
                declared_sev_attr = h5readatt(f,'/',sprintf('fault_%02d_severity', i));
            end
        catch
        end

        fprintf('  Fault F%02d: declared t_start=%.1fs | label transitions to 1 at t=%.1fs (diff=%.2fs, dt=%.2fs)\n', ...
            fid, declared_t_start, actual_t_start, actual_t_start - declared_t_start, dt);
        fprintf('    severity_label final value=%d | declared severity attr=%s\n', final_sev, mat2str(declared_sev_attr));

        % Check monotonic non-decreasing severity_label after activation, and 0 before
        sev_col = sl(:,col);
        pre_ok  = all(sev_col(pre_mask) == 0);
        post_vals = sev_col(post_mask);
        mono_ok = all(diff(post_vals) >= 0);
        fprintf('    severity_label == 0 before activation: %d | non-decreasing after activation: %d\n', pre_ok, mono_ok);

        % Find ramp completion (first index where severity reaches final value) to report effective ramp length
        ramp_complete_idx = find(post_vals == final_sev, 1, 'first');
        if ~isempty(ramp_complete_idx)
            t_post = t(post_mask);
            fprintf('    severity reaches final value %d at t=%.1fs (%.1fs after activation)\n', ...
                final_sev, t_post(ramp_complete_idx), t_post(ramp_complete_idx) - actual_t_start);
        end
    end

    % Sensor sanity check: pick one representative sensor per fault and compare
    % pre- vs post-activation statistics (mean, std) to confirm the sensor
    % actually responds when the label says the fault is active.
    sensors = h5read(f, '/sensors');
    sensor_map = containers.Map({7,21,18,37,13,2,24}, {7, 24, 16, 19, 1, 12, 14});
    % F07->S07(air flow, indirectly via fuel pressure->combustor), F21->S24(GG speed),
    % F18->S16(combustor exit temp, oscillation), F37->S19(freeze target),
    % F13->S01(FG supply pressure, oscillation), F02->S12(compressor eff), F24->S14(rotor cooling flow)
    for i = 1:length(fault_ids)
        fid = fault_ids(i);
        col = fid;
        pre_mask  = fl(:,col) == 0;
        post_mask = fl(:,col) == 1;
        if isKey(sensor_map, fid)
            s = sensor_map(fid);
            pre_vals  = sensors(pre_mask, s);
            post_vals = sensors(post_mask, s);
            fprintf('  Sensor S%02d (mapped to F%02d): pre-activation mean=%.4f std=%.4f | post-activation mean=%.4f std=%.4f\n', ...
                s, fid, mean(pre_vals), std(pre_vals), mean(post_vals), std(post_vals));
        end
    end
end

fprintf('\n\nAll checks read-only. No files modified.\n');
end
