function ues = generate_ues(cfg, topology)
%GENERATE_UES Generate UE coordinates for LTE RF validation.
%
% Important distinction:
%   cfg.area_m controls the study/plot window.
%   cfg.plannedRadius_m controls the intended per-site planned service area.
%   Multi-site service-area drops use the union of planned site circles.

numUE = cfg.numUE;
R = cfg.plannedRadius_m;

switch lower(cfg.ueDropMode)
    case 'service_area_uniform'
        if height(topology.sites) == 1
            [x, y] = uniform_points_in_circle(numUE, R);
            x = x + topology.sites.x_m(1);
            y = y + topology.sites.y_m(1);
        else
            [x, y] = uniform_points_in_planned_union(numUE, topology.sites, R);
        end

    case 'square_uniform'
        halfArea = cfg.area_m / 2;
        x = -halfArea + cfg.area_m * rand(numUE, 1);
        y = -halfArea + cfg.area_m * rand(numUE, 1);

    case 'mixed_radius'
        nOutside = round(cfg.outsideFraction * numUE);
        nInside = numUE - nOutside;

        if height(topology.sites) == 1
            [xIn, yIn] = uniform_points_in_circle(nInside, R);
            xIn = xIn + topology.sites.x_m(1);
            yIn = yIn + topology.sites.y_m(1);
        else
            [xIn, yIn] = uniform_points_in_planned_union(nInside, topology.sites, R);
        end

        [xOut, yOut] = uniform_points_outside_planned_union(nOutside, topology.sites, R, cfg.area_m);

        x = [xIn; xOut];
        y = [yIn; yOut];

    otherwise
        error('Unknown cfg.ueDropMode: %s', cfg.ueDropMode);
end

ueId = (1:numUE).';
ues = table(ueId, x, y, cfg.hUE_m * ones(numUE, 1), 'VariableNames', {'ueId','x_m','y_m','h_m'});
end

function [x, y] = uniform_points_in_circle(n, radius)
% Uniform spatial distribution in a disk.
theta = 2 * pi * rand(n, 1);
r = radius * sqrt(rand(n, 1));
x = r .* cos(theta);
y = r .* sin(theta);
end

function [x, y] = uniform_points_in_planned_union(n, sites, radius)
% Rejection sample uniformly over the union of planned coverage circles.
x = zeros(n, 1);
y = zeros(n, 1);
count = 0;

xMin = min(sites.x_m) - radius;
xMax = max(sites.x_m) + radius;
yMin = min(sites.y_m) - radius;
yMax = max(sites.y_m) + radius;

maxAttempts = max(10000, 200 * n);
attempts = 0;
while count < n && attempts < maxAttempts
    batchN = max(1000, 2 * (n - count));
    candX = xMin + (xMax - xMin) * rand(batchN, 1);
    candY = yMin + (yMax - yMin) * rand(batchN, 1);
    inside = is_inside_planned_union(candX, candY, sites, radius);
    keepX = candX(inside);
    keepY = candY(inside);
    nKeep = min(numel(keepX), n - count);
    if nKeep > 0
        idx = count + (1:nKeep);
        x(idx) = keepX(1:nKeep);
        y(idx) = keepY(1:nKeep);
        count = count + nKeep;
    end
    attempts = attempts + batchN;
end

if count < n
    error('Unable to generate enough UEs inside planned coverage union after %d attempts.', attempts);
end
end

function [x, y] = uniform_points_outside_planned_union(n, sites, radius, area_m)
% Rejection sample UEs in the study window but outside planned coverage.
x = zeros(n, 1);
y = zeros(n, 1);
count = 0;

halfArea = area_m / 2;
maxAttempts = max(10000, 300 * n);
attempts = 0;
while count < n && attempts < maxAttempts
    batchN = max(1000, 3 * (n - count));
    candX = -halfArea + area_m * rand(batchN, 1);
    candY = -halfArea + area_m * rand(batchN, 1);
    outside = ~is_inside_planned_union(candX, candY, sites, radius);
    keepX = candX(outside);
    keepY = candY(outside);
    nKeep = min(numel(keepX), n - count);
    if nKeep > 0
        idx = count + (1:nKeep);
        x(idx) = keepX(1:nKeep);
        y(idx) = keepY(1:nKeep);
        count = count + nKeep;
    end
    attempts = attempts + batchN;
end

if count < n
    error('Unable to generate enough UEs outside planned coverage union after %d attempts.', attempts);
end
end

function inside = is_inside_planned_union(x, y, sites, radius)
inside = false(size(x));
for i = 1:height(sites)
    d2 = (x - sites.x_m(i)).^2 + (y - sites.y_m(i)).^2;
    inside = inside | (d2 <= radius^2);
end
end
