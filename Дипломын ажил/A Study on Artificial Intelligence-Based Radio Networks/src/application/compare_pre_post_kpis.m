function summary = compare_pre_post_kpis(preState, postState)
%COMPARE_PRE_POST_KPIS Compute group-level delta KPIs from pre and post state structs.
%
% Inputs are the result structs from recompute_kpis_after_action. Returns
% a scalar struct with mean RSRP/SINR/load/QoS/attach/served-traffic
% values for both states and their deltas.

summary = struct();

summary.pre_attach_rate = mean(preState.rf.isAttached);
summary.post_attach_rate = mean(postState.rf.isAttached);
summary.delta_attach_rate = summary.post_attach_rate - summary.pre_attach_rate;

attached = preState.rf.isAttached;
summary.pre_mean_rsrp_dBm = mean(preState.rf.bestRSRP_dBm(attached), 'omitnan');
summary.post_mean_rsrp_dBm = mean(postState.rf.bestRSRP_dBm(postState.rf.isAttached), 'omitnan');
if ~isfinite(summary.pre_mean_rsrp_dBm), summary.pre_mean_rsrp_dBm = mean(preState.rf.bestRSRP_dBm, 'omitnan'); end
if ~isfinite(summary.post_mean_rsrp_dBm), summary.post_mean_rsrp_dBm = mean(postState.rf.bestRSRP_dBm, 'omitnan'); end
summary.delta_mean_rsrp_dB = summary.post_mean_rsrp_dBm - summary.pre_mean_rsrp_dBm;

summary.pre_mean_sinr_dB = mean(preState.rf.bestSINR_dB(attached), 'omitnan');
summary.post_mean_sinr_dB = mean(postState.rf.bestSINR_dB(postState.rf.isAttached), 'omitnan');
if ~isfinite(summary.pre_mean_sinr_dB), summary.pre_mean_sinr_dB = mean(preState.rf.bestSINR_dB, 'omitnan'); end
if ~isfinite(summary.post_mean_sinr_dB), summary.post_mean_sinr_dB = mean(postState.rf.bestSINR_dB, 'omitnan'); end
summary.delta_mean_sinr_dB = summary.post_mean_sinr_dB - summary.pre_mean_sinr_dB;

summary.pre_mean_sector_load = mean(preState.sectorKpiTable.sector_load_ratio, 'omitnan');
summary.post_mean_sector_load = mean(postState.sectorKpiTable.sector_load_ratio, 'omitnan');
summary.delta_mean_sector_load = summary.post_mean_sector_load - summary.pre_mean_sector_load;

summary.pre_qos_satisfaction_ratio = preState.networkKpiTable.qos_satisfaction_ratio;
summary.post_qos_satisfaction_ratio = postState.networkKpiTable.qos_satisfaction_ratio;
summary.delta_qos_satisfaction_ratio = summary.post_qos_satisfaction_ratio - summary.pre_qos_satisfaction_ratio;

summary.pre_total_served_traffic_Mbps = preState.networkKpiTable.total_served_traffic_Mbps;
summary.post_total_served_traffic_Mbps = postState.networkKpiTable.total_served_traffic_Mbps;
summary.delta_served_traffic_Mbps = summary.post_total_served_traffic_Mbps - summary.pre_total_served_traffic_Mbps;
end
