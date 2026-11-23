function [count, sgn] = RTFAdvanceStreak(breach, residual, count, sgn)
% RTFAdvanceStreak - Advance the cross-cycle persistence streak of the ambient check by one
% ACCEPTED cycle: consecutive same-sign breaches extend it, any non-breach or sign
% change resets it. sgn = 0 means "no active streak". Called once per accepted cycle by
% RunRTFUnit.m, and once per stored cycle by RestoreRTFUnitState.m when it replays a stored unit.
%

    if breach
        this_sign = sign(residual);
        if count > 0 && this_sign == sgn
            count = count + 1;
        else
            count = 1;
            sgn = this_sign;
        end
    else
        count = 0;
        sgn = 0;
    end
end
