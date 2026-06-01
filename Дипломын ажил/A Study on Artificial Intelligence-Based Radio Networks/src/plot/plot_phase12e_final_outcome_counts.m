function plot_phase12e_final_outcome_counts(cfg, baselineAi)
if isempty(baselineAi), return; end
classes = {'improved','improved_with_tradeoff','worsened','unchanged','mixed'};
counts = zeros(numel(classes), 1);
for i = 1:numel(classes)
    counts(i) = sum(strcmp(baselineAi.outcome_class, classes{i}));
end

fig = figure('Visible', 'off', 'Position', [100 100 900 500]);
bar(counts);
set(gca, 'XTick', 1:numel(classes), 'XTickLabel', classes, 'XTickLabelRotation', 15);
ylabel('action count');
title(sprintf('Phase 12E final outcome counts (n=%d)', height(baselineAi)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12e_final_outcome_counts.png'));
end
