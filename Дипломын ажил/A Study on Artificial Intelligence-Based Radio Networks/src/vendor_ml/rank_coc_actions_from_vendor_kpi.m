function [ranking, selected] = rank_coc_actions_from_vendor_kpi(codTable, vcfg)
%RANK_COC_ACTIONS_FROM_VENDOR_KPI Rank KPI-only COC candidates with ML.
%
% The saved COC/OH action-value model was trained on RF-simulation
% counterfactual rewards. This adapter maps vendor KPI rows to the same
% feature schema using explicit proxies where real RF features are missing.
% The output is advisory only: predicted_reward is not a measured real
% before/after improvement.

ranking = table();
selected = table();
if isempty(codTable) || ~getfield_or_default(vcfg, 'vendorCocMlEnabled', true)
    return;
end
if ~isfile(vcfg.vendorCocModelFile)
    warning('Vendor COC ML model file missing: %s', vcfg.vendorCocModelFile);
    return;
end

S = load(vcfg.vendorCocModelFile);
model = S.model;
inputFeatures = S.inputFeatures;

badMask = ismember(string(codTable.cod_state), ["outage_like", "degraded_kpi"]);
badRows = codTable(badMask, :);
if isempty(badRows)
    return;
end

siteOutage = detect_site_outage(codTable);
baseline = build_coc_baseline(codTable);
maxRows = height(badRows) * (1 + vcfg.vendorCocMlTopTargets * ...
    numel(vcfg.vendorCocMlDeltaRsPowerDb) * numel(vcfg.vendorCocMlDeltaTiltDeg) * ...
    numel(vcfg.vendorCocMlDeltaCioDb));
rows = cell(maxRows, 50);
rowIdx = 0;

for i = 1:height(badRows)
    src = badRows(i, :);
    sameTime = codTable(codTable.timestamp == src.timestamp, :);
    sameTimeBad = sameTime(ismember(string(sameTime.cod_state), ["outage_like","degraded_kpi"]), :);
    impact = estimate_compensation_impact(sameTimeBad, baseline, vcfg);
    sourceEventId = sprintf('%s|S%d', datestr(src.timestamp, 'yyyy-mm-dd HH:MM:SS'), src.sim_sector_id);
    sameSiteOut = is_site_outage(siteOutage, src.timestamp, src.sim_site_id);
    siteLevelIssue = sameSiteOut;

    targetCandidates = sameTime(sameTime.sim_site_id ~= src.sim_site_id & ...
        strcmp(string(sameTime.cod_state), 'normal') & ...
        sameTime.cell_availability >= vcfg.cocMinAvailabilityForTarget & ...
        sameTime.dl_prb_utilization <= vcfg.cocNeighborLoadSafeThreshold & ...
        sameTime.erab_drop_rate <= vcfg.cocMaxDropRateForTarget & ...
        sameTime.rrc_drop_rate <= vcfg.codRrcDropHighThreshold, :);
    if ~isempty(targetCandidates)
        targetCandidates = sortrows(targetCandidates, {'dl_prb_utilization','erab_drop_rate'});
        keepN = min(height(targetCandidates), vcfg.vendorCocMlTopTargets);
        targetCandidates = targetCandidates(1:keepN, :);
    end

    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = build_candidate_row(src, table(), impact, vcfg, sourceEventId, ...
        model.modelType, siteLevelIssue, 'no_op', 0, 0, 0, true);

    for t = 1:height(targetCandidates)
        target = targetCandidates(t, :);
        for prs = vcfg.vendorCocMlDeltaRsPowerDb
            for tilt = vcfg.vendorCocMlDeltaTiltDeg
                for cio = vcfg.vendorCocMlDeltaCioDb
                    if prs == 0 && tilt == 0 && cio == 0
                        continue;
                    end
                    if vcfg.defaultRsPowerDbm + prs > vcfg.maxRsPowerDbm
                        continue;
                    end
                    if vcfg.defaultElectricalTiltDeg + tilt < vcfg.minElectricalTiltDeg || ...
                            vcfg.defaultElectricalTiltDeg + tilt > vcfg.maxElectricalTiltDeg
                        continue;
                    end
                    rowIdx = rowIdx + 1;
                    rows(rowIdx, :) = build_candidate_row(src, target, impact, vcfg, sourceEventId, ...
                        model.modelType, siteLevelIssue, 'compensate_neighbor', prs, tilt, cio, false);
                end
            end
        end
    end
end

ranking = cell2table(rows(1:rowIdx, :), 'VariableNames', output_columns());
X = ranking(:, inputFeatures);
switch model.modelType
    case 'LSBoost'
        ranking.predicted_reward = double(predict(model.model, X));
    case 'TreeBagger'
        ranking.predicted_reward = double(predict(model.model, table2array(X)));
    otherwise
        error('Unsupported COC action-value model type: %s', model.modelType);
