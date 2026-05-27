function esTable = suggest_es_from_vendor_kpi(tpTable, codTable, vcfg)
%SUGGEST_ES_FROM_VENDOR_KPI Conservative ES advisory from predicted load.
%
% ES is last priority. It is blocked when COD marks the cell abnormal or
% when a multi-sector/site-level incident is active at the same timestamp.

esTable = table();
if isempty(tpTable)
    return;
end

T = sortrows(tpTable, {'sim_sector_id','timestamp'});
siteIncident = build_site_incident_table(codTable);

rows = cell(height(T), 30);
rowIdx = 0;
sectors = unique(T.sim_sector_id);
for s = sectors(:)'
    S = T(T.sim_sector_id == s, :);
    lowPrb = S.predicted_dl_prb_utilization_1h <= vcfg.esLowPredictedDlPrbThreshold;
    lowUsers = S.predicted_active_users_1h <= vcfg.esLowActiveUsersThreshold;
    lowTraffic = S.predicted_traffic_volume_dl_kbyte_1h <= vcfg.esLowTrafficDlKbyteThreshold;
    lowBase = lowPrb & lowUsers & lowTraffic;
    consecutiveCount = consecutive_true_count(lowBase, S.timestamp, vcfg.expectedGranularityMinutes);
    consecutiveLow = consecutiveCount >= vcfg.esMinConsecutiveLowLoadSteps;
    gateScore = max([safe_ratio(S.predicted_dl_prb_utilization_1h, vcfg.esLowPredictedDlPrbThreshold), ...
        safe_ratio(S.predicted_active_users_1h, vcfg.esLowActiveUsersThreshold), ...
        safe_ratio(S.predicted_traffic_volume_dl_kbyte_1h, vcfg.esLowTrafficDlKbyteThreshold)], [], 2);

    for i = 1:height(S)
        codState = lookup_cod_state(codTable, S.timestamp(i), S.sim_sector_id(i));
        siteIsIncident = lookup_site_incident(siteIncident, S.timestamp(i), S.sim_site_id(i));
        [safeNeighborLoad, minNeighborPrb] = estimate_safe_neighbor_load(tpTable, ...
            S.timestamp(i), S.sim_site_id(i), vcfg);

        if ~consecutiveLow(i)
            decision = "not_es_candidate";
            reason = build_low_load_rejection_reason(lowPrb(i), lowUsers(i), lowTraffic(i), ...
                consecutiveCount(i), vcfg);
        elseif codState ~= "normal"
            decision = "blocked_by_cod";
            reason = "cell is degraded/outage-like; ES must not reduce service during impairment";
        elseif siteIsIncident
            decision = "blocked_by_site_incident";
            reason = "site-level incident active; ES is lower priority than outage handling";
        elseif ~safeNeighborLoad
            decision = "blocked_neighbor_load";
            reason = "neighbor/load safety not sufficient for sleep review";
        else
            decision = "sleep_candidate_manual_review";
            reason = "low predicted load with normal COD state and safe neighbor-load proxy";
        end
        displayCell = sprintf('S%d | cell %s', S.sim_sector_id(i), char(string(S.cell_uid(i))));
        action = recommended_action(decision);
        proof = build_es_proof(displayCell, S.timestamp(i), S.predicted_dl_prb_utilization_1h(i), ...
            S.predicted_active_users_1h(i), S.predicted_traffic_volume_dl_kbyte_1h(i), ...
            consecutiveCount(i), codState, safeNeighborLoad, minNeighborPrb, decision, reason, vcfg);

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = {S.timestamp(i), S.sim_site_id(i), char(string(S.sim_position(i))), ...
            S.sim_sector_id(i), char(string(S.vendor_site_key(i))), char(string(S.cell_uid(i))), ...
            S.cell_id(i), char(string(S.vendor_cell_name(i))), sprintf('S%d', S.sim_sector_id(i)), ...
            displayCell, char(codState), ...
            S.predicted_dl_prb_utilization_1h(i), S.predicted_active_users_1h(i), ...
            S.predicted_traffic_volume_dl_kbyte_1h(i), lowPrb(i), lowUsers(i), ...
            lowTraffic(i), lowBase(i), consecutiveCount(i), ...
            consecutiveCount(i) * vcfg.expectedGranularityMinutes, consecutiveLow(i), ...
            siteIsIncident, safeNeighborLoad, minNeighborPrb, gateScore(i), ...
            char(decision), char(action), char(reason), char(proof), ...
            'Advisory only: no real sleep action applied'};
    end
end

esTable = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
    {'timestamp','sim_site_id','sim_position','sim_sector_id','vendor_site_key', ...
    'cell_uid','cell_id','vendor_cell_name','affected_sector','display_cell','cod_state', ...
    'predicted_dl_prb_utilization_1h','predicted_active_users_1h', ...
    'predicted_traffic_volume_dl_kbyte_1h','low_prb_gate','low_users_gate', ...
    'low_traffic_gate','instant_low_load_gate','consecutive_low_load_count', ...
    'consecutive_low_load_minutes','low_load_consecutive_flag', ...
    'site_incident_active','neighbor_load_safe_proxy','min_neighbor_predicted_dl_prb', ...
    'es_gate_score','es_decision','recommended_es_action', ...
    'decision_reason','proof_summary','claim_boundary'});
