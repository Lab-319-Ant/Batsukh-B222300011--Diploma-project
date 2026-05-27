function out = recompute_kpis_after_action(cfg, topology, ues, ueTrafficSeedOffset)
%RECOMPUTE_KPIS_AFTER_ACTION One-step RF + KPI chain, CIO-aware.
%
% Inputs:
%   topology - sectors table must include cio_dB, referencePowerOffset_dB,
%              txPowerOffset_dB, electricalTilt_deg
%   ues      - UE table (ueId, x_m, y_m)
%   ueTrafficSeedOffset - optional; if nonempty, rng is set deterministically
%              from cfg.seed + offset so pre and post share the same traffic.
%
% Output (struct):
%   rf            - rf struct after CIO re-association
%   ueTraffic     - assigned traffic demand
%   ueTrafficResult, sectorCapacity_Mbps
%   sectorKpiTable, networkKpiTable
%
% This function does NOT mutate topology or ues.

if nargin >= 4 && ~isempty(ueTrafficSeedOffset)
    rngState = rng();
    cleanup = onCleanup(@() rng(rngState));
    rng(cfg.seed + ueTrafficSeedOffset);
end

% Step 1: physical RSRP/SINR via the standard RF engine. calc_rsrp_sinr
% already reads referencePowerOffset_dB, txPowerOffset_dB, and the
% (possibly updated) electricalTilt_deg from topology.sectors.
rf = calc_rsrp_sinr(cfg, topology, ues);

% Step 2: re-associate with CIO bias if any sector has nonzero cio_dB.
cioRow = reshape(double(topology.sectors.cio_dB), 1, []);
if any(cioRow ~= 0)
    rf = apply_cio_reassociation(cfg, rf, cioRow);
end

% Step 3: traffic & KPI engine.
ueTraffic = assign_ue_traffic_demand(cfg, ues, rf);
[ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfg, ueTraffic, rf, topology);
sectorKpiTable = compute_sector_kpis(cfg, topology, ueTrafficResult, sectorCapacity_Mbps);

% Minimal rfMap stub (compute_network_kpis only reads the four coverage
% fields). For Phase 12D we report sector- and network-level KPIs that
% don't depend on a precomputed coverage map.
rfMap = struct('plannedCoverageRatio', NaN, ...
    'plannedRSRPCoverageRatio', mean(rf.bestRSRP_dBm >= cfg.minRSRP_dBm), ...
    'plannedSINRThresholdRatio', mean(rf.bestSINR_dB >= cfg.minSINR_dB), ...
    'studyCoverageRatio', NaN);
networkKpiTable = compute_network_kpis(cfg, topology, ueTrafficResult, sectorKpiTable, rfMap);

out = struct();
out.rf = rf;
out.ueTraffic = ueTraffic;
out.ueTrafficResult = ueTrafficResult;
out.sectorCapacity_Mbps = sectorCapacity_Mbps;
out.sectorKpiTable = sectorKpiTable;
out.networkKpiTable = networkKpiTable;
end

function rf = apply_cio_reassociation(cfg, rf, cioRow)
% Re-associate using biased metric; recompute SINR using physical signal
% from the new serving sector. Physical RSRP matrix is NOT mutated.

biasedMetric = rf.RSRP_dBm + cioRow;
[~, servingBiased] = max(biasedMetric, [], 2);
numUE = numel(servingBiased);

RxTotal_dBm = rf.RxTotal_dBm;
RxTotal_mW = 10 .^ (RxTotal_dBm ./ 10);
noise_mW = 10 .^ (rf.noise_dBm ./ 10);

servingPower_mW = zeros(numUE, 1);
interference_mW = zeros(numUE, 1);
for u = 1:numUE
    ss = servingBiased(u);
    servingPower_mW(u) = RxTotal_mW(u, ss);
    interference_mW(u) = sum(RxTotal_mW(u, :)) - servingPower_mW(u);
end
sinrLinear = servingPower_mW ./ (interference_mW + noise_mW);
bestSINR_dB = 10 * log10(sinrLinear);

% Physical RSRP at the biased serving sector (this is the attach metric).
servingRSRP_dBm = zeros(numUE, 1);
for u = 1:numUE
    servingRSRP_dBm(u) = rf.RSRP_dBm(u, servingBiased(u));
end

isAttached = servingRSRP_dBm >= cfg.minRSRP_dBm & bestSINR_dB >= cfg.minSINR_dB;
servingBiased(~isAttached) = 0;

% Second-best for boundary indicator (still using physical RSRP, excluding
% the new serving sector).
secondBestRSRP_dBm = zeros(numUE, 1);
rsrpMat = rf.RSRP_dBm;
for u = 1:numUE
    row = rsrpMat(u, :);
    ss = max(servingBiased(u), 1);
    row(ss) = -Inf;
    secondBestRSRP_dBm(u) = max(row);
end
rsrpGap = servingRSRP_dBm - secondBestRSRP_dBm;

rf.bestRSRP_dBm = servingRSRP_dBm;
rf.secondBestRSRP_dBm = secondBestRSRP_dBm;
rf.rsrpGapBestSecond_dB = rsrpGap;
rf.bestSINR_dB = bestSINR_dB;
rf.bestServer = servingBiased;
rf.servingSector = servingBiased;
rf.isAttached = isAttached;
rf.isBoundaryUE = isAttached & rsrpGap < cfg.handoverMarginRisk_dB;
end
