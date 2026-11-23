function d = AvonLogDir()
% AvonLogDir - Folder for logs, progress manifests and driver lock files.
%
% Release layout: the data root (AvonDataRoot) holds ONLY the released
% tree and may be read-only, so nothing operational is written there. Logs live in
% <repo>/Logs, overridable by the AVON_LOG_DIR environment variable. The folder is
% created on first call.
    env_dir = getenv('AVON_LOG_DIR');
    if ~isempty(env_dir)
        d = env_dir;
    else
        sc_path = which('ScenarioConfig');
        if isempty(sc_path)
            error('AvonLogDir:NoScenarioConfig', ...
                'ScenarioConfig.m is not on the MATLAB path -- run setup_paths.m first.');
        end
        d = fullfile(fileparts(fileparts(sc_path)), 'Logs');
    end
    if ~isfolder(d)
        mkdir(d);
    end
    d = char(java.io.File(d).getCanonicalPath());
end
