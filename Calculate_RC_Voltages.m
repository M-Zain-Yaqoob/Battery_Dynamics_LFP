function [V1_next, V2_next] = Calculate_RC_Voltages(I_pack, V1, V2, R1, C1, R2, C2)

% Battery parameters
Np = 1;
dt = 1;             % Time step (s)

% Current per cell
I = I_pack / Np;

% RC branch 1 (exact solution for constant current over one step)
tau1 = R1 * C1;
a1 = exp(-dt / tau1);
V1_next = V1 * a1 + R1 * I * (1 - a1);

% RC branch 2
tau2 = R2 * C2;
a2 = exp(-dt / tau2);
V2_next = V2 * a2 + R2 * I * (1 - a2);

end
