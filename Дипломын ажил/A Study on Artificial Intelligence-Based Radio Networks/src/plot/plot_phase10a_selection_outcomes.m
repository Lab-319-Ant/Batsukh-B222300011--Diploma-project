function plot_phase10a_selection_outcomes(cfg, selectedTable)
%PLOT_PHASE10A_SELECTION_OUTCOMES Stacked outcome composition per module.

if isempty(selectedTable)
    return;
end
modules = string(selectedTable.module_name);
uniqueMods = unique(modules, 'stable');
n = numel(uniqueMods);

% Three outcome categories: safe-non-noop, safe-noop, fallback-unsafe.
safeNoNoop = zeros(n, 1);
safeNoop = zeros(n, 1);
fallbackUnsafe = zeros(n, 1);
for k = 1:n
    mask = modules == uniqueMods(k);
    safeFlag = selectedTable.safe_selected_safety_valid(mask);
    noopFlag = selectedTable.noop_selected(mask);
    safeNoNoop(k) = sum(safeFlag & ~noopFlag);
    safeNoop(k) = sum(safeFlag & noopFlag);
    fallbackUnsafe(k) = sum(~safeFlag);
end

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
data = [safeNoNoop, safeNoop, fallbackUnsafe];
bar(1:n, data, 'stacked');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(uniqueMods));
ylabel('decision group count');
xlabel('module');
legend({'safe (non-noop)','safe (noop / keep_active)','unsafe fallback'}, ...
    'Location', 'best');
title(sprintf('Phase 10A selection outcomes per module (n=%d)', height(selectedTable)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase10a_selection_outcomes.png'));
end
