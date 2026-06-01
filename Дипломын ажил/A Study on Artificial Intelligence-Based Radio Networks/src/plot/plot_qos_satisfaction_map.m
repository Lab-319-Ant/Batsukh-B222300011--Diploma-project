function plot_qos_satisfaction_map(cfg, topology, ueTrafficResult)
%PLOT_QOS_SATISFACTION_MAP Plot QoS-satisfied, QoS-failed, and unattached UEs.

fig = figure('Color', 'w', 'Name', 'Phase 2 QoS satisfaction map');
hold on; grid on; axis equal;

plot_planned_circles(cfg, topology);

attached = ueTrafficResult.isAttached;
qosOk = ueTrafficResult.qosSatisfied;
qosFail = attached & ~qosOk;
unattached = ~attached;

hOk = scatter(ueTrafficResult.x_m(qosOk), ueTrafficResult.y_m(qosOk), 24, 'filled', ...
    'MarkerFaceColor', [0.0 0.55 0.25], 'MarkerFaceAlpha', 0.75);
hFail = scatter(ueTrafficResult.x_m(qosFail), ueTrafficResult.y_m(qosFail), 28, 'filled', ...
    'MarkerFaceColor', [0.85 0.15 0.10], 'MarkerFaceAlpha', 0.75);
hUnattached = scatter(ueTrafficResult.x_m(unattached), ueTrafficResult.y_m(unattached), 38, 'x', ...
    'LineWidth', 1.3, 'MarkerEdgeColor', [0.1 0.1 0.1]);
hSite = scatter(topology.sites.x_m, topology.sites.y_m, 80, 'filled', 'Marker', '^', ...
    'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', [0.1 0.1 0.1]);

xlabel('x position [m]');
ylabel('y position [m]');
title('Phase 2 QoS satisfaction map');
legend([hOk, hFail, hUnattached, hSite], ...
    {'QoS satisfied','QoS failed','Unattached UE','Site'}, 'Location', 'bestoutside');

halfArea = cfg.area_m / 2;
xlim([-halfArea, halfArea]);
ylim([-halfArea, halfArea]);

save_figure(fig, fullfile(cfg.figuresDir, 'phase2_qos_satisfaction_map.png'));
end

function plot_planned_circles(cfg, topology)
th = linspace(0, 2*pi, 361);
for i = 1:height(topology.sites)
    plot(topology.sites.x_m(i) + cfg.plannedRadius_m*cos(th), ...
        topology.sites.y_m(i) + cfg.plannedRadius_m*sin(th), ...
        'k--', 'LineWidth', 0.8);
end
end
