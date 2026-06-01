function report = validate_vendor_kpi(T, vcfg)
%VALIDATE_VENDOR_KPI Build validation reports for vendor KPI mode.

selected = T(T.selected_for_21cell_topology, :);
ignored = T(~T.selected_for_21cell_topology, :);

report.cellCompleteness = build_cell_completeness(selected, vcfg);
report.ignoredCells = build_ignored_cells(ignored);
report.duplicateCellNames = build_duplicate_cell_names(T);
report.rangeChecks = build_range_checks(selected);
report.impossibleStates = build_impossible_states(selected);
report.siteInventory = build_site_inventory(T);
end

function C = build_cell_completeness(T, vcfg)
if isempty(T)
    C = table();
    return;
end
[groups, simSite, simSector, cellUid, siteKey, cellName] = findgroups( ...
    T.sim_site_id, T.sim_sector_id, string(T.cell_uid), string(T.vendor_site_key), string(T.vendor_cell_name));
rowCount = splitapply(@numel, T.timestamp, groups);
uniqueTimestampCount = splitapply(@(x) numel(unique(x)), T.timestamp, groups);
startTime = splitapply(@(x) min(x), T.timestamp, groups);
endTime = splitapply(@(x) max(x), T.timestamp, groups);
duplicateTimestampCount = rowCount - uniqueTimestampCount;
missingVsExpected = vcfg.expectedIntervalsPerCell - uniqueTimestampCount;
completeFlag = uniqueTimestampCount == vcfg.expectedIntervalsPerCell;
C = table(simSite, simSector, cellstr(siteKey), cellstr(cellUid), cellstr(cellName), ...
    rowCount, uniqueTimestampCount, duplicateTimestampCount, missingVsExpected, ...
    completeFlag, startTime, endTime, ...
    'VariableNames', {'sim_site_id','sim_sector_id','vendor_site_key','cell_uid', ...
    'vendor_cell_name','row_count','unique_timestamp_count','duplicate_timestamp_count', ...
    'missing_vs_expected_7day_15min','complete_7day_15min','start_time','end_time'});
end

function I = build_ignored_cells(T)
if isempty(T)
    I = table('Size', [0 6], 'VariableTypes', {'double','cell','double','cell','double','double'}, ...
        'VariableNames', {'sim_site_id','vendor_site_key','cell_id','vendor_cell_name','row_count','unique_timestamp_count'});
    return;
end
[groups, simSite, siteKey, cellId, cellName] = findgroups(T.sim_site_id, string(T.vendor_site_key), T.cell_id, string(T.vendor_cell_name));
rowCount = splitapply(@numel, T.timestamp, groups);
uniqueTimestampCount = splitapply(@(x) numel(unique(x)), T.timestamp, groups);
I = table(simSite, cellstr(siteKey), cellId, cellstr(cellName), rowCount, uniqueTimestampCount, ...
    'VariableNames', {'sim_site_id','vendor_site_key','cell_id','vendor_cell_name','row_count','unique_timestamp_count'});
end

function D = build_duplicate_cell_names(T)
[groups, name] = findgroups(string(T.vendor_cell_name));
uidCount = splitapply(@(x) numel(unique(string(x))), T.cell_uid, groups);
siteCount = splitapply(@(x) numel(unique(string(x))), T.vendor_site_key, groups);
rowCount = splitapply(@numel, T.cell_uid, groups);
D = table(cellstr(name), uidCount, siteCount, rowCount, ...
    'VariableNames', {'vendor_cell_name','unique_cell_uid_count','unique_site_count','row_count'});
D = D(D.unique_cell_uid_count > 1 | D.unique_site_count > 1, :);
end

function R = build_range_checks(T)
checks = {
    'rrc_setup_success_rate', 0, 1;
    'rrc_drop_rate', 0, 1;
    'erab_setup_success_rate', 0, 1;
    'erab_drop_rate', 0, 1;
    'cell_availability', 0, 1;
    'dl_prb_utilization', 0, 1;
    'ul_prb_utilization', 0, 1;
    'dl_bler', 0, 1;
    'ul_bler', 0, 1;
    'active_users', 0, inf;
    'traffic_volume_dl_kbyte', 0, inf;
    'traffic_volume_ul_kbyte', 0, inf;
    'rssi_avg_dbm', -140, -40;
    'tx_power_w', 0, inf;
    };
rows = cell(size(checks, 1), 6);
for i = 1:size(checks, 1)
    col = checks{i, 1};
    lo = checks{i, 2};
    hi = checks{i, 3};
    v = T.(col);
    bad = isfinite(v) & (v < lo | v > hi);
    rows(i, :) = {col, lo, hi, sum(bad), min(v, [], 'omitnan'), max(v, [], 'omitnan')};
end
R = cell2table(rows, 'VariableNames', {'kpi_name','min_allowed','max_allowed', ...
    'out_of_range_count','observed_min','observed_max'});
end

function S = build_impossible_states(T)
highTrafficZeroUsers = T.active_users == 0 & ...
    (T.traffic_volume_dl_kbyte > 0 | T.traffic_volume_ul_kbyte > 0);
unavailableHasTraffic = T.cell_availability <= 0.01 & ...
    (T.traffic_volume_dl_kbyte > 0 | T.traffic_volume_ul_kbyte > 0 | T.active_users > 0);
prbOver100 = T.dl_prb_utilization > 1 | T.ul_prb_utilization > 1;

names = {'high_traffic_with_zero_users'; 'unavailable_but_has_traffic_or_users'; 'prb_over_100_percent'};
counts = [sum(highTrafficZeroUsers); sum(unavailableHasTraffic); sum(prbOver100)];
S = table(names, counts, 'VariableNames', {'check_name','row_count'});
end

function S = build_site_inventory(T)
[groups, simSite, pos, key, fileName] = findgroups(T.sim_site_id, string(T.sim_position), ...
    string(T.vendor_site_key), string(T.vendor_file));
rowCount = splitapply(@numel, T.timestamp, groups);
selectedRows = splitapply(@sum, double(T.selected_for_21cell_topology), groups);
uniqueCells = splitapply(@(x) numel(unique(x)), T.cell_id, groups);
selectedCells = splitapply(@(x, y) numel(unique(x(logical(y)))), T.cell_id, double(T.selected_for_21cell_topology), groups);
S = table(simSite, cellstr(pos), cellstr(key), cellstr(fileName), rowCount, selectedRows, uniqueCells, selectedCells, ...
    'VariableNames', {'sim_site_id','sim_position','vendor_site_key','vendor_file', ...
    'row_count','selected_row_count','unique_vendor_cell_count','selected_vendor_cell_count'});
end
