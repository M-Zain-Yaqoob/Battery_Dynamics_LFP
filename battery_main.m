%% LFP BATTERY MODEL - SINGLE OPERATING POINT (24s1p, 3 kW)
clc;
clear;
close all;

%% 1. LOAD BATTERY PARAMETERS
run('battery_parameters.m');

%% 2. OPERATING CONDITIONS
SOC = 0.80;         % State of charge (-)
T_cell = 25;        % Pack temperature (degC)
T_amb = 25;         % Ambient temperature (degC)
V1 = 0;             % RC branch 1 voltage (V)
V2 = 0;             % RC branch 2 voltage (V)
trip = 0;           % BMS trip state (0 = ok, 1 = tripped)
P_req_kW = 3.0;     % Requested battery power (kW), + discharge, - charge

%% 3. PARAMETER LOOKUP (temperature and SOC dependent)
s = min(max(SOC, SOC_grid(1)), SOC_grid(end));
T = min(max(T_cell, T_grid(1)), T_grid(end));

OCV = interp2(SOC_grid, T_grid, OCV_map, s, T);
R0  = interp2(SOC_grid, T_grid, R0_map,  s, T);
R1  = interp2(SOC_grid, T_grid, R1_map,  s, T);
C1  = interp2(SOC_grid, T_grid, C1_map,  s, T);
R2  = interp2(SOC_grid, T_grid, R2_map,  s, T);
C2  = interp2(SOC_grid, T_grid, C2_map,  s, T);

% Rest voltage, used for the power-to-current conversion
V_prev = Ns * OCV;

%% 4. CURRENT LIMITS
[I_dis_max, I_chg_max] = Calculate_CurrentLimits(SOC, T_cell, V_prev, trip);

%% 5. BATTERY CURRENT
I_pack = Calculate_BatteryCurrent(P_req_kW, V_prev, I_dis_max, I_chg_max);

%% 6. TERMINAL VOLTAGE
[V_cell, V_pack] = Calculate_TerminalVoltage(OCV, I_pack, R0, V1, V2);
P_pack_kW = V_pack * I_pack / 1000;

%% 7. NEXT-STEP STATES
SOC_next = Calculate_SOC(I_pack, SOC);
[V1_next, V2_next] = Calculate_RC_Voltages(I_pack, V1, V2, R1, C1, R2, C2);
[T_next, Q_gen] = Calculate_HeatAndTemperature(I_pack, V1, V2, R0, R1, R2, T_cell, T_amb);

%% 8. PROTECTION AND AVAILABLE POWER
trip_next = Calculate_BMS_Trip(T_cell, V_pack, trip);
[P_dis_kW, P_chg_kW] = Calculate_PowerAvailability(V_pack, I_dis_max, I_chg_max);

%% RESULTS

fprintf('SOC: %.3f   Temperature: %.1f degC   Requested power: %.2f kW\n', SOC, T_cell, P_req_kW);

fprintf('\nParameters from lookup:\n');
fprintf('OCV per cell: %.4f V\n', OCV);
fprintf('R0: %.3f mOhm   R1: %.3f mOhm   R2: %.3f mOhm\n', R0*1e3, R1*1e3, R2*1e3);
fprintf('C1: %.0f F   C2: %.0f F\n', C1, C2);

fprintf('\nCurrent limits:\n');
fprintf('Discharge limit: %.2f A\n', I_dis_max);
fprintf('Charge limit: %.2f A\n', I_chg_max);

fprintf('\nBattery current: %.2f A\n', I_pack);
fprintf('Cell voltage: %.4f V\n', V_cell);
fprintf('Pack voltage: %.2f V\n', V_pack);
fprintf('Delivered power: %.3f kW\n', P_pack_kW);

fprintf('\nNext-step states:\n');
fprintf('SOC: %.6f\n', SOC_next);
fprintf('V1: %.2f mV   V2: %.2f mV\n', V1_next*1e3, V2_next*1e3);
fprintf('Heat generation: %.1f W   Temperature: %.4f degC\n', Q_gen, T_next);

fprintf('\nBMS trip (next): %d\n', trip_next);
fprintf('Available discharge power: %.2f kW\n', P_dis_kW);
fprintf('Available charge power: %.2f kW\n', P_chg_kW);
