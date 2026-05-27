function plot_phase11b_final_decision_status(cfg, finalDecisions)
if isempty(finalDecisions)
    return;
end
statuses = {'final_safe_action','final_noop','rejected_priority_conflict', ...
    'rejected_safety_conflict','unresolved_unsafe_fallback','diagnostic_only'};
counts = zeros(numel(statuses), 1);
for i = 1:numel(statuses)
    counts(i) = sum(strcmp(finalDecisions.final_decision_status, statuses{i}));
end

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
bar(counts);
set(gca, 'XTick', 1:numel(statuses), 'XTickLabel', statuses, 'XTickLabelRotation', 20);
ylabel('decision count');
title(sprintf('Phase 11B final decision status (n=%d)', height(finalDecisions)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase11b_final_decision_status.png'));
end