end

ranking = add_event_ranks(ranking);
selected = ranking(ranking.ml_selected, :);
end

function row = build_candidate_row(src, target, impact, vcfg, sourceEventId, modelName, siteLevelIssue, ...
    actionType, deltaPrs, deltaTilt, deltaCio, isNoOp)
sourceLoad = clamp01(src.dl_prb_utilization);
sourceRsrpProxy = estimate_rsrp_proxy(src.rssi_avg_dbm);
sourceSinrProxy = estimate_sinr_proxy(src);
sourceQos = estimate_qos_ratio(src);
sourceHoRisk = estimate_handover_risk(src);
sourceAttach = clamp01(src.rrc_setup_success_rate);
sourceUsers = read_row_number(src, 'active_users', NaN);

if isempty(target)
    targetSector = NaN;
    targetUid = "";
    targetSite = "";
    targetLoad = sourceLoad;
    targetUsers = NaN;
    targetTraffic = NaN;
    targetAvailability = NaN;
    targetDrop = NaN;
    projectedTargetLoad = NaN;
    projectedTargetUsers = NaN;
    targetLoadHeadroom = NaN;
    overloadSafetyStatus = "no_op_baseline";
else
    targetSector = target.sim_sector_id;
    targetUid = string(target.cell_uid);
    targetSite = string(target.vendor_site_key);
    targetLoad = clamp01(target.dl_prb_utilization);
    targetUsers = read_row_number(target, 'active_users', NaN);
    targetTraffic = read_row_number(target, 'traffic_volume_dl_kbyte', NaN);
    targetAvailability = target.cell_availability;
    targetDrop = target.erab_drop_rate;
    projectedTargetLoad = clamp01(targetLoad + impact.loadToAbsorb);
    projectedTargetUsers = targetUsers + impact.usersToAbsorb;
    targetLoadHeadroom = max(0, vcfg.cocNeighborLoadHardRejectThreshold - targetLoad);
    if targetLoad > vcfg.cocNeighborLoadSafeThreshold
        overloadSafetyStatus = "target_current_load_not_safe";
    elseif projectedTargetLoad > vcfg.cocNeighborLoadHardRejectThreshold
        overloadSafetyStatus = "projected_target_overload_reject";
    else
        overloadSafetyStatus = "target_load_headroom_ok";
    end
end

if isNoOp
    suggestedRsPower = NaN;
    suggestedTilt = NaN;
    safetyStatus = "no_op_baseline";
    suggestion = "no RF parameter change";
    engineeringAllowed = true;
    engineeringNote = "no-op baseline";
else
    suggestedRsPower = vcfg.defaultRsPowerDbm + deltaPrs;
    suggestedTilt = vcfg.defaultElectricalTiltDeg + deltaTilt;
    if siteLevelIssue
        safetyStatus = "site_outage_coc_ml_advisory";
    else
        safetyStatus = "candidate_for_manual_review";
    end
    suggestion = sprintf('ML-ranked COC target S%d: %+g dB RS power, %+g deg electrical tilt', ...
        targetSector, deltaPrs, deltaTilt);
    targetCapacitySafe = overloadSafetyStatus == "target_load_headroom_ok";
    engineeringAllowed = deltaPrs <= vcfg.vendorCocMlMaxSelectedRsPowerDeltaDb && targetCapacitySafe;
    if deltaPrs > 3
        engineeringNote = "+6 dB is extrapolated beyond the original RF-simulation COC training action range";
    elseif ~targetCapacitySafe
        engineeringNote = "rejected: estimated post-COC target PRB would exceed safety headroom";
    elseif engineeringAllowed
        engineeringNote = "within KPI-only COC advisory action range with target load headroom check";
    else
        engineeringNote = "ranked but not selected by KPI-only COC safety cap";
    end
end

row = {char(sourceEventId), src.timestamp, src.sim_site_id, char(string(src.sim_position)), ...
    src.sim_sector_id, char(string(src.vendor_site_key)), char(string(src.cell_uid)), ...
    src.cell_id, char(string(src.vendor_cell_name)), char(string(src.cod_state)), ...
    char(string(src.cod_reason)), targetSector, char(targetSite), char(targetUid), ...
    char(actionType), deltaPrs, deltaTilt, deltaCio, logical(isNoOp), ...
    sourceLoad, targetLoad, sourceRsrpProxy, sourceSinrProxy, sourceQos, ...
    sourceHoRisk, sourceAttach, sourceUsers, targetUsers, targetTraffic, ...
    impact.loadToAbsorb, impact.usersToAbsorb, projectedTargetLoad, projectedTargetUsers, ...
    targetLoadHeadroom, char(overloadSafetyStatus), vcfg.defaultRsPowerDbm, ...
    vcfg.defaultElectricalTiltDeg, suggestedRsPower, suggestedTilt, ...
    targetAvailability, targetDrop, char(safetyStatus), char(modelName), ...
    char(vcfg.vendorRsrpProxyMethod), char(vcfg.vendorSinrProxyMethod), ...
    char(vcfg.vendorConfigSource), char(suggestion), ...
    'simulation-trained action-value estimate; not observed real KPI after-action', ...
    logical(engineeringAllowed), char(engineeringNote)};
