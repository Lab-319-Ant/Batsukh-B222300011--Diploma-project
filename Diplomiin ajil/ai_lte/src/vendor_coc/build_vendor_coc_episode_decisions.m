function [episodeSummary, decisionTable] = build_vendor_coc_episode_decisions(codTable, cocMlRanking, cocMlSelected, vcfg)
%BUILD_VENDOR_COC_EPISODE_DECISIONS Timestamp-level COD/COC episode audit.

episodeSummary = table();
decisionTable = table();
if isempty(codTable)
    return;
end

abnormal = codTable(~strcmp(string(codTable.cod_state), "normal"), :);
if isempty(abnormal)
    return;
end

tsSummary = build_timestamp_summary(abnormal, vcfg);
episodeSummary = build_episode_summary(tsSummary, cocMlSelected);
decisionTable = build_decision_table(tsSummary, cocMlRanking, cocMlSelected);
end

function tsSummary = build_timestamp_summary(abnormal, vcfg)
[groups, ts] = findgroups(abnormal.timestamp);
n = max(groups);
rows = cell(n, 8);
for i = 1:n
    G = abnormal(groups == i, :);
    sectors = sort(unique(G.sim_sector_id));
    sites = sort(unique(G.sim_site_id));
    rows(i, :) = {ts(i), numel(sites), height(G), ...
        char(strjoin(compose('Site %d', sites), ' + ')), ...
        char(strjoin(compose('S%d', sectors), ', ')), ...
        char(strjoin(build_sector_cell_labels(G), ', ')), ...
        sum(strcmp(string(G.cod_state), "outage_like")), ...
        sum(strcmp(string(G.cod_state), "degraded_kpi"))};
end
tsSummary = cell2table(rows, 'VariableNames', {'timestamp','affected_site_count', ...
    'affected_sector_count','affected_sites','affected_sectors', ...
    'affected_sector_cells','outage_like_count','degraded_count'});
tsSummary = sortrows(tsSummary, 'timestamp');

episodeId = zeros(height(tsSummary), 1);
currentEpisode = 1;
for i = 1:height(tsSummary)
    if i > 1 && minutes(tsSummary.timestamp(i) - tsSummary.timestamp(i-1)) > ...
            vcfg.expectedGranularityMinutes
        currentEpisode = currentEpisode + 1;
    end
    episodeId(i) = currentEpisode;
end
tsSummary.episode_id = episodeId;
end

function episodeSummary = build_episode_summary(tsSummary, cocMlSelected)
episodeIds = unique(tsSummary.episode_id);
rows = cell(numel(episodeIds), 13);
for i = 1:numel(episodeIds)
    eid = episodeIds(i);
    E = tsSummary(tsSummary.episode_id == eid, :);
    firstTs = E.timestamp(1);
    lastTs = E.timestamp(end);
    selectedRows = table();
    if ~isempty(cocMlSelected)
        selectedRows = cocMlSelected(cocMlSelected.timestamp >= firstTs & ...
            cocMlSelected.timestamp <= lastTs, :);
    end
    selectedComp = selectedRows(strcmp(string(selectedRows.action_type), "compensate_neighbor"), :);
    noOpRows = selectedRows(strcmp(string(selectedRows.action_type), "no_op"), :);
    if isempty(selectedComp)
        selectedTargets = "";
    else
        selectedTargets = strjoin(compose('S%d', sort(unique(selectedComp.target_sim_sector_id))), ', ');
    end
    allAffectedSectors = strings(0, 1);
    allAffectedSectorCells = strings(0, 1);
    allAffectedSites = strings(0, 1);
    for k = 1:height(E)
        allAffectedSectors = [allAffectedSectors; split(string(E.affected_sectors{k}), ', ')]; %#ok<AGROW>
        allAffectedSectorCells = [allAffectedSectorCells; split(string(E.affected_sector_cells{k}), ', ')]; %#ok<AGROW>
        allAffectedSites = [allAffectedSites; split(string(E.affected_sites{k}), ' + ')]; %#ok<AGROW>
    end
    allAffectedSectors = unique(allAffectedSectors(allAffectedSectors ~= ""));
    allAffectedSectorCells = unique(allAffectedSectorCells(allAffectedSectorCells ~= ""));
    allAffectedSites = unique(allAffectedSites(allAffectedSites ~= ""));
    rows(i, :) = {eid, firstTs, lastTs, height(E), ...
        minutes(lastTs - firstTs) + 15, max(E.affected_sector_count), ...
        char(strjoin(allAffectedSites, ' + ')), char(strjoin(allAffectedSectors, ', ')), ...
        char(strjoin(allAffectedSectorCells, ', ')), ...
        height(selectedComp), height(noOpRows), char(selectedTargets), ...
        char(build_episode_note(height(selectedComp), height(noOpRows)))};
end
episodeSummary = cell2table(rows, 'VariableNames', {'episode_id','first_timestamp', ...
    'last_timestamp','timestamp_count','duration_minutes','max_affected_sector_count', ...
    'affected_sites','affected_sectors','affected_sector_cells','selected_compensation_rows', ...
    'selected_no_op_rows','selected_targets','episode_note'});
episodeSummary = sortrows(episodeSummary, {'max_affected_sector_count','selected_compensation_rows', ...
    'duration_minutes'}, {'descend','descend','descend'});
end

