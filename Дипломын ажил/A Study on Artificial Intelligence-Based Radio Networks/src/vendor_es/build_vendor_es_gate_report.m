function gateReport = build_vendor_es_gate_report(esTable, vcfg)
%BUILD_VENDOR_ES_GATE_REPORT Explain ES gate pass/fail behavior by sector.

gateReport = table();
if isempty(esTable)
    return;
end

[groups, sector, cellUid, displayCell] = findgroups(esTable.sim_sector_id, ...
    string(esTable.cell_uid), string(esTable.display_cell));
nGroups = max(groups);
rows = cell(nGroups, 20);

for i = 1:nGroups
    G = esTable(groups == i, :);
    [minScore, minIdx] = min(G.es_gate_score);
    totalRows = height(G);
    prbRows = sum(logical(G.low_prb_gate));
    userRows = sum(logical(G.low_users_gate));
    trafficRows = sum(logical(G.low_traffic_gate));
    instantRows = sum(logical(G.instant_low_load_gate));
    maxConsecutive = max(G.consecutive_low_load_count, [], 'omitnan');
    consecutiveRows = sum(logical(G.low_load_consecutive_flag));
    candidateRows = sum(strcmp(string(G.es_decision), "sleep_candidate_manual_review"));
    codBlocked = sum(strcmp(string(G.es_decision), "blocked_by_cod"));
    siteBlocked = sum(strcmp(string(G.es_decision), "blocked_by_site_incident"));
    neighborBlocked = sum(strcmp(string(G.es_decision), "blocked_neighbor_load"));
    closestTimestamp = G.timestamp(minIdx);
    mainReason = classify_sector_reason(candidateRows, maxConsecutive, instantRows, codBlocked, ...
        siteBlocked, neighborBlocked, vcfg);
    proof = sprintf(['%s ES gate summary: PRB pass %d/%d, users pass %d/%d, traffic pass %d/%d, ' ...
        'instant all-gate pass %d, max consecutive low-load %d/%d intervals, sleep candidates %d.'], ...
        string(displayCell(i)), prbRows, totalRows, userRows, totalRows, trafficRows, totalRows, ...
        instantRows, maxConsecutive, vcfg.esMinConsecutiveLowLoadSteps, candidateRows);

    rows(i, :) = {compose('S%d', sector(i)), sector(i), char(cellUid(i)), char(displayCell(i)), ...
        totalRows, prbRows, userRows, trafficRows, instantRows, maxConsecutive, ...
        maxConsecutive * vcfg.expectedGranularityMinutes, consecutiveRows, candidateRows, ...
        codBlocked, siteBlocked, neighborBlocked, minScore, closestTimestamp, ...
        char(mainReason), char(proof)};
end

gateReport = cell2table(rows, 'VariableNames', {'affected_sector','sim_sector_id', ...
    'cell_uid','display_cell','total_rows','low_prb_rows','low_users_rows', ...
    'low_traffic_rows','instant_low_load_rows','max_consecutive_low_load_count', ...
    'max_consecutive_low_load_minutes','consecutive_low_load_rows','sleep_candidate_rows', ...
    'cod_blocked_rows','site_incident_blocked_rows','neighbor_load_blocked_rows', ...
    'best_es_gate_score','closest_low_load_timestamp','main_block_reason','proof_summary'});
gateReport = sortrows(gateReport, {'sleep_candidate_rows','max_consecutive_low_load_count', ...
    'best_es_gate_score'}, {'descend','descend','ascend'});
end

function reason = classify_sector_reason(candidateRows, maxConsecutive, instantRows, codBlocked, ...
    siteBlocked, neighborBlocked, vcfg)
if candidateRows > 0
    reason = "sleep_candidate_manual_review";
elseif maxConsecutive < vcfg.esMinConsecutiveLowLoadSteps
    if instantRows > 0
        reason = "instant_low_load_seen_but_not_consecutive";
    else
        reason = "low_load_gate_not_satisfied";
    end
elseif codBlocked > 0
    reason = "blocked_by_cod";
elseif siteBlocked > 0
    reason = "blocked_by_site_incident";
elseif neighborBlocked > 0
    reason = "blocked_neighbor_load";
else
    reason = "not_es_candidate";
end
end
