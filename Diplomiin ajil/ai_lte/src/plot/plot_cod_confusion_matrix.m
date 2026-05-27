function plot_cod_confusion_matrix(cfg, confusionTable, plotTitle, fileName)
%PLOT_COD_CONFUSION_MATRIX Plot COD confusion matrix.

classNames = confusionTable.actual_label;
matrixValues = table2array(confusionTable(:, startsWith(confusionTable.Properties.VariableNames, 'predicted_')));

fig = figure('Color', 'w', 'Name', plotTitle);
imagesc(matrixValues);
colormap(parula);
colorbar;
axis equal tight;
xticks(1:numel(classNames));
yticks(1:numel(classNames));
xticklabels(classNames);
yticklabels(classNames);
xlabel('Predicted label');
ylabel('Actual label');
title(plotTitle);

for r = 1:size(matrixValues, 1)
    for c = 1:size(matrixValues, 2)
        text(c, r, sprintf('%d', matrixValues(r, c)), ...
            'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold');
    end
end

save_figure(fig, fullfile(cfg.figuresDir, fileName));
end
