%% BUILD battery_model.slx
% One MATLAB Function block per equation (Calculate_*), chained like vehicle_dynamics.slx.
% The block code is read from the Calculate_*.m files in this folder, so the scripts
% (battery_dynamic_main.m, battery_main_csv.m) and the Simulink model use the same equations.
% Run this once. It creates battery_model.slx and opens it.

clc;
clear;
close all;

root = fileparts(mfilename('fullpath'));
run(fullfile(root,'battery_parameters.m'));

mdl = 'battery_model';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
open_system(mdl);
set_param(mdl, 'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', ...
    'FixedStep', num2str(dt), 'StopTime', '1800');

ts_str = num2str(dt);

%% 1. INPUT: requested power and ambient temperature (from workspace, see prepareBatteryProfile.m)
addb(mdl, 'simulink/Sources/From Workspace', 'Battery_Input', ...
    'VariableName','battery_input_ts', 'SampleTime',ts_str, ...
    'OutputAfterFinalValue','Holding final value');
addb(mdl, 'simulink/Signal Routing/Demux', 'Demux', 'Outputs','2');

%% 2. STATE MEMORY (one step delay: the value of the previous step)
addb(mdl, 'simulink/Discrete/Unit Delay', 'SOC_State',   'InitialCondition',num2str(SOC0),       'SampleTime',ts_str);
addb(mdl, 'simulink/Discrete/Unit Delay', 'V1_State',    'InitialCondition','0',                  'SampleTime',ts_str);
addb(mdl, 'simulink/Discrete/Unit Delay', 'V2_State',    'InitialCondition','0',                  'SampleTime',ts_str);
addb(mdl, 'simulink/Discrete/Unit Delay', 'T_State',     'InitialCondition',num2str(T0),          'SampleTime',ts_str);
addb(mdl, 'simulink/Discrete/Unit Delay', 'Trip_State',  'InitialCondition','0',                  'SampleTime',ts_str);
addb(mdl, 'simulink/Discrete/Unit Delay', 'Vpack_State', 'InitialCondition',num2str(V_pack_nom),  'SampleTime',ts_str);

%% 3. PARAMETER MAPS (temperature x SOC), inputs: 1 = temperature, 2 = SOC
maps = {'Lookup_OCV',OCV_map; 'Lookup_R0',R0_map; 'Lookup_R1',R1_map; ...
        'Lookup_C1',C1_map;   'Lookup_R2',R2_map; 'Lookup_C2',C2_map};
for k = 1:size(maps,1)
    addb(mdl, 'simulink/Lookup Tables/2-D Lookup Table', maps{k,1}, ...
        'BreakpointsForDimension1', mat2str(T_grid,8), ...
        'BreakpointsForDimension2', mat2str(SOC_grid,8), ...
        'Table', mat2str(maps{k,2},8), 'ExtrapMethod','Clip');
end

%% 4. EQUATION BLOCKS (code read from Calculate_*.m)
addeq(mdl, root, 'Calculate_CurrentLimits',       4, 2);
addeq(mdl, root, 'Calculate_BatteryCurrent',      4, 1);
addeq(mdl, root, 'Calculate_SOC',                 2, 1);
addeq(mdl, root, 'Calculate_RC_Voltages',         7, 2);
addeq(mdl, root, 'Calculate_TerminalVoltage',     5, 2);
addeq(mdl, root, 'Calculate_HeatAndTemperature',  8, 2);
addeq(mdl, root, 'Calculate_BMS_Trip',            3, 1);
addeq(mdl, root, 'Calculate_PowerAvailability',   3, 2);

%% 5. LOGGING (To Workspace)
logs = {'SOC_log','Vpack_log','Ipack_log','Tcell_log','Pdis_log','Pchg_log','Trip_log','Idis_log','Ichg_log','Vcell_log','Qgen_log'};
for k = 1:numel(logs)
    addb(mdl, 'simulink/Sinks/To Workspace', logs{k}, ...
        'VariableName',logs{k}, 'SaveFormat','Timeseries');
end

%% 6. WIRING
L = @(a,b) add_line(mdl, a, b, 'autorouting','on');

L('Battery_Input/1','Demux/1');

% Parameter maps use the previous-step temperature and SOC
for k = 1:size(maps,1)
    L('T_State/1',   [maps{k,1} '/1']);
    L('SOC_State/1', [maps{k,1} '/2']);
end

% Current limits: SOC, T, V_prev, trip
L('SOC_State/1','Calculate_CurrentLimits/1');
L('T_State/1','Calculate_CurrentLimits/2');
L('Vpack_State/1','Calculate_CurrentLimits/3');
L('Trip_State/1','Calculate_CurrentLimits/4');

% Battery current: P_req_kW, V_prev, I_dis_max, I_chg_max
L('Demux/1','Calculate_BatteryCurrent/1');
L('Vpack_State/1','Calculate_BatteryCurrent/2');
L('Calculate_CurrentLimits/1','Calculate_BatteryCurrent/3');
L('Calculate_CurrentLimits/2','Calculate_BatteryCurrent/4');

