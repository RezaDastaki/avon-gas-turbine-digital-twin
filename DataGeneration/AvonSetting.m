function val = AvonSetting(key, default)
% AvonSetting - Resolves one AVON_* setting, the same way AvonWorkers.m and AvonShard.m do.
%
% Resolution order (identical to the other AVON_* settings):
%   1. the environment variable <key>, if set and non-empty;
%   2. otherwise <key>=<value> inside config.txt (KEY=VALUE lines, '#' comments);
%   3. otherwise `default`.
%
% A numeric `default` makes the setting numeric: a set value must then parse as a positive
% integer, and anything else is an error rather than a silent fall-through to the default (a
% typo in a run-to-failure cap must not quietly restore the production value). A char `default`
% returns the raw string.
%
% Used by ScenarioConfig.RTFCapCycles and GenerateRTFParallel for the two test-only RTF
% settings (AVON_RTF_CAP_CYCLES, AVON_RTF_MAX_UNITS); production never sets either.
%

    raw = getenv(key);
    where = 'environment variable';

    if isempty(raw)
        cfg_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'config.txt');   % config.txt
        raw = local_read_config_key(cfg_path, key);
        where = 'config.txt';
    end

    if isempty(raw)
        val = default;
        return;
    end

    if ischar(default)
        val = raw;
        return;
    end

    num = str2double(strtrim(raw));
    if isnan(num) || ~isfinite(num) || num <= 0 || num ~= round(num)
        error('AvonSetting:BadValue', '%s (%s) must be a positive integer. Got: "%s"', key, where, raw);
    end
    val = double(num);
end

function val = local_read_config_key(cfg_path, key)
    val = '';
    if ~isfile(cfg_path)
        return;
    end
    fid = fopen(cfg_path, 'r');
    if fid < 0
        return;
    end
    cleanup = onCleanup(@() fclose(fid));
    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        line = strtrim(line);
        if isempty(line) || startsWith(line, '#')
            continue;
        end
        parts = strsplit(line, '=');
        if numel(parts) >= 2 && strcmpi(strtrim(parts{1}), key)
            val = strtrim(strjoin(parts(2:end), '='));
            return;
        end
    end
end
