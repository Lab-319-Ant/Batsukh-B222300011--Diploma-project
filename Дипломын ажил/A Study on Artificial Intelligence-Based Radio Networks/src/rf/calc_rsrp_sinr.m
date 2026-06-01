function rf = calc_rsrp_sinr(cfg, topology, ues)
%CALC_RSRP_SINR Compute RSRP, full-band SINR, association, and attach status.
%
% RSRP:
%   P_RS + antenna_gain - path_loss - losses
%
% SINR:
%   serving total received power / (sum other sector received powers + noise)
%
% The same-site two non-serving sectors are included as interference.

numUE = height(ues);
numSec = height(topology.sectors);

RSRP_dBm = zeros(numUE, numSec);
RxTotal_dBm = zeros(numUE, numSec);
pathloss_dB = zeros(numUE, numSec);
antGain_dBi = zeros(numUE, numSec);

for s = 1:numSec
    sx = topology.sectors.x_m(s);
    sy = topology.sectors.y_m(s);
    dx = ues.x_m - sx;
    dy = ues.y_m - sy;
    d2D = sqrt(dx.^2 + dy.^2);

    PL = calc_3gpp_uma_pathloss(cfg, d2D, cfg.shadowingEnabled);
    G = calc_antenna_gain(cfg, topology.sectors.azimuth_deg(s), ...
        topology.sectors.electricalTilt_deg(s), dx, dy);

    pathloss_dB(:, s) = PL;
    antGain_dBi(:, s) = G;

    refSignalPower_dBm = topology.sectors.refSignalPower_dBm(s) + get_sector_offset(topology.sectors, s, 'referencePowerOffset_dB');
    txPower_dBm = topology.sectors.txPower_dBm(s) + get_sector_offset(topology.sectors, s, 'txPowerOffset_dB');

    RSRP_dBm(:, s) = refSignalPower_dBm + G + cfg.ueAntennaGain_dBi ...
        - PL - cfg.cableLoss_dB - cfg.bodyLoss_dB;

    RxTotal_dBm(:, s) = txPower_dBm + G + cfg.ueAntennaGain_dBi ...
        - PL - cfg.cableLoss_dB - cfg.bodyLoss_dB;
end

[bestRSRP_dBm, servingSector] = max(RSRP_dBm, [], 2);
bestServer = servingSector;
secondBestRSRP_dBm = compute_second_best_rsrp(RSRP_dBm);
rsrpGapBestSecond_dB = bestRSRP_dBm - secondBestRSRP_dBm;

RxTotal_mW = dbm_to_mw(RxTotal_dBm);
noise_dBm = cfg.thermalNoiseDensity_dBmHz + 10 * log10(cfg.bandwidth_MHz * 1e6) + cfg.noiseFigure_dB;
noise_mW = dbm_to_mw(noise_dBm);

servingPower_mW = zeros(numUE, 1);
interference_mW = zeros(numUE, 1);
for u = 1:numUE
    ss = servingSector(u);
    servingPower_mW(u) = RxTotal_mW(u, ss);
    interference_mW(u) = sum(RxTotal_mW(u, :)) - servingPower_mW(u);
end

SINR_linear = servingPower_mW ./ (interference_mW + noise_mW);
bestSINR_dB = 10 * log10(SINR_linear);

isAttached = bestRSRP_dBm >= cfg.minRSRP_dBm & bestSINR_dB >= cfg.minSINR_dB;
servingSector(~isAttached) = 0;

rf = struct();
rf.RSRP_dBm = RSRP_dBm;
rf.RxTotal_dBm = RxTotal_dBm;
rf.pathloss_dB = pathloss_dB;
rf.antGain_dBi = antGain_dBi;
rf.bestRSRP_dBm = bestRSRP_dBm;
rf.secondBestRSRP_dBm = secondBestRSRP_dBm;
rf.rsrpGapBestSecond_dB = rsrpGapBestSecond_dB;
rf.bestSINR_dB = bestSINR_dB;
rf.bestServer = bestServer;
rf.servingSector = servingSector;
rf.isAttached = isAttached;
rf.isBoundaryUE = isAttached & rsrpGapBestSecond_dB < cfg.handoverMarginRisk_dB;
rf.noise_dBm = noise_dBm;
end

function mw = dbm_to_mw(dbm)
mw = 10 .^ (dbm ./ 10);
end

function offset_dB = get_sector_offset(sectors, rowIdx, varName)
if ismember(varName, sectors.Properties.VariableNames)
    offset_dB = sectors.(varName)(rowIdx);
else
    offset_dB = 0;
end
end

function secondBestRSRP = compute_second_best_rsrp(RSRP_dBm)
sortedRSRP = sort(RSRP_dBm, 2, 'descend');
if size(sortedRSRP, 2) < 2
    secondBestRSRP = nan(size(sortedRSRP, 1), 1);
else
    secondBestRSRP = sortedRSRP(:, 2);
end
end
