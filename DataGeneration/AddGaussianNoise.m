function sensor_data_noisy = AddGaussianNoise(sensor_data, noise_model, noise_seed, bias_seed, add_bias)
% AddGaussianNoise - Add per-channel measurement noise + per-epoch calibration
% bias to extracted channel data.
%
% NOT CALLED by RunScenario.m as of — Step 6 now calls
% ApplyMeasurementModel.m instead (the full six-step chain: sensor-fault gain/offset, bias,
% noise, quantisation, F37's graded hold). Kept, unmodified, for any external caller that still
% wants the level-relative (percentage-of-signal) noise/bias model; GetSensorNoiseModel.m
% still returns the `noise_pct`/`bias_pct` fields this function consumes, now derived from the
% new absolute-unit model rather than hand-tuned, for exactly this backward compatibility.
%
% For each channel c:
%   level      = (is_temp) ? (mean_degC + 273.15)  : abs(mean(col))   % absolute-K for temps
%   sigma      = (noise_pct(c)/100) * level                            % white measurement noise
%   bias(c)    = (bias_pct(c)/100)  * level * randn                    % constant offset, once per epoch
%   noisy(:,c) = col + bias(c) + sigma * randn(N,1)
%
% Temperatures use the ABSOLUTE temperature as the noise base so cool stations
% (e.g. FG temp ~20 degC) get realistic +/-1..4 K noise rather than the
% near-zero noise the earlier "% of degC mean" model produced.
%
% Inputs:
%   sensor_data - [N x C] double — channel matrix (post-extraction, C=39)
%   noise_model - struct from GetSensorNoiseModel with fields
%                 .noise_pct [1xC], .bias_pct [1xC], .is_temp [1xC].
%                 (To freeze a channel — e.g. F37 on S19 — set its noise_pct
%                  and bias_pct to 0 in the caller.)
%   noise_seed  - integer RNG seed for the white noise realisation
%   bias_seed   - integer RNG seed for the per-epoch bias offsets
%   add_bias    - logical (default true) — include the constant bias term
%
% Output:
%   sensor_data_noisy - [N x C] double — channels with noise (+bias) applied
%
% Date: 2026-07-26 (type-driven noise, absolute-K temps, per-epoch bias)

    if nargin < 5 || isempty(add_bias), add_bias = true; end

    [N, C] = size(sensor_data);

    if numel(noise_model.noise_pct) ~= C
        error('AddGaussianNoise:InvalidInput', ...
              'noise_model has %d channels but sensor_data has %d columns', ...
              numel(noise_model.noise_pct), C);
    end

    noise_pct = noise_model.noise_pct;
    bias_pct  = noise_model.bias_pct;
    is_temp   = noise_model.is_temp;

    %% Per-channel signal level (absolute-K for temperatures)
    level = zeros(1, C);
    for c = 1:C
        m = mean(sensor_data(:, c), 'omitnan');
        if is_temp(c)
            level(c) = m + 273.15;          % degC -> absolute K
        else
            level(c) = abs(m);
        end
    end

    %% Per-epoch constant bias (drawn once per channel)
    bias_vec = zeros(1, C);
    if add_bias
        rng(bias_seed, 'twister');
        for c = 1:C
            if level(c) < 1e-9, continue; end
            bias_vec(c) = (bias_pct(c) / 100) * level(c) * randn;
        end
    end

    %% White measurement noise
    sensor_data_noisy = sensor_data;
    rng(noise_seed, 'twister');
    for c = 1:C
        if level(c) < 1e-9
            continue;   % near-zero signal — no physical noise/bias
        end
        sigma = (noise_pct(c) / 100) * level(c);
        sensor_data_noisy(:, c) = sensor_data(:, c) + bias_vec(c) + sigma * randn(N, 1);
    end
end
