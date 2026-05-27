function phase7 = generate_phase7_temporal_dataset(cfg, topology)
%GENERATE_PHASE7_TEMPORAL_DATASET Build time-indexed TP/QP datasets.
%
% Phase 7A creates temporal KPI tables only. It does not train TP/QP models
% and does not apply predicted values to future network states.

scenarioTypes = cfg.phase7ScenarioTypes;
numSteps = cfg.phase7TimeStepsPerDay * cfg.phase7NumDays;
sectorTemporal = table();
networkTemporal = table();

for s = 1:numel(scenarioTypes)
    scenario = make_phase7_scenario(cfg, s, scenarioTypes{s});
    [cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, topology, scenario);

    if scenario.enable_handover_stress_metrics
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverStressMarginRisk_dB;
    else
        cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;
    end

    rng(cfg.phase7BaseSeed + 1000 * s + 11);
    baseUes = generate_ues(cfgScenario, topologyScenario);
    if scenario.enable_handover_stress_metrics
        cfgScenario.handoverStressSeed = cfg.phase7BaseSeed + 1000 * s + 22;
        ues = generate_handover_stress_ues(cfgScenario, topologyScenario, baseUes);
    else
        ues = baseUes;
    end

    rng(cfg.phase7BaseSeed + 1000 * s + 33);
    rf = calc_rsrp_sinr(cfgScenario, topologyScenario, ues);
    boundaryMetrics = compute_phase7_boundary_metrics(cfgScenario, rf);

    for t = 1:numSteps
        timeInfo = phase7_time_info(cfg, s, scenario.scenario_name, scenario.traffic_mode, t);
        trafficCfg = apply_temporal_traffic_profile(cfgScenario, timeInfo);

        rng(cfg.phase7BaseSeed + 100000 * s + t);
        ueTraffic = assign_ue_traffic_demand(trafficCfg, ues, rf);
        [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(trafficCfg, ueTraffic, rf, topologyScenario);
        sectorKpiTable = compute_sector_kpis(trafficCfg, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);
        sectorKpiTable = add_phase7_sector_boundary_metrics(trafficCfg, rf, sectorKpiTable);

        sampleRfMap = struct();
        sampleRfMap.plannedCoverageRatio = mean(rf.isAttached);
        networkKpiTable = compute_network_kpis(trafficCfg, topologyScenario, ueTrafficResult, sectorKpiTable, sampleRfMap);
        networkKpiTable.mean_best_RSRP_dBm = mean(rf.bestRSRP_dBm, 'omitnan');
        networkKpiTable.mean_best_SINR_dB = mean(rf.bestSINR_dB(rf.isAttached), 'omitnan');
        networkKpiTable.boundary_ue_count = boundaryMetrics.boundary_ue_count;
        networkKpiTable.boundary_ue_ratio = boundaryMetrics.boundary_ue_ratio;
        networkKpiTable.handover_risk_score = boundaryMetrics.handover_risk_score;

        sectorTemporal = [sectorTemporal; add_time_columns_to_sector(timeInfo, sectorKpiTable)]; %#ok<AGROW>
        networkTemporal = [networkTemporal; add_time_columns_to_network(timeInfo, networkKpiTable)]; %#ok<AGROW>
    end
end

featureTable = build_phase7_tp_qp_feature_table(cfg, networkTemporal);
[sectorFeatureTable, sectorFeatureDictionary] = build_phase7_sector_tp_qp_feature_table(cfg, sectorTemporal);
validationTable = validate_phase7_temporal_dataset(cfg, sectorTemporal, networkTemporal, featureTable, sectorFeatureTable, sectorFeatureDictionary);
summaryTable = summarize_phase7_temporal_dataset(networkTemporal);
summaryTable.network_lag_feature_rows = repmat(height(featureTable), height(summaryTable), 1);
summaryTable.sector_lag_feature_rows = repmat(height(sectorFeatureTable), height(summaryTable), 1);

writetable(sectorTemporal, fullfile(cfg.tablesDir, 'phase7a_temporal_sector_dataset.csv'));
writetable(networkTemporal, fullfile(cfg.tablesDir, 'phase7a_temporal_network_dataset.csv'));
writetable(featureTable, fullfile(cfg.tablesDir, 'phase7a_tp_qp_feature_table.csv'));
writetable(sectorFeatureTable, fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_table.csv'));
writetable(sectorFeatureDictionary, fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_dictionary.csv'));
writetable(summaryTable, fullfile(cfg.tablesDir, 'phase7a_temporal_summary.csv'));
plot_phase7_temporal_summary(cfg, networkTemporal);

phase7 = struct();
phase7.sectorTemporal = sectorTemporal;
phase7.networkTemporal = networkTemporal;
phase7.featureTable = featureTable;
phase7.sectorFeatureTable = sectorFeatureTable;
phase7.sectorFeatureDictionary = sectorFeatureDictionary;
phase7.summaryTable = summaryTable;
phase7.validationTable = validationTable;
end

function scenario = make_phase7_scenario(cfg, id, scenarioName)
scenario = struct('scenario_id', id, 'scenario_name', scenarioName, 'traffic_mode', 'normal', ...
    'impaired_sector_id', 0, 'impaired_sector_status', 'normal', ...
    'referencePowerOffset_dB', 0, 'txPowerOffset_dB', 0, ...
    'enable_es_candidate_flag', false, 'enable_handover_stress_metrics', false);

switch scenarioName
    case 'normal'
        scenario.traffic_mode = 'normal';
    case 'low_load'
        scenario.traffic_mode = 'low_load';
    case 'overload'
        scenario.traffic_mode = 'overload';
    case 'handover_stress'
        scenario.traffic_mode = 'normal';
        scenario.enable_handover_stress_metrics = true;
    case 'mixed_conflict'
        scenario.traffic_mode = 'overload';
        scenario.impaired_sector_id = cfg.defaultImpairedSectorId;
        scenario.impaired_sector_status = 'degraded';
        scenario.referencePowerOffset_dB = cfg.degradedReferencePowerOffset_dB;
        scenario.txPowerOffset_dB = cfg.degradedTxPowerOffset_dB;
    otherwise
        error('Unsupported Phase 7 scenario type: %s', scenarioName);
end
end

function timeInfo = phase7_time_info(cfg, scenarioId, scenarioName, trafficMode, timeIndex)
stepInDay = mod(timeIndex - 1, cfg.phase7TimeStepsPerDay) + 1;
dayIndex = floor((timeIndex - 1) / cfg.phase7TimeStepsPerDay) + 1;
minuteOfDay = (stepInDay - 1) * cfg.phase7TimeStepMinutes;
hourOfDay = minuteOfDay / 60;
timeInfo = struct();
timeInfo.scenario_id = scenarioId;
timeInfo.scenario_name = scenarioName;
timeInfo.traffic_mode = trafficMode;
timeInfo.time_index = timeIndex;
timeInfo.day_index = dayIndex;
timeInfo.step_in_day = stepInDay;
timeInfo.minute_of_day = minuteOfDay;
timeInfo.hour_of_day = hourOfDay;
timeInfo.sin_time_of_day = sin(2 * pi * minuteOfDay / (24 * 60));
timeInfo.cos_time_of_day = cos(2 * pi * minuteOfDay / (24 * 60));
end

function trafficCfg = apply_temporal_traffic_profile(cfgScenario, timeInfo)
trafficCfg = cfgScenario;
profileMultiplier = 1;
if strcmpi(trafficCfg.phase7TrafficDailyProfile, 'diurnal')
    profileMultiplier = 1 + 0.45 * sin(2 * pi * (timeInfo.hour_of_day - 8) / 24);
end
noiseMultiplier = 1 + trafficCfg.phase7TrafficNoiseStd * randn();
trafficMultiplier = min(max(profileMultiplier * noiseMultiplier, 0.35), 1.75);

switch lower(trafficCfg.trafficMode)
    case 'low_load'
        trafficCfg.lowLoadActiveUserRatio = min(max(trafficCfg.lowLoadActiveUserRatio * trafficMultiplier, 0), 1);
        trafficCfg.lowLoadDemandRange_Mbps = max(0, trafficCfg.lowLoadDemandRange_Mbps * trafficMultiplier);
    case 'normal'
        trafficCfg.normalLoadActiveUserRatio = min(max(trafficCfg.normalLoadActiveUserRatio * trafficMultiplier, 0), 1);
        trafficCfg.normalLoadDemandRange_Mbps = max(0, trafficCfg.normalLoadDemandRange_Mbps * trafficMultiplier);
    case 'overload'
        trafficCfg.overloadActiveUserRatio = min(max(trafficCfg.overloadActiveUserRatio * trafficMultiplier, 0), 1);
        trafficCfg.overloadDemandRange_Mbps = max(0, trafficCfg.overloadDemandRange_Mbps * trafficMultiplier);
end
trafficCfg.temporalTrafficMultiplier = trafficMultiplier;
end

function metrics = compute_phase7_boundary_metrics(cfg, rf)
threshold = cfg.handoverMarginRisk_dB;
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold = cfg.boundaryRiskThreshold_dB;
end
boundaryFlag = rf.isAttached & rf.rsrpGapBestSecond_dB < threshold;
metrics.boundary_ue_count = sum(boundaryFlag);
metrics.boundary_ue_ratio = metrics.boundary_ue_count / max(sum(rf.isAttached), 1);
metrics.handover_risk_score = metrics.boundary_ue_ratio;
end

function sectorKpiTable = add_phase7_sector_boundary_metrics(cfg, rf, sectorKpiTable)
threshold = cfg.handoverMarginRisk_dB;
if isfield(cfg, 'boundaryRiskThreshold_dB')
    threshold = cfg.boundaryRiskThreshold_dB;
end
numSectors = height(sectorKpiTable);
boundary_ue_ratio = zeros(numSectors, 1);
handover_risk_score = zeros(numSectors, 1);
attach_rate_sector = zeros(numSectors, 1);
boundaryFlag = rf.isAttached & rf.rsrpGapBestSecond_dB < threshold;
for sec = 1:numSectors
    attachedIdx = rf.isAttached & rf.servingSector == sec;
    boundary_ue_ratio(sec) = sum(boundaryFlag & rf.servingSector == sec) / max(sum(attachedIdx), 1);
    handover_risk_score(sec) = boundary_ue_ratio(sec);
    attach_rate_sector(sec) = sum(attachedIdx) / max(sum(rf.bestServer == sec), 1);
end
sectorKpiTable.boundary_ue_ratio = boundary_ue_ratio;
sectorKpiTable.handover_risk_score = handover_risk_score;
sectorKpiTable.attach_rate_sector = attach_rate_sector;
end

function tbl = add_time_columns_to_sector(timeInfo, sectorKpiTable)
numRows = height(sectorKpiTable);
tbl = addvars(sectorKpiTable, repmat(timeInfo.scenario_id, numRows, 1), ...
    repmat({timeInfo.scenario_name}, numRows, 1), repmat({timeInfo.traffic_mode}, numRows, 1), ...
    repmat(timeInfo.time_index, numRows, 1), repmat(timeInfo.day_index, numRows, 1), ...
    repmat(timeInfo.step_in_day, numRows, 1), repmat(timeInfo.minute_of_day, numRows, 1), ...
    repmat(timeInfo.hour_of_day, numRows, 1), repmat(timeInfo.sin_time_of_day, numRows, 1), ...
    repmat(timeInfo.cos_time_of_day, numRows, 1), 'Before', 1, ...
    'NewVariableNames', {'scenario_id','scenario_name','traffic_mode','time_index', ...
    'day_index','step_in_day','minute_of_day','hour_of_day','sin_time_of_day','cos_time_of_day'});
end

function tbl = add_time_columns_to_network(timeInfo, networkKpiTable)
tbl = addvars(networkKpiTable, timeInfo.scenario_id, {timeInfo.scenario_name}, ...
    {timeInfo.traffic_mode}, timeInfo.time_index, timeInfo.day_index, timeInfo.step_in_day, ...
    timeInfo.minute_of_day, timeInfo.hour_of_day, timeInfo.sin_time_of_day, timeInfo.cos_time_of_day, ...
    'Before', 1, 'NewVariableNames', {'scenario_id','scenario_name','traffic_mode','time_index', ...
    'day_index','step_in_day','minute_of_day','hour_of_day','sin_time_of_day','cos_time_of_day'});
end
