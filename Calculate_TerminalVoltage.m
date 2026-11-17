function [V_cell, V_pack] = Calculate_TerminalVoltage(OCV, I_pack, R0, V1, V2)

% Battery parameters
Ns = 24;
Np = 1;

% Current per cell
I = I_pack / Np;

% Cell terminal voltage
V_cell = OCV - I * R0 - V1 - V2;

% Pack terminal voltage
V_pack = Ns * V_cell;

end
