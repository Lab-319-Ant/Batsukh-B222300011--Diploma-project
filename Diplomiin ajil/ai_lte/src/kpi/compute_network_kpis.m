function networkKpiTable = compute_network_kpis(cfg, topology, ueTrafficResult, sectorKpiTable, rfMap)
%COMPUTE_NETWORK_KPIS Compute one-row Phase 2 network KPI summary.

num_sites = height(topology.sites);
num_sectors = height(topology.sectors);
num_ues = height(ueTrafficResult);

attached_ues = sum(ueTrafficResult.isAttached);
unattached_ues = num_ues - attached_ues;
attach_rate = attached_ues / max(num_ues, 1);
coverage_ratio = rfMap.plannedCoverageRatio;
sinr_threshold_ratio = mean(ueTrafficResult.bestSINR_dB >= cfg.minSINR_dB);
active_ues = sum(ueTrafficResult.isTrafficActive);
active_attached_ues = sum(ueTrafficResult.isTrafficActive & ueTrafficResult.isAttached);

total_offered_traffic_Mbps = sum(ueTrafficResult.demand_Mbps, 'omitnan');
total_served_traffic_Mbps = sum(ueTrafficResult.servedThroughput_Mbps, 'omitnan');
total_unserved_traffic_Mbps = sum(ueTrafficResult.unservedDemand_Mbps, 'omitnan');

mean_ue_throughput_Mbps = mean(ueTrafficResult.servedThroughput_Mbps, 'omitnan');
median_ue_throughput_Mbps = median(ueTrafficResult.servedThroughput_Mbps, 'omitnan');

qos_satisfied_ues = sum(ueTrafficResult.qosSatisfied);
qos_satisfaction_ratio = qos_satisfied_ues / max(active_ues, 1);
active_attach_rate = active_attached_ues / max(active_ues, 1);

overloaded_sector_count = sum(sectorKpiTable.overload_flag);
finiteLoad = sectorKpiTable.sector_load_ratio(isfinite(sectorKpiTable.sector_load_ratio));
if isempty(finiteLoad)
    mean_sector_load = NaN;
    max_sector_load = Inf;
else
    mean_sector_load = mean(finiteLoad, 'omitnan');
    max_sector_load = max(sectorKpiTable.sector_load_ratio);
end

% Phase 2 fairness includes all UEs, so unattached and unserved users
% contribute zero throughput to the fairness calculation.
jain_fairness_index = compute_jain_fairness(ueTrafficResult.servedThroughput_Mbps);

networkKpiTable = table(num_sites, num_sectors, num_ues, attached_ues, ...
    unattached_ues, attach_rate, active_ues, active_attached_ues, active_attach_rate, ...
    coverage_ratio, sinr_threshold_ratio, ...
    total_offered_traffic_Mbps, total_served_traffic_Mbps, total_unserved_traffic_Mbps, ...
    mean_ue_throughput_Mbps, median_ue_throughput_Mbps, qos_satisfied_ues, ...
    qos_satisfaction_ratio, overloaded_sector_count, mean_sector_load, max_sector_load, ...
    jain_fairness_index, ...
    'VariableNames', {'num_sites','num_sectors','num_ues','attached_ues', ...
    'unattached_ues','attach_rate','active_ues','active_attached_ues','active_attach_rate', ...
    'coverage_ratio','sinr_threshold_ratio', ...
    'total_offered_traffic_Mbps','total_served_traffic_Mbps','total_unserved_traffic_Mbps', ...
    'mean_ue_throughput_Mbps','median_ue_throughput_Mbps','qos_satisfied_ues', ...
    'qos_satisfaction_ratio','overloaded_sector_count','mean_sector_load','max_sector_load', ...
    'jain_fairness_index'});
end
