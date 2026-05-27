function networkState = build_network_state_table(planRow, networkKpiTable, rf, boundaryMetrics, esCandidateCount)
%BUILD_NETWORK_STATE_TABLE Build one Phase 4 network-state row.

networkState = networkKpiTable;
networkState = addvars(networkState, ...
    planRow.dataset_id, planRow.scenario_id, planRow.realization_id, ...
    planRow.scenario_name, planRow.traffic_mode, planRow.impaired_sector_id, ...
    planRow.impaired_sector_status, planRow.ue_seed, planRow.shadowing_seed, planRow.traffic_seed, ...
    'Before', 1, ...
    'NewVariableNames', {'dataset_id','scenario_id','realization_id','scenario_name', ...
    'traffic_mode','impaired_sector_id','impaired_sector_status', ...
    'ue_seed','shadowing_seed','traffic_seed'});

networkState.mean_best_RSRP_dBm = mean(rf.bestRSRP_dBm, 'omitnan');
networkState.mean_best_SINR_dB = mean(rf.bestSINR_dB(rf.isAttached), 'omitnan');
networkState.boundary_ue_count = boundaryMetrics.boundary_ue_count;
networkState.boundary_ue_ratio = boundaryMetrics.boundary_ue_ratio;
networkState.handover_risk_score = boundaryMetrics.handover_risk_score;
networkState.es_candidate_sector_count = esCandidateCount;
networkState.outage_scenario_label = strcmp(planRow.scenario_name, 'outage_sector');
networkState.degraded_scenario_label = strcmp(planRow.scenario_name, 'degraded_sector');
networkState.overload_scenario_label = strcmp(planRow.scenario_name, 'overload') || strcmp(planRow.scenario_name, 'mixed_conflict');
networkState.handover_stress_label = strcmp(planRow.scenario_name, 'handover_stress');
networkState.energy_saving_candidate_label = strcmp(planRow.scenario_name, 'low_load_energy_saving_candidate');
end
