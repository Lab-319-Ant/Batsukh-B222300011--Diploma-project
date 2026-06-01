function plot_phase8a_candidate_action_counts(cfg, summaryTable)
%PLOT_PHASE8A_CANDIDATE_ACTION_COUNTS Plot candidate counts by module.

if isempty(summaryTable)
    return;
end
[groups, moduleName] = findgroups(summaryTable.module_name);
counts = splitapply(@sum, summaryTable.candidate_count, groups);
labels = categorical(moduleName);
labels = reordercats(labels, moduleName);

fig = figure('Color', 'w', 'Name', 'Phase 8A candidate action counts');
bar(labels, counts);
grid on;
ylabel('Candidate action rows');
title('Phase 8A candidate action counts by module');
save_figure(fig, fullfile(cfg.figuresDir, 'phase8a_candidate_action_counts.png'));
end
