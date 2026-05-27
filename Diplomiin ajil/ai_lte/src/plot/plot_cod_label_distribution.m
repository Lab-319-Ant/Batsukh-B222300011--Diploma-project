function plot_cod_label_distribution(cfg, labelDistribution)
%PLOT_COD_LABEL_DISTRIBUTION Plot Phase 6A COD class balance.

labels = categorical(labelDistribution.cod_label);
labels = reordercats(labels, labelDistribution.cod_label);

fig = figure('Color', 'w', 'Name', 'Phase 6A COD label distribution');
bar(labels, labelDistribution.row_count);
grid on;
ylabel('Rows');
title('Phase 6A balanced COD dataset');
save_figure(fig, fullfile(cfg.figuresDir, 'phase6a_cod_label_distribution.png'));
end
