% LFP battery pack for the FCHEV: 24s1p EVE LF105, 3 kW
% Same role as vehicle_parameters.m. The numbers in the Calculate_*.m files
% (and therefore in the Simulink blocks) must match the ones below.

% Cell properties (EVE LF105)
Q_cell    = 105;      % Cell capacity (Ah)
V_cell_nom = 3.2;     % Nominal cell voltage (V)
V_cell_min = 2.5;     % Minimum cell voltage (V)
V_cell_max = 3.65;    % Maximum cell voltage (V)
eta_chg   = 0.995;    % Charge efficiency (assumed, not in the source data)

% Pack configuration
Ns = 24;              % Cells in series
Np = 1;               % Strings in parallel
V_pack_nom = Ns * V_cell_nom;   % Nominal pack voltage (V)
V_pack_min = Ns * V_cell_min;   % Undervoltage trip (V)
V_pack_max = Ns * V_cell_max;   % Overvoltage trip (V)
E_pack_kWh = V_pack_nom * Q_cell * Np / 1000;   % Pack energy (kWh)

% Power and current limits
P_max     = 3000;     % Battery power rating (W)
I_dis_cap = 105 * Np; % Cell discharge cap, 1C (A)
I_chg_cap = 52.5 * Np;% Cell charge cap, 0.5C (A)

% Thermal model (provisional)
Cth       = 5.0e4;    % Pack heat capacity (J/K)
hA        = 10;       % Pack-to-ambient conductance (W/K)
T_trip    = 55;       % Over-temperature trip (degC)

% BMS derating curves (engineering assumptions)
socDisX = [0 0.10 0.20 0.90 0.98 1];  socDisY = [0 0 1 1 0.5 0];
socChgX = [0 0.80 0.90 0.98 1];       socChgY = [1 1 0.5 0 0];
tmpDisX = [0 5 10 40 45 50 55];       tmpDisY = [0.25 0.5 1 1 0.8 0.4 0];
tmpChgX = [0 5 10 15 35 40 45 50 55];tmpChgY = [0 0.2 0.7 1 1 0.5 0.1 0 0];

% Initial conditions
SOC0 = 0.80;          % Initial state of charge (-)
T0   = 25;            % Initial pack temperature (degC)

% Simulation settings
dt = 1;               % Time step (s)

% Parameter maps (temperature x SOC), +0.5C column of the LF105 data.
% Lookup blocks in the Simulink model read these workspace variables.
S = load(fullfile(fileparts(mfilename('fullpath')),'data','lf105_representative_maps.mat'));
T_grid   = double(S.temp_grid_C(:)');
SOC_grid = double(S.soc_grid(:)');
jc = find(abs(double(S.crate_grid(:)')-0.5) < 1e-9, 1);
fillmap = @(M) fillmissing(fillmissing(double(M),'linear',2,'EndValues','nearest'),'nearest',1);
OCV_map = fillmap(S.OCV_V);                    % (V)
R0_map  = fillmap(squeeze(S.R0_ohm(:,:,jc)));  % (ohm)
R1_map  = fillmap(squeeze(S.R1_ohm(:,:,jc)));  % (ohm)
C1_map  = fillmap(squeeze(S.C1_F(:,:,jc)));    % (F)
R2_map  = fillmap(squeeze(S.R2_ohm(:,:,jc)));  % (ohm)
C2_map  = fillmap(squeeze(S.C2_F(:,:,jc)));    % (F)
clear S jc fillmap
