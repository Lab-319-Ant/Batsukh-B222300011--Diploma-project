function plot_phase12d_load_change_by_scenario(cfg, resultRows)
if isempty(resultRows), return; end
scenarios = unique(string(resultRows.scenario_name), 'stable');
n = numel(scenarios);
deltaLoad = zeros(n, 1);
for k = 1:n
    mask = string(resultRows.scenario_name) == scenarios(k);
    deltaLoad(k) = mean(resultRows.delta_mean_sector_load(mask), 'omitnan');
end

fig = figure('Visible', 'off', 'Position', [100 100 900 500]);
bar(deltaLoad);
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(scenarios), 'XTickLabelRotation', 20);
ylabel('\\Delta mean sector load (post - pre)');
title('Phase 12D: mean sector-load change per scenario');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12d_load_change_by_scenario.png'));
end
