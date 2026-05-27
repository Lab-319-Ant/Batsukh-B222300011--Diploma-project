function plot_ue_throughput_map(cfg, topology, ueTrafficResult)
%PLOT_UE_THROUGHPUT_MAP Plot served UE throughput after Phase 2 allocation.

fig = figure('Color', 'w', 'Name', 'Phase 2 UE throughput map');
hold on; grid on; axis equal;

plot_planned_circles(cfg, topology);
attached = ueTrafficResult.isAttached;

scatter(ueTrafficResult.x_m(attached), ueTrafficResult.y_m(attached), 24, ...
    ueTrafficResult.servedThroughput_Mbps(attached), 'filled', 'MarkerFaceAlpha', 0.75);
scatter(ueTrafficResult.x_m(~attached), ueTrafficResult.y_m(~attached), 36, 'x', ...
    'LineWidth', 1.3, 'MarkerEdgeColor', [0.1 0.1 0.1]);
scatter(topology.sites.x_m, topology.sites.y_m, 80, 'filled', 'Marker', '^', ...
    'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', [0.1 0.1 0.1]);

cb = colorbar;
ylabel(cb, 'Served throughput [Mbps]');
xlabel('x position [m]');
ylabel('y position [m]');
title('Phase 2 UE served throughput map');

halfArea = cfg.area_m / 2;
xlim([-halfArea, halfArea]);
ylim([-halfArea, halfArea]);

save_figure(fig, fullfile(cfg.figuresDir, 'phase2_ue_throughput_map.png'));
end

function plot_planned_circles(cfg, topology)
th = linspace(0, 2*pi, 361);
for i = 1:height(topology.sites)
    plot(topology.sites.x_m(i) + cfg.plannedRadius_m*cos(th), ...
        topology.sites.y_m(i) + cfg.plannedRadius_m*sin(th), ...
        'k--', 'LineWidth', 0.8);
end
end
