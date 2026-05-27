function plot_traffic_calibration_summary(cfg, calibrationSummary)
%PLOT_TRAFFIC_CALIBRATION_SUMMARY Plot traffic-mode sensitivity KPIs.

fig = figure('Color', 'w', 'Name', 'Traffic calibration summary');
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

modeLabels = strrep(calibrationSummary.traffic_mode, '_', ' ');
modes = categorical(modeLabels);
modes = reordercats(modes, modeLabels);

nexttile;
bar(modes, calibrationSummary.total_offered_traffic_Mbps);
grid on;
ylabel('Offered traffic [Mbps]');
title('Offered traffic');
set(gca, 'YScale', 'log');

nexttile;
bar(modes, calibrationSummary.mean_sector_load);
grid on;
ylabel('Mean sector load');
title('Mean load');
yline(cfg.sectorOverloadThreshold, 'r--', 'Overload threshold', ...
    'LabelHorizontalAlignment', 'left');
set(gca, 'YScale', 'log');

nexttile;
bar(modes, 100 * calibrationSummary.qos_satisfaction_ratio);
grid on;
ylabel('QoS satisfied active UEs [%]');
title('QoS satisfaction');
ylim([0 100]);

nexttile;
bar(modes, calibrationSummary.overloaded_sector_count);
grid on;
ylabel('Overloaded sectors');
title('Overload count');
ylim([0 max(height_placeholder(calibrationSummary), max(calibrationSummary.overloaded_sector_count) + 1)]);

if isfield(cfg, 'phase') && startsWith(cfg.phase, 'Phase2C')
    fileName = 'phase2c_traffic_calibration_summary.png';
else
    fileName = 'phase2b_traffic_calibration_summary.png';
end
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end

function n = height_placeholder(calibrationSummary)
if ismember('num_sectors', calibrationSummary.Properties.VariableNames)
    n = max(calibrationSummary.num_sectors);
else
    n = 21;
end
end
