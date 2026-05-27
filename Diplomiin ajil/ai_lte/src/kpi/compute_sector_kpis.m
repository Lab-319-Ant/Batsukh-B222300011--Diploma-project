function sectorKpiTable = compute_sector_kpis(cfg, topology, ueTrafficResult, sectorCapacity_Mbps)
%COMPUTE_SECTOR_KPIS Compute Phase 2 traffic-aware KPIs per LTE sector.

numSectors = height(topology.sectors);

attached_ue_count = zeros(numSectors, 1);
active_ue_count = zeros(numSectors, 1);
active_attached_ue_count = zeros(numSectors, 1);
offered_traffic_Mbps = zeros(numSectors, 1);
served_traffic_Mbps = zeros(numSectors, 1);
unserved_traffic_Mbps = zeros(numSectors, 1);
sector_load_ratio = zeros(numSectors, 1);
mean_RSRP_dBm = nan(numSectors, 1);
median_RSRP_dBm = nan(numSectors, 1);
mean_SINR_dB = nan(numSectors, 1);
median_SINR_dB = nan(numSectors, 1);
mean_UE_throughput_Mbps = nan(numSectors, 1);
median_UE_throughput_Mbps = nan(numSectors, 1);
qos_satisfaction_ratio = zeros(numSectors, 1);
overload_flag = false(numSectors, 1);

for s = 1:numSectors
    idx = ueTrafficResult.isAttached & ueTrafficResult.serving_sector == s;
    activeIdx = ueTrafficResult.isTrafficActive & ueTrafficResult.serving_sector == s;
    activeAttachedIdx = idx & ueTrafficResult.isTrafficActive;
    attached_ue_count(s) = sum(idx);
    active_ue_count(s) = sum(activeIdx);
    active_attached_ue_count(s) = sum(activeAttachedIdx);

    offered_traffic_Mbps(s) = sum(ueTrafficResult.demand_Mbps(activeAttachedIdx), 'omitnan');
    served_traffic_Mbps(s) = sum(ueTrafficResult.servedThroughput_Mbps(activeAttachedIdx), 'omitnan');
    unserved_traffic_Mbps(s) = sum(ueTrafficResult.unservedDemand_Mbps(activeAttachedIdx), 'omitnan');

    if sectorCapacity_Mbps(s) > 0
        sector_load_ratio(s) = offered_traffic_Mbps(s) / sectorCapacity_Mbps(s);
    elseif offered_traffic_Mbps(s) > 0
        sector_load_ratio(s) = Inf;
    else
        sector_load_ratio(s) = 0;
    end

    overload_flag(s) = sector_load_ratio(s) > cfg.sectorOverloadThreshold;

    if attached_ue_count(s) > 0
        mean_RSRP_dBm(s) = mean(ueTrafficResult.bestRSRP_dBm(idx), 'omitnan');
        median_RSRP_dBm(s) = median(ueTrafficResult.bestRSRP_dBm(idx), 'omitnan');
        mean_SINR_dB(s) = mean(ueTrafficResult.bestSINR_dB(idx), 'omitnan');
        median_SINR_dB(s) = median(ueTrafficResult.bestSINR_dB(idx), 'omitnan');
        if active_attached_ue_count(s) > 0
            mean_UE_throughput_Mbps(s) = mean(ueTrafficResult.servedThroughput_Mbps(activeAttachedIdx), 'omitnan');
            median_UE_throughput_Mbps(s) = median(ueTrafficResult.servedThroughput_Mbps(activeAttachedIdx), 'omitnan');
            qos_satisfaction_ratio(s) = mean(ueTrafficResult.qosSatisfied(activeAttachedIdx));
        else
            mean_UE_throughput_Mbps(s) = NaN;
            median_UE_throughput_Mbps(s) = NaN;
            qos_satisfaction_ratio(s) = NaN;
        end
    end
end

sector_id = topology.sectors.sectorId;
site_id = topology.sectors.siteId;
azimuth_deg = topology.sectors.azimuth_deg;
sector_capacity_Mbps = sectorCapacity_Mbps(:);

sectorKpiTable = table(sector_id, site_id, azimuth_deg, attached_ue_count, ...
    active_ue_count, active_attached_ue_count, ...
    offered_traffic_Mbps, served_traffic_Mbps, unserved_traffic_Mbps, ...
    sector_capacity_Mbps, sector_load_ratio, mean_RSRP_dBm, median_RSRP_dBm, ...
    mean_SINR_dB, median_SINR_dB, mean_UE_throughput_Mbps, ...
    median_UE_throughput_Mbps, qos_satisfaction_ratio, overload_flag, ...
    'VariableNames', {'sector_id','site_id','azimuth_deg','attached_ue_count', ...
    'active_ue_count','active_attached_ue_count', ...
    'offered_traffic_Mbps','served_traffic_Mbps','unserved_traffic_Mbps', ...
    'sector_capacity_Mbps','sector_load_ratio','mean_RSRP_dBm','median_RSRP_dBm', ...
    'mean_SINR_dB','median_SINR_dB','mean_UE_throughput_Mbps', ...
    'median_UE_throughput_Mbps','qos_satisfaction_ratio','overload_flag'});
end
