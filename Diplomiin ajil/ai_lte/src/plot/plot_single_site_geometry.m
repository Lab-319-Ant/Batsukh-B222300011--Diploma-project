function plot_single_site_geometry(cfg, topology, ues, rf)
%PLOT_SINGLE_SITE_GEOMETRY Plot site, sector azimuths, planned radius, and UE attach status.

fig = figure('Color', 'w', 'Name', 'Single-site geometry and UE attachment');
hold on; grid on; axis equal;

% Planned service radius
th = linspace(0, 2*pi, 361);
plot(cfg.plannedRadius_m * cos(th), cfg.plannedRadius_m * sin(th), 'k--', 'LineWidth', 1.5);

% UEs
attached = rf.isAttached;
scatter(ues.x_m(attached), ues.y_m(attached), 18, 'filled', 'MarkerFaceAlpha', 0.65);
scatter(ues.x_m(~attached), ues.y_m(~attached), 22, 'x', 'LineWidth', 1.2);

% Site
scatter(topology.sites.x_m, topology.sites.y_m, 90, 'filled', 'Marker', '^');
text(topology.sites.x_m + 30, topology.sites.y_m + 30, 'Site 1', 'FontWeight', 'bold');

% Sector arrows
arrowLen = 0.35 * cfg.plannedRadius_m;
for s = 1:height(topology.sectors)
    az = topology.sectors.azimuth_deg(s);
    dx = arrowLen * sind(az);
    dy = arrowLen * cosd(az);
    quiver(0, 0, dx, dy, 0, 'LineWidth', 2, 'MaxHeadSize', 0.7);
    text(dx * 1.08, dy * 1.08, sprintf('S%d: %d°', s, az), 'FontWeight', 'bold');
end

halfArea = cfg.area_m / 2;
xlim([-halfArea, halfArea]);
ylim([-halfArea, halfArea]);
xlabel('x position [m]');
ylabel('y position [m]');
title(sprintf('Single-site / 3-sector geometry, attach rate = %.1f%%', 100*mean(attached)));
legend({'Planned radius','Attached UE','Unattached UE','Site','Sector azimuth'}, 'Location', 'bestoutside');

save_figure(fig, fullfile(cfg.figuresDir, 'single_site_ue_attachment.png'));
end
