function plot_regression_error_by_scenario(cfg, predictionsTable, plotTitle, fileName)
%PLOT_REGRESSION_ERROR_BY_SCENARIO Plot absolute error by scenario.

testRows = strcmp(predictionsTable.split, 'test');
tbl = predictionsTable(testRows, :);
scenarioNames = unique(tbl.scenario_name, 'stable');
mae = zeros(numel(scenarioNames), 1);
for i = 1:numel(scenarioNames)
    idx = strcmp(tbl.scenario_name, scenarioNames{i});
    mae(i) = mean(abs(tbl.error(idx)), 'omitnan');
end
labels = categorical(strrep(scenarioNames, '_', ' '));
labels = reordercats(labels, strrep(scenarioNames, '_', ' '));

fig = figure('Color', 'w', 'Name', plotTitle);
bar(labels, mae);
grid on;
ylabel('Test MAE');
title(plotTitle);
xtickangle(30);
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end
