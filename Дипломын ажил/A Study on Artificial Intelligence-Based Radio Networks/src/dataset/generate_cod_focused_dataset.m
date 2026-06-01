function codFocusedRows = generate_cod_focused_dataset(cfg, topology)
%GENERATE_COD_FOCUSED_DATASET Generate impaired-sector rows for COD balancing.
%
% This function reuses the existing RF/KPI scenario engine. It generates
% sector rows only for the impaired sector in degraded and outage scenarios.

inputFeatures = get_cod_input_features();
metadataColumns = {'realization_id','scenario_name','site_id','sector_id','impaired_sector_id'};
codFocusedRows = table();

scenarioSpecs = { ...
    'degraded_sector', 'degraded', cfg.degradedReferencePowerOffset_dB, cfg.degradedTxPowerOffset_dB; ...
    'outage_sector', 'outage', cfg.outageReferencePowerOffset_dB, cfg.outageTxPowerOffset_dB};

numPerClass = cfg.phase6NumCODRealizationsPerClass;
impairedSectorIds = cfg.phase6CODImpairedSectorIds(:);

for c = 1:size(scenarioSpecs, 1)
    scenarioName = scenarioSpecs{c, 1};
    sectorStatus = scenarioSpecs{c, 2};
    refOffset = scenarioSpecs{c, 3};
    txOffset = scenarioSpecs{c, 4};

    for r = 1:numPerClass
        impairedSectorId = impairedSectorIds(mod(r - 1, numel(impairedSectorIds)) + 1);
        realizationId = cfg.phase6CODBaseSeed + c * 10000 + r;

        scenario = struct();
        scenario.scenario_id = 600 + c;
        scenario.scenario_name = scenarioName;
        scenario.traffic_mode = 'normal';
        scenario.impaired_sector_id = impairedSectorId;
        scenario.impaired_sector_status = sectorStatus;
        scenario.referencePowerOffset_dB = refOffset;
        scenario.txPowerOffset_dB = txOffset;
        scenario.enable_es_candidate_flag = false;
        scenario.enable_handover_stress_metrics = false;

        [cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, topology, scenario);
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;

        rng(realizationId + 101);
        ues = generate_ues(cfgScenario, topologyScenario);
        rng(realizationId + 202);
        rf = calc_rsrp_sinr(cfgScenario, topologyScenario, ues);
        rng(realizationId + 303);
        ueTraffic = assign_ue_traffic_demand(cfgScenario, ues, rf);
        [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgScenario, ueTraffic, rf, topologyScenario);
        sectorKpiTable = compute_sector_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);
        sectorKpiTable = add_cod_boundary_metrics(cfgScenario, rf, sectorKpiTable);
        sectorKpiTable = impute_cod_features(sectorKpiTable, inputFeatures);

        rowIdx = sectorKpiTable.sector_id == impairedSectorId;
        row = sectorKpiTable(rowIdx, inputFeatures);
        row = addvars(row, realizationId, {scenarioName}, ...
            topologyScenario.sectors.siteId(rowIdx), impairedSectorId, impairedSectorId, ...
            'Before', 1, 'NewVariableNames', metadataColumns);
        row.cod_label = categorical({sectorStatus}, {'normal','degraded','outage'});

        codFocusedRows = [codFocusedRows; row]; %#ok<AGROW>
    end
end
end

function inputFeatures = get_cod_input_features()
featureSets = define_feature_sets();
inputFeatures = featureSets.cod.inputs;
end

function sectorKpiTable = add_cod_boundary_metrics(cfg, rf, sectorKpiTable)
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold_dB = cfg.boundaryRiskThreshold_dB;
else
    threshold_dB = cfg.handoverMarginRisk_dB;
end

numSectors = height(sectorKpiTable);
boundary_ue_ratio = zeros(numSectors, 1);
handover_risk_score = zeros(numSectors, 1);
attach_rate_sector = zeros(numSectors, 1);
boundaryFlag = rf.isAttached & rf.rsrpGapBestSecond_dB < threshold_dB;

for s = 1:numSectors
    attachedIdx = rf.isAttached & rf.servingSector == s;
    attachedCount = sum(attachedIdx);
    boundary_ue_ratio(s) = sum(boundaryFlag & rf.servingSector == s) / max(attachedCount, 1);
    handover_risk_score(s) = boundary_ue_ratio(s);
    bestServerIdx = rf.bestServer == s;
    attach_rate_sector(s) = attachedCount / max(sum(bestServerIdx), 1);
end

sectorKpiTable.boundary_ue_ratio = boundary_ue_ratio;
sectorKpiTable.handover_risk_score = handover_risk_score;
sectorKpiTable.attach_rate_sector = attach_rate_sector;
end

function tbl = impute_cod_features(tbl, inputFeatures)
for i = 1:numel(inputFeatures)
    name = inputFeatures{i};
    values = tbl.(name);
    replacement = 0;
    if strcmp(name, 'qos_satisfaction_ratio')
        replacement = 1;
    elseif contains(name, 'RSRP')
        replacement = -125;
    elseif contains(name, 'SINR')
        replacement = -20;
    end
    values = double(values);
    values(ismissing(values) | isinf(values)) = replacement;
    tbl.(name) = values;
end
end
