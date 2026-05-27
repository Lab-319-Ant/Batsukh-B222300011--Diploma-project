function row = make_action_cell(src, moduleName, actionType, targetSectorId, deltaPrs, deltaTilt, deltaCio, deltaHom, deltaTtt, sleepFlag, notes)
%MAKE_ACTION_CELL Construct one candidate action as a cell row.

row = {src.dataset_id, src.scenario_id, src.realization_id, char(string(src.scenario_name)), ...
    src.site_id, src.sector_id, targetSectorId, src.impaired_sector_id, ...
    src.sector_load_ratio, src.mean_RSRP_dBm, src.mean_SINR_dB, src.qos_satisfaction_ratio, ...
    src.handover_risk_score, src.attach_rate_sector, src.cluster_id, ...
    str2double_safe(src.score_normal), str2double_safe(src.score_degraded), str2double_safe(src.score_outage), ...
    moduleName, actionType, deltaPrs, deltaTilt, deltaCio, deltaHom, deltaTtt, sleepFlag, ...
    strcmp(actionType, 'no_op'), notes};
end

function value = str2double_safe(x)
if isnumeric(x)
    value = x;
else
    value = str2double(string(x));
end
if isnan(value)
    value = 0;
end
end