end

function counts = consecutive_true_count(flag, timestamp, granularityMinutes)
counts = zeros(size(flag));
for i = 1:numel(flag)
    if ~flag(i)
        counts(i) = 0;
    elseif i == 1 || ~flag(i-1) || minutes(timestamp(i) - timestamp(i-1)) ~= granularityMinutes
        counts(i) = 1;
    else
        counts(i) = counts(i-1) + 1;
    end
end
end

function ratio = safe_ratio(value, threshold)
if threshold <= 0
    ratio = inf(size(value));
else
    ratio = value ./ threshold;
end
ratio(~isfinite(ratio)) = inf;
end

function state = lookup_cod_state(codTable, timestamp, sectorId)
mask = codTable.timestamp == timestamp & codTable.sim_sector_id == sectorId;
if any(mask)
    state = string(codTable.cod_state{find(mask, 1, 'first')});
else
    state = "missing_cod";
end
end

function siteIncident = build_site_incident_table(codTable)
if isempty(codTable)
    siteIncident = table();
    return;
end
[groups, ts, site] = findgroups(codTable.timestamp, codTable.sim_site_id);
outCount = splitapply(@(x) sum(strcmp(string(x), 'outage_like')), codTable.cod_state, groups);
abnormalCount = splitapply(@(x) sum(ismember(string(x), ["outage_like","degraded_kpi"])), codTable.cod_state, groups);
cellCount = splitapply(@numel, codTable.cod_state, groups);
siteIncident = table(ts, site, outCount >= 2 | abnormalCount >= min(cellCount, 3), ...
    'VariableNames', {'timestamp','sim_site_id','site_incident_active'});
end

function tf = lookup_site_incident(siteIncident, timestamp, siteId)
if isempty(siteIncident)
    tf = false;
    return;
end
mask = siteIncident.timestamp == timestamp & siteIncident.sim_site_id == siteId;
tf = any(siteIncident.site_incident_active(mask));
end

function [tf, minLoad] = estimate_safe_neighbor_load(tpTable, timestamp, sourceSiteId, vcfg)
sameTime = tpTable(tpTable.timestamp == timestamp & tpTable.sim_site_id ~= sourceSiteId, :);
if isempty(sameTime)
    tf = false;
    minLoad = NaN;
else
    minLoad = min(sameTime.predicted_dl_prb_utilization_1h, [], 'omitnan');
    tf = any(sameTime.predicted_dl_prb_utilization_1h <= vcfg.esNeighborLoadSafeThreshold);
end
end

function reason = build_low_load_rejection_reason(lowPrb, lowUsers, lowTraffic, consecutiveCount, vcfg)
missing = strings(0, 1);
if ~lowPrb, missing(end+1) = "PRB not low"; end %#ok<AGROW>
if ~lowUsers, missing(end+1) = "active users not low"; end %#ok<AGROW>
if ~lowTraffic, missing(end+1) = "traffic not low"; end %#ok<AGROW>
if consecutiveCount < vcfg.esMinConsecutiveLowLoadSteps
    missing(end+1) = sprintf('only %d/%d consecutive low-load intervals', ...
        consecutiveCount, vcfg.esMinConsecutiveLowLoadSteps); %#ok<AGROW>
end
reason = strjoin(missing, '|');
end

function action = recommended_action(decision)
switch string(decision)
    case "sleep_candidate_manual_review"
        action = "manual_sleep_review_only";
    case "blocked_by_cod"
        action = "do_not_sleep_resolve_cod_first";
    case "blocked_by_site_incident"
        action = "do_not_sleep_site_incident_active";
    case "blocked_neighbor_load"
        action = "do_not_sleep_neighbor_load_not_safe";
    otherwise
        action = "no_sleep_action";
end
end

function proof = build_es_proof(displayCell, timestamp, predPrb, predUsers, predTraffic, ...
    consecutiveCount, codState, safeNeighborLoad, minNeighborPrb, decision, reason, vcfg)
if isfinite(minNeighborPrb)
    neighborText = sprintf('min other-site predicted PRB %.1f%%', 100 * minNeighborPrb);
else
    neighborText = 'neighbor load proxy unavailable';
end
proof = sprintf(['%s at %s: predicted PRB %.1f%%, users %.2f, DL traffic %.0f kbyte; ' ...
    'low-load run %d/%d intervals; COD=%s; neighbor safe=%d (%s); decision=%s; reason=%s'], ...
    displayCell, datestr(timestamp, 'dd-mmm HH:MM'), 100 * predPrb, predUsers, predTraffic, ...
    consecutiveCount, vcfg.esMinConsecutiveLowLoadSteps, string(codState), safeNeighborLoad, ...
    neighborText, string(decision), string(reason));
end
