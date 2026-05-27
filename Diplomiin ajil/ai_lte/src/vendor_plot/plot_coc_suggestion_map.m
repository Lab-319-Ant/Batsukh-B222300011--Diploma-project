function plot_coc_suggestion_map(vcfg, suggestions)
%PLOT_COC_SUGGESTION_MAP Summary of COC recommendation counts by sector.

if isempty(suggestions)
    return;
end

[groups, sector] = findgroups(suggestions.sim_sector_id);
total = splitapply(@numel, suggestions.recommended_coc_action, groups);
accepted = splitapply(@(x) sum(strcmp(string(x), 'candidate_for_manual_review')), ...
    suggestions.safety_status, groups);
rejected = splitapply(@(x) sum(contains(string(x), 'rejected')), ...
    suggestions.safety_status, groups);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 900 420]);
bar(categorical(compose('S%d', sector)), [total, accepted, rejected]);
grid on;
xlabel('simulated sector');
ylabel('recommendation rows');
legend({'total abnormal rows','COC candidate','rejected'}, 'Location', 'best');
title('Vendor KPI COC/OH suggestion summary by sector');
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_suggestion_summary.png'));
end
