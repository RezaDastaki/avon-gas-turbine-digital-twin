function ReleaseFamilyLock(lock_path)
% ReleaseFamilyLock - Companion to AcquireFamilyLock.m. Deletes the lock file if present.
% Best-effort: wrapped in try/catch so a cleanup call (typically via onCleanup) never throws
% during error unwinding. A hard kill of the MATLAB process (not a normal error/Ctrl-C) will
% not run this -- AcquireFamilyLock.m's stale-PID check is what recovers from that case on the
% NEXT run, not this function.
%
    try
        if isfile(lock_path)
            delete(lock_path);
        end
    catch
        % best-effort only
    end
end
