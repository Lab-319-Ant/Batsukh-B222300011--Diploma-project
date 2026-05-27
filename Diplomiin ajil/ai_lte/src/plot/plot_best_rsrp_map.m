function plot_best_rsrp_map(cfg, topology, map)
%PLOT_BEST_RSRP_MAP Plot best-sector RSRP over square study area.

if nargin < 3 || isempty(map)
    map = compute_best_server_map(cfg, topology);
end

fig = figure('Color', 'w', 'Name', 'Best RSRP map');
imagesc(map.x, map.y, map.bestRSRP_dBm);
set(gca, 'YDir', 'normal');
axis equal tight;
hold on;

contour(map.X, map.Y, map.bestRSRP_dBm, [cfg.minRSRP_dBm cfg.minRSRP_dBm], 'k', 'LineWidth', 1.8);
draw_planned_circles(cfg, topology);
scatter(topology.sites.x_m, topology.sites.y_m, 90, 'filled', 'Marker', '^');

cb = colorbar;
ylabel(cb, 'Best RSRP [dBm]');
xlabel('x position [m]');
ylabel('y position [m]');
title(sprintf('Best-sector RSRP map, threshold %.0f dBm', cfg.minRSRP_dBm));

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_best_rsrp_map.png'));
end

function draw_planned_circles(cfg, topology)
th = linspace(0, 2*pi, 361);
for i = 1:height(topology.sites)
    cx = topology.sites.x_m(i);
    cy = topology.sites.y_m(i);
    plot(cx + cfg.plannedRadius_m*cos(th), cy + cfg.plannedRadius_m*sin(th), ...
        'k--', 'LineWidth', 1.0);
end
end
