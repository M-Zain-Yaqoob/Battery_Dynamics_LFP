function SOC_next = Calculate_SOC(I_pack, SOC)

% Battery parameters
Np = 1;
Q = 105;            % Cell capacity (Ah)
eta_chg = 0.995;    % Charge efficiency
dt = 1;             % Time step (s)

% Current per cell
I = I_pack / Np;

% Effective current (charging is less than 100 % efficient)
if I >= 0
    I_eff = I;
else
    I_eff = eta_chg * I;
end

% State of charge
SOC_next = SOC - I_eff * dt / (3600 * Q);
SOC_next = min(max(SOC_next, 0), 1);

end
