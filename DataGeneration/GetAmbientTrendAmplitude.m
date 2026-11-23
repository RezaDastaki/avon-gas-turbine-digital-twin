function [delta_T_signed, trend_timeseries] = GetAmbientTrendAmplitude(scenario_hash, epoch, attempt, ...
    nominal_temp_C, sim_duration_s, output_dt)
% GetAmbientTrendAmplitude - the within-record ambient trend.
%
% Draws a trend amplitude DeltaT ~ U(0.5, 2.0) degC and a sign with probability 1/2, seeded on
% the same discipline as every other per-record draw.
% Applies it as a LINEAR ramp across the WHOLE simulated window (including the pre-roll), centred
% so the record's mean inlet temperature is the drawn nominal_temp_C --
%:
%
%   T(t) = nominal_temp_C + DeltaT_signed * (t/T_total - 0.5),   t in [0, T_total]
%
% Linear, not sinusoidal (D-3: a diurnal cycle is wrong for a ~70-minute window). One axis only
% (compressor inlet temperature) -- the axis the engine's whole operating point keys on.
%
% Inputs:
%   scenario_hash  - this scenario's hash (ScenarioConfig.ScenarioHash)
%   epoch, attempt - this record's epoch/attempt
%   nominal_temp_C - the record's drawn mean inlet temperature (env.compressor_inlet_temp_C)
%   sim_duration_s - T_total: this record's full simulated duration (preroll_s + STORED_SAMPLES)
%   output_dt      - sampling interval for the timeseries fed to the From Workspace block
%
% Outputs:
%   delta_T_signed   - the REALISED (signed) trend amplitude, degC -- stored as
%                       ambient_trend_amplitude_C (C24: store the realised draw)
%   trend_timeseries - [N x 2] = [t, T(t)], ready for a From Workspace block's VariableName
%

    seed = ScenarioConfig.TREND_BASE_SEED + scenario_hash + epoch * 89 + attempt * 100523;
    rng(seed, 'twister');

    AMPLITUDE_MIN_C = 0.5;
    AMPLITUDE_MAX_C = 2.0;
    amplitude = AMPLITUDE_MIN_C + (AMPLITUDE_MAX_C - AMPLITUDE_MIN_C) * rand();
    sign_draw = 2 * (rand() >= 0.5) - 1;   % +1 or -1, each probability 1/2
    delta_T_signed = sign_draw * amplitude;

    t = (0:output_dt:sim_duration_s)';
    T_t = nominal_temp_C + delta_T_signed * (t / sim_duration_s - 0.5);
    trend_timeseries = [t, T_t];
end
