function I_pack = Calculate_BatteryCurrent(P_req_kW, V_prev, I_dis_max, I_chg_max)

% Voltage used to convert power to current (previous step)
V_use = min(max(V_prev, 30), 120);

% Requested current (+ discharge, - charge)
I_req = 1000 * P_req_kW / V_use;

% Limited battery current
I_pack = max(min(I_req, I_dis_max), -I_chg_max);

end
