%% BATTERY MODEL VALIDATION
% Part A: operating-point checks on the Calculate_* functions (no Simulink needed).
% Part B: Simulink model (battery_model.slx) against the script model on the same profile.
% Part C: protection and limit checks in Simulink.
% Parts B and C run only if battery_model.slx exists (run build_battery_model.m first).

clc;
clear;

run('battery_parameters.m');
par = struct('T_grid',T_grid,'SOC_grid',SOC_grid,'OCV_map',OCV_map,'R0_map',R0_map, ...
    'R1_map',R1_map,'C1_map',C1_map,'R2_map',R2_map,'C2_map',C2_map,'Ns',Ns);
x0 = struct('SOC',SOC0,'V1',0,'V2',0,'T',T0,'trip',0,'V_prev',V_pack_nom);

results = struct('name',{},'pass',{},'detail',{});

%% PART A: OPERATING POINTS

% Columns: SOC, temperature (degC), requested power (kW)
tests = [
    0.80,  25,  0;     % Rest
    0.80,  25,  3;     % 3 kW discharge
    0.80,  25, -3;     % 3 kW charge
    0.10,  25,  2;     % Low SOC: discharge blocked
    0.80,   0,  3;     % Cold: derated discharge
    0.80,  25,  5;     % Over-request: power cap
];

% Expected battery current (A) and pack voltage (V), from an independent calculation
I_expected = [0.00,  37.45, -37.45,  0.00,  9.36,  37.45];
V_expected = [80.10, 79.57,  80.63, 77.01, 79.73,  79.57];

fprintf('\nBATTERY MODEL VALIDATION\n');

for k = 1:size(tests,1)

    SOC = tests(k,1);
    T_cell = tests(k,2);
    P_req_kW = tests(k,3);

    s = min(max(SOC, SOC_grid(1)), SOC_grid(end));
    T = min(max(T_cell, T_grid(1)), T_grid(end));
    OCV = interp2(SOC_grid, T_grid, OCV_map, s, T);
    V_prev = Ns * OCV;

    [I_dis_max, I_chg_max] = Calculate_CurrentLimits(SOC, T_cell, V_prev, 0);
    I_pack = Calculate_BatteryCurrent(P_req_kW, V_prev, I_dis_max, I_chg_max);
    R0 = interp2(SOC_grid, T_grid, R0_map, s, T);
    [~, V_pack] = Calculate_TerminalVoltage(OCV, I_pack, R0, 0, 0);

    fprintf('\nTest %d\n', k);
    fprintf('SOC %.2f, %g degC, request %.1f kW\n', SOC, T_cell, P_req_kW);
    fprintf('Discharge limit: %.2f A, charge limit: %.2f A\n', I_dis_max, I_chg_max);
    fprintf('Battery current: %.2f A\n', I_pack);
    fprintf('Pack voltage: %.2f V\n', V_pack);
    fprintf('Delivered power: %.3f kW\n', V_pack*I_pack/1000);

    ok = abs(I_pack - I_expected(k)) < 0.05 && abs(V_pack - V_expected(k)) < 0.05;
    results = addres(results, sprintf('A%d operating point', k), ok, ...
        sprintf('I = %.2f A (expected %.2f), V = %.2f V (expected %.2f)', ...
        I_pack, I_expected(k), V_pack, V_expected(k)));

end

%% PARTS B AND C: SIMULINK

mdl = 'battery_model';

if ~isfile('battery_model.slx')
    fprintf('\nbattery_model.slx not found: Parts B and C skipped. Run build_battery_model.m first.\n');
