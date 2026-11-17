function battery_input_ts = prepareBatteryProfile()

    data = readtable('battery_profile.xlsx');

    t = data.Time;
    P_req_kW = data.P_req_kW;
    T_amb = data.T_amb_C;

    input_data = [P_req_kW, T_amb];

    battery_input_ts = timeseries(input_data, t);

end
