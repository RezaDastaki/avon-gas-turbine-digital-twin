function n = AvonWorkers()
% AvonWorkers - Resolves the worker count for the parallel drivers.
%
% Resolution order:
%   1. The AVON_WORKERS environment variable, if set, non-empty and a valid
%      positive integer.
%   2. Otherwise AVON_WORKERS=<n> inside config.txt (a simple KEY=VALUE
%      text file, one setting per line, '#' comments allowed), if present and
%      parseable.
%   3. Otherwise a default of feature('numcores') (the machine's physical core
%      count), capped at 32.
%

    n = [];

    env_val = getenv('AVON_WORKERS');
    if ~isempty(env_val)
        n = local_parse_positive_int(env_val);
    end

    if isempty(n)
        % config.txt, derived from where AvonWorkers.m itself lives
        % (<repo>/DataGeneration/AvonWorkers.m -> up 1 -> DataGeneration -> up 1 -> the repository root).
        super_dir = fileparts(fileparts(mfilename('fullpath')));
        cfg_path = fullfile(super_dir, 'config.txt');
        if isfile(cfg_path)
            n = local_read_config_workers(cfg_path);
        end
    end

    if isempty(n)
        try
            n = feature('numcores');
        catch
            n = 4; % conservative fallback if feature is unavailable
        end
        n = min(n, 32);
    end

    n = double(n);
end

function val = local_parse_positive_int(str)
    val = [];
    num = str2double(strtrim(str));
    if ~isnan(num) && isfinite(num) && num > 0 && num == round(num)
        val = round(num);
    end
end

function val = local_read_config_workers(cfg_path)
    val = [];
    fid = fopen(cfg_path, 'r');
    if fid < 0
        return;
    end
    try
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
            if numel(parts) >= 2 && strcmpi(strtrim(parts{1}), 'AVON_WORKERS')
                val = local_parse_positive_int(strtrim(strjoin(parts(2:end), '=')));
                if ~isempty(val)
                    break;
                end
            end
        end
    catch
        % fall through to empty
    end
    fclose(fid);
end