else

    load_system(mdl);

    %% PART B: SIMULINK VS SCRIPT ON THE SAME PROFILE

    [t, P_req_kW, T_amb] = test_profile(dt);
    ref = simulate_script(par, P_req_kW, T_amb, x0);
    sim_out = run_sim(mdl, t, P_req_kW, T_amb, {});

    dSOC = max(abs(sim_out.SOC - ref.SOC));
    dV   = max(abs(sim_out.V_pack - ref.V_pack));
    dI   = max(abs(sim_out.I_pack - ref.I_pack));
    dT   = max(abs(sim_out.T_cell - ref.T_cell));
    ok = dSOC < 1e-6 && dV < 1e-3 && dI < 1e-3 && dT < 1e-3;
    results = addres(results, 'B Simulink vs script', ok, ...
        sprintf('max difference: SOC %.1e, V %.1e V, I %.1e A, T %.1e degC', dSOC, dV, dI, dT));

    % Reference numbers for the profile (independent calculation):
    % SOC 80.0 -> 74.26 %, V_pack 78.56-80.56 V, Tmax about 25.49 degC, no trip
    fprintf('\nProfile (Simulink): SOC %.1f -> %.2f %%, V %.2f-%.2f V, Tmax %.2f degC, trip %d\n', ...
        100*sim_out.SOC(1), 100*sim_out.SOC(end), min(sim_out.V_pack), max(sim_out.V_pack), ...
        max(sim_out.T_cell), max(sim_out.trip) > 0);

    %% PART C: LIMITS AND PROTECTION

    % C1: power cap, +5 kW then -5 kW requested
    t = (0:dt:60)';  P = zeros(size(t));  P(t>=5 & t<30) = 5;  P(t>=35) = -5;
    D = run_sim(mdl, t, P, 25*ones(size(t)), {});
    Pd = D.V_pack .* D.I_pack / 1000;
    ok = max(Pd) > 2.9 && max(Pd) < 3.1 && min(Pd) < -2.9 && min(Pd) > -3.1 && max(D.trip) < 0.5;
    results = addres(results, 'C1 Power cap (3 kW)', ok, ...
        sprintf('max P %.3f kW, min P %.3f kW, I %.1f to %.1f A', max(Pd), min(Pd), min(D.I_pack), max(D.I_pack)));

    % C2: cold derating at 0 degC, 3 kW requested
    t = (0:dt:150)';  P = zeros(size(t));  P(t>=5 & t<120) = 3;
    D = run_sim(mdl, t, P, zeros(size(t)), {'T_State','InitialCondition','0'});
    pm = mean(D.V_pack(21:111) .* D.I_pack(21:111) / 1000);
    ok = pm > 0.5 && pm < 1.0;
    results = addres(results, 'C2 Cold derating (0 degC)', ok, ...
        sprintf('delivered %.3f kW for a 3 kW request (derating factor 0.25)', pm));

    % C3: low SOC, discharge blocked, charging allowed
    t = (0:dt:20)';  P = zeros(size(t));  P(t<10) = 1;  P(t>=10) = -1;
    D = run_sim(mdl, t, P, 25*ones(size(t)), {'SOC_State','InitialCondition','0.095'});
    ok = max(abs(D.I_pack(2:10))) < 0.5 && mean(D.I_pack(12:end)) < -10 && max(D.trip) < 0.5;
    results = addres(results, 'C3 Low SOC limit', ok, ...
        sprintf('discharge-phase |I| max %.2f A, charge-phase mean I %.1f A', ...
        max(abs(D.I_pack(2:10))), mean(D.I_pack(12:end))));

    % C4: high SOC, charging blocked, discharge allowed
    t = (0:dt:20)';  P = zeros(size(t));  P(t<10) = -1;  P(t>=10) = 1;
    D = run_sim(mdl, t, P, 25*ones(size(t)), {'SOC_State','InitialCondition','0.985'});
    ok = max(abs(D.I_pack(2:10))) < 0.5 && mean(D.I_pack(12:end)) > 10 && max(D.trip) < 0.5;
    results = addres(results, 'C4 High SOC limit', ok, ...
        sprintf('charge-phase |I| max %.2f A, discharge-phase mean I %.1f A', ...
        max(abs(D.I_pack(2:10))), mean(D.I_pack(12:end))));

    % C5-C7: trip logic, forced by the initial state of one block
    t = (0:dt:10)';  P = zeros(size(t));  Ta = 25*ones(size(t));

    D = run_sim(mdl, t, P, Ta, {'V1_State','InitialCondition','1.0'});    % pack voltage 56 V < 60 V
    [ok, msg] = check_trip(D);
    results = addres(results, 'C5 Undervoltage trip', ok, msg);

    D = run_sim(mdl, t, P, Ta, {'V1_State','InitialCondition','-0.5'});   % pack voltage 92 V > 87.6 V
    [ok, msg] = check_trip(D);
    results = addres(results, 'C6 Overvoltage trip', ok, msg);

    D = run_sim(mdl, t, P, Ta, {'T_State','InitialCondition','56'});      % 56 degC > 55 degC
    [ok, msg] = check_trip(D);
    results = addres(results, 'C7 Over-temperature trip', ok, msg);

end

%% SUMMARY

fprintf('\n================ BATTERY VALIDATION SUMMARY ================\n');
for k = 1:numel(results)
    if results(k).pass, status = 'PASS'; else, status = 'FAIL'; end
    fprintf('%-30s %s\n   %s\n', results(k).name, status, results(k).detail);
end
fprintf('============================================================\n');
if ~all([results.pass])
    error('One or more checks FAILED. See the summary above.');
end
fprintf('All checks passed.\n');

%% ---------------- local functions ----------------
function [t, P_req_kW, T_amb] = test_profile(dt)
t = (0:dt:1800)';
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
T_amb = 25 + 2*sin(2*pi*t/1800);
end

