function T = map_vendor_kpi_to_project_schema(rawTable, vcfg)
%MAP_VENDOR_KPI_TO_PROJECT_SCHEMA Normalize vendor KPI columns.
%
% Output values use project-standard units:
%   rates/utilization/availability are ratios in [0, 1]
%   traffic volumes remain KByte as reported by vendor
%   DL/UL average rates are converted from KByte/s to Mbps

T = table();
T.timestamp = datetime(read_col(rawTable, 'Begin Time'), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
T.end_timestamp = datetime(read_col(rawTable, 'End Time'), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
T.granularity = string(read_col(rawTable, 'Granularity'));
T.vendor_site_key = string(rawTable.vendor_site_key);
T.vendor_file = string(rawTable.vendor_file);
T.sim_site_id = rawTable.sim_site_id;
T.sim_position = string(rawTable.sim_position);

T.site_id = rawTable.sim_site_id;
T.eNodeBId = numeric_col(rawTable, 'eNodeBId');
T.cell_id = numeric_col(rawTable, 'cellId');
T.cell_uid = strcat(string(T.eNodeBId), "_", string(T.cell_id));
T.vendor_cell_name = string(read_col(rawTable, 'E-UTRAN TDD Cell Name'));
T.vendor_site_name = string(read_col(rawTable, 'Managed Element'));

T.rrc_setup_success_rate = normalize_ratio(numeric_col(rawTable, 'RRC Establishment Success Rate(percent)'));
T.rrc_drop_rate = normalize_ratio(numeric_col(rawTable, 'RRC Drop Rate(percent)'));
T.erab_setup_success_rate = normalize_ratio(numeric_col(rawTable, 'E-RAB Setup Success Rate(percent)'));
T.erab_drop_rate = normalize_ratio(numeric_col(rawTable, 'E-RAB Drop Rate(percent)'));
T.cell_availability = normalize_ratio(numeric_col(rawTable, 'Cell Availability(percent)'));

T.traffic_volume_dl_kbyte = numeric_col(rawTable, 'DL Cell PDCP SDU Volume(KByte)');
T.traffic_volume_ul_kbyte = numeric_col(rawTable, 'UL Cell PDCP SDU Volume(KByte)');
T.active_users = numeric_col(rawTable, 'Average Active User Number on User Plane(unit)');
T.max_active_users = numeric_col(rawTable, 'Maximum Active User Number on User Plane(unit)');
T.dl_throughput_mbps = numeric_col(rawTable, 'DL Traffic Average Rate(Kbyte/s)') * 8 / 1000;
T.ul_throughput_mbps = numeric_col(rawTable, 'UL Traffic Average Rate(Kbyte/s)') * 8 / 1000;

T.dl_bler = normalize_ratio(numeric_col(rawTable, 'Cell Downlink BLER(percent)'));
T.ul_bler = normalize_ratio(numeric_col(rawTable, 'Cell Uplink BLER(percent)'));
T.ul_prb_utilization = normalize_ratio(numeric_col(rawTable, 'UL PRB Utilization Rate(percent)'));
T.dl_prb_utilization = normalize_ratio(numeric_col(rawTable, 'DL PRB Utilization Rate(percent)'));

T.handover_intra_enb_intra_freq_success = normalize_ratio(numeric_col(rawTable, 'Success Rate of Intra-eNB Intra-freq Cell Outgoing Handover(percent)'));
T.handover_intra_enb_inter_freq_success = normalize_ratio(numeric_col(rawTable, 'Success Rate of Intra-eNB Inter-freq Cell Outgoing Handover(percent)'));
T.handover_inter_enb_x2_success = normalize_ratio(numeric_col(rawTable, 'Success Rate of Inter-eNB Intra-freq Cell Outgoing Handover Via X2(percent)'));
T.handover_inter_enb_s1_success = normalize_ratio(numeric_col(rawTable, 'Success Rate of Inter-eNB Intra-freq Cell Outgoing Handover Via S1(percent)'));

T.rssi_min_dbm = numeric_col(rawTable, 'Minimum Cell RSSI(dBm)');
T.rssi_max_dbm = numeric_col(rawTable, 'Maximum Cell RSSI(dBm)');
T.rssi_avg_dbm = numeric_col(rawTable, 'Average Cell RSSI(dBm)');
T.tx_power_w = numeric_col(rawTable, 'Average Cell Transmit Power(W)');

T = attach_sim_sector_mapping(T, vcfg);
end

function T = attach_sim_sector_mapping(T, vcfg)
T.sim_sector_id = nan(height(T), 1);
T.sim_azimuth_deg = nan(height(T), 1);
T.selected_for_21cell_topology = false(height(T), 1);
for i = 1:height(vcfg.cellMap)
    mask = T.sim_site_id == vcfg.cellMap.sim_site_id(i) & ...
        T.cell_id == vcfg.cellMap.vendor_cell_id(i);
    T.sim_sector_id(mask) = vcfg.cellMap.sim_sector_id(i);
    T.sim_azimuth_deg(mask) = vcfg.cellMap.sim_azimuth_deg(i);
    T.selected_for_21cell_topology(mask) = true;
end
end

function v = read_col(T, name)
if ismember(name, T.Properties.VariableNames)
    v = T.(name);
else
    v = repmat({''}, height(T), 1);
end
end

function v = numeric_col(T, name)
if ~ismember(name, T.Properties.VariableNames)
    v = nan(height(T), 1);
    return;
end
x = T.(name);
if isnumeric(x)
    v = double(x);
elseif iscell(x)
    v = str2double(string(x));
else
    v = str2double(string(x));
end
end

function r = normalize_ratio(x)
r = x;
mask = isfinite(r) & r > 1;
r(mask) = r(mask) / 100;
end
