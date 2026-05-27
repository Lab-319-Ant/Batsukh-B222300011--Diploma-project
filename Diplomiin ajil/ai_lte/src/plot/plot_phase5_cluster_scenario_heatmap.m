function plot_phase5_cluster_scenario_heatmap(cfg, scenarioCrosstab)
%PLOT_PHASE5_CLUSTER_SCENARIO_HEATMAP Plot row-normalized scenario fractions.

vars = scenarioCrosstab.Properties.VariableNames;
fractionVars = vars(contains(vars, '_fraction'));
if isempty(fractionVars)
    warning('Phase5:NoFractionColumns', 'No scenario-cluster fraction columns available for heatmap.');
    return;
end

data = table2array(scenarioCrosstab(:, fractionVars));
clusterLabels = erase(fractionVars, '_fraction');
scenarioLabels = strrep(scenarioCrosstab.scenario_name, '_', ' ');

fig = figure('Color', 'w', 'Name', 'Phase 5 scenario-cluster heatmap');
imagesc(data);
colormap(parula);
colorbar;
xticks(1:numel(clusterLabels));
xticklabels(strrep(clusterLabels, '_', ' '));
yticks(1:numel(scenarioLabels));
yticklabels(scenarioLabels);
xtickangle(35);
xlabel('Cluster');
ylabel('Scenario label used for interpretation only');
title('Scenario distribution by cluster');
save_figure(fig, fullfile(cfg.figuresDir, 'phase5_cluster_scenario_heatmap.png'));
end
