function plot_phase11b_executable_actions_by_module(cfg, moduleSummary)
if isempty(moduleSummary)
    return;
end
modules = string(moduleSummary.module_name);
n = numel(modules);

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
data = [moduleSummary.final_safe_action, moduleSummary.final_noop, ...
    moduleSummary.rejected_priority_conflict + moduleSummary.rejected_safety_conflict, ...
    moduleSummary.unresolved_unsafe_fallback];
bar(1:n, data, 'stacked');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(modules));
ylabel('decision count');
legend({'final safe action (executable)','final no-op','rejected', ...
    'unresolved unsafe fallback'}, 'Location', 'best');
title('Phase 11B: final decision composition per module');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase11b_executable_actions_by_module.png'));
end