% SOC: I_pack, SOC -> SOC_next
L('Calculate_BatteryCurrent/1','Calculate_SOC/1');
L('SOC_State/1','Calculate_SOC/2');
L('Calculate_SOC/1','SOC_State/1');

% RC voltages: I_pack, V1, V2, R1, C1, R2, C2 -> V1_next, V2_next
L('Calculate_BatteryCurrent/1','Calculate_RC_Voltages/1');
L('V1_State/1','Calculate_RC_Voltages/2');
L('V2_State/1','Calculate_RC_Voltages/3');
L('Lookup_R1/1','Calculate_RC_Voltages/4');
L('Lookup_C1/1','Calculate_RC_Voltages/5');
L('Lookup_R2/1','Calculate_RC_Voltages/6');
L('Lookup_C2/1','Calculate_RC_Voltages/7');
L('Calculate_RC_Voltages/1','V1_State/1');
L('Calculate_RC_Voltages/2','V2_State/1');

% Terminal voltage: OCV, I_pack, R0, V1, V2 -> V_cell, V_pack
L('Lookup_OCV/1','Calculate_TerminalVoltage/1');
L('Calculate_BatteryCurrent/1','Calculate_TerminalVoltage/2');
L('Lookup_R0/1','Calculate_TerminalVoltage/3');
L('V1_State/1','Calculate_TerminalVoltage/4');
L('V2_State/1','Calculate_TerminalVoltage/5');
L('Calculate_TerminalVoltage/2','Vpack_State/1');

% Heat and temperature: I_pack, V1, V2, R0, R1, R2, T, T_amb -> T_next, Q_gen
L('Calculate_BatteryCurrent/1','Calculate_HeatAndTemperature/1');
L('V1_State/1','Calculate_HeatAndTemperature/2');
L('V2_State/1','Calculate_HeatAndTemperature/3');
L('Lookup_R0/1','Calculate_HeatAndTemperature/4');
L('Lookup_R1/1','Calculate_HeatAndTemperature/5');
L('Lookup_R2/1','Calculate_HeatAndTemperature/6');
L('T_State/1','Calculate_HeatAndTemperature/7');
L('Demux/2','Calculate_HeatAndTemperature/8');
L('Calculate_HeatAndTemperature/1','T_State/1');

% BMS trip: T, V_pack, trip -> trip_next
L('T_State/1','Calculate_BMS_Trip/1');
L('Calculate_TerminalVoltage/2','Calculate_BMS_Trip/2');
L('Trip_State/1','Calculate_BMS_Trip/3');
L('Calculate_BMS_Trip/1','Trip_State/1');

% Available power: V_pack, I_dis_max, I_chg_max
L('Calculate_TerminalVoltage/2','Calculate_PowerAvailability/1');
L('Calculate_CurrentLimits/1','Calculate_PowerAvailability/2');
L('Calculate_CurrentLimits/2','Calculate_PowerAvailability/3');

% Logging
L('SOC_State/1','SOC_log/1');
L('Calculate_TerminalVoltage/2','Vpack_log/1');
L('Calculate_BatteryCurrent/1','Ipack_log/1');
L('T_State/1','Tcell_log/1');
L('Calculate_PowerAvailability/1','Pdis_log/1');
L('Calculate_PowerAvailability/2','Pchg_log/1');
L('Trip_State/1','Trip_log/1');
L('Calculate_CurrentLimits/1','Idis_log/1');
L('Calculate_CurrentLimits/2','Ichg_log/1');
L('Calculate_TerminalVoltage/1','Vcell_log/1');
L('Calculate_HeatAndTemperature/2','Qgen_log/1');

try, Simulink.BlockDiagram.arrangeSystem(mdl); catch, end
save_system(mdl, fullfile(root, [mdl '.slx']));

fprintf('Created battery_model.slx\n');
fprintf('Before running it, load the input profile:\n');
fprintf('    battery_input_ts = prepareBatteryProfile();\n');
fprintf('    sim(''battery_model'');\n');

%% ---------------- local functions ----------------
function addb(mdl, type, name, varargin)
% Add a block on a coarse grid; arrangeSystem tidies the layout afterwards.
n   = numel(find_system(mdl,'SearchDepth',1,'Type','Block'));
col = mod(n,6);  row = floor(n/6);
x = 40 + col*220;  y = 40 + row*120;
add_block(type, [mdl '/' name], 'Position', [x y x+110 y+60], varargin{:});
end

function addeq(mdl, root, name, nIn, nOut)
% MATLAB Function block whose code is the Calculate_*.m file of the same name.
blk = [mdl '/' name];
addb(mdl, 'simulink/User-Defined Functions/MATLAB Function', name);
rt = sfroot;
ch = rt.find('-isa','Stateflow.EMChart','Path',blk);
if isempty(ch), error('Could not access the MATLAB Function chart for %s.', name); end
ch.Script = fileread(fullfile(root, [name '.m']));
ph = get_param(blk, 'PortHandles');
if numel(ph.Inport) ~= nIn || numel(ph.Outport) ~= nOut
    error('%s has %d inputs / %d outputs, expected %d / %d.', ...
        name, numel(ph.Inport), numel(ph.Outport), nIn, nOut);
end
end
