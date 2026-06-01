function plot_phase12d_pre_post_kpi_by_module(cfg, resultRows)
if isempty(resultRows), return; end
modules = unique(string(resultRows.module_name), 'stable');
n = numel(modules);

fig = figure('Visible', 'off', 'Position', [100 100 1000 600]);
metrics = {'delta_attach_rate','delta_mean_rsrp_dB','delta_mean_sinr_dB', ...
    'delta_mean_sector_load','delta_qos_satisfaction_ratio'};
labels = {'\\Delta attach rate','\\Delta RSRP (dB)','\\Delta SINR (dB)', ...
    '\\Delta sector load','\\Delta QoS'};

tl = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
title(tl, 'Phase 12D: pre vs post mean delta KPI by module');

for k = 1:numel(metrics)
    nexttile;
    vals = zeros(n, 1);
    for m = 1:n
        mask = string(resultRows.module_name) == modules(m);
        vals(m) = mean(resultRows.(metrics{k})(mask), 'omitnan');
    end
    bar(vals);
    set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(modules));
    ylabel(labels{k});
    grid on;
end

save_figure(fig, fullfile(cfg.figuresDir, 'phase12d_pre_post_kpi_by_module.png'));
end
