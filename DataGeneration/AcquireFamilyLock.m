function AcquireFamilyLock(lock_path)
% AcquireFamilyLock - (spec, "Both drivers"): refuses to let two drivers for the
% SAME family (diagnosis or RTF) run at once, since they would race writing the same files.
%
% Writes a small text lock file recording this process's PID, host and start time. If a lock
% file already exists AND its recorded PID is still a live process on this machine, errors
% (D8's acceptance: "The lock file prevents a second concurrent driver in the same family").
% If the recorded PID is no longer running (a prior run crashed/was killed without cleanup),
% the stale lock is removed and this call proceeds -- otherwise a crashed driver would
% permanently block every future run, which is worse than the race this guards against.
%
% Pair with ReleaseFamilyLock(lock_path), normally via onCleanup so the lock is released even
% on an error or Ctrl-C (best effort -- a hard kill of the MATLAB process cannot run cleanup
% code; see ReleaseFamilyLock.m / the stale-lock path above for why this is still safe).
%
% Usage:
%   AcquireFamilyLock(lock_path)   % throws AcquireFamilyLock:Held if a live lock exists
%

    lock_dir = fileparts(lock_path);
    if ~isempty(lock_dir) && ~isfolder(lock_dir)
        mkdir(lock_dir);
    end

    if isfile(lock_path)
        info = local_read_lock(lock_path);
        if ~isempty(info) && local_pid_alive(info.pid)
            error('AcquireFamilyLock:Held', ...
                ['A driver for this family is already running: PID %d on %s, started %s ' ...
                 '(lock file %s). Wait for it to finish, or confirm it is dead and delete ' ...
                 'the lock file by hand.'], ...
                info.pid, info.host, info.started, lock_path);
        else
            warning('AcquireFamilyLock:Stale', ...
                'Stale lock file at %s (recorded PID is no longer running) -- removing and proceeding.', ...
                lock_path);
            try
                delete(lock_path);
            catch
            end
        end
    end

    try
        pid = feature('getpid');
    catch
        pid = -1;  % feature('getpid') unavailable -- lock still written, liveness check degrades gracefully
    end
    host = getenv('COMPUTERNAME');
    if isempty(host), host = 'unknown-host'; end

    fid = fopen(lock_path, 'w');
    if fid < 0
        error('AcquireFamilyLock:CannotWrite', 'Cannot write lock file at %s.', lock_path);
    end
    fprintf(fid, 'pid=%d\n', pid);
    fprintf(fid, 'host=%s\n', host);
    fprintf(fid, 'started=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fclose(fid);
end

function info = local_read_lock(lock_path)
    info = [];
    try
        fid = fopen(lock_path, 'r');
        if fid < 0, return; end
        pid = -1; host = ''; started = '';
        while true
            line = fgetl(fid);
            if ~ischar(line), break; end
            parts = strsplit(line, '=');
            if numel(parts) < 2, continue; end
            key = strtrim(parts{1}); val = strtrim(strjoin(parts(2:end), '='));
            switch key
                case 'pid', pid = str2double(val);
                case 'host', host = val;
                case 'started', started = val;
            end
        end
        fclose(fid);
        if isnan(pid), pid = -1; end
        info = struct('pid', pid, 'host', host, 'started', started);
    catch
        info = [];
    end
end

function alive = local_pid_alive(pid)
    alive = false;
    if isempty(pid) || pid <= 0
        return;
    end
    try
        [status, out] = system(sprintf('tasklist /FI "PID eq %d" /NH', pid));
        if status == 0
            alive = contains(out, sprintf('%d', pid));
        end
    catch
        alive = false;  % cannot determine -- treat as not alive rather than deadlock forever
    end
end
