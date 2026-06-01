function plot_sector_load_map(cfg, topology, sectorKpiTable, ueTrafficResult)
%PLOT_SECTOR_LOAD_MAP Plot Phase 2 sector traffic load over the topology.

fig = figure('Color', 'w', 'Name', 'Phase 2 sector load map');
hold on; grid on; axis equal;

plot_planned_circles(cfg, topology);

scatter(ueTrafficResult.x_m, ueTrafficResult.y_m, 8, [0.75 0.75 0.75], 'filled', ...
    'MarkerFaceAlpha', 0.35);
scatter(topology.sites.x_m, topology.sites.y_m, 80, 'filled', 'Marker', '^', ...
    'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', [0.1 0.1 0.1]);

markerX = zeros(height(sectorKpiTable), 1);
markerY = zeros(height(sectorKpiTable), 1);
offset = 0.22 * cfg.plannedRadius_m;
for i = 1:height(sectorKpiTable)
    siteIdx = topology.sites.siteId == sectorKpiTable.site_id(i);
    az = sectorKpiTable.azimuth_deg(i);
    markerX(i) = topology.sites.x_m(siteIdx) + offset * sind(az);
    markerY(i) = topology.sites.y_m(siteIdx) + offset * cosd(az);
end

rawLoad = sectorKpiTable.sector_load_ratio;
finiteLoad = rawLoad(isfinite(rawLoad));
loadForColor = rawLoad;
if isempty(finiteLoad)
    loadForColor(:) = 0;
else
    loadForColor(~isfinite(loadForColor)) = max(finiteLoad);
end

markerSize = 70 + 80 * min(loadForColor, 2);
scatter(markerX, markerY, markerSize, loadForColor, 'filled', ...
    'MarkerEdgeColor', 'k', 'LineWidth', 0.8);

overIdx = sectorKpiTable.overload_flag;
scatter(markerX(overIdx), markerY(overIdx), 150, 'x', 'LineWidth', 2.0, ...
    'MarkerEdgeColor', [0.85 0 0]);

for i = 1:height(sectorKpiTable)
    text(markerX(i) + 15, markerY(i) + 15, sprintf('S%d', sectorKpiTable.sector_id(i)), ...
        'FontSize', 8, 'FontWeight', 'bold');
end

cb = colorbar;
ylabel(cb, 'Sector load ratio');
caxis([0, max(1, max(loadForColor))]);
xlabel('x position [m]');
ylabel('y position [m]');
title('Phase 2 sector load ratio map');

halfArea = cfg.area_m / 2;
xlim([-halfArea, halfArea]);
ylim([-halfArea, halfArea]);

save_figure(fig, fullfile(cfg.figuresDir, 'phase2_sector_load_map.png'));
end

function plot_planned_circles(cfg, topology)
th = linspace(0, 2*pi, 361);
for i = 1:height(topology.sites)
    plot(topology.sites.x_m(i) + cfg.plannedRadius_m*cos(th), ...
        topology.sites.y_m(i) + cfg.plannedRadius_m*sin(th), ...
        'k--', 'LineWidth', 0.8);
end
end
