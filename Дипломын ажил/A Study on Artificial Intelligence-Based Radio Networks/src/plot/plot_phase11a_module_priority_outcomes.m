function plot_phase11a_module_priority_outcomes(cfg, moduleSummary)
if isempty(moduleSummary)
    return;
end
modules = string(moduleSummary.module_name);
n = numel(modules);

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
data = [moduleSummary.safety_rejection_count, ...
    moduleSummary.priority_rejection_count, ...
    moduleSummary.noop_count, ...
    moduleSummary.fallback_count];
bar(1:n, data, 'grouped');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(modules));
ylabel('count per module');
legend({'safety rejection','priority rejection','noop selected','fallback used'}, ...
    'Location', 'best');
title('Phase 11A: per-module outcomes');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase11a_module_priority_outcomes.png'));
end