function note = build_episode_note(selectedCompRows, noOpRows)
if selectedCompRows > 0
    note = "COC compensation selected at some timestamps; no-op where safety gate rejects target load.";
elseif noOpRows > 0
    note = "COD incident detected but COC selected no-op after ML/safety checks.";
else
    note = "COD incident detected; no COC ML rows available.";
end
end

function decisionTable = build_decision_table(tsSummary, cocMlRanking, cocMlSelected)
rows = cell(max(1, height(tsSummary) * 12), 19);
rowIdx = 0;
for i = 1:height(tsSummary)
    ts = tsSummary.timestamp(i);
    rankingRows = table();
    selectedRows = table();
    if ~isempty(cocMlRanking)
        rankingRows = cocMlRanking(cocMlRanking.timestamp == ts & ...
            strcmp(string(cocMlRanking.action_type), "compensate_neighbor") & ...
            isfinite(cocMlRanking.target_sim_sector_id), :);
    end
    if ~isempty(cocMlSelected)
        selectedRows = cocMlSelected(cocMlSelected.timestamp == ts, :);
    end

    targets = sort(unique(rankingRows.target_sim_sector_id));
    for t = targets(:)'
        G = rankingRows(rankingRows.target_sim_sector_id == t, :);
        selectedCount = sum(logical(G.ml_selected));
        safeCount = sum(strcmp(string(G.target_overload_safety_status), "target_load_headroom_ok"));
        rejectedCount = height(G) - safeCount;
        if selectedCount > 0
            decision = "selected_compensation";
        elseif safeCount > 0
            decision = "safe_not_selected";
        else
            decision = "rejected_projected_overload";
        end
        rowIdx = rowIdx + 1;
        rows = grow_rows_if_needed(rows, rowIdx);
        rows(rowIdx, :) = {tsSummary.episode_id(i), ts, tsSummary.affected_sector_count(i), ...
            tsSummary.affected_sites{i}, tsSummary.affected_sectors{i}, ...
            tsSummary.affected_sector_cells{i}, format_target_label(t, G), ...
            char(first_string(G.target_cell_uid)), t, ...
            safeCount, rejectedCount, selectedCount, ...
            mean(G.target_sector_load, 'omitnan'), ...
            mean(G.estimated_absorbed_load_proxy, 'omitnan'), ...
            mean(G.estimated_target_load_after_coc, 'omitnan'), ...
            mean(G.target_active_users, 'omitnan'), ...
            mean(G.estimated_target_users_after_coc, 'omitnan'), ...
            char(decision), char(build_decision_note(decision))};
    end

    noOpCount = 0;
    if ~isempty(selectedRows)
        noOpCount = sum(strcmp(string(selectedRows.action_type), "no_op"));
    end
    if noOpCount > 0
        rowIdx = rowIdx + 1;
        rows = grow_rows_if_needed(rows, rowIdx);
        rows(rowIdx, :) = {tsSummary.episode_id(i), ts, tsSummary.affected_sector_count(i), ...
            tsSummary.affected_sites{i}, tsSummary.affected_sectors{i}, ...
            tsSummary.affected_sector_cells{i}, 'no-op', '', NaN, ...
            0, 0, noOpCount, NaN, NaN, NaN, NaN, NaN, ...
            'selected_no_op', 'ML/safety selected no-op for affected source rows'};
    end
end

if rowIdx == 0
    decisionTable = table();
else
    decisionTable = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
        {'episode_id','timestamp','affected_sector_count','affected_sites', ...
        'affected_sectors','affected_sector_cells','target_label','target_cell_uid', ...
        'target_sim_sector_id','safe_candidate_rows', ...
        'rejected_candidate_rows','selected_rows','mean_target_prb', ...
        'mean_estimated_absorbed_load','mean_estimated_target_prb_after_coc', ...
        'mean_target_active_users','mean_estimated_target_users_after_coc', ...
        'decision','decision_note'});
end
end

function labels = build_sector_cell_labels(G)
sectorIds = sort(unique(G.sim_sector_id));
labels = strings(numel(sectorIds), 1);
for i = 1:numel(sectorIds)
    sid = sectorIds(i);
    R = G(G.sim_sector_id == sid, :);
    labels(i) = sprintf('S%d | cell %s', sid, string(R.cell_uid{1}));
end
end

function label = format_target_label(targetSectorId, G)
cellUid = first_string(G.target_cell_uid);
if cellUid == ""
    label = sprintf('S%d', targetSectorId);
else
    label = sprintf('S%d | cell %s', targetSectorId, cellUid);
end
end

function value = first_string(values)
values = string(values);
values = values(values ~= "" & values ~= "<missing>");
if isempty(values)
    value = "";
else
    value = values(1);
end
end

function note = build_decision_note(decision)
switch string(decision)
    case "selected_compensation"
        note = "ML selected this target after target load/headroom safety.";
    case "safe_not_selected"
        note = "Target was safe at this timestamp but ML chose another action/target.";
    case "rejected_projected_overload"
        note = "Rejected because estimated post-COC target load exceeded safety headroom.";
    otherwise
        note = "No decision note.";
end
end

function rows = grow_rows_if_needed(rows, rowIdx)
if rowIdx <= size(rows, 1)
    return;
end
rows = [rows; cell(size(rows, 1), size(rows, 2))]; %#ok<AGROW>
end
