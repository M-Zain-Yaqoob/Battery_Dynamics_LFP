function trip_next = Calculate_BMS_Trip(T_cell, V_pack, trip)

% Battery parameters
Ns = 24;
V_pack_min = Ns * 2.5;      % Undervoltage trip (V)
V_pack_max = Ns * 3.65;     % Overvoltage trip (V)
T_trip = 55;                % Over-temperature trip (degC)

% Fault conditions
over_temperature = T_cell > T_trip;
over_voltage = V_pack > V_pack_max;
under_voltage = V_pack < V_pack_min;

% Latched trip: once set, it stays set
if (trip > 0.5) || over_temperature || over_voltage || under_voltage
    trip_next = 1;
else
    trip_next = 0;
end

end
