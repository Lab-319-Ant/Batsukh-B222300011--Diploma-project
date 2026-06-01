function episodes = build_vendor_tp_overload_episodes(tpTable, codTable, performanceTable, vcfg)
%BUILD_VENDOR_TP_OVERLOAD_EPISODES Create exact TP overload windows.

episodes = table();
if isempty(tpTable)
    return;
end

maxRows = height(tpTable);
rows = cell(maxRows, 19);
rowIdx = 0;
sectors = unique(tpTable.sim_sector_id);
for s = sectors(:)'
    S = tpTable(tpTable.sim_sector_id == s, :);
    S = sortrows(S, 'timestamp');
    flag = S.predicted_dl_prb_utilization_1h >= vcfg.tpOverloadPrbThreshold;
    if ~any(flag)
        continue;
    end

    idx = find(flag);
    starts = idx([true; minutes(S.timestamp(idx(2:end)) - S.timestamp(idx(1:end-1))) > ...
        vcfg.expectedGranularityMinutes]);
    ends = idx([minutes(S.timestamp(idx(2:end)) - S.timestamp(idx(1:end-1))) > ...
        vcfg.expectedGranularityMinutes; true]);

    for k = 1:numel(starts)
        G = S(starts(k):ends(k), :);
        [maxPrb, peakLocalIdx] = max(G.predicted_dl_prb_utilization_1h);
        peakTs = G.timestamp(peakLocalIdx);
        actualAtPeak = G.actual_dl_prb_utilization_1h(peakLocalIdx);
        firstTs = G.timestamp(1);
        lastTs = G.timestamp(end);
        intervalCount = height(G);
        durationMinutes = intervalCount * vcfg.expectedGranularityMinutes;
        meanPrb = mean(G.predicted_dl_prb_utilization_1h, 'omitnan');
        maxUsers = max(G.predicted_active_users_1h, [], 'omitnan');
        perf = lookup_performance(performanceTable, s);
        codBlocked = has_cod_incident(codTable, s, firstTs, lastTs);
        action = recommend_action(maxPrb, codBlocked);
        displayCell = sprintf('S%d | cell %s', s, char(string(G.cell_uid(1))));
        proof = sprintf(['%s predicted DL PRB above %.0f%% from %s to %s; peak %s: ' ...
            'predicted %.1f%%, actual +1h %.1f%%; MAE %.1f%%, R2 %.2f'], ...
            displayCell, 100 * vcfg.tpOverloadPrbThreshold, ...
            datestr(firstTs, 'dd-mmm HH:MM'), datestr(lastTs, 'dd-mmm HH:MM'), ...
            datestr(peakTs, 'dd-mmm HH:MM'), 100 * maxPrb, 100 * actualAtPeak, ...
            100 * perf.mae, perf.r2);

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = {compose('S%d', s), s, char(string(G.cell_uid(1))), ...
            G.cell_id(1), char(string(G.vendor_cell_name(1))), displayCell, ...
            firstTs, lastTs, peakTs, intervalCount, durationMinutes, maxPrb, ...
            actualAtPeak, meanPrb, maxUsers, perf.mae, perf.r2, char(action), char(proof)};
    end
end

if rowIdx == 0
    episodes = empty_episode_table();
    return;
end

episodes = cell2table(rows(1:rowIdx, :), 'VariableNames', episode_columns());
episodes = sortrows(episodes, {'interval_count','max_predicted_dl_prb'}, {'descend','descend'});
end

function T = empty_episode_table()
T = table('Size', [0 numel(episode_columns())], ...
    'VariableTypes', {'cell','double','cell','double','cell','cell','datetime', ...
    'datetime','datetime','double','double','double','double','double','double', ...
    'double','double','cell','cell'}, ...
    'VariableNames', episode_columns());
end

function names = episode_columns()
names = {'affected_sector','sim_sector_id','cell_uid','cell_id','vendor_cell_name', ...
    'display_cell','first_timestamp','last_timestamp','peak_timestamp', ...
    'interval_count','duration_minutes','max_predicted_dl_prb', ...
    'actual_dl_prb_at_peak_1h','mean_predicted_dl_prb', ...
    'max_predicted_active_users','mae_dl_prb_1h','r2_dl_prb_1h', ...
    'recommended_tp_action','proof_summary'};
end

function perf = lookup_performance(performanceTable, sectorId)
perf = struct('mae', NaN, 'r2', NaN);
if isempty(performanceTable)
    return;
end
idx = find(performanceTable.sim_sector_id == sectorId, 1, 'first');
if isempty(idx)
    return;
end
perf.mae = performanceTable.mae_dl_prb_1h(idx);
perf.r2 = performanceTable.r2_dl_prb_1h(idx);
end

function action = recommend_action(maxPrb, codBlocked)
if codBlocked
    action = "blocked_by_cod_incident_first";
elseif maxPrb >= 0.90
    action = "high_overload_risk_review_LB_or_capacity_help";
else
    action = "moderate_overload_risk_monitor";
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
