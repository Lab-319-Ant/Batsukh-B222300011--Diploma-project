function codTable = run_cod_from_vendor_kpi(cleanKpi, vcfg)
%RUN_COD_FROM_VENDOR_KPI KPI-rule COD for real vendor data.
%
% Labels are KPI-evidence labels, not confirmed alarm-ground-truth labels.

T = cleanKpi(cleanKpi.selected_for_21cell_topology, :);
if isempty(T)
    codTable = table();
    return;
end

T = sortrows(T, {'sim_sector_id','timestamp'});

trafficBaseline = group_median(T, 'cell_uid', 'traffic_volume_dl_kbyte');
userBaseline = group_median(T, 'cell_uid', 'active_users');

n = height(T);
state = repmat("normal", n, 1);
confidence = repmat("medium", n, 1);
reason = strings(n, 1);

availabilityOut = T.cell_availability <= vcfg.codAvailabilityOutageThreshold;
txOff = T.tx_power_w <= 0.01;
rssiVeryLow = T.rssi_avg_dbm <= vcfg.codRssiVeryLow_dBm;
trafficCollapse = T.traffic_volume_dl_kbyte <= vcfg.codTrafficCollapseRatio .* max(trafficBaseline, 1);
usersCollapse = T.active_users <= vcfg.codTrafficCollapseRatio .* max(userBaseline, 1);

outageLike = availabilityOut | (txOff & rssiVeryLow) | ...
    (trafficCollapse & usersCollapse & rssiVeryLow);

degraded = T.rrc_setup_success_rate < vcfg.codRrcDegradedThreshold | ...
    T.erab_setup_success_rate < vcfg.codErabSetupDegradedThreshold | ...
    T.rrc_drop_rate > vcfg.codRrcDropHighThreshold | ...
    T.erab_drop_rate > vcfg.codErabDropHighThreshold | ...
    T.rssi_avg_dbm <= vcfg.cocRssiWeak_dBm;

state(degraded) = "degraded_kpi";
state(outageLike) = "outage_like";
confidence(outageLike & availabilityOut & txOff) = "high";
confidence(outageLike & ~(availabilityOut & txOff)) = "medium";
confidence(degraded & ~outageLike) = "medium";

for i = 1:n
    tags = strings(0, 1);
    if availabilityOut(i), tags(end+1) = "availability_zero_or_low"; end %#ok<AGROW>
    if txOff(i), tags(end+1) = "tx_power_zero_or_low"; end %#ok<AGROW>
    if rssiVeryLow(i), tags(end+1) = "very_low_rssi"; end %#ok<AGROW>
    if trafficCollapse(i), tags(end+1) = "traffic_collapse"; end %#ok<AGROW>
    if usersCollapse(i), tags(end+1) = "active_user_collapse"; end %#ok<AGROW>
    if T.rrc_setup_success_rate(i) < vcfg.codRrcDegradedThreshold, tags(end+1) = "low_rrc_setup"; end %#ok<AGROW>
    if T.erab_setup_success_rate(i) < vcfg.codErabSetupDegradedThreshold, tags(end+1) = "low_erab_setup"; end %#ok<AGROW>
    if T.rrc_drop_rate(i) > vcfg.codRrcDropHighThreshold, tags(end+1) = "high_rrc_drop"; end %#ok<AGROW>
    if T.erab_drop_rate(i) > vcfg.codErabDropHighThreshold, tags(end+1) = "high_erab_drop"; end %#ok<AGROW>
    if isempty(tags), tags = "normal_kpi"; end
    reason(i) = strjoin(tags, "|");
end

codTable = T(:, {'timestamp','sim_site_id','sim_position','sim_sector_id', ...
    'vendor_site_key','cell_uid','cell_id','vendor_cell_name', ...
    'cell_availability','rrc_setup_success_rate','rrc_drop_rate', ...
    'erab_setup_success_rate','erab_drop_rate','dl_prb_utilization', ...
    'active_users','traffic_volume_dl_kbyte','rssi_avg_dbm','tx_power_w', ...
    'dl_throughput_mbps','ul_throughput_mbps','dl_bler','ul_bler', ...
    'handover_intra_enb_intra_freq_success','handover_intra_enb_inter_freq_success', ...
    'handover_inter_enb_x2_success','handover_inter_enb_s1_success'});
codTable.cod_state = cellstr(state);
codTable.cod_confidence = cellstr(confidence);
codTable.cod_reason = cellstr(reason);
end

function med = group_median(T, groupCol, valueCol)
[groups, key] = findgroups(string(T.(groupCol)));
groupMed = splitapply(@(x) median(x, 'omitnan'), T.(valueCol), groups);
med = nan(height(T), 1);
[~, loc] = ismember(string(T.(groupCol)), key);
med(:) = groupMed(loc);
med(~isfinite(med)) = 0;
end
