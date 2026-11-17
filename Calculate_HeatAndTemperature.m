function [T_next, Q_gen] = Calculate_HeatAndTemperature(I_pack, V1, V2, R0, R1, R2, T_cell, T_amb)

% Battery parameters
Ns = 24;
Np = 1;
Cth = 5.0e4;        % Pack heat capacity (J/K)
hA = 10;            % Pack-to-ambient conductance (W/K)
dt = 1;             % Time step (s)

% Current per cell
I = I_pack / Np;

% Heat generation: ohmic loss plus loss in both RC branches
Q_gen = Ns * Np * (I^2 * R0 + V1^2 / R1 + V2^2 / R2);

% Cooling to ambient
Q_loss = hA * (T_cell - T_amb);

% Pack temperature
T_next = T_cell + dt * (Q_gen - Q_loss) / Cth;

end
