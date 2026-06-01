function episodes = build_vendor_qp_degradation_report(qpTable, vcfg)
%BUILD_VENDOR_QP_DEGRADATION_REPORT Consecutive QP risk windows by sector.

episodes = table();
if isempty(qpTable)
    return;
end

rows = cell(height(qpTable), 22);
rowIdx = 0;
sectors = unique(qpTable.sim_sector_id);

for s = sectors(:)'
    S = qpTable(qpTable.sim_sector_id == s, :);
    S = sortrows(S, 'timestamp');
    classText = string(S.qp_risk_class);
    hasThroughputEvidence = S.predicted_throughput_drop_ratio >= vcfg.qpThroughputDropWarningRatio | ...
        S.actual_throughput_drop_ratio_1h >= vcfg.qpThroughputDropWarningRatio;
    flag = ismember(classText, ["degradation_risk","critical_qos_risk"]) & hasThroughputEvidence;
    if ~any(flag)
        continue;
    end

    idx = find(flag);
    breakMask = minutes(S.timestamp(idx(2:end)) - S.timestamp(idx(1:end-1))) > ...
        vcfg.expectedGranularityMinutes;
    starts = idx([true; breakMask]);
    ends = idx([breakMask; true]);

    for k = 1:numel(starts)
        G = S(starts(k):ends(k), :);
        [maxRisk, peakLocalIdx] = max(G.qp_risk_score);
        firstTs = G.timestamp(1);
        lastTs = G.timestamp(end);
        peakTs = G.timestamp(peakLocalIdx);
        intervalCount = height(G);
        durationMinutes = intervalCount * vcfg.expectedGranularityMinutes;
        peakPrb = G.predicted_dl_prb_utilization_1h(peakLocalIdx);
        peakPredThr = G.predicted_dl_throughput_mbps_1h(peakLocalIdx);
        peakCurrentThr = G.current_dl_throughput_mbps(peakLocalIdx);
        peakPredDrop = G.predicted_throughput_drop_ratio(peakLocalIdx);
        peakActualDrop = G.actual_throughput_drop_ratio_1h(peakLocalIdx);
        minPredThr = min(G.predicted_dl_throughput_mbps_1h, [], 'omitnan');
        [maeThr, r2Thr, metricRows] = throughput_metrics(qpTable, s);
        action = string(G.qp_decision(peakLocalIdx));
        riskClass = string(G.qp_risk_class(peakLocalIdx));
        proof = build_proof(G.display_cell{1}, firstTs, lastTs, peakTs, maxRisk, ...
            peakPrb, peakCurrentThr, peakPredThr, peakPredDrop, peakActualDrop, ...
            maeThr, r2Thr, metricRows, G.qp_reason{peakLocalIdx});

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = {G.affected_sector{1}, s, G.cell_uid{1}, G.cell_id(1), ...
            G.display_cell{1}, firstTs, lastTs, peakTs, intervalCount, ...
            durationMinutes, maxRisk, char(riskClass), peakPrb, minPredThr, ...
            peakCurrentThr, peakPredThr, peakPredDrop, peakActualDrop, maeThr, ...
            r2Thr, char(action), char(proof)};
    end
end

if rowIdx == 0
    episodes = empty_episode_table();
    return;
end

episodes = cell2table(rows(1:rowIdx, :), 'VariableNames', episode_columns());
episodes = sortrows(episodes, {'predicted_throughput_drop_ratio_at_peak', ...
    'actual_throughput_drop_ratio_at_peak_1h','max_qp_risk_score'}, ...
    {'descend','descend','descend'});
end

function T = empty_episode_table()
T = table('Size', [0 numel(episode_columns())], ...
    'VariableTypes', {'cell','double','cell','double','cell','datetime','datetime', ...
    'datetime','double','double','double','cell','double','double','double', ...
    'double','double','double','double','double','cell','cell'}, ...
    'VariableNames', episode_columns());
end

function names = episode_columns()
names = {'affected_sector','sim_sector_id','cell_uid','cell_id','display_cell', ...
    'first_timestamp','last_timestamp','peak_timestamp','interval_count', ...
    'duration_minutes','max_qp_risk_score','peak_qp_risk_class', ...
    'predicted_dl_prb_at_peak','min_predicted_dl_throughput_mbps_1h', ...
    'current_dl_throughput_at_peak_mbps','predicted_dl_throughput_at_peak_mbps_1h', ...
    'predicted_throughput_drop_ratio_at_peak','actual_throughput_drop_ratio_at_peak_1h', ...
    'mae_dl_throughput_mbps_1h','r2_dl_throughput_1h', ...
    'recommended_qp_action','proof_summary'};
end

function [maeThr, r2Thr, n] = throughput_metrics(qpTable, sectorId)
M = qpTable(qpTable.sim_sector_id == sectorId & logical(qpTable.actual_1h_available), :);
M = M(isfinite(M.predicted_dl_throughput_mbps_1h) & ...
    isfinite(M.actual_dl_throughput_mbps_1h), :);
n = height(M);
if n == 0
    maeThr = NaN;
    r2Thr = NaN;
    return;
end
err = M.predicted_dl_throughput_mbps_1h - M.actual_dl_throughput_mbps_1h;
maeThr = mean(abs(err), 'omitnan');
sse = sum(err.^2, 'omitnan');
actualMean = mean(M.actual_dl_throughput_mbps_1h, 'omitnan');
sst = sum((M.actual_dl_throughput_mbps_1h - actualMean).^2, 'omitnan');
if sst <= eps
    r2Thr = NaN;
else
    r2Thr = 1 - sse / sst;
end
end

function proof = build_proof(displayCell, firstTs, lastTs, peakTs, maxRisk, peakPrb, ...
    currentThr, predThr, predDrop, actualDrop, maeThr, r2Thr, metricRows, reason)
if isfinite(actualDrop)
    actualText = sprintf('actual +1h throughput drop %.1f%%', 100 * actualDrop);
else
    actualText = 'actual +1h throughput unavailable';
end
proof = sprintf(['%s QP risk from %s to %s; peak %s risk %.2f, predicted PRB %.1f%%, ' ...
    'current throughput %.1f Mbps, predicted +1h throughput %.1f Mbps, predicted drop %.1f%%, %s; ' ...
    'throughput check rows=%d, MAE %.2f Mbps, R2 %.2f; reason: %s'], ...
    displayCell, datestr(firstTs, 'dd-mmm HH:MM'), datestr(lastTs, 'dd-mmm HH:MM'), ...
    datestr(peakTs, 'dd-mmm HH:MM'), maxRisk, 100 * peakPrb, currentThr, predThr, ...
    100 * predDrop, actualText, metricRows, maeThr, r2Thr, reason);
end
