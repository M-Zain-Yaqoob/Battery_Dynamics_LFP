# LFP battery (24s1p EVE LF105, 3 kW) in the Vehicle_Dynamics format

Same structure as `Vehicle_Dynamics_FCHEV`: a parameters script, numbered-section scripts, one
`Calculate_*` MATLAB Function block per equation, and a chain wired from a From Workspace block.

| Vehicle_Dynamics_FCHEV | This project |
|---|---|
| `vehicle_parameters.m` | `battery_parameters.m` |
| `main.m` (single point) | `battery_main.m` |
| `dynamic_main.m` | `battery_dynamic_main.m` |
| `main_csv.m` + `drive_Cycle.xlsx` | `battery_main_csv.m` + `battery_profile.xlsx` |
| `prepareDrivingCycle.m` | `prepareBatteryProfile.m` |
| `validate.m` | `validate_battery.m` |
| `vehicle_dynamics.slx` | `battery_model.slx` (created by `build_battery_model.m`) |
| `Calculate_Forces`, `Calculate_WheelTorque`, ... blocks | `Calculate_CurrentLimits`, `Calculate_SOC`, ... blocks |

Difference: your model was drawn by hand. I can't produce a `.slx` file without MATLAB, so
`build_battery_model.m` generates it. It reads the code of each block from the `Calculate_*.m`
files, so the scripts and the Simulink blocks always use the same equations.

## How to run
1. Keep all files and the `data` folder together in one folder, and `cd` into it.
2. `battery_main` for one operating point, `battery_dynamic_main` for the built-in 30-minute profile,
   `battery_main_csv` for the profile in `battery_profile.xlsx`.
3. `build_battery_model` creates `battery_model.slx`. Then:
   ```matlab
   battery_input_ts = prepareBatteryProfile();
   sim('battery_model');
   ```
4. `validate_battery` runs the checks (Part A needs no Simulink; Parts B and C need `battery_model.slx`).

## Pack
24 cells in series, 1 parallel, 105 Ah: 76.8 V nominal, 60 to 87.6 V trip window, 8.06 kWh, 3 kW rating.
Discrete time with dt = 1 s (fixed-step), like the vehicle model's 1 s driving cycle.

## Blocks and equations (one step, k to k+1)
Inputs: requested power `P_req_kW` (+ discharge, - charge) and `T_amb`. States, kept in Unit Delay blocks:
SOC, V1, V2, temperature T, trip, and the previous pack voltage.

| Block | Equations |
|---|---|
| `Calculate_CurrentLimits` | I_dis_max = min(105 Np, P_max/V_use) f_soc_dis(SOC) f_T_dis(T); I_chg_max = min(52.5 Np, P_max/V_use) f_soc_chg(SOC) f_T_chg(T); both 0 when tripped; V_use = clamp(V_prev, 30, 120) |
| `Calculate_BatteryCurrent` | I_req = 1000 P_req_kW / V_use; I_pack = max(min(I_req, I_dis_max), -I_chg_max) |
| `Calculate_SOC` | I_eff = I (discharge) or eta_chg I (charge); SOC(k+1) = SOC - I_eff dt/(3600 Q), limited to 0..1 |
| `Calculate_RC_Voltages` | tau_i = R_i C_i; Vi(k+1) = Vi exp(-dt/tau_i) + R_i I (1 - exp(-dt/tau_i)), i = 1, 2 |
| `Calculate_TerminalVoltage` | V_cell = OCV - I R0 - V1 - V2; V_pack = Ns V_cell |
| `Calculate_HeatAndTemperature` | Q_gen = Ns Np (I^2 R0 + V1^2/R1 + V2^2/R2); T(k+1) = T + dt (Q_gen - hA (T - T_amb)) / Cth |
| `Calculate_BMS_Trip` | trip = 1 if trip already 1, T > 55 degC, V_pack > 87.6 V or V_pack < 60 V |
| `Calculate_PowerAvailability` | P_dis = V_pack I_dis_max / 1000; P_chg = V_pack I_chg_max / 1000 |

Here I = I_pack / Np (per cell). OCV, R0, R1, C1, R2, C2 are 2-D lookups on temperature and SOC
(`Lookup_*` blocks), from the +0.5C column of your LF105 maps (NaN entries filled, clipped outside the data).

## Reference numbers (independent Python calculation, not MATLAB)
| Case | Expected |
|---|---|
| `battery_dynamic_main` profile | SOC 80.0 to 74.26 %, V_pack 78.56 to 80.56 V, Tmax 25.49 degC, Imax 38.2 A, no trip |
| 3 kW discharge at SOC 0.8, 25 degC | I 37.45 A, V_pack 79.57 V, delivered 2.98 kW |
| 3 kW request at 0 degC | limited to 9.36 A, 0.75 kW |
| 2 kW request at SOC 0.10 | discharge blocked (0 A), charging still allowed |
| 3 kW pulse sag at 10 / 25 / 40 degC | 2.57 / 1.55 / 1.09 V |

## Assumptions and limits
- Delivered power is a little different from the request at the first sample after a step (up to about
  1 %), because the pack voltage used for the power-to-current conversion is one step old.
- BMS derating curves, `Cth` = 50 kJ/K and `hA` = 10 W/K are provisional. The 0.25 factor at 0 degC is very
  conservative; check the LF105 datasheet.
- The numbers inside the `Calculate_*.m` files must match `battery_parameters.m` (same as in your vehicle project).
- Not modelled: OCV hysteresis, charge/discharge-specific maps, cell imbalance, ageing. Validation against
  measured data is still in-sample only.
- Your vehicle cycle needs up to about 23 kW at the DC bus and returns about 12 kW in regeneration,
  far beyond this 3 kW battery; the fuel cell, ultracapacitor and EMS must supply the rest.


## Organized Simulink diagram

The top-level `battery_model.slx` layout has been reorganized into six functional
columns while preserving the model equations and signal connections:

1. Inputs and state memory
2. ECM parameter maps
3. Request conditioning and current limiting
4. Battery electrical and thermal dynamics
5. Protection and available power
6. Logged outputs

The layout is deliberately spacious, uses consistent block sizes and subtle
function-based colors, and places section headings above each group. Signal
connections are created only after blocks have been positioned, allowing
Simulink's autorouter to route wires around the final layout.

To regenerate the diagram with freshly autorouted connections from the MATLAB
source files, run from this project folder:

```matlab
build_battery_model
```

The generator intentionally does not call `Simulink.BlockDiagram.arrangeSystem`
because its automatic arrangement produced a cramped, difficult-to-follow
diagram for this model. Layout changes are presentation-only; they do not
change the battery equations, parameter maps, sample time, or signal logic.
