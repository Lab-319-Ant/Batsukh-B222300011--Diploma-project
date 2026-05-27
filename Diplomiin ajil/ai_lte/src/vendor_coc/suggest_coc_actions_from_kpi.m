function suggestions = suggest_coc_actions_from_kpi(codTable, vcfg)
%SUGGEST_COC_ACTIONS_FROM_KPI Generate COC/OH recommendations from KPI COD.
%
% These are recommendation rows only. No RF/network parameter is applied.

suggestions = table();
if isempty(codTable)
    return;
end

codTable.timestamp_key = string(codTable.timestamp);
siteOutage = detect_site_outage(codTable);

badMask = ismember(string(codTable.cod_state), ["outage_like", "degraded_kpi"]);
badRows = codTable(badMask, :);

rows = cell(height(badRows), 26);
rowIdx = 0;
for i = 1:height(badRows)
    src = badRows(i, :);
    sameTime = codTable(codTable.timestamp == src.timestamp, :);
    sameSiteOut = is_site_outage(siteOutage, src.timestamp, src.sim_site_id);

    weakRadio = src.rssi_avg_dbm <= vcfg.cocRssiWeak_dBm;
    siteLevelIssue = sameSiteOut;

    targetCandidates = sameTime(sameTime.sim_site_id ~= src.sim_site_id & ...
        strcmp(sameTime.cod_state, 'normal') & ...
        sameTime.cell_availability >= vcfg.cocMinAvailabilityForTarget & ...
        sameTime.dl_prb_utilization <= vcfg.cocNeighborLoadSafeThreshold, :);
    if ~isempty(targetCandidates)
        targetCandidates = sortrows(targetCandidates, {'dl_prb_utilization','erab_drop_rate'});
    end

    [safeFlag, rejectReason] = check_vendor_action_safety(src, targetCandidates, vcfg);
    param = initialize_parameter_review(vcfg);

    if siteLevelIssue
        action = "investigate_site_outage_no_same_site_coc";
        targetUid = "";
        targetSector = NaN;
        confidence = "high";
        safetyStatus = "rejected_for_action";
        reason = "multi-sector/site-level outage-like; check alarm/power/backhaul before compensation";
    elseif weakRadio && safeFlag
        action = "neighbor_compensation_review_plus_rs_power_tilt_review";
        target = targetCandidates(1, :);
        targetUid = string(target.cell_uid);
        targetSector = target.sim_sector_id;
        confidence = "medium";
        safetyStatus = "candidate_for_manual_review";
        reason = "degraded/outage-like source with weak RSSI and safe lower-load target";
        param = build_neighbor_compensation_review(src, target, vcfg);
    elseif weakRadio && ~safeFlag
        action = "no_op_coc_target_unsafe";
        targetUid = "";
        targetSector = NaN;
        confidence = "medium";
        safetyStatus = "rejected_for_action";
        reason = rejectReason;
    else
        action = "no_coc_qos_or_load_issue_review_other_modules";
        targetUid = "";
        targetSector = NaN;
        confidence = "low";
        safetyStatus = "not_coc_evidence";
        reason = "COD abnormal but no weak-radio evidence for COC/OH";
    end

    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = {src.timestamp, src.sim_site_id, char(string(src.sim_position)), ...
        src.sim_sector_id, char(string(src.vendor_site_key)), char(string(src.cell_uid)), ...
        src.cell_id, char(string(src.vendor_cell_name)), char(string(src.cod_state)), ...
        char(action), targetSector, char(targetUid), char(safetyStatus), ...
        char(confidence), char(reason), char(string(src.cod_reason)), ...
        char(param.configSource), param.sourceRsPowerDbm, param.sourceElectricalTiltDeg, ...
        param.targetRsPowerDbm, param.targetElectricalTiltDeg, ...
        param.suggestedTargetRsPowerDbm, param.suggestedTargetElectricalTiltDeg, ...
        param.deltaRsPowerDb, param.deltaElectricalTiltDeg, char(param.parameterSuggestion)};
end

if rowIdx == 0
    suggestions = table();
    return;
end

suggestions = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
    {'timestamp','sim_site_id','sim_position','sim_sector_id','vendor_site_key', ...
    'source_cell_uid','source_cell_id','source_cell_name','cod_state', ...
    'recommended_coc_action','target_sim_sector_id','target_cell_uid', ...
    'safety_status','confidence','recommendation_reason','cod_reason', ...
    'config_source','current_source_rs_power_dbm','current_source_electrical_tilt_deg', ...
    'current_target_rs_power_dbm','current_target_electrical_tilt_deg', ...
    'suggested_target_rs_power_dbm','suggested_target_electrical_tilt_deg', ...
    'delta_rs_power_db','delta_electrical_tilt_deg','parameter_suggestion'});
end

function param = initialize_parameter_review(vcfg)
param.configSource = string(vcfg.vendorConfigSource);
param.sourceRsPowerDbm = vcfg.defaultRsPowerDbm;
param.sourceElectricalTiltDeg = vcfg.defaultElectricalTiltDeg;
param.targetRsPowerDbm = NaN;
param.targetElectricalTiltDeg = NaN;
param.suggestedTargetRsPowerDbm = NaN;
param.suggestedTargetElectricalTiltDeg = NaN;
param.deltaRsPowerDb = NaN;
param.deltaElectricalTiltDeg = NaN;
param.parameterSuggestion = "no RF parameter change suggested";
end

function param = build_neighbor_compensation_review(src, target, vcfg)
param = initialize_parameter_review(vcfg);
param.targetRsPowerDbm = vcfg.defaultRsPowerDbm;
param.targetElectricalTiltDeg = vcfg.defaultElectricalTiltDeg;

severeSource = strcmp(string(src.cod_state), 'outage_like') || ...
    src.rssi_avg_dbm <= vcfg.codRssiVeryLow_dBm || ...
    src.cell_availability <= 0.50;
lowTargetLoad = target.dl_prb_utilization <= 0.60;

rsDelta = vcfg.cocDefaultRsPowerDeltaDb;
if severeSource && lowTargetLoad
    rsDelta = vcfg.cocSevereRsPowerDeltaDb;
end

tiltDelta = vcfg.cocTiltDeltaDeg;
param.suggestedTargetRsPowerDbm = min(param.targetRsPowerDbm + rsDelta, vcfg.maxRsPowerDbm);
param.suggestedTargetElectricalTiltDeg = min(max(param.targetElectricalTiltDeg + tiltDelta, ...
    vcfg.minElectricalTiltDeg), vcfg.maxElectricalTiltDeg);
param.deltaRsPowerDb = param.suggestedTargetRsPowerDbm - param.targetRsPowerDbm;
param.deltaElectricalTiltDeg = param.suggestedTargetElectricalTiltDeg - param.targetElectricalTiltDeg;

param.parameterSuggestion = sprintf(['manual review target S%d: RS power %.1f -> %.1f dBm, ' ...
    'electrical tilt %.1f -> %.1f deg; source S%d remains outage/degradation evidence, ' ...
    'do not apply without RF/config validation'], ...
    target.sim_sector_id, param.targetRsPowerDbm, param.suggestedTargetRsPowerDbm, ...
    param.targetElectricalTiltDeg, param.suggestedTargetElectricalTiltDeg, src.sim_sector_id);
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
