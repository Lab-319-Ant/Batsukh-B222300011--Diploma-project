function [sectorFeatureTable, featureDictionary] = build_phase7_sector_tp_qp_feature_table(cfg, sectorTemporal)
%BUILD_PHASE7_SECTOR_TP_QP_FEATURE_TABLE Build sector-level lag features.
%
% Lags are computed within each scenario-sector sequence only. Scenario and
% sector identifiers are retained as metadata, not model inputs.

lagSteps = cfg.phase7LagSteps(:)';
horizon = cfg.phase7PredictionHorizonSteps;

baseInputFeatures = {'hour_of_day','sin_hour','cos_hour','attached_ue_count', ...
    'active_ue_count','mean_RSRP_dBm','median_RSRP_dBm','mean_SINR_dB', ...
    'median_SINR_dB','boundary_ue_ratio','handover_risk_score','attach_rate_sector'};
lagBaseFeatures = {'offered_traffic_Mbps','served_traffic_Mbps','sector_load_ratio', ...
    'qos_satisfaction_ratio','mean_UE_throughput_Mbps'};
targetColumns = {'next_offered_traffic_Mbps','next_sector_load_ratio', ...
    'next_qos_satisfaction_ratio','next_mean_UE_throughput_Mbps','next_served_traffic_Mbps'};

sectorTemporal = normalize_sector_temporal_columns(sectorTemporal);
scenarioNames = unique(sectorTemporal.scenario_name, 'stable');
sectorFeatureTable = table();
sampleId = 0;

for s = 1:numel(scenarioNames)
    scenarioName = scenarioNames{s};
    scenarioIdx = strcmp(sectorTemporal.scenario_name, scenarioName);
    sectorIds = unique(sectorTemporal.sector_id(scenarioIdx));
    for sec = sectorIds(:)'
        groupRows = sectorTemporal(scenarioIdx & sectorTemporal.sector_id == sec, :);
        groupRows = sortrows(groupRows, 'time_index');
        maxLag = max(lagSteps);
        for r = (maxLag + 1):(height(groupRows) - horizon)
            sampleId = sampleId + 1;
            current = groupRows(r, :);
            target = groupRows(r + horizon, :);

            row = table(sampleId, current.day_index, current.time_index, current.hour_of_day, ...
                current.scenario_name, current.realization_id, current.site_id, current.sector_id, ...
                current.sin_hour, current.cos_hour, ...
                'VariableNames', {'temporal_sample_id','day_id','time_step','hour_of_day', ...
                'scenario_name','realization_id','site_id','sector_id','sin_hour','cos_hour'});

            for i = 1:numel(baseInputFeatures)
                name = baseInputFeatures{i};
                if any(strcmp(name, {'hour_of_day','sin_hour','cos_hour'}))
                    continue;
                end
                row.(name) = current.(name);
            end

            for i = 1:numel(lagBaseFeatures)
                name = lagBaseFeatures{i};
                for lag = lagSteps
                    row.(sprintf('%s_lag%d', name, lag)) = groupRows.(name)(r - lag);
                end
            end

            row.next_offered_traffic_Mbps = target.offered_traffic_Mbps;
            row.next_sector_load_ratio = target.sector_load_ratio;
            row.next_qos_satisfaction_ratio = target.qos_satisfaction_ratio;
            row.next_mean_UE_throughput_Mbps = target.mean_UE_throughput_Mbps;
            row.next_served_traffic_Mbps = target.served_traffic_Mbps;

            sectorFeatureTable = [sectorFeatureTable; row]; %#ok<AGROW>
        end
    end
end

featureDictionary = build_sector_feature_dictionary(sectorFeatureTable, targetColumns);
end

function tbl = normalize_sector_temporal_columns(tbl)
tbl.realization_id = ones(height(tbl), 1);
tbl.sin_hour = tbl.sin_time_of_day;
tbl.cos_hour = tbl.cos_time_of_day;

inputNames = {'mean_RSRP_dBm','median_RSRP_dBm','mean_SINR_dB','median_SINR_dB', ...
    'qos_satisfaction_ratio','mean_UE_throughput_Mbps','offered_traffic_Mbps', ...
    'served_traffic_Mbps','sector_load_ratio','boundary_ue_ratio','handover_risk_score', ...
    'attach_rate_sector'};
for i = 1:numel(inputNames)
    name = inputNames{i};
    values = double(tbl.(name));
    replacement = 0;
    if strcmp(name, 'qos_satisfaction_ratio')
        replacement = 1;
    elseif contains(name, 'RSRP')
        replacement = -125;
    elseif contains(name, 'SINR')
        replacement = -20;
    end
    values(ismissing(values) | isinf(values)) = replacement;
    tbl.(name) = values;
end
end

function dictionary = build_sector_feature_dictionary(featureTable, targetColumns)
metadataColumns = {'temporal_sample_id','day_id','time_step','scenario_name', ...
    'realization_id','site_id','sector_id'};
forbiddenColumns = {'sector_status','impaired_sector_id','impaired_site_id', ...
    'impaired_sector_status','is_impaired_sector','referencePowerOffset_dB', ...
    'txPowerOffset_dB','outage_flag','degradation_flag','cod_label'};

rows = {};
vars = featureTable.Properties.VariableNames;
for i = 1:numel(vars)
    name = vars{i};
    if any(strcmp(name, metadataColumns))
        role = 'metadata';
        module = 'both';
        reason = 'Traceability metadata only; excluded from TP/QP input matrix.';
    elseif any(strcmp(name, targetColumns)) || startsWith(name, 'next_')
        role = 'target';
        module = 'both';
        reason = 'One-step-ahead prediction target; forbidden as input.';
    elseif any(strcmp(name, forbiddenColumns))
        role = 'forbidden_leakage';
        module = 'both';
        reason = 'Direct impairment/status metadata; forbidden as input.';
    elseif contains(name, 'traffic') || contains(name, 'load') || contains(name, 'throughput')
        role = 'input_feature_candidate';
        module = 'TP';
        reason = 'Lagged or current sector traffic/load feature candidate.';
    elseif contains(name, 'qos') || contains(name, 'SINR') || contains(name, 'RSRP')
        role = 'input_feature_candidate';
        module = 'QP';
        reason = 'Lagged or current RF/QoS feature candidate.';
    else
        role = 'input_feature_candidate';
        module = 'both';
        reason = 'Time, RF, or handover-risk feature candidate.';
    end
    rows(end+1, :) = {name, role, module, reason}; %#ok<AGROW>
end

dictionary = cell2table(rows, 'VariableNames', ...
    {'column_name','role','intended_module','reason'});
end
