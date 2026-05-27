function [clusterSummary, scenarioCrosstab, triggerSupport] = summarize_cluster_states(assignments)
%SUMMARIZE_CLUSTER_STATES Build interpretation tables for Phase 5 clusters.

clusterIds = unique(assignments.cluster_id);
numRows = height(assignments);
rows = {};
triggerRows = {};

for i = 1:numel(clusterIds)
    clusterId = clusterIds(i);
    idx = assignments.cluster_id == clusterId;
    rowCount = sum(idx);
    meanLoad = mean(assignments.sector_load_ratio(idx), 'omitnan');
    meanRsrp = mean(assignments.mean_RSRP_dBm(idx), 'omitnan');
    meanSinr = mean(assignments.mean_SINR_dB(idx), 'omitnan');
    meanThroughput = mean(assignments.mean_UE_throughput_Mbps(idx), 'omitnan');
    meanQos = mean(assignments.qos_satisfaction_ratio(idx), 'omitnan');
    meanBoundary = mean(assignments.boundary_ue_ratio(idx), 'omitnan');
    meanHoRisk = mean(assignments.handover_risk_score(idx), 'omitnan');
    meanAttach = mean(assignments.attach_rate_sector(idx), 'omitnan');
    dominantScenario = dominant_value(assignments.scenario_name(idx));
    dominantTraffic = dominant_value(assignments.traffic_mode(idx));
    suggestedState = suggest_state_name(meanLoad, meanRsrp, meanQos, meanHoRisk, meanAttach);
    triggerCandidate = suggest_trigger_candidate(meanLoad, meanRsrp, meanQos, meanHoRisk, meanAttach);

    rows(end+1, :) = {clusterId, rowCount, rowCount / max(numRows, 1), ...
        meanLoad, meanRsrp, meanSinr, meanThroughput, meanQos, meanBoundary, ...
        meanHoRisk, meanAttach, dominantScenario, dominantTraffic, suggestedState}; %#ok<AGROW>
    triggerRows(end+1, :) = {clusterId, suggestedState, triggerCandidate, ...
        sprintf('load=%.3f, RSRP=%.2f dBm, QoS=%.3f, HO risk=%.3f, attach=%.3f', ...
        meanLoad, meanRsrp, meanQos, meanHoRisk, meanAttach)}; %#ok<AGROW>
end

clusterSummary = cell2table(rows, 'VariableNames', {'cluster_id','row_count', ...
    'row_fraction','mean_sector_load','mean_RSRP_dBm','mean_SINR_dB', ...
    'mean_throughput_Mbps','mean_qos_satisfaction_ratio','mean_boundary_ue_ratio', ...
    'mean_handover_risk_score','mean_attach_rate_sector','dominant_scenario_name', ...
    'dominant_traffic_mode','suggested_state_name'});

triggerSupport = cell2table(triggerRows, 'VariableNames', ...
    {'cluster_id','suggested_state_name','trigger_candidate','rule_basis'});

scenarioCrosstab = build_scenario_crosstab(assignments, clusterIds);
end

function value = dominant_value(values)
values = string(values);
uniqueValues = unique(values, 'stable');
counts = zeros(numel(uniqueValues), 1);
for i = 1:numel(uniqueValues)
    counts(i) = sum(values == uniqueValues(i));
end
[~, maxIdx] = max(counts);
value = char(uniqueValues(maxIdx));
end

function stateName = suggest_state_name(meanLoad, meanRsrp, meanQos, meanHoRisk, meanAttach)
if meanLoad > 0.8
    stateName = 'overloaded';
elseif meanHoRisk > 0.22
    stateName = 'handover_risk';
elseif meanLoad < 0.10 && meanQos > 0.70
    stateName = 'low_load_good_rf';
elseif meanRsrp < -95 || meanAttach < 0.90
    stateName = 'weak_rf_or_impaired';
elseif meanQos < 0.80
    stateName = 'mixed_degraded';
else
    stateName = 'normal_good_rf';
end
end

function triggerCandidate = suggest_trigger_candidate(meanLoad, meanRsrp, meanQos, meanHoRisk, meanAttach)
triggers = {};
if meanLoad > 0.8
    triggers{end+1} = 'LB/MLB'; %#ok<AGROW>
end
if meanRsrp < -95 || meanAttach < 0.90
    triggers{end+1} = 'COC/OH or COD review'; %#ok<AGROW>
end
if meanQos < 0.80
    triggers{end+1} = 'QP/QoS review'; %#ok<AGROW>
end
if meanHoRisk > 0.22
    triggers{end+1} = 'HO/MRO'; %#ok<AGROW>
end
if meanLoad < 0.10 && meanQos > 0.70
    triggers{end+1} = 'ES candidate'; %#ok<AGROW>
end
if isempty(triggers)
    triggers{1} = 'no_action_monitoring';
end
triggerCandidate = strjoin(triggers, '; ');
end

function crosstabTable = build_scenario_crosstab(assignments, clusterIds)
scenarioNames = unique(string(assignments.scenario_name), 'stable');
rows = table(cellstr(scenarioNames), 'VariableNames', {'scenario_name'});

for i = 1:numel(clusterIds)
    clusterId = clusterIds(i);
    countValues = zeros(numel(scenarioNames), 1);
    fractionValues = zeros(numel(scenarioNames), 1);
    for s = 1:numel(scenarioNames)
        scenarioIdx = string(assignments.scenario_name) == scenarioNames(s);
        countValues(s) = sum(scenarioIdx & assignments.cluster_id == clusterId);
        fractionValues(s) = countValues(s) / max(sum(scenarioIdx), 1);
    end
    rows.(sprintf('cluster_%d_count', clusterId)) = countValues;
    rows.(sprintf('cluster_%d_fraction', clusterId)) = fractionValues;
end

crosstabTable = rows;
end
