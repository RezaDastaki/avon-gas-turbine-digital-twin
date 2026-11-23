function y=thresholdbound(u)
% u(1) is varaible 
% u(2) is upper bound
% u(3) is lower bound

if u(1) > u(2)
    y=u(1)-u(2);
elseif u(1)<u(3)
    y= u(1)-u(3);
elseif u(1) < u(2) && u(1)>u(3)
    y=0;
end

    