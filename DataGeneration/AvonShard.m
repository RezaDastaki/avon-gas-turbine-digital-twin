function [shard, n_shards] = AvonShard()
% AvonShard - Resolves this machine's shard index and shard count for
% multi-machine split.
%
% Resolves EXACTLY like AvonWorkers.m resolves its value -- same three-stage order, same
% config.txt file, same "env wins over config.txt wins over default" precedence -- so a
% single-machine run behaves exactly as it does today (spec: "so a single-machine
% run behaves exactly as it does today and nothing already tested changes"):
%
%   1. The AVON_SHARD / AVON_SHARDS environment variables, if set, non-empty and valid
%      positive integers.
%   2. Otherwise AVON_SHARD=<k> / AVON_SHARDS=<n> inside config.txt.
%   3. Otherwise the default: shard 1 of 1 (i.e. everything, unsharded).
%
% shard and n_shards are resolved TOGETHER but INDEPENDENTLY of each other (either may come
% from the environment while the other comes from config.txt or the default) -- there is no
% requirement that both come from the same source, matching AvonWorkers.m's own per-key
% resolution and keeping the two settings orthogonal in config.txt.
%
% Validity is enforced here, not just at the call site: AVON_SHARD and AVON_SHARDS must each
% be a positive integer, and AVON_SHARD must be <= AVON_SHARDS, or this errors outright --
% spec "a typo here silently duplicates or drops part of the release, which is the
% worst failure mode available and must be caught before generation starts." 1_SETUP.bat's
% own check (W7) calls this function precisely so the failure happens there, before anything
% is generated.
%

    env_shard_raw  = getenv('AVON_SHARD');
    env_shards_raw = getenv('AVON_SHARDS');

    repo_dir = fileparts(fileparts(mfilename('fullpath')));  % <repo>/DataGeneration -> the repository root
    cfg_path  = fullfile(repo_dir, 'config.txt');
    cfg_shard_raw  = '';
    cfg_shards_raw = '';
    if isfile(cfg_path)
        cfg_shard_raw  = local_read_config_key(cfg_path, 'AVON_SHARD');
        cfg_shards_raw = local_read_config_key(cfg_path, 'AVON_SHARDS');
    end

    % For each of AVON_SHARD / AVON_SHARDS independently: if the env var is SET
    % (non-empty), it must parse as a positive integer -- a non-numeric env value is a typo
    % and must fail loudly here (W7), never silently fall through to config.txt/default.
    % Same rule for config.txt once an env var is absent: a present-but-bad config.txt key
    % also fails loudly rather than silently defaulting.
    if ~isempty(env_shard_raw)
        shard = local_parse_positive_int(env_shard_raw);
        if isempty(shard)
            error('AvonShard:BadShard', 'AVON_SHARD environment variable is not a positive integer. Got: "%s"', env_shard_raw);
        end
    elseif ~isempty(cfg_shard_raw)
        shard = local_parse_positive_int(cfg_shard_raw);
        if isempty(shard)
            error('AvonShard:BadShard', 'AVON_SHARD in config.txt is not a positive integer. Got: "%s"', cfg_shard_raw);
        end
    else
        shard = 1;
    end

    if ~isempty(env_shards_raw)
        n_shards = local_parse_positive_int(env_shards_raw);
        if isempty(n_shards)
            error('AvonShard:BadShards', 'AVON_SHARDS environment variable is not a positive integer. Got: "%s"', env_shards_raw);
        end
    elseif ~isempty(cfg_shards_raw)
        n_shards = local_parse_positive_int(cfg_shards_raw);
        if isempty(n_shards)
            error('AvonShard:BadShards', 'AVON_SHARDS in config.txt is not a positive integer. Got: "%s"', cfg_shards_raw);
        end
    else
        n_shards = 1;
    end

    if shard > n_shards
        error('AvonShard:ShardOutOfRange', ...
            'AVON_SHARD (%d) must be <= AVON_SHARDS (%d). A typo here silently drops part of the release.', ...
            shard, n_shards);
    end

    shard = double(shard);
    n_shards = double(n_shards);
end

function val = local_parse_positive_int(str)
    val = [];
    if isempty(str)
        return;
    end
    num = str2double(strtrim(str));
    if ~isnan(num) && isfinite(num) && num > 0 && num == round(num)
        val = round(num);
    end
end

function val = local_read_config_key(cfg_path, key)
% Returns the RAW string value of key in config.txt (not parsed/validated -- the caller
% validates, so a non-numeric config.txt value fails loudly rather than being silently
% treated as absent).
    val = '';
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
            if numel(parts) >= 2 && strcmpi(strtrim(parts{1}), key)
                candidate = strtrim(strjoin(parts(2:end), '='));
                if ~isempty(candidate)
                    val = candidate;
                    break;
                end
            end
        end
    catch
        % fall through to empty
    end
    fclose(fid);
end
