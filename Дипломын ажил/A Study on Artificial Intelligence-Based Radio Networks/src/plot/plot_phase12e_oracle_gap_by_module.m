function plot_phase12e_oracle_gap_by_module(cfg, comparisonTable)
if isempty(comparisonTable), return; end
mask = isfinite(comparisonTable.qos_gap_to_oracle);
sub = comparisonTable(mask, :);
if isempty(sub), return; end

modules = unique(string(sub.module_name), 'stable');
n = numel(modules);
meanGap = zeros(n, 1);
for k = 1:n
    m = string(sub.module_name) == modules(k);
    meanGap(k) = mean(sub.qos_gap_to_oracle(m), 'omitnan');
end

fig = figure('Visible', 'off', 'Position', [100 100 800 500]);
bar(meanGap);
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(modules));
ylabel('mean QoS gap to oracle (oracle - AI)');
title(sprintf('Phase 12E: oracle KPI gap by module (n=%d comparable)', height(sub)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12e_oracle_gap_by_module.png'));
end
