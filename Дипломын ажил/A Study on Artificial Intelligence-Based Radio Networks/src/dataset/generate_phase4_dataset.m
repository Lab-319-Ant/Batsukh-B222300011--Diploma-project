function [sectorStateDataset, networkStateDataset, scenarioPlan] = generate_phase4_dataset(cfg, topology)
%GENERATE_PHASE4_DATASET Generate multi-scenario KPI datasets.
%
% Phase 4 creates reusable state tables only. It does not train ML, perform
% action selection, compute oracle regret, or run closed-loop control.

scenarioPlan = get_phase4_scenario_plan(cfg);
sectorStateDataset = table();
networkStateDataset = table();

for i = 1:height(scenarioPlan)
    planRow = scenarioPlan(i, :);
    scenario = plan_row_to_scenario(planRow);
    [cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, topology, scenario);

    if scenario.enable_handover_stress_metrics
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverStressMarginRisk_dB;
    else
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;
    end

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

    rng(planRow.traffic_seed);
    ueTraffic = assign_ue_traffic_demand(cfgScenario, scenarioUes, rf);
    [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgScenario, ueTraffic, rf, topologyScenario);
    sectorKpiTable = compute_sector_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);

    esCandidate = false(height(sectorKpiTable), 1);
    if scenario.enable_es_candidate_flag
        esCandidate = sectorKpiTable.sector_load_ratio < cfg.energySavingCandidateLoadThreshold;
    end
    sectorKpiTable.es_candidate = esCandidate;
    esCandidateCount = sum(esCandidate);
    sectorKpiTable = add_sector_boundary_metrics(cfgScenario, rf, sectorKpiTable);

    sampleRfMap = struct();
    sampleRfMap.plannedCoverageRatio = mean(rf.isAttached);
    networkKpiTable = compute_network_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorKpiTable, sampleRfMap);

    boundaryMetrics = compute_boundary_metrics(cfgScenario, rf);

    sectorState = build_sector_state_table(planRow, topologyScenario, sectorKpiTable);
    networkState = build_network_state_table(planRow, networkKpiTable, rf, boundaryMetrics, esCandidateCount);

    sectorStateDataset = [sectorStateDataset; sectorState]; %#ok<AGROW>
    networkStateDataset = [networkStateDataset; networkState]; %#ok<AGROW>
end
end

function scenario = plan_row_to_scenario(planRow)
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
end

function metrics = compute_boundary_metrics(cfg, rf)
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold_dB = cfg.boundaryRiskThreshold_dB;
else
    threshold_dB = cfg.handoverMarginRisk_dB;
end

boundaryFlag = rf.isAttached & rf.rsrpGapBestSecond_dB < threshold_dB;
metrics = struct();
metrics.boundary_ue_count = sum(boundaryFlag);
metrics.boundary_ue_ratio = metrics.boundary_ue_count / max(sum(rf.isAttached), 1);
metrics.handover_risk_score = metrics.boundary_ue_ratio;
end

function sectorKpiTable = add_sector_boundary_metrics(cfg, rf, sectorKpiTable)
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold_dB = cfg.boundaryRiskThreshold_dB;
else
    threshold_dB = cfg.handoverMarginRisk_dB;
end

numSectors = height(sectorKpiTable);
boundary_ue_count = zeros(numSectors, 1);
boundary_ue_ratio = zeros(numSectors, 1);
handover_risk_score = zeros(numSectors, 1);
attach_rate_sector = zeros(numSectors, 1);

boundaryFlag = rf.isAttached & rf.rsrpGapBestSecond_dB < threshold_dB;
for s = 1:numSectors
    attachedIdx = rf.isAttached & rf.servingSector == s;
    attachedCount = sum(attachedIdx);
    boundary_ue_count(s) = sum(boundaryFlag & rf.servingSector == s);
    boundary_ue_ratio(s) = boundary_ue_count(s) / max(attachedCount, 1);
    handover_risk_score(s) = boundary_ue_ratio(s);

    % Sector-local RF attachment proxy. The denominator is all UEs whose
    % best server is this sector before thresholding, so unattached edge UEs
    % are included in the sector-level RF availability estimate.
    bestServerIdx = rf.bestServer == s;
    attach_rate_sector(s) = attachedCount / max(sum(bestServerIdx), 1);
end

sectorKpiTable.boundary_ue_count = boundary_ue_count;
sectorKpiTable.boundary_ue_ratio = boundary_ue_ratio;
sectorKpiTable.handover_risk_score = handover_risk_score;
sectorKpiTable.attach_rate_sector = attach_rate_sector;
end
