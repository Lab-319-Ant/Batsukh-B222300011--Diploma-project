function plot_phase12e_baseline_ai_oracle_kpis(cfg, comparisonTable)
if isempty(comparisonTable), return; end
gapMask = isfinite(comparisonTable.oracle_qos);
sub = comparisonTable(gapMask, :);
if isempty(sub), return; end

fig = figure('Visible', 'off', 'Position', [100 100 1000 500]);
metrics = {'baseline_qos','ai_qos','oracle_qos'};
labels = {'baseline','AI/ML','oracle'};
data = [mean(sub.baseline_qos, 'omitnan'), mean(sub.ai_qos, 'omitnan'), mean(sub.oracle_qos, 'omitnan')];

bar(data);
set(gca, 'XTick', 1:3, 'XTickLabel', labels);
ylabel('mean QoS satisfaction ratio');
title(sprintf('Phase 12E: baseline vs AI/ML vs oracle QoS (n=%d comparable rows)', height(sub)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12e_baseline_ai_oracle_kpis.png'));
metrics = metrics; %#ok<NASGU,ASGSL>
end
