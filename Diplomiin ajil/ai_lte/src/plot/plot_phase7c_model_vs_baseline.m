function plot_phase7c_model_vs_baseline(cfg, comparisonTable, plotTitle, fileName)
%PLOT_PHASE7C_MODEL_VS_BASELINE Plot overall test RMSE by model/baseline.

idx = strcmp(comparisonTable.split, 'test') & strcmp(comparisonTable.scenario_name, 'ALL');
tbl = comparisonTable(idx, :);
labels = categorical(tbl.model_name);
labels = reordercats(labels, tbl.model_name);

fig = figure('Color', 'w', 'Name', plotTitle);
bar(labels, tbl.RMSE);
grid on;
ylabel('Test RMSE');
title(plotTitle);
xtickangle(25);
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end
