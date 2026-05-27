function plot_cod_feature_importance(cfg, featureImportance, fileName)
%PLOT_COD_FEATURE_IMPORTANCE Plot Random Forest COD feature importance.

topN = min(16, height(featureImportance));
plotTable = featureImportance(1:topN, :);
labels = categorical(plotTable.feature_name);
labels = reordercats(labels, plotTable.feature_name);

fig = figure('Color', 'w', 'Name', 'Phase 6B COD feature importance');
barh(labels, plotTable.importance);
set(gca, 'YDir', 'reverse');
grid on;
xlabel('Importance');
title('COD Random Forest feature importance');
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end
