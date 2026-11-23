function nm = GetSensorNoiseModel()
% GetSensorNoiseModel - Per-channel measurement-noise + sensor-bias model.
%
% CHANGE: table-driven from
% P3_noise_model.csv (standards-anchored per-channel sigma, not a unit-keyed switch) rather
% than the earlier model's hard-coded per-unit percentages. P3_noise_model.csv is the authority; see
% for the interpretation rules and every
% channel's citation. The OLD per-unit figures are kept, verbatim, as the fallback this table
% itself used for every `noise_basis='type_default'` channel (18 of 39) -- so nothing here
% invents a number the previous model did not already contain.
%
% Output struct nm — OLD fields kept (so AddGaussianNoise.m and any existing caller still
% works unchanged; NOT used by the new measurement layer, ApplyMeasurementModel.m, which reads
% the NEW absolute-unit fields directly):
%   .noise_pct  [1x39]  LEGACY/compat only. Derived as 100*sigma_noise/level_c, level_c being
%                       the same absolute-K (temperature) or abs(reading) basis the earlier model used, so a
%                       caller still computing sigma = noise_pct/100*level gets approximately
%                       the right absolute sigma at that record's own operating point.
%   .bias_pct   [1x39]  LEGACY/compat only, same derivation against sigma_bias (at the
%                       t_since_cal=1.0 reference figure — see .sigma_bias_ref below).
%   .is_temp    [1x39]  logical — true for channels whose unit_stored ends in 'C' (degC).
%   .type       {1x39}  human-readable type label (from P3_noise_model.csv's noise_basis/
%                       instrument_type, collapsed to the same short vocabulary the earlier model used).
%
% NEW fields (what ApplyMeasurementModel.m actually consumes), all in ABSOLUTE engineering
% units at the reference condition (15 degC / nominal ambient / SP_POWER_CMD=13):
%   .channel          {1x39}  'S01'..'S39'
%   .sigma_noise      [1x39]  white measurement-noise sigma (absolute units)
%   .sigma_window     [1x39]  sigma_noise/sqrt(60) — the 60-sample benchmark-window sigma
%   .sigma_bias_ref   [1x39]  per-record calibration-bias sigma AT t_since_cal=1.0 (the
%                             dictionary's reference figure — NOT what a record actually uses)
%   .drift_rate_abs   [1x39]  recovered effective drift-rate term (absolute units/year):
%                             sqrt(max(0, sigma_bias_ref^2 - sigma_noise^2)) — exactly
%                             reproduces P3_01_build_noise_model.py's rule (e)
%                             (sigma_bias_ref = sqrt(sigma_noise^2 + (drift_rate_abs*1.0)^2)),
%                             derived from the two stored sigmas rather than re-parsing the
%                             CSV's free-text drift column for why this is
%                             exact, not an approximation, given rule (b)'s sigma_noise ==
%                             sigma_bias_white identity.
%   .reference_reading[1x39]  the channel's own tail-mean at the reference condition
%   .span_min/.span_max [1x39]  instrument span (or TypicalRanges fallback where UNKNOWN)
%   .quant_bits       [1x39]  ADC bit depth (default 12; see P3_noise_model.csv per-channel)
%   .noise_basis      {1x39}  'standard' | 'type_default'
%   .band_rule        {1x39}  'span' | 'reading' | 'max_of_two' | 'type_default'
%   .confidence       {1x39}  'high' | 'medium' | 'low'
%

    persistent cached_nm
    if ~isempty(cached_nm)
        nm = cached_nm;
        return;
    end

    S = GetSensorDefinitions();
    n = S.Count;

    % Canonical runtime copy lives alongside this function in DataGeneration/, so the
    % production pipeline reads only files shipped with the code.
    thisDir = fileparts(mfilename('fullpath'));
    csvPath = fullfile(thisDir, 'P3_noise_model.csv');
    T = readtable(csvPath, 'TextType', 'string');
    if height(T) ~= n
        error('GetSensorNoiseModel:BadTable', ...
            'P3_noise_model.csv has %d rows, expected %d.', height(T), n);
    end
    % Align to S01..S39 order explicitly (do not assume file row order == channel order)
    [~, order] = ismember(S.ShortNames, cellstr(T.channel));
    if any(order == 0)
        error('GetSensorNoiseModel:MissingChannel', 'P3_noise_model.csv is missing a channel row.');
    end
    T = T(order, :);

    nm = struct();
    nm.channel           = S.ShortNames;
    nm.sigma_noise        = T.sigma_noise';
    nm.sigma_window       = T.sigma_window';
    nm.sigma_bias_ref     = T.sigma_bias';
    nm.reference_reading  = T.reference_reading';
    nm.span_min           = T.span_min';
    nm.span_max           = T.span_max';
    nm.quant_bits         = T.quant_bits';
    nm.noise_basis        = cellstr(T.noise_basis)';
    nm.band_rule          = cellstr(T.band_rule)';
    nm.confidence         = cellstr(T.confidence)';

    % drift_rate_abs recovered exactly from the two stored sigmas (rule b's sigma_noise ==
    % sigma_bias_white identity makes this exact, not an approximation — see header).
    nm.drift_rate_abs = sqrt(max(0, nm.sigma_bias_ref.^2 - nm.sigma_noise.^2));

    % is_temp: every unit_stored string ending in 'C' is a degC channel (no other unit in this
    % model ends in 'C' — kPa/kg/s/deg/-/MW/%/%RH all end differently). Robust to the literal
    % degree-sign byte's encoding, which is not ASCII-stable across readers.
    unitStored = cellstr(T.unit_stored);
    nm.is_temp = false(1, n);
    for c = 1:n
        u = unitStored{c};
        nm.is_temp(c) = ~isempty(u) && strcmp(u(end), 'C');
    end

    % ---- LEGACY/compat fields only: noise_pct / bias_pct / type ----
    nm.noise_pct = zeros(1, n);
    nm.bias_pct  = zeros(1, n);
    nm.type      = cell(1, n);
    for c = 1:n
        if nm.is_temp(c)
            level = abs(nm.reference_reading(c)) + 273.15;
        else
            level = abs(nm.reference_reading(c));
        end
        if level < 1e-9
            nm.noise_pct(c) = 0; nm.bias_pct(c) = 0;
        else
            nm.noise_pct(c) = 100 * nm.sigma_noise(c) / level;
            nm.bias_pct(c)  = 100 * nm.sigma_bias_ref(c) / level;
        end
        if strcmp(nm.noise_basis{c}, 'type_default')
            nm.type{c} = ['type_default:' char(T.unit_stored(c))];
        else
            nm.type{c} = 'standards_anchored';
        end
    end

    cached_nm = nm;
end
