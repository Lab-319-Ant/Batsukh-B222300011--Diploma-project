function overloadReport = build_vendor_tp_overload_report(tpTable, codTable, vcfg)
%BUILD_VENDOR_TP_OVERLOAD_REPORT Summarize cells likely to overload.

overloadReport = table();
if isempty(tpTable)
    return;
end

T = tpTable(tpTable.predicted_dl_prb_utilization_1h >= vcfg.tpOverloadPrbThreshold, :);
if isempty(T)
    overloadReport = empty_report();
    return;
end

[groups, sector, cellUid, cellId, cellName] = findgroups(T.sim_sector_id, ...
    string(T.cell_uid), T.cell_id, string(T.vendor_cell_name));
nGroups = max(groups);
rows = cell(nGroups, 18);

for i = 1:nGroups
    G = T(groups == i, :);
    eventCount = height(G);
    firstTs = min(G.timestamp);
    lastTs = max(G.timestamp);
    [maxPrb, peakIdx] = max(G.predicted_dl_prb_utilization_1h);
    peakTs = G.timestamp(peakIdx);
    peakActual = G.actual_dl_prb_utilization_1h(peakIdx);
    meanPrb = mean(G.predicted_dl_prb_utilization_1h, 'omitnan');
    maxUsers = max(G.predicted_active_users_1h, [], 'omitnan');
    [maePrb, r2Prb, metricRows] = sector_prediction_metrics(tpTable, sector(i));

    if has_cod_incident(codTable, sector(i), firstTs, lastTs)
        recommended = "blocked_by_cod_incident_first";
    elseif maxPrb >= 0.90
        recommended = "high_overload_risk_review_LB_or_capacity_help";
    else
        recommended = "moderate_overload_risk_monitor";
    end

    proof = sprintf(['S%d cell %s exceeded %.0f%% predicted DL PRB for %d intervals; ' ...
        'peak %s predicted %.1f%%, actual %.1f%%; TP check rows=%d, MAE=%.1f%%, R2=%.2f'], ...
        sector(i), cellUid(i), 100 * vcfg.tpOverloadPrbThreshold, eventCount, ...
        datestr(peakTs, 'dd-mmm HH:MM'), 100 * maxPrb, 100 * peakActual, ...
        metricRows, 100 * maePrb, r2Prb);

    rows(i, :) = {compose('S%d', sector(i)), sector(i), char(cellUid(i)), cellId(i), ...
        char(cellName(i)), sprintf('S%d | cell %s', sector(i), cellUid(i)), ...
        eventCount, firstTs, lastTs, peakTs, maxPrb, peakActual, meanPrb, ...
        maxUsers, maePrb, r2Prb, char(recommended), char(proof)};
end

overloadReport = cell2table(rows, 'VariableNames', report_columns());
overloadReport = sortrows(overloadReport, {'overload_event_count','max_predicted_dl_prb'}, {'descend','descend'});
end

function report = empty_report()
report = table('Size', [0 numel(report_columns())], ...
    'VariableTypes', {'cell','double','cell','double','cell','cell','double', ...
    'datetime','datetime','datetime','double','double','double','double', ...
    'double','double','cell','cell'}, ...
    'VariableNames', report_columns());
end

function names = report_columns()
names = {'affected_sector','sim_sector_id','cell_uid','cell_id','vendor_cell_name', ...
    'display_cell','overload_event_count','first_timestamp','last_timestamp', ...
    'peak_timestamp','max_predicted_dl_prb','actual_dl_prb_at_peak_1h', ...
    'mean_predicted_dl_prb','max_predicted_active_users','mae_dl_prb_1h', ...
    'r2_dl_prb_1h','recommended_tp_action','proof_summary'};
end

function [maePrb, r2Prb, n] = sector_prediction_metrics(tpTable, sectorId)
M = tpTable(tpTable.sim_sector_id == sectorId & logical(tpTable.actual_1h_available), :);
M = M(isfinite(M.predicted_dl_prb_utilization_1h) & isfinite(M.actual_dl_prb_utilization_1h), :);
n = height(M);
if n == 0
    maePrb = NaN;
    r2Prb = NaN;
    return;
end
err = M.predicted_dl_prb_utilization_1h - M.actual_dl_prb_utilization_1h;
maePrb = mean(abs(err), 'omitnan');
sse = sum(err.^2, 'omitnan');
actualMean = mean(M.actual_dl_prb_utilization_1h, 'omitnan');
sst = sum((M.actual_dl_prb_utilization_1h - actualMean).^2, 'omitnan');
if sst <= eps
    r2Prb = NaN;
else
    r2Prb = 1 - sse / sst;
end
end

function tf = has_cod_incident(codTable, sectorId, firstTs, lastTs)
if isempty(codTable)
    tf = false;
    return;
end
mask = codTable.sim_sector_id == sectorId & codTable.timestamp >= firstTs & codTable.timestamp <= lastTs;
tf = any(ismember(string(codTable.cod_state(mask)), ["degraded_kpi","outage_like"]));
end
