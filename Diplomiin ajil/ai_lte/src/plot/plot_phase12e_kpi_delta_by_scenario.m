function plot_phase12e_kpi_delta_by_scenario(cfg, baselineAi)
if isempty(baselineAi), return; end
scenarios = unique(string(baselineAi.scenario_name), 'stable');
n = numel(scenarios);
dq = zeros(n, 1); da = zeros(n, 1); ds = zeros(n, 1); dl = zeros(n, 1);
for k = 1:n
    mask = string(baselineAi.scenario_name) == scenarios(k);
    dq(k) = mean(baselineAi.delta_qos_satisfaction_ratio(mask), 'omitnan');
    da(k) = mean(baselineAi.delta_attach_rate(mask), 'omitnan');
    ds(k) = mean(baselineAi.delta_mean_sinr_dB(mask), 'omitnan');
    dl(k) = mean(baselineAi.delta_mean_sector_load(mask), 'omitnan');
end

fig = figure('Visible', 'off', 'Position', [100 100 1000 520]);
bar(1:n, [dq, da, ds, dl], 'grouped');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(scenarios), 'XTickLabelRotation', 20);
ylabel('mean delta KPI');
legend({'\\Delta QoS','\\Delta attach','\\Delta SINR (dB)','\\Delta load'}, 'Location', 'best');
title('Phase 12E: AI/ML mean delta KPIs per scenario');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12e_kpi_delta_by_scenario.png'));
end
