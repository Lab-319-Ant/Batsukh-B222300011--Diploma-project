function plot_topology_site_sector_labels(cfg, topology)
%PLOT_TOPOLOGY_SITE_SECTOR_LABELS Clean map for assigning KPI sites.
%
% This figure intentionally excludes UE drops and coverage circles so the
% simulated site positions and sector IDs are readable when mapping real
% vendor KPI sites onto the RF-simulation topology.

fig = figure('Color', 'w', 'Name', 'Simulated topology site and sector labels', ...
    'Position', [100 100 1050 820]);
hold on; grid on; axis equal;

siteLabels = get_sim_site_labels(height(topology.sites));
siteColors = lines(height(topology.sites));

% Site markers and position labels.
for i = 1:height(topology.sites)
    x = topology.sites.x_m(i);
    y = topology.sites.y_m(i);
    scatter(x, y, 150, siteColors(i, :), 'filled', '^', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8);

    [ox, oy, ha] = label_offset_for_site(topology.sites.siteId(i), cfg.ISD_m);
    text(x + ox, y + oy, sprintf('Site %d  %s', topology.sites.siteId(i), siteLabels{i}), ...
        'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', ha, ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none', ...
        'BackgroundColor', 'w', 'Margin', 2);
end

% Sector arrows and labels.
arrowLen = 0.30 * cfg.plannedRadius_m;
for s = 1:height(topology.sectors)
    az = topology.sectors.azimuth_deg(s);
    x = topology.sectors.x_m(s);
    y = topology.sectors.y_m(s);
    siteId = topology.sectors.siteId(s);
    color = siteColors(siteId, :);

    dx = arrowLen * sind(az);
    dy = arrowLen * cosd(az);
    quiver(x, y, dx, dy, 0, 'Color', color, 'LineWidth', 1.8, ...
        'MaxHeadSize', 0.9);

    text(x + 1.20 * dx, y + 1.20 * dy, ...
        sprintf('S%d', topology.sectors.sectorId(s)), ...
        'FontSize', 9, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none', ...
        'Color', color, 'BackgroundColor', 'w', 'Margin', 1);
end

halfArea = 1.95 * (cfg.ISD_m + cfg.plannedRadius_m);
xlim([-halfArea, halfArea]);
ylim([-halfArea, halfArea]);
xlabel('x position [m]');
ylabel('y position [m]');
title({'Simulated 7-site / 21-sector topology labels', ...
    'Sector azimuth slot at every site: first = 30 deg, second = 150 deg, third = 270 deg'});

subtitleText = ['Assign vendor KPI sites to positions first; sector orientation mapping comes next. ', ...
    'Outer labels are simulated positions, not real site names yet.'];
text(-0.96 * halfArea, -0.93 * halfArea, subtitleText, 'FontSize', 9, ...
    'Interpreter', 'none', 'BackgroundColor', 'w', 'Margin', 2);

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_topology_site_sector_labels.png'));
end

function labels = get_sim_site_labels(numSites)
base = {'CENTER', 'NORTH', 'NORTHEAST', 'SOUTHEAST', ...
    'SOUTH', 'SOUTHWEST', 'NORTHWEST'};
labels = base(1:min(numSites, numel(base)));
if numSites > numel(base)
    for i = numel(base)+1:numSites
        labels{i} = sprintf('SIM_SITE_%d', i); %#ok<AGROW>
    end
end
labels = labels(:);
end

function [ox, oy, ha] = label_offset_for_site(siteId, isd)
offset = 0.34 * isd;
switch siteId
    case 1
        ox = 0.22 * isd; oy = 0; ha = 'left';
    case 2
        ox = 0; oy = 0.80 * offset; ha = 'center';
    case 3
        ox = offset; oy = 0.45 * offset; ha = 'left';
    case 4
        ox = offset; oy = -0.45 * offset; ha = 'left';
    case 5
        ox = 0; oy = -0.80 * offset; ha = 'center';
    case 6
        ox = -offset; oy = -0.45 * offset; ha = 'right';
    case 7
        ox = -offset; oy = 0.45 * offset; ha = 'right';
    otherwise
        ox = offset; oy = offset; ha = 'left';
end
end