end

function names = output_columns()
names = {'source_event_id','timestamp','sim_site_id','sim_position', ...
    'source_sim_sector_id','source_vendor_site_key','source_cell_uid', ...
    'source_cell_id','source_cell_name','cod_state','cod_reason', ...
    'target_sim_sector_id','target_vendor_site_key','target_cell_uid', ...
    'action_type','delta_prs_dB','delta_tilt_deg','delta_cio_dB','is_no_op', ...
    'source_sector_load','target_sector_load','source_mean_RSRP_dBm', ...
    'source_mean_SINR_dB','source_qos_satisfaction_ratio', ...
    'source_handover_risk_score','source_attach_rate_sector', ...
    'source_active_users','target_active_users','target_traffic_volume_dl_kbyte', ...
    'estimated_absorbed_load_proxy','estimated_absorbed_users_proxy', ...
    'estimated_target_load_after_coc','estimated_target_users_after_coc', ...
    'target_load_headroom_to_hard_limit','target_overload_safety_status', ...
    'current_target_rs_power_dbm','current_target_electrical_tilt_deg', ...
    'suggested_target_rs_power_dbm','suggested_target_electrical_tilt_deg', ...
    'target_cell_availability','target_erab_drop_rate','ml_safety_status', ...
    'model_name','rsrp_proxy_method','sinr_proxy_method','config_source', ...
    'parameter_suggestion','prediction_claim','engineering_selection_allowed', ...
    'engineering_selection_note'};
end

function baseline = build_coc_baseline(T)
keys = unique(string(T.cell_uid), 'stable');
loadMedian = nan(numel(keys), 1);
userMedian = nan(numel(keys), 1);
trafficMedian = nan(numel(keys), 1);
for i = 1:numel(keys)
    G = T(string(T.cell_uid) == keys(i) & strcmp(string(T.cod_state), "normal"), :);
    if isempty(G)
        G = T(string(T.cell_uid) == keys(i), :);
    end
    loadMedian(i) = median(G.dl_prb_utilization, 'omitnan');
    userMedian(i) = median(G.active_users, 'omitnan');
    trafficMedian(i) = median(G.traffic_volume_dl_kbyte, 'omitnan');
end
baseline = table(keys, loadMedian, userMedian, trafficMedian, ...
    'VariableNames', {'cell_uid','baseline_load','baseline_users','baseline_traffic'});
end

function impact = estimate_compensation_impact(badRows, baseline, vcfg)
lostLoad = 0;
lostUsers = 0;
lostTraffic = 0;
for i = 1:height(badRows)
    idx = find(baseline.cell_uid == string(badRows.cell_uid(i)), 1, 'first');
    if isempty(idx)
        baseLoad = badRows.dl_prb_utilization(i);
        baseUsers = badRows.active_users(i);
        baseTraffic = badRows.traffic_volume_dl_kbyte(i);
    else
        baseLoad = baseline.baseline_load(idx);
        baseUsers = baseline.baseline_users(idx);
        baseTraffic = baseline.baseline_traffic(idx);
    end
    lostLoad = lostLoad + max(0, baseLoad - badRows.dl_prb_utilization(i));
    lostUsers = lostUsers + max(0, baseUsers - badRows.active_users(i));
    lostTraffic = lostTraffic + max(0, baseTraffic - badRows.traffic_volume_dl_kbyte(i));
end
impact = struct();
impact.loadToAbsorb = min(1, vcfg.cocCompensationLoadCaptureFactor * lostLoad);
impact.usersToAbsorb = vcfg.cocCompensationUserCaptureFactor * lostUsers;
impact.trafficToAbsorb = vcfg.cocCompensationLoadCaptureFactor * lostTraffic;
end

function ranking = add_event_ranks(ranking)
ranking.ml_rank = nan(height(ranking), 1);
ranking.ml_selected = false(height(ranking), 1);
events = unique(string(ranking.source_event_id), 'stable');
for i = 1:numel(events)
    idx = find(string(ranking.source_event_id) == events(i));
    [~, order] = sort(ranking.predicted_reward(idx), 'descend');
    orderedIdx = idx(order);
    ranking.ml_rank(orderedIdx) = (1:numel(orderedIdx))';
    isCompensation = strcmp(string(ranking.action_type(idx)), "compensate_neighbor");
    positiveReward = ranking.predicted_reward(idx) > 0;
    selectableIdx = idx(logical(ranking.engineering_selection_allowed(idx)) & isCompensation & positiveReward);
    if isempty(selectableIdx)
        selectableIdx = idx(logical(ranking.engineering_selection_allowed(idx)));
    end
    if isempty(selectableIdx)
        selectableIdx = idx;
    end
    [~, selectedOrder] = sort(ranking.predicted_reward(selectableIdx), 'descend');
    ranking.ml_selected(selectableIdx(selectedOrder(1))) = true;
