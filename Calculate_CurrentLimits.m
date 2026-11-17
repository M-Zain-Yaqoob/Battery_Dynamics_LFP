function [I_dis_max, I_chg_max] = Calculate_CurrentLimits(SOC, T_cell, V_prev, trip)

% Battery parameters
Np = 1;
P_max = 3000;       % Battery power rating (W)
I_dis_cap = 105;    % Cell discharge cap, 1C (A)
I_chg_cap = 52.5;   % Cell charge cap, 0.5C (A)

% BMS derating curves
socDisX = [0 0.10 0.20 0.90 0.98 1];   socDisY = [0 0 1 1 0.5 0];
socChgX = [0 0.80 0.90 0.98 1];        socChgY = [1 1 0.5 0 0];
tmpDisX = [0 5 10 40 45 50 55];        tmpDisY = [0.25 0.5 1 1 0.8 0.4 0];
tmpChgX = [0 5 10 15 35 40 45 50 55]; tmpChgY = [0 0.2 0.7 1 1 0.5 0.1 0 0];

% Voltage used for the power cap
V_use = min(max(V_prev, 30), 120);

% Current caps: cell limit or power limit, whichever is lower
I_dis_lim = min(I_dis_cap*Np, P_max/V_use);
I_chg_lim = min(I_chg_cap*Np, P_max/V_use);

% Derating with SOC and temperature
if trip > 0.5
    I_dis_max = 0;
    I_chg_max = 0;
else
    I_dis_max = I_dis_lim * lin(SOC, socDisX, socDisY) * lin(T_cell, tmpDisX, tmpDisY);
    I_chg_max = I_chg_lim * lin(SOC, socChgX, socChgY) * lin(T_cell, tmpChgX, tmpChgY);
end

end

function y = lin(x, xp, yp)
% Piecewise-linear interpolation, clipped at both ends
n = numel(xp);
if x <= xp(1)
    y = yp(1);
elseif x >= xp(n)
    y = yp(n);
else
    y = yp(n);
    for k = 1:n-1
        if x >= xp(k) && x <= xp(k+1)
            y = yp(k) + (yp(k+1) - yp(k)) * (x - xp(k)) / (xp(k+1) - xp(k));
            break;
        end
    end
end
end
