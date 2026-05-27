function plot_phase10a_regret_by_module(cfg, regretTable)
%PLOT_PHASE10A_REGRET_BY_MODULE Box chart of raw vs safety-enforced regret.

if isempty(regretTable)
    return;
end
modules = string(regretTable.module_name);
uniqueMods = unique(modules, 'stable');
n = numel(uniqueMods);

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
hold on;
rawMeans = zeros(n, 1);
safeMeans = zeros(n, 1);
for k = 1:n
    mask = modules == uniqueMods(k);
    rawMeans(k) = mean(regretTable.raw_regret(mask), 'omitnan');
    safeMeans(k) = mean(regretTable.safety_enforced_regret(mask), 'omitnan');
end

x = 1:n;
width = 0.35;
bar(x - width/2, rawMeans, width, 'FaceColor', [0.85 0.45 0.45], 'DisplayName', 'raw top-1');
bar(x + width/2, safeMeans, width, 'FaceColor', [0.30 0.55 0.85], 'DisplayName', 'safety-enforced');
set(gca, 'XTick', x, 'XTickLabel', cellstr(uniqueMods));
ylabel('mean oracle regret');
xlabel('module');
title(sprintf('Phase 10A: mean regret per module (decision groups = %d)', height(regretTable)));
legend('Location', 'best');
grid on;
hold off;

save_figure(fig, fullfile(cfg.figuresDir, 'phase10a_regret_by_module.png'));
end