end
ranking = sortrows(ranking, {'timestamp','source_sim_sector_id','ml_rank'});
end

function siteOutage = detect_site_outage(T)
[groups, ts, site] = findgroups(T.timestamp, T.sim_site_id);
outCount = splitapply(@(x) sum(strcmp(string(x), 'outage_like')), T.cod_state, groups);
abnormalCount = splitapply(@(x) sum(ismember(string(x), ["outage_like","degraded_kpi"])), T.cod_state, groups);
cellCount = splitapply(@numel, T.cod_state, groups);
siteOutage = table(ts, site, outCount, abnormalCount, cellCount, ...
    outCount >= 2 | abnormalCount >= min(cellCount, 3), ...
    'VariableNames', {'timestamp','sim_site_id','outage_like_count','abnormal_count', ...
    'cell_count','is_site_outage_like'});
end

function tf = is_site_outage(siteOutage, timestamp, simSiteId)
mask = siteOutage.timestamp == timestamp & siteOutage.sim_site_id == simSiteId;
tf = any(siteOutage.is_site_outage_like(mask));
end

function rsrp = estimate_rsrp_proxy(rssi)
if ~isfinite(rssi)
    rsrp = -110;
else
    rsrp = rssi - 20;
end
rsrp = min(max(rsrp, -125), -70);
end

function sinr = estimate_sinr_proxy(row)
rssi = read_row_number(row, 'rssi_avg_dbm', NaN);
if ~isfinite(rssi)
    base = 0;
elseif rssi <= -115
    base = -3;
elseif rssi <= -105
    base = 0;
elseif rssi <= -95
    base = 4;
else
    base = 8;
end
rrcSetup = read_row_number(row, 'rrc_setup_success_rate', 1);
erabSetup = read_row_number(row, 'erab_setup_success_rate', rrcSetup);
rrcDrop = read_row_number(row, 'rrc_drop_rate', 0);
erabDrop = read_row_number(row, 'erab_drop_rate', 0);
dlBler = read_row_number(row, 'dl_bler', 0);
ulBler = read_row_number(row, 'ul_bler', 0);
dlThroughput = read_row_number(row, 'dl_throughput_mbps', 0);
setupPenalty = 8 * max(0, 0.98 - min(rrcSetup, erabSetup));
dropPenalty = 20 * max(erabDrop, rrcDrop);
blerPenalty = 4 * max(dlBler, ulBler);
loadBonus = 1.5 * max(0, dlThroughput - 5) / max(1, dlThroughput + 5);
sinr = base - setupPenalty - dropPenalty - blerPenalty + loadBonus;
sinr = min(max(sinr, -5), 20);
end

function q = estimate_qos_ratio(row)
parts = [read_row_number(row, 'cell_availability', 1), ...
    read_row_number(row, 'rrc_setup_success_rate', 1), ...
    read_row_number(row, 'erab_setup_success_rate', 1), ...
    1 - read_row_number(row, 'rrc_drop_rate', 0), ...
    1 - read_row_number(row, 'erab_drop_rate', 0), ...
    1 - read_row_number(row, 'dl_bler', 0)];
parts = parts(isfinite(parts));
if isempty(parts)
    q = 0.5;
else
    q = min(parts);
end
q = clamp01(q);
end

function risk = estimate_handover_risk(row)
names = {'handover_intra_enb_intra_freq_success','handover_intra_enb_inter_freq_success', ...
    'handover_inter_enb_x2_success','handover_inter_enb_s1_success'};
vals = nan(1, numel(names));
for k = 1:numel(names)
    if ismember(names{k}, row.Properties.VariableNames)
        vals(k) = row.(names{k});
    end
end
vals = vals(isfinite(vals));
if isempty(vals)
    risk = 0.5;
else
    risk = 1 - min(vals);
end
risk = clamp01(risk);
end

function y = clamp01(x)
if ~isfinite(x)
    y = 0;
else
    y = min(max(x, 0), 1);
end
end

function v = read_row_number(row, name, default)
if ismember(name, row.Properties.VariableNames)
    v = row.(name);
    if iscell(v)
        v = str2double(v{1});
    end
    v = double(v);
else
    v = default;
end
if isempty(v) || ~isfinite(v)
    v = default;
end
end

function v = getfield_or_default(s, name, default)
if isfield(s, name)
    v = s.(name);
else
    v = default;
end
end
