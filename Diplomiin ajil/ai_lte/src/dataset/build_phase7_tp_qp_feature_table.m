function featureTable = build_phase7_tp_qp_feature_table(cfg, networkTemporal)
%BUILD_PHASE7_TP_QP_FEATURE_TABLE Add lag inputs and future targets.

lagSteps = cfg.phase7LagSteps(:)';
horizon = cfg.phase7PredictionHorizonSteps;
baseFeatures = {'active_ues','total_offered_traffic_Mbps','total_served_traffic_Mbps', ...
    'total_unserved_traffic_Mbps','overloaded_sector_count','mean_sector_load', ...
    'max_sector_load','qos_satisfaction_ratio','mean_ue_throughput_Mbps', ...
    'mean_best_RSRP_dBm','mean_best_SINR_dB','coverage_ratio', ...
    'boundary_ue_ratio','handover_risk_score'};

featureTable = table();
scenarioNames = unique(networkTemporal.scenario_name, 'stable');
for s = 1:numel(scenarioNames)
    scenarioRows = networkTemporal(strcmp(networkTemporal.scenario_name, scenarioNames{s}), :);
    scenarioRows = sortrows(scenarioRows, 'time_index');
    maxLag = max(lagSteps);
    for r = (maxLag + 1):(height(scenarioRows) - horizon)
        row = scenarioRows(r, {'scenario_id','scenario_name','traffic_mode','time_index', ...
            'day_index','step_in_day','minute_of_day','hour_of_day','sin_time_of_day','cos_time_of_day'});
        for f = 1:numel(baseFeatures)
            name = baseFeatures{f};
            row.(name) = scenarioRows.(name)(r);
            for lag = lagSteps
                row.(sprintf('%s_lag%d', name, lag)) = scenarioRows.(name)(r - lag);
            end
        end
        targetRow = scenarioRows(r + horizon, :);
        row.target_next_total_offered_traffic_Mbps = targetRow.total_offered_traffic_Mbps;
        row.target_next_total_served_traffic_Mbps = targetRow.total_served_traffic_Mbps;
        row.target_next_mean_sector_load = targetRow.mean_sector_load;
        row.target_next_qos_satisfaction_ratio = targetRow.qos_satisfaction_ratio;
        row.target_next_mean_ue_throughput_Mbps = targetRow.mean_ue_throughput_Mbps;
        featureTable = [featureTable; row]; %#ok<AGROW>
    end
end
end
