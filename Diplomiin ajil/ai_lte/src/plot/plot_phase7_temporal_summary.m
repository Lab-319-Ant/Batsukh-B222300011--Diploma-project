function plot_phase7_temporal_summary(cfg, networkTemporal)
%PLOT_PHASE7_TEMPORAL_SUMMARY Plot offered traffic and QoS timelines.

scenarioNames = unique(networkTemporal.scenario_name, 'stable');
fig = figure('Color', 'w', 'Name', 'Phase 7A temporal TP/QP dataset');
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
hold on;
for i = 1:numel(scenarioNames)
    idx = strcmp(networkTemporal.scenario_name, scenarioNames{i});
    plot(networkTemporal.time_index(idx), networkTemporal.total_offered_traffic_Mbps(idx), ...
        'DisplayName', strrep(scenarioNames{i}, '_', ' '));
end
hold off;
grid on;
ylabel('Offered traffic [Mbps]');
title('Temporal offered traffic');
legend('Location', 'bestoutside');

nexttile;
hold on;
for i = 1:numel(scenarioNames)
    idx = strcmp(networkTemporal.scenario_name, scenarioNames{i});
    plot(networkTemporal.time_index(idx), 100 * networkTemporal.qos_satisfaction_ratio(idx), ...
        'DisplayName', strrep(scenarioNames{i}, '_', ' '));
end
hold off;
grid on;
xlabel('Time step');
ylabel('QoS satisfaction [%]');
title('Temporal QoS satisfaction');

save_figure(fig, fullfile(cfg.figuresDir, 'phase7a_traffic_qos_timeline.png'));
end
