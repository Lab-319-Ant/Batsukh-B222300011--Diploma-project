function plot_phase12d_kpi_update_outcomes(cfg, resultRows)
if isempty(resultRows), return; end

% Categorize per-action outcome by sign of delta_qos.
modules = unique(string(resultRows.module_name), 'stable');
n = numel(modules);
improved = zeros(n, 1);
unchanged = zeros(n, 1);
worsened = zeros(n, 1);
for k = 1:n
    mask = string(resultRows.module_name) == modules(k);
    sub = resultRows(mask, :);
    improved(k) = sum(sub.delta_qos_satisfaction_ratio > 1e-6);
    worsened(k) = sum(sub.delta_qos_satisfaction_ratio < -1e-6);
    unchanged(k) = height(sub) - improved(k) - worsened(k);
end

fig = figure('Visible', 'off', 'Position', [100 100 900 500]);
bar(1:n, [improved, unchanged, worsened], 'stacked');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(modules));
ylabel('action count');
legend({'QoS improved','QoS unchanged','QoS worsened'}, 'Location', 'best');
title(sprintf('Phase 12D: per-module QoS outcome (n=%d)', height(resultRows)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12d_kpi_update_outcomes.png'));
end
