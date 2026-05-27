function plot_best_sinr_map(cfg, topology, map)
%PLOT_BEST_SINR_MAP Plot best-sector full-band SINR over square study area.

if nargin < 3 || isempty(map)
    map = compute_best_server_map(cfg, topology);
end

fig = figure('Color', 'w', 'Name', 'Best SINR map');
imagesc(map.x, map.y, map.bestSINR_dB);
set(gca, 'YDir', 'normal');
axis equal tight;
hold on;

contour(map.X, map.Y, map.bestSINR_dB, [cfg.minSINR_dB cfg.minSINR_dB], 'k', 'LineWidth', 1.8);
draw_planned_circles(cfg, topology);
scatter(topology.sites.x_m, topology.sites.y_m, 90, 'filled', 'Marker', '^');

cb = colorbar;
ylabel(cb, 'Best-sector SINR [dB]');
xlabel('x position [m]');
ylabel('y position [m]');
title(sprintf('Best-sector SINR map, threshold %.0f dB', cfg.minSINR_dB));

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_best_sinr_map.png'));
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
