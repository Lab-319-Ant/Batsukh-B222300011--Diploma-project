function [scenarioSummary, sectorKpisByScenario, networkKpisByScenario, ueResultsByScenario] = run_phase3_scenarios(cfg, topology, ues)
%RUN_PHASE3_SCENARIOS Run synthetic LTE scenarios over one common topology.
%
% This phase generates labeled simulation data. It does not train ML, select
% SON actions, compute oracle regret, or run closed-loop control.

scenarios = generate_scenario_config(cfg);

scenarioSummary = table();
sectorKpisByScenario = table();
networkKpisByScenario = table();
ueResultsByScenario = table();

for i = 1:numel(scenarios)
    scenario = scenarios(i);
    [cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, topology, scenario);

    scenarioUes = ues;
    if scenario.enable_handover_stress_metrics
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverStressMarginRisk_dB;
        scenarioUes = generate_handover_stress_ues(cfgScenario, topologyScenario, ues);
    else
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;
    end

    % Use the same shadowing draw across scenarios so KPI changes come from
    % scenario settings rather than random RF variation.
    rng(cfg.seed + 5000);
    rfScenario = calc_rsrp_sinr(cfgScenario, topologyScenario, scenarioUes);
    rfMapScenario = compute_best_server_map(cfgScenario, topologyScenario);

    rng(get_traffic_seed(cfg, scenario.traffic_mode));
    ueTraffic = assign_ue_traffic_demand(cfgScenario, scenarioUes, rfScenario);
    [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgScenario, ueTraffic, rfScenario, topologyScenario);
    sectorKpiTable = compute_sector_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);
    networkKpiTable = compute_network_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorKpiTable, rfMapScenario);

    [boundary_ue_count, boundary_ue_ratio, handover_risk_score, boundaryFlag] = ...
        compute_handover_boundary_metrics(cfgScenario, rfScenario);

    esCandidate = false(height(sectorKpiTable), 1);
    if scenario.enable_es_candidate_flag
        esCandidate = sectorKpiTable.sector_load_ratio < cfg.energySavingCandidateLoadThreshold;
    end
    sectorKpiTable.es_candidate = esCandidate;
    es_candidate_sector_count = sum(esCandidate);

    impairedSiteId = 0;
    if scenario.impaired_sector_id > 0
        idx = topologyScenario.sectors.sectorId == scenario.impaired_sector_id;
        impairedSiteId = topologyScenario.sectors.siteId(idx);
    end

    summaryRow = make_summary_row(cfgScenario, scenario, topologyScenario, ...
        networkKpiTable, rfScenario, rfMapScenario, impairedSiteId, ...
        boundary_ue_count, boundary_ue_ratio, handover_risk_score, ...
        es_candidate_sector_count);
    scenarioSummary = [scenarioSummary; summaryRow]; %#ok<AGROW>

    sectorKpiTable = addvars(sectorKpiTable, ...
        repmat(scenario.scenario_id, height(sectorKpiTable), 1), ...
        repmat({scenario.scenario_name}, height(sectorKpiTable), 1), ...
        'Before', 1, 'NewVariableNames', {'scenario_id','scenario_name'});
    sectorKpisByScenario = [sectorKpisByScenario; sectorKpiTable]; %#ok<AGROW>

    networkKpiTable = addvars(networkKpiTable, ...
        scenario.scenario_id, {scenario.scenario_name}, {scenario.traffic_mode}, ...
        'Before', 1, 'NewVariableNames', {'scenario_id','scenario_name','traffic_mode'});
    networkKpisByScenario = [networkKpisByScenario; networkKpiTable]; %#ok<AGROW>

    secondBestRSRP_dBm = compute_second_best_rsrp(rfScenario.RSRP_dBm);
    ueResults = addvars(ueTrafficResult, ...
        repmat(scenario.scenario_id, height(ueTrafficResult), 1), ...
        repmat({scenario.scenario_name}, height(ueTrafficResult), 1), ...
        secondBestRSRP_dBm, rfScenario.bestRSRP_dBm - secondBestRSRP_dBm, boundaryFlag, ...
        'Before', 1, ...
        'NewVariableNames', {'scenario_id','scenario_name','secondBestRSRP_dBm','bestSecondRSRPDiff_dB','isBoundaryUE'});
    ueResultsByScenario = [ueResultsByScenario; ueResults]; %#ok<AGROW>
