
%% LFP BATTERY - DYNAMIC MODEL (24s1p, 3 kW)
clc;
clear;
close all;

%% 1. LOAD BATTERY PARAMETERS
run('battery_parameters.m');

%% 2. TIME VECTOR
t = 0:dt:1800;
N = length(t);

%% 3. OPERATING CONDITIONS

% Requested battery power (kW): + discharge, - charge
P_req_kW = zeros(size(t));
P_req_kW(t >= 60   & t < 240)  =  1.5;
P_req_kW(t >= 240  & t < 480)  =  0.6;
P_req_kW(t >= 480  & t < 600)  =  3.0;
P_req_kW(t >= 600  & t < 720)  = -1.0;
P_req_kW(t >= 720  & t < 960)  =  1.2;
P_req_kW(t >= 960  & t < 1080) = -0.5;
P_req_kW(t >= 1080 & t < 1440) =  2.5;
P_req_kW(t >= 1440 & t < 1620) =  0.4;
P_req_kW(t >= 1620)            = -0.8;

% Ambient temperature (degC)
T_amb = 25 + 2*sin(2*pi*t/1800);

%% 4. PREALLOCATE RESULTS

SOC = zeros(1,N);      V1 = zeros(1,N);       V2 = zeros(1,N);
T_cell = zeros(1,N);   trip = zeros(1,N);     V_prev = zeros(1,N);
I_dis_max = zeros(1,N); I_chg_max = zeros(1,N);
I_pack = zeros(1,N);   V_cell = zeros(1,N);   V_pack = zeros(1,N);
Q_gen = zeros(1,N);    P_dis_kW = zeros(1,N); P_chg_kW = zeros(1,N);
OCV = zeros(1,N);      R0 = zeros(1,N);       R1 = zeros(1,N);
R2 = zeros(1,N);       C1 = zeros(1,N);       C2 = zeros(1,N);

% Initial states
SOC(1) = SOC0;  V1(1) = 0;  V2(1) = 0;  T_cell(1) = T0;
trip(1) = 0;    V_prev(1) = V_pack_nom;

%% 5. TIME LOOP

for k = 1:N

    % Parameter lookup (clipped to the measured range)
    s = min(max(SOC(k), SOC_grid(1)), SOC_grid(end));
    T = min(max(T_cell(k), T_grid(1)), T_grid(end));
    OCV(k) = interp2(SOC_grid, T_grid, OCV_map, s, T);
    R0(k)  = interp2(SOC_grid, T_grid, R0_map,  s, T);
    R1(k)  = interp2(SOC_grid, T_grid, R1_map,  s, T);
    C1(k)  = interp2(SOC_grid, T_grid, C1_map,  s, T);
    R2(k)  = interp2(SOC_grid, T_grid, R2_map,  s, T);
    C2(k)  = interp2(SOC_grid, T_grid, C2_map,  s, T);

    % Current limits and battery current
    [I_dis_max(k), I_chg_max(k)] = Calculate_CurrentLimits(SOC(k), T_cell(k), V_prev(k), trip(k));
    I_pack(k) = Calculate_BatteryCurrent(P_req_kW(k), V_prev(k), I_dis_max(k), I_chg_max(k));

    % Terminal voltage
    [V_cell(k), V_pack(k)] = Calculate_TerminalVoltage(OCV(k), I_pack(k), R0(k), V1(k), V2(k));

    % Available power
    [P_dis_kW(k), P_chg_kW(k)] = Calculate_PowerAvailability(V_pack(k), I_dis_max(k), I_chg_max(k));

    % Next-step states
    if k < N
        SOC(k+1) = Calculate_SOC(I_pack(k), SOC(k));
        [V1(k+1), V2(k+1)] = Calculate_RC_Voltages(I_pack(k), V1(k), V2(k), R1(k), C1(k), R2(k), C2(k));
        [T_cell(k+1), Q_gen(k)] = Calculate_HeatAndTemperature(I_pack(k), V1(k), V2(k), R0(k), R1(k), R2(k), T_cell(k), T_amb(k));
        trip(k+1) = Calculate_BMS_Trip(T_cell(k), V_pack(k), trip(k));
        V_prev(k+1) = V_pack(k);
    end

end

%% 6. DELIVERED POWER

P_pack_kW = V_pack .* I_pack / 1000;

%% 7. DISPLAY RESULTS

fprintf('Final SOC: %.2f %%\n', 100*SOC(end));
fprintf('Pack voltage range: %.2f to %.2f V\n', min(V_pack), max(V_pack));
fprintf('Maximum discharge current: %.2f A\n', max(I_pack));
fprintf('Maximum charge current: %.2f A\n', -min(I_pack));
fprintf('Maximum delivered power: %.2f kW\n', max(P_pack_kW));
fprintf('Maximum pack temperature: %.2f degC\n', max(T_cell));
fprintf('BMS trip occurred: %d\n', max(trip) > 0);

%% 8. PLOT RESULTS

figure('Name','Battery Dynamic Results');

subplot(4,2,1);
plot(t, P_req_kW, t, P_pack_kW, 'LineWidth', 1.3);
ylabel('Power (kW)');
title('Requested and Delivered Power');
legend('Requested','Delivered');
grid on;

subplot(4,2,2);
plot(t, I_pack, 'LineWidth', 1.3);
ylabel('Current (A)');
title('Battery Current');
grid on;

subplot(4,2,3);
plot(t, V_pack, 'LineWidth', 1.3);
ylabel('Voltage (V)');
title('Pack Terminal Voltage');
grid on;

subplot(4,2,4);
plot(t, 100*SOC, 'LineWidth', 1.3);
ylabel('SOC (%)');
title('State of Charge');
grid on;

subplot(4,2,5);
plot(t, V1*1000, t, V2*1000, 'LineWidth', 1.3);
ylabel('Voltage (mV)');
title('RC Branch Voltages (per cell)');
legend('V1','V2');
grid on;

subplot(4,2,6);
plot(t, T_cell, 'LineWidth', 1.3);
ylabel('Temperature (degC)');
title('Pack Temperature');
grid on;

subplot(4,2,7);
plot(t, I_dis_max, t, -I_chg_max, 'LineWidth', 1.3);
ylabel('Current (A)');
xlabel('Time (s)');
title('Current Limits');
legend('Discharge limit','Charge limit');
grid on;

subplot(4,2,8);
plot(t, P_dis_kW, t, -P_chg_kW, 'LineWidth', 1.3);
ylabel('Power (kW)');
xlabel('Time (s)');
title('Available Power');
legend('Discharge','Charge');
grid on;

sgtitle('LFP Battery Dynamic Model');
