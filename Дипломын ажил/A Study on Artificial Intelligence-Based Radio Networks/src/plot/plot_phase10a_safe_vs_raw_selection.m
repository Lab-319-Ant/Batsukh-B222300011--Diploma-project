function plot_phase10a_safe_vs_raw_selection(cfg, comparisonTable)
%PLOT_PHASE10A_SAFE_VS_RAW_SELECTION Bar chart of raw-unsafe vs safe-residual-unsafe per module.

if isempty(comparisonTable)
    return;
end
modules = string(comparisonTable.module_name);
uniqueMods = unique(modules, 'stable');
n = numel(uniqueMods);

rawUnsafe = zeros(n, 1);
safeUnsafe = zeros(n, 1);
filterChanged = zeros(n, 1);
for k = 1:n
    mask = modules == uniqueMods(k);
    rawUnsafe(k) = sum(~comparisonTable.raw_selected_safety_valid(mask));
    safeUnsafe(k) = sum(~comparisonTable.safe_selected_safety_valid(mask));
    filterChanged(k) = sum(comparisonTable.safety_filter_changed_action(mask));
end

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
hold on;
x = 1:n;
w = 0.27;
bar(x - w, rawUnsafe, w, 'FaceColor', [0.85 0.40 0.40], 'DisplayName', 'raw top-1 unsafe');
bar(x,     filterChanged, w, 'FaceColor', [0.55 0.55 0.55], 'DisplayName', 'safety filter changed action');
bar(x + w, safeUnsafe, w, 'FaceColor', [0.30 0.55 0.85], 'DisplayName', 'residual unsafe after safety filter');
set(gca, 'XTick', x, 'XTickLabel', cellstr(uniqueMods));
ylabel('decision group count');
xlabel('module');
title('Phase 10A: raw vs safety-enforced selection per module');
legend('Location', 'best');
grid on;
hold off;

save_figure(fig, fullfile(cfg.figuresDir, 'phase10a_raw_vs_safe_selection.png'));
end
