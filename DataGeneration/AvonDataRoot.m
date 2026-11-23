function root = AvonDataRoot()
% AvonDataRoot - Resolves the dataset root for this machine/checkout.
%
% the pipeline must run on any machine, at any path, on any drive
% letter, because the code is released alongside the data. This function is what
% ScenarioConfig.m's four output-root constants call to become absolute instead
% of cwd-relative.
%
% Resolution order:
%   1. The AVON_DATA_ROOT environment variable, if set and non-empty.
%   2. Otherwise <repo>/Data, derived from where the code actually is
%      (<repo>/DataGeneration/ScenarioConfig.m -> up 2 -> <repo>, then /Data).
%
% RELEASE LAYOUT: the released tree sits DIRECTLY inside this root,
% exactly as on Zenodo -- DIAG_Healthy/, DIAG_F01_<Code>/ ... DIAG_DualFault/,
% DIAG_TripleFault/, DIAG_QuadFault/, RTF_Fxx_<Code>/, DiagnosisTurndown/ -- so a
% regenerated tree is the release tree. Nothing but data goes in this root: logs,
% manifests, locks and checkpoints live under <repo>/Logs and <repo>/Checkpoints
% (see AvonLogDir.m), so the root may safely be read-only.
%
% Returns an absolute path and creates the folder if absent.
%
% The default root is <repo>/Data, one level below the repository root; there is no
% extra 'Dataset' folder level.

    env_root = getenv('AVON_DATA_ROOT');
    if ~isempty(env_root)
        root = env_root;
    else
        sc_path = which('ScenarioConfig');
        if isempty(sc_path)
            error('AvonDataRoot:NoScenarioConfig', ...
                'ScenarioConfig.m is not on the MATLAB path -- run setup_paths.m first.');
        end
        % sc_path = <repo>/DataGeneration/ScenarioConfig.m
        % fileparts once  -> <repo>/DataGeneration
        % fileparts twice -> <repo>
        root = fullfile(fileparts(fileparts(sc_path)), 'Data');
    end

    % Return an absolute, fully-qualified path regardless of how it was built.
    % The folder is created only if absent (an existing, possibly read-only, root is
    % never touched).
    if ~isfolder(root)
        mkdir(root);
    end
    root = char(java.io.File(root).getCanonicalPath());
end
