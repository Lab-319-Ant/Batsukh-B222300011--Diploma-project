function out = build_before_after_kpi_tables(bundle)
%BUILD_BEFORE_AFTER_KPI_TABLES Pre/post KPI tables for Phase 13.
%
% Reads Phase 12E baseline-vs-AI comparison + per-module / per-scenario
% summaries from the result bundle and produces:
%   - summary table (one row per KPI, overall means)
%   - per-module table
%   - per-scenario table
%   - interpretation lines used by the markdown narrative
%
% Every row carries baseline_kpi_t, ai_ml_kpi_t_plus_1, delta, and a
% human-readable interpretation string.

out = struct();
out.summary = table();
out.byModule = table();
out.byScenario = table();
out.interpretation = "";

T = bundle.phase12e_baseline_ai;
if isempty(T)
    return;
end

kpis = {
    'attach_rate',           'pre_attach_rate',                 'ai_post_attach_rate',                 'delta_attach_rate',                 'lower is unfavourable; CIO bias reduces attach when borderline UEs fall below the physical RSRP threshold';
    'mean_rsrp_dBm',         'pre_mean_rsrp_dBm',               'ai_post_mean_rsrp_dBm',               'delta_mean_rsrp_dB',                'higher dB is favourable for attached UEs';
    'mean_sinr_dB',          'pre_mean_sinr_dB',                'ai_post_mean_sinr_dB',                'delta_mean_sinr_dB',                'higher dB is favourable for attached UEs';
    'mean_sector_load',      'pre_mean_sector_load',            'ai_post_mean_sector_load',            'delta_mean_sector_load',            'lower is favourable; LB/MLB CIO bias offloads from source to neighbour';
    'qos_satisfaction_ratio','pre_qos_satisfaction_ratio',      'ai_post_qos_satisfaction_ratio',      'delta_qos_satisfaction_ratio',      'higher is favourable';
    'served_traffic_Mbps',   'pre_served_traffic_Mbps',         'ai_post_served_traffic_Mbps',         'delta_served_traffic_Mbps',         'higher is favourable for active UEs';
};

rows = {};
interpLines = strings(0, 1);
for k = 1:size(kpis, 1)
    name = kpis{k, 1};
    preCol = kpis{k, 2};
    postCol = kpis{k, 3};
    deltaCol = kpis{k, 4};
    interpHint = kpis{k, 5};

    if ~ismember(preCol, T.Properties.VariableNames)
        continue;
    end
    pre = mean(T.(preCol), 'omitnan');
    post = mean(T.(postCol), 'omitnan');
    if ismember(deltaCol, T.Properties.VariableNames)
        delta = mean(T.(deltaCol), 'omitnan');
    else
        delta = post - pre;
    end
    rows(end + 1, :) = {name, pre, post, delta, format_interpretation(name, delta, interpHint)}; %#ok<AGROW>
    interpLines(end + 1, 1) = sprintf('- %s: %.4f -> %.4f (delta %+.4f) -- %s', ...
        name, pre, post, delta, interpHint); %#ok<AGROW>
end

out.summary = cell2table(rows, 'VariableNames', ...
    {'kpi_name','baseline_kpi_t','ai_ml_kpi_t_plus_1','delta','interpretation'});

if ~isempty(bundle.phase12e_module)
    out.byModule = bundle.phase12e_module;
end
if ~isempty(bundle.phase12e_scenario)
    out.byScenario = bundle.phase12e_scenario;
end
out.interpretation = interpLines;
end

function s = format_interpretation(name, delta, hint)
sign = '+';
if delta < 0, sign = ''; end
s = sprintf('%s%.4f (%s)', sign, delta, hint);
end
