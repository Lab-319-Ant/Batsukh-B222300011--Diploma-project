function out = replay_phase4_realization_on_topology(cfg, baseTopology, planRow)
%REPLAY_PHASE4_REALIZATION_ON_TOPOLOGY Reproduce one Phase 4 realization on a topology.
%
% Identical evaluation chain Phase 12D uses internally, exposed as a
% public helper so Phase 12E can re-run the same realization with the
% oracle's action substituted on a cloned topology. CIO bias is applied
% at association only - physical RSRP is never modified by CIO.

scenario = struct();
scenario.scenario_id = planRow.scenario_id;
scenario.scenario_name = planRow.scenario_name{1};
scenario.traffic_mode = planRow.traffic_mode{1};
scenario.impaired_sector_id = planRow.impaired_sector_id;
scenario.impaired_sector_status = planRow.impaired_sector_status{1};
scenario.referencePowerOffset_dB = planRow.referencePowerOffset_dB;
scenario.txPowerOffset_dB = planRow.txPowerOffset_dB;
scenario.enable_es_candidate_flag = planRow.enable_es_candidate_flag;
scenario.enable_handover_stress_metrics = planRow.enable_handover_stress_metrics;

[cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, baseTopology, scenario);

if scenario.enable_handover_stress_metrics
    cfgScenario.boundaryRiskThreshold_dB = cfg.handoverStressMarginRisk_dB;
else
    cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;
end

topologyScenario.sectors = inherit_phase12b_columns(topologyScenario.sectors, baseTopology.sectors);

rng(planRow.ue_seed);
baseUes = generate_ues(cfgScenario, topologyScenario);
if scenario.enable_handover_stress_metrics
    cfgScenario.handoverStressSeed = planRow.ue_seed + 7000;
    scenarioUes = generate_handover_stress_ues(cfgScenario, topologyScenario, baseUes);
else
    scenarioUes = baseUes;
end

rng(planRow.shadowing_seed);
rf = calc_rsrp_sinr(cfgScenario, topologyScenario, scenarioUes);

cioRow = reshape(double(topologyScenario.sectors.cio_dB), 1, []);
if any(cioRow ~= 0)
    rf = apply_cio_reassociation(cfgScenario, rf, cioRow);
end

rng(planRow.traffic_seed);
ueTraffic = assign_ue_traffic_demand(cfgScenario, scenarioUes, rf);
[ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgScenario, ueTraffic, rf, topologyScenario);
sectorKpiTable = compute_sector_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);

rfMap = struct();
rfMap.plannedCoverageRatio = mean(rf.isAttached);
rfMap.plannedRSRPCoverageRatio = mean(rf.bestRSRP_dBm >= cfg.minRSRP_dBm);
rfMap.plannedSINRThresholdRatio = mean(rf.bestSINR_dB >= cfg.minSINR_dB);
rfMap.studyCoverageRatio = NaN;
networkKpiTable = compute_network_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorKpiTable, rfMap);

out = struct();
out.topologyScenario = topologyScenario;
out.ues = scenarioUes;
out.rf = rf;
out.sectorKpiTable = sectorKpiTable;
out.networkKpiTable = networkKpiTable;
end

function newSectors = inherit_phase12b_columns(newSectors, refSectors)
cols = {'cio_dB','hom_offset_dB','ttt_offset_ms','is_sleeping'};
n = height(newSectors);
for k = 1:numel(cols)
    c = cols{k};
    if ~ismember(c, newSectors.Properties.VariableNames)
        if ismember(c, refSectors.Properties.VariableNames)
            newSectors.(c) = refSectors.(c);
        elseif strcmp(c, 'is_sleeping')
            newSectors.(c) = false(n, 1);
        else
            newSectors.(c) = zeros(n, 1);
        end
    elseif ismember(c, refSectors.Properties.VariableNames)
        newSectors.(c) = refSectors.(c);
    end
end
end

function rf = apply_cio_reassociation(cfg, rf, cioRow)
biasedMetric = rf.RSRP_dBm + cioRow;
[~, servingBiased] = max(biasedMetric, [], 2);
numUE = numel(servingBiased);

RxTotal_mW = 10 .^ (rf.RxTotal_dBm ./ 10);
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

servingRSRP_dBm = zeros(numUE, 1);
for u = 1:numUE
    servingRSRP_dBm(u) = rf.RSRP_dBm(u, servingBiased(u));
end

isAttached = servingRSRP_dBm >= cfg.minRSRP_dBm & bestSINR_dB >= cfg.minSINR_dB;
servingBiased(~isAttached) = 0;

secondBest_dBm = zeros(numUE, 1);
rsrpMat = rf.RSRP_dBm;
for u = 1:numUE
    row = rsrpMat(u, :);
    ss = max(servingBiased(u), 1);
    row(ss) = -Inf;
    secondBest_dBm(u) = max(row);
end

rf.bestRSRP_dBm = servingRSRP_dBm;
rf.secondBestRSRP_dBm = secondBest_dBm;
rf.rsrpGapBestSecond_dB = servingRSRP_dBm - secondBest_dBm;
rf.bestSINR_dB = bestSINR_dB;
rf.bestServer = servingBiased;
rf.servingSector = servingBiased;
rf.isAttached = isAttached;
rf.isBoundaryUE = isAttached & rf.rsrpGapBestSecond_dB < cfg.handoverMarginRisk_dB;
end
