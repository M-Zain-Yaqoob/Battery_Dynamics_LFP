%% BUILD battery_model.slx
% Organized battery model: inputs/state, parameter maps, current control,
% battery dynamics, protection/power availability, and logging are placed
% in spacious functional columns. Wires are autorouted after placement.
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

%% 6. SPACIOUS FUNCTIONAL LAYOUT
% Apply the final positions BEFORE creating connections so Simulink's
% autorouter routes the wires around the organized block layout.
applyBatteryLayout(mdl);

%% 7. WIRING
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

% Do not call arrangeSystem here: it tends to collapse this model into
% a tall, tangled layout. The manual functional layout above is intentional.
try
    set_param(mdl, 'ZoomFactor', 'FitSystem');
catch
end
save_system(mdl, fullfile(root, [mdl '.slx']));

fprintf('Created battery_model.slx\n');
fprintf('Before running it, load the input profile:\n');
fprintf('    battery_input_ts = prepareBatteryProfile();\n');
fprintf('    sim(''battery_model'');\n');

%% ---------------- local functions ----------------

function applyBatteryLayout(mdl)
% Organize the top-level model into six readable functional columns.
% Positions are [left top right bottom] in Simulink canvas coordinates.
% All calculations and signal connections remain unchanged.

layout = {
    % 01. Inputs and state memory
    'Battery_Input',                 [70 145 190 179];
    'Demux',                         [255 125 275 215];
    'SOC_State',                     [70 405 180 465];
    'V1_State',                      [70 520 180 580];
    'V2_State',                      [70 635 180 695];
    'T_State',                       [70 750 180 810];
    'Trip_State',                    [70 865 180 925];
    'Vpack_State',                   [70 980 180 1040];

    % 02. Temperature/SOC-dependent ECM parameter maps
    'Lookup_OCV',                    [405 140 535 200];
    'Lookup_R0',                     [405 245 535 305];
    'Lookup_R1',                     [405 350 535 410];
    'Lookup_C1',                     [405 455 535 515];
    'Lookup_R2',                     [405 560 535 620];
    'Lookup_C2',                     [405 665 535 725];

    % 03. Request conditioning and current limiting
    'Calculate_CurrentLimits',       [760 245 930 335];
    'Calculate_BatteryCurrent',      [1035 300 1210 390];

    % 04. Battery electrical and state dynamics
    'Calculate_SOC',                 [1350 135 1500 220];
    'Calculate_RC_Voltages',         [1350 310 1520 425];
    'Calculate_TerminalVoltage',     [1350 535 1530 650];
    'Calculate_HeatAndTemperature',  [1350 800 1575 905];

    % 05. Protection and available power
    'Calculate_BMS_Trip',            [1710 545 1855 625];
    'Calculate_PowerAvailability',   [1710 800 1900 890];

    % 06. Logged outputs
    'SOC_log',                       [2150 135 2240 165];
    'Vpack_log',                     [2150 210 2240 240];
    'Ipack_log',                     [2150 285 2240 315];
    'Tcell_log',                     [2150 360 2240 390];
    'Pdis_log',                      [2150 435 2240 465];
    'Pchg_log',                      [2150 510 2240 540];
    'Trip_log',                      [2150 585 2240 615];
    'Idis_log',                      [2150 660 2240 690];
    'Ichg_log',                      [2150 735 2240 765];
    'Vcell_log',                     [2150 810 2240 840];
    'Qgen_log',                      [2150 885 2240 915];
};

for k = 1:size(layout,1)
    set_param([mdl '/' layout{k,1}], 'Position', layout{k,2});
end

% Subtle color coding by function. These are presentation properties only.
colorGroups = {
    {'Battery_Input','Demux'}, 'lightBlue';
    {'SOC_State','V1_State','V2_State','T_State','Trip_State','Vpack_State'}, 'gray';
    {'Lookup_OCV','Lookup_R0','Lookup_R1','Lookup_C1','Lookup_R2','Lookup_C2'}, 'lightBlue';
    {'Calculate_CurrentLimits','Calculate_BatteryCurrent'}, 'yellow';
    {'Calculate_SOC','Calculate_RC_Voltages','Calculate_TerminalVoltage','Calculate_HeatAndTemperature'}, 'green';
    {'Calculate_BMS_Trip','Calculate_PowerAvailability'}, 'orange';
    {'SOC_log','Vpack_log','Ipack_log','Tcell_log','Pdis_log','Pchg_log','Trip_log','Idis_log','Ichg_log','Vcell_log','Qgen_log'}, 'white';
};
for k = 1:size(colorGroups,1)
    names = colorGroups{k,1};
    color = colorGroups{k,2};
    for j = 1:numel(names)
        try
            set_param([mdl '/' names{j}], 'BackgroundColor', color);
        catch
            % Ignore unsupported color names; layout must still be applied.
        end
    end
end

% Section headings make the signal flow easier to scan. Annotations do not
% participate in simulation and are intentionally kept above the blocks.
addHeading(mdl, '01  INPUTS & STATE MEMORY', [70 45 320 75]);
addHeading(mdl, '02  ECM PARAMETER MAPS', [405 45 690 75]);
addHeading(mdl, '03  CURRENT LIMITING', [760 45 1030 75]);
addHeading(mdl, '04  BATTERY DYNAMICS', [1350 45 1640 75]);
addHeading(mdl, '05  PROTECTION & POWER', [1710 45 2010 75]);
addHeading(mdl, '06  LOGGING', [2150 45 2350 75]);
end

function addHeading(mdl, text, position)
try
    note = Simulink.Annotation(mdl, text);
    note.Position = position;
    note.FontSize = 13;
    note.FontWeight = 'bold';
    note.ForegroundColor = 'blue';
    note.BackgroundColor = 'lightBlue';
    note.FixedHeight = 'on';
catch
    % Annotations are optional; block placement and wiring are unaffected.
end
end

function addb(mdl, type, name, varargin)
% Add a block at a temporary position. applyBatteryLayout assigns the final
% coordinates before any signal lines are created.
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
