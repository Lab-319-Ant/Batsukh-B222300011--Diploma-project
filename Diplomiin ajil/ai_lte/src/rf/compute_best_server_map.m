function map = compute_best_server_map(cfg, topology)
%COMPUTE_BEST_SERVER_MAP Compute deterministic grid RF maps for the topology.
%
% Shadowing is disabled for map generation so the saved RF maps show the
% topology-driven coverage shape rather than one random shadowing draw.

N = 220;
halfArea = cfg.area_m / 2;
x = linspace(-halfArea, halfArea, N);
y = linspace(-halfArea, halfArea, N);
[X, Y] = meshgrid(x, y);
pointsX = X(:);
pointsY = Y(:);

numP = numel(pointsX);
numSec = height(topology.sectors);
RSRP = zeros(numP, numSec);
RxTotal = zeros(numP, numSec);

for s = 1:numSec
    dx = pointsX - topology.sectors.x_m(s);
    dy = pointsY - topology.sectors.y_m(s);
    d2D = sqrt(dx.^2 + dy.^2);
    PL = calc_3gpp_uma_pathloss(cfg, d2D, false);
    G = calc_antenna_gain(cfg, topology.sectors.azimuth_deg(s), ...
        topology.sectors.electricalTilt_deg(s), dx, dy);

    refSignalPower_dBm = topology.sectors.refSignalPower_dBm(s) + get_sector_offset(topology.sectors, s, 'referencePowerOffset_dB');
    txPower_dBm = topology.sectors.txPower_dBm(s) + get_sector_offset(topology.sectors, s, 'txPowerOffset_dB');

    RSRP(:, s) = refSignalPower_dBm + G + cfg.ueAntennaGain_dBi ...
        - PL - cfg.cableLoss_dB - cfg.bodyLoss_dB;
    RxTotal(:, s) = txPower_dBm + G + cfg.ueAntennaGain_dBi ...
        - PL - cfg.cableLoss_dB - cfg.bodyLoss_dB;
end

[bestRSRP, bestSec] = max(RSRP, [], 2);
RxTotal_mW = 10 .^ (RxTotal ./ 10);
noise_dBm = cfg.thermalNoiseDensity_dBmHz + 10 * log10(cfg.bandwidth_MHz * 1e6) + cfg.noiseFigure_dB;
noise_mW = 10 .^ (noise_dBm ./ 10);

sinr_dB = zeros(numP, 1);
for p = 1:numP
    ss = bestSec(p);
    sig = RxTotal_mW(p, ss);
    interf = sum(RxTotal_mW(p, :)) - sig;
    sinr_dB(p) = 10 * log10(sig / (interf + noise_mW));
end

function offset_dB = get_sector_offset(sectors, rowIdx, varName)
if ismember(varName, sectors.Properties.VariableNames)
    offset_dB = sectors.(varName)(rowIdx);
else
    offset_dB = 0;
end
end

insidePlanned = is_inside_planned_union(pointsX, pointsY, topology.sites, cfg.plannedRadius_m);
rsrpCovered = bestRSRP >= cfg.minRSRP_dBm;
sinrOk = sinr_dB >= cfg.minSINR_dB;
attachedGrid = rsrpCovered & sinrOk;

map = struct();
map.x = x;
map.y = y;
map.X = X;
map.Y = Y;
map.bestSector = reshape(bestSec, size(X));
map.bestRSRP_dBm = reshape(bestRSRP, size(X));
map.bestSINR_dB = reshape(sinr_dB, size(X));
map.insidePlanned = reshape(insidePlanned, size(X));
map.attachedGrid = reshape(attachedGrid, size(X));
map.noise_dBm = noise_dBm;
map.studyCoverageRatio = mean(rsrpCovered & sinrOk);
map.studyRSRPCoverageRatio = mean(rsrpCovered);
map.studySINRThresholdRatio = mean(sinrOk);

if any(insidePlanned)
    map.plannedCoverageRatio = mean(attachedGrid(insidePlanned));
    map.plannedRSRPCoverageRatio = mean(rsrpCovered(insidePlanned));
    map.plannedSINRThresholdRatio = mean(sinrOk(insidePlanned));
else
    map.plannedCoverageRatio = NaN;
    map.plannedRSRPCoverageRatio = NaN;
    map.plannedSINRThresholdRatio = NaN;
end
end

function inside = is_inside_planned_union(x, y, sites, radius)
inside = false(size(x));
for i = 1:height(sites)
    d2 = (x - sites.x_m(i)).^2 + (y - sites.y_m(i)).^2;
    inside = inside | (d2 <= radius^2);
end
end
