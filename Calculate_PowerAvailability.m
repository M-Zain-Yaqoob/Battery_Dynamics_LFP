function [P_dis_kW, P_chg_kW] = Calculate_PowerAvailability(V_pack, I_dis_max, I_chg_max)

% Power the battery can deliver and accept now (zero while tripped,
% because both current limits are zero)
P_dis_kW = V_pack * I_dis_max / 1000;
P_chg_kW = V_pack * I_chg_max / 1000;

end
