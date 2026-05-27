function plot_phase3_scenario_summary(cfg, scenarioSummary)
%PLOT_PHASE3_SCENARIO_SUMMARY Plot key KPIs across Phase 3 scenarios.

fig = figure('Color', 'w', 'Name', 'Phase 3 scenario summary');
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

labels = strrep(scenarioSummary.scenario_name, '_', ' ');
scenarioCats = categorical(labels);
scenarioCats = reordercats(scenarioCats, labels);

nexttile;
bar(scenarioCats, 100 * scenarioSummary.attach_rate);
grid on;
ylabel('Attach rate [%]');
title('RF attachment');
ylim([0 100]);
xtickangle(35);

nexttile;
bar(scenarioCats, 100 * scenarioSummary.qos_satisfaction_ratio_active);
grid on;
ylabel('QoS active UEs [%]');
title('QoS satisfaction');
ylim([0 100]);
xtickangle(35);

nexttile;
bar(scenarioCats, scenarioSummary.mean_sector_load);
grid on;
ylabel('Mean sector load');
title('Traffic load');
yline(cfg.sectorOverloadThreshold, 'r--', 'Overload threshold', ...
    'LabelHorizontalAlignment', 'left');
xtickangle(35);

nexttile;
bar(scenarioCats, scenarioSummary.overloaded_sector_count);
grid on;
ylabel('Overloaded sectors');
title('Overload count');
ylim([0 max(height_placeholder(scenarioSummary), max(scenarioSummary.overloaded_sector_count) + 1)]);
xtickangle(35);

save_figure(fig, fullfile(cfg.figuresDir, 'phase3_scenario_summary.png'));
end

function n = height_placeholder(scenarioSummary)
if ismember('num_sectors', scenarioSummary.Properties.VariableNames)
    n = max(scenarioSummary.num_sectors);
else
    n = 21;
end
end
