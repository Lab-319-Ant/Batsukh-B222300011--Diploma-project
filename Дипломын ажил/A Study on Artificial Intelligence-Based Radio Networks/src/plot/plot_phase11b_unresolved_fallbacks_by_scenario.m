function plot_phase11b_unresolved_fallbacks_by_scenario(cfg, scenarioSummary)
if isempty(scenarioSummary)
    return;
end
scenarios = string(scenarioSummary.scenario_name);
n = numel(scenarios);

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
data = [scenarioSummary.unresolved_unsafe_fallback, ...
    scenarioSummary.rejected_priority_conflict + scenarioSummary.rejected_safety_conflict, ...
    scenarioSummary.final_safe_action];
bar(1:n, data, 'stacked');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(scenarios), 'XTickLabelRotation', 20);
ylabel('decision count');
legend({'unresolved unsafe fallback','rejected','final safe action'}, ...
    'Location', 'best');
title('Phase 11B: unresolved fallbacks and outcomes per scenario');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase11b_unresolved_fallbacks_by_scenario.png'));
end
