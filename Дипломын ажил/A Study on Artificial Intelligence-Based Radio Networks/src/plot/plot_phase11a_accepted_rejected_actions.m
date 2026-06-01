function plot_phase11a_accepted_rejected_actions(cfg, candidateActions)
if isempty(candidateActions)
    return;
end
modules = string(candidateActions.module_name);
uniqueMods = unique(modules, 'stable');
n = numel(uniqueMods);
accepted = zeros(n, 1);
rejected = zeros(n, 1);
for k = 1:n
    mask = modules == uniqueMods(k);
    accepted(k) = sum(mask & candidateActions.accepted_flag);
    rejected(k) = sum(mask & candidateActions.rejected_flag);
end

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
bar(1:n, [accepted, rejected], 'stacked');
set(gca, 'XTick', 1:n, 'XTickLabel', cellstr(uniqueMods));
ylabel('action count');
legend({'accepted','rejected'}, 'Location', 'best');
title('Phase 11A: coordinator accept/reject per module');
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase11a_accepted_rejected_actions.png'));
end
