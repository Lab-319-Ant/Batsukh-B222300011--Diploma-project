function plot_best_server_map(cfg, topology, map)
%PLOT_BEST_SERVER_MAP Plot best serving sector over the study window.

fig = figure('Color', 'w', 'Name', 'Best server map');
imagesc(map.x, map.y, map.bestSector);
set(gca, 'YDir', 'normal');
axis equal tight;
hold on;

draw_planned_circles(cfg, topology);
scatter(topology.sites.x_m, topology.sites.y_m, 70, 'filled', 'Marker', '^', ...
    'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');

cb = colorbar;
ylabel(cb, 'Best sector ID');
xlabel('x position [m]');
ylabel('y position [m]');
title('Best-server map from maximum RSRP association');

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_best_server_map.png'));
end

function draw_planned_circles(cfg, topology)
th = linspace(0, 2*pi, 361);
for i = 1:height(topology.sites)
    cx = topology.sites.x_m(i);
    cy = topology.sites.y_m(i);
    plot(cx + cfg.plannedRadius_m*cos(th), cy + cfg.plannedRadius_m*sin(th), ...
        'k--', 'LineWidth', 0.9);
end
end
