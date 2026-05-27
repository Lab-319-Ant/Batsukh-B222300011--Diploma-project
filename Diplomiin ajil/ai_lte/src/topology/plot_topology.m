function plot_topology(cfg, topology, ues, rf)
%PLOT_TOPOLOGY Baseline map: зөвхөн сайтууд, тэдгээрийн coverage хүрээ,
% мөн UE байршил харагдана. Сайтын нэр, sector azimuth, "Site N \n NAME",
% "S\d \n NN deg" гэх мэт нэршил, градус харагдахгүй.

fig = figure('Color', 'w', 'Name', 'LTE topology baseline map');
hold on; grid on; axis equal;

th = linspace(0, 2*pi, 361);
hCoverage = gobjects(1, 1);
for i = 1:height(topology.sites)
    cx = topology.sites.x_m(i);
    cy = topology.sites.y_m(i);
    h = plot(cx + cfg.plannedRadius_m * cos(th), cy + cfg.plannedRadius_m * sin(th), ...
        'k--', 'LineWidth', 1.0);
    if i == 1
        hCoverage = h;
    end
end

hAttached = gobjects(1, 1);
hUnattached = gobjects(1, 1);
if nargin >= 4 && ~isempty(ues) && ~isempty(rf)
    attached = rf.isAttached;
    hAttached = scatter(ues.x_m(attached), ues.y_m(attached), 14, 'filled', 'MarkerFaceAlpha', 0.55);
    hUnattached = scatter(ues.x_m(~attached), ues.y_m(~attached), 20, 'x', 'LineWidth', 1.0);
end

% Сайтуудыг гурвалжин маркераар зөвхөн харуулна — текст шошгогүй.
hSite = scatter(topology.sites.x_m, topology.sites.y_m, 110, 'filled', ...
    'Marker', '^', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);

% Axis-ын хүрээг сайтуудын байршил + coverage хүрээгээр л таруулна
% (cfg.area_m бүхэлд биш) — ингэснээр сайтууд илүү ойр харагдана.
sitesX = topology.sites.x_m;
sitesY = topology.sites.y_m;
pad = 1.25 * cfg.plannedRadius_m;
xLo = min(sitesX) - pad;
xHi = max(sitesX) + pad;
yLo = min(sitesY) - pad;
yHi = max(sitesY) + pad;
% Квадрат болгож тэгшитгэе (axis equal-тай хослон).
xCenter = (xLo + xHi) / 2;
yCenter = (yLo + yHi) / 2;
halfSpan = max(xHi - xLo, yHi - yLo) / 2;
xlim([xCenter - halfSpan, xCenter + halfSpan]);
ylim([yCenter - halfSpan, yCenter + halfSpan]);

xlabel('x position [m]');
ylabel('y position [m]');
title(sprintf('%d-site baseline map', height(topology.sites)));

if nargin >= 4 && ~isempty(ues) && ~isempty(rf)
    legend([hCoverage, hAttached, hUnattached, hSite], ...
        {'Coverage хүрээ','Холбогдсон UE','Холбогдоогүй UE','Сайт'}, ...
        'Location', 'bestoutside');
else
    legend([hCoverage, hSite], ...
        {'Coverage хүрээ','Сайт'}, 'Location', 'bestoutside');
end

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_topology_ue_attachment.png'));
end