end
end

function seed = get_traffic_seed(cfg, trafficMode)
switch lower(trafficMode)
    case 'low_load'
        seed = cfg.seed + 2001;
    case 'normal'
        seed = cfg.seed + 2000;
    case 'overload'
        seed = cfg.seed + 2003;
    case 'heavy_overload'
        seed = cfg.seed + 2004;
    otherwise
        seed = cfg.seed + 2099;
end
end

function [boundaryCount, boundaryRatio, riskScore, boundaryFlag] = compute_handover_boundary_metrics(cfg, rf)
secondBestRSRP = compute_second_best_rsrp(rf.RSRP_dBm);
rsrpGap = rf.bestRSRP_dBm - secondBestRSRP;
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold_dB = cfg.boundaryRiskThreshold_dB;
else
    threshold_dB = cfg.handoverMarginRisk_dB;
end
boundaryFlag = rf.isAttached & rsrpGap < threshold_dB;
boundaryCount = sum(boundaryFlag);
attachedCount = sum(rf.isAttached);
boundaryRatio = boundaryCount / max(attachedCount, 1);
riskScore = boundaryRatio;
end

function secondBestRSRP = compute_second_best_rsrp(RSRP_dBm)
sortedRSRP = sort(RSRP_dBm, 2, 'descend');
if size(sortedRSRP, 2) < 2
    secondBestRSRP = nan(size(sortedRSRP, 1), 1);
else
    secondBestRSRP = sortedRSRP(:, 2);
end
end

function summaryRow = make_summary_row(cfgScenario, scenario, topologyScenario, networkKpiTable, rfScenario, rfMapScenario, impairedSiteId, boundaryCount, boundaryRatio, riskScore, esCandidateCount)
scenario_id = scenario.scenario_id;
scenario_name = {scenario.scenario_name};
traffic_mode = {scenario.traffic_mode};
impaired_sector_id = scenario.impaired_sector_id;
impaired_site_id = impairedSiteId;
impaired_sector_status = {scenario.impaired_sector_status};

num_sites = networkKpiTable.num_sites;
num_sectors = networkKpiTable.num_sectors;
num_ues = networkKpiTable.num_ues;
attached_ues = networkKpiTable.attached_ues;
unattached_ues = networkKpiTable.unattached_ues;
attach_rate = networkKpiTable.attach_rate;
active_ues = networkKpiTable.active_ues;
total_offered_traffic_Mbps = networkKpiTable.total_offered_traffic_Mbps;
total_served_traffic_Mbps = networkKpiTable.total_served_traffic_Mbps;
total_unserved_traffic_Mbps = networkKpiTable.total_unserved_traffic_Mbps;
qos_satisfaction_ratio_active = networkKpiTable.qos_satisfaction_ratio;
overloaded_sector_count = networkKpiTable.overloaded_sector_count;
mean_sector_load = networkKpiTable.mean_sector_load;
max_sector_load = networkKpiTable.max_sector_load;
mean_best_RSRP_dBm = mean(rfScenario.bestRSRP_dBm, 'omitnan');
mean_best_SINR_dB = mean(rfScenario.bestSINR_dB(rfScenario.isAttached), 'omitnan');
coverage_ratio = rfMapScenario.plannedCoverageRatio;
boundary_ue_count = boundaryCount;
boundary_ue_ratio = boundaryRatio;
handover_risk_score = riskScore;
es_candidate_sector_count = esCandidateCount;

summaryRow = table(scenario_id, scenario_name, traffic_mode, impaired_sector_id, ...
    impaired_site_id, impaired_sector_status, num_sites, num_sectors, num_ues, ...
    attached_ues, unattached_ues, attach_rate, active_ues, ...
    total_offered_traffic_Mbps, total_served_traffic_Mbps, total_unserved_traffic_Mbps, ...
    qos_satisfaction_ratio_active, overloaded_sector_count, mean_sector_load, max_sector_load, ...
    mean_best_RSRP_dBm, mean_best_SINR_dB, coverage_ratio, ...
    boundary_ue_count, boundary_ue_ratio, handover_risk_score, es_candidate_sector_count);

% cfgScenario and topologyScenario are intentionally unused in this summary
% helper today; keeping the arguments documents the scenario context.
unused = {cfgScenario, topologyScenario}; %#ok<NASGU>
end
