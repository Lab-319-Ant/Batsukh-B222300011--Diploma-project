function plot_phase11a_conflict_counts(cfg, conflictLog)
if isempty(conflictLog)
    return;
end
types = string(conflictLog.conflict_type);
[uniqueTypes, ~, idx] = unique(types, 'stable');
counts = accumarray(idx, 1);

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
b = bar(counts);
set(gca, 'XTick', 1:numel(uniqueTypes), 'XTickLabel', cellstr(uniqueTypes), ...
    'XTickLabelRotation', 25);
ylabel('conflict count');
title(sprintf('Phase 11A conflict counts by type (n=%d)', height(conflictLog)));
grid on;
b = b; %#ok<NASGU>

save_figure(fig, fullfile(cfg.figuresDir, 'phase11a_conflict_counts.png'));
end