function R = simulate_script(par, P_req_kW, T_amb, x0)
% The same time loop as battery_dynamic_main.m, packaged as a function.
N = numel(P_req_kW);
f = {'SOC','V_pack','I_pack','T_cell','P_dis_kW','P_chg_kW','trip','I_dis_max','I_chg_max'};
for i = 1:numel(f), R.(f{i}) = zeros(N,1); end
SOC = x0.SOC;  V1 = x0.V1;  V2 = x0.V2;  T_cell = x0.T;  trip = x0.trip;  V_prev = x0.V_prev;
for k = 1:N
    s = min(max(SOC, par.SOC_grid(1)), par.SOC_grid(end));
    T = min(max(T_cell, par.T_grid(1)), par.T_grid(end));
    OCV = interp2(par.SOC_grid, par.T_grid, par.OCV_map, s, T);
    R0  = interp2(par.SOC_grid, par.T_grid, par.R0_map,  s, T);
    R1  = interp2(par.SOC_grid, par.T_grid, par.R1_map,  s, T);
    C1  = interp2(par.SOC_grid, par.T_grid, par.C1_map,  s, T);
    R2  = interp2(par.SOC_grid, par.T_grid, par.R2_map,  s, T);
    C2  = interp2(par.SOC_grid, par.T_grid, par.C2_map,  s, T);
    [I_dis_max, I_chg_max] = Calculate_CurrentLimits(SOC, T_cell, V_prev, trip);
    I_pack = Calculate_BatteryCurrent(P_req_kW(k), V_prev, I_dis_max, I_chg_max);
    [~, V_pack] = Calculate_TerminalVoltage(OCV, I_pack, R0, V1, V2);
    [P_dis_kW, P_chg_kW] = Calculate_PowerAvailability(V_pack, I_dis_max, I_chg_max);
    vals = {SOC, V_pack, I_pack, T_cell, P_dis_kW, P_chg_kW, trip, I_dis_max, I_chg_max};
    for i = 1:numel(f), R.(f{i})(k) = vals{i}; end
    SOC_n = Calculate_SOC(I_pack, SOC);
    [V1_n, V2_n] = Calculate_RC_Voltages(I_pack, V1, V2, R1, C1, R2, C2);
    [T_n, ~] = Calculate_HeatAndTemperature(I_pack, V1, V2, R0, R1, R2, T_cell, T_amb(k));
    trip_n = Calculate_BMS_Trip(T_cell, V_pack, trip);
    SOC = SOC_n;  V1 = V1_n;  V2 = V2_n;  T_cell = T_n;  trip = trip_n;  V_prev = V_pack;
end
end

function D = run_sim(mdl, t, P_req_kW, T_amb, overrides)
ts = timeseries([P_req_kW(:), T_amb(:)], t(:));
in = Simulink.SimulationInput(mdl);
in = setVariable(in, 'battery_input_ts', ts, 'Workspace', 'global-workspace');
in = setModelParameter(in, 'StopTime', num2str(t(end)));
for k = 1:size(overrides,1)
    in = setBlockParameter(in, [mdl '/' overrides{k,1}], overrides{k,2}, overrides{k,3});
end
out = sim(in);
names = {'SOC','V_pack','I_pack','T_cell','P_dis_kW','P_chg_kW','trip','I_dis_max','I_chg_max'};
logs  = {'SOC_log','Vpack_log','Ipack_log','Tcell_log','Pdis_log','Pchg_log','Trip_log','Idis_log','Ichg_log'};
for k = 1:numel(names)
    v = squeeze(out.get(logs{k}).Data);
    D.(names{k}) = v(:);
end
end

function [ok, msg] = check_trip(D)
trip = D.trip > 0.5;
if ~any(trip), ok = false; msg = 'no trip detected'; return; end
i0 = find(trip, 1, 'first');
post = i0:numel(trip);
latched = all(trip(post));
current_zero = all(abs(D.I_pack(post)) < 1e-6);
limits_zero = all(abs(D.I_dis_max(post)) < 1e-9) && all(abs(D.I_chg_max(post)) < 1e-9);
power_zero = all(abs(D.P_dis_kW(post)) < 1e-9) && all(abs(D.P_chg_kW(post)) < 1e-9);
ok = latched && current_zero && limits_zero && power_zero;
msg = sprintf('trip at sample %d, latched %d, current zero %d, limits zero %d, power zero %d', ...
    i0, latched, current_zero, limits_zero, power_zero);
end

function results = addres(results, name, pass, detail)
results(end+1) = struct('name', name, 'pass', logical(pass), 'detail', detail);
end
