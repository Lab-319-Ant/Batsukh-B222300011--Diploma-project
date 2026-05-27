function plot_regression_actual_vs_predicted(cfg, predictionsTable, plotTitle, fileName)
%PLOT_REGRESSION_ACTUAL_VS_PREDICTED Scatter actual vs predicted values.

testRows = strcmp(predictionsTable.split, 'test');
tbl = predictionsTable(testRows, :);
fig = figure('Color', 'w', 'Name', plotTitle);
scatter(tbl.actual_target, tbl.predicted_target, 12, 'filled', 'MarkerFaceAlpha', 0.35);
hold on;
minVal = min([tbl.actual_target; tbl.predicted_target]);
maxVal = max([tbl.actual_target; tbl.predicted_target]);
plot([minVal maxVal], [minVal maxVal], 'r--', 'LineWidth', 1.2);
hold off;
grid on;
xlabel('Actual target');
ylabel('Predicted target');
title(plotTitle);
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end
