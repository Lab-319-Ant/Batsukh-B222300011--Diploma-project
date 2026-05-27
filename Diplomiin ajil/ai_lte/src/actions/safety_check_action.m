function safetyTable = safety_check_action(cfg, counterfactualTable)
%SAFETY_CHECK_ACTION Deterministic Phase 8B safety-flag stub.
%
% This is NOT a final safety enforcer. It only flags candidate actions
% that would violate basic SON safety constraints based on the local
% counterfactual KPI proxies in Phase 8B. The decision coordinator and
% live safety enforcement are out of scope for Phase 8B.
%
% Flag categories (per action row):
%   safety_attach_loss      : delta_source_attach_rate           < -cfg.safetyAttachLossThreshold
%   safety_qos_loss         : delta_source_qos_satisfaction      < -cfg.safetyQosLossThreshold
%   safety_sinr_loss        : delta_source_SINR_dB               < -cfg.safetySinrLossThreshold_dB
%   safety_rsrp_loss        : delta_source_RSRP_dB               < -cfg.safetyRsrpLossThreshold_dB
%   safety_neighbor_overload: post_target_load_ratio             >  cfg.safetyNeighborOverloadThreshold
%   safety_handover_risk    : delta_source_handover_risk_score   >  cfg.safetyHandoverRiskIncrease
%   safety_es_sleep_impaired: ES sleep action on impaired/degraded source
%
% safety_is_unsafe = OR of all individual flags.
%
% Inputs:
%   cfg                  - simulation config (must contain safety* thresholds)
%   counterfactualTable  - Phase 8B counterfactual action table
%
% Output:
%   safetyTable - one row per action with all flag columns and an
%                 'invalid_reason' string summary.

n = height(counterfactualTable);
if n == 0
    safetyTable = build_empty_safety_table();
    return;
end

attachLossT = get_field(cfg, 'safetyAttachLossThreshold', 0.05);
qosLossT = get_field(cfg, 'safetyQosLossThreshold', 0.05);
sinrLossT = get_field(cfg, 'safetySinrLossThreshold_dB', 1.0);
rsrpLossT = get_field(cfg, 'safetyRsrpLossThreshold_dB', 2.0);
neighborOverloadT = get_field(cfg, 'safetyNeighborOverloadThreshold', 0.90);
handoverRiskT = get_field(cfg, 'safetyHandoverRiskIncrease', 0.05);
blockEsSleepOnImpaired = get_field(cfg, 'safetyEsSleepBlockOnImpaired', true);

attach = counterfactualTable.delta_source_attach_rate;
qos    = counterfactualTable.delta_source_qos_satisfaction_ratio;
sinr   = counterfactualTable.delta_source_SINR_dB;
rsrp   = counterfactualTable.delta_source_RSRP_dB;
postTgtLoad = counterfactualTable.post_target_load_ratio;
deltaRisk = counterfactualTable.delta_source_handover_risk_score;

flagAttachLoss      = attach < -attachLossT;
flagQosLoss         = qos    < -qosLossT;
flagSinrLoss        = sinr   < -sinrLossT;
flagRsrpLoss        = rsrp   < -rsrpLossT;
flagNeighborOverload = postTgtLoad > neighborOverloadT;
flagHandoverRisk    = deltaRisk > handoverRiskT;

module = string(counterfactualTable.module_name);
actionType = string(counterfactualTable.action_type);
isEsSleep = module == "ES" & actionType == "sleep";
impairedHint = load_impaired_evidence(cfg, counterfactualTable);
flagEsSleepImpaired = blockEsSleepOnImpaired & isEsSleep & impairedHint;

unsafe = flagAttachLoss | flagQosLoss | flagSinrLoss | flagRsrpLoss | ...
    flagNeighborOverload | flagHandoverRisk | flagEsSleepImpaired;

invalidReason = strings(n, 1);
invalidReason(flagAttachLoss)        = append_reason(invalidReason(flagAttachLoss), "attach_loss");
invalidReason(flagQosLoss)           = append_reason(invalidReason(flagQosLoss), "qos_loss");
invalidReason(flagSinrLoss)          = append_reason(invalidReason(flagSinrLoss), "sinr_loss");
invalidReason(flagRsrpLoss)          = append_reason(invalidReason(flagRsrpLoss), "rsrp_loss");
invalidReason(flagNeighborOverload)  = append_reason(invalidReason(flagNeighborOverload), "neighbor_overload");
invalidReason(flagHandoverRisk)      = append_reason(invalidReason(flagHandoverRisk), "handover_risk_increase");
invalidReason(flagEsSleepImpaired)   = append_reason(invalidReason(flagEsSleepImpaired), "es_sleep_on_impaired");
invalidReason(invalidReason == "")   = "ok";

safetyTable = table(counterfactualTable.action_id, ...
    cellstr(module), cellstr(actionType), ...
    flagAttachLoss, flagQosLoss, flagSinrLoss, flagRsrpLoss, ...
    flagNeighborOverload, flagHandoverRisk, flagEsSleepImpaired, ...
    unsafe, cellstr(invalidReason), ...
    'VariableNames', {'action_id','module_name','action_type', ...
    'safety_attach_loss','safety_qos_loss','safety_sinr_loss','safety_rsrp_loss', ...
    'safety_neighbor_overload','safety_handover_risk','safety_es_sleep_impaired', ...
    'safety_is_unsafe','invalid_reason'});
end

function reason = append_reason(reason, tag)
isEmpty = reason == "";
reason(isEmpty) = tag;
reason(~isEmpty) = strcat(reason(~isEmpty), "|", tag);
end

function value = get_field(cfg, fieldName, defaultValue)
if isfield(cfg, fieldName)
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end

function flag = load_impaired_evidence(cfg, T)
%LOAD_IMPAIRED_EVIDENCE Best-effort source-sector impairment evidence.
n = height(T);
flag = false(n, 1);

stateFile = fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv');
if ~isfile(stateFile)
    return;
end
sectorState = readtable(stateFile);
keyState = make_key(sectorState.dataset_id, sectorState.scenario_id, ...
    sectorState.realization_id, sectorState.sector_id);
keyAction = make_key(T.dataset_id, T.scenario_id, T.realization_id, T.source_sector_id);
[matched, loc] = ismember(keyAction, keyState);

if ~any(matched)
    return;
end
matchedIdx = find(matched);
sourceRows = sectorState(loc(matched), :);

groundTruth = false(numel(matchedIdx), 1);
if ismember('outage_label', sourceRows.Properties.VariableNames)
    groundTruth = groundTruth | logical(sourceRows.outage_label);
end
if ismember('degraded_label', sourceRows.Properties.VariableNames)
    groundTruth = groundTruth | logical(sourceRows.degraded_label);
end
if ismember('is_target_impaired_sector', sourceRows.Properties.VariableNames)
    groundTruth = groundTruth | logical(sourceRows.is_target_impaired_sector);
end

% Coverage corroboration: low RSRP or very low attach rate.
if ismember('mean_RSRP_dBm', sourceRows.Properties.VariableNames)
    rsrpHint = sourceRows.mean_RSRP_dBm <= get_field(cfg, 'cocLowRsrpThreshold_dBm', -105);
    groundTruth = groundTruth | rsrpHint;
end
if ismember('attach_rate_sector', sourceRows.Properties.VariableNames)
    attachHint = sourceRows.attach_rate_sector < get_field(cfg, 'cocLowAttachThreshold', 0.50);
    groundTruth = groundTruth | attachHint;
end

flag(matchedIdx) = groundTruth;
end

function key = make_key(datasetId, scenarioId, realizationId, sectorId)
key = strcat(string(datasetId), "_", string(scenarioId), "_", ...
    string(realizationId), "_", string(sectorId));
end

function T = build_empty_safety_table()
T = table('Size', [0 12], ...
    'VariableTypes', {'double','cell','cell','logical','logical','logical','logical', ...
    'logical','logical','logical','logical','cell'}, ...
    'VariableNames', {'action_id','module_name','action_type', ...
    'safety_attach_loss','safety_qos_loss','safety_sinr_loss','safety_rsrp_loss', ...
    'safety_neighbor_overload','safety_handover_risk','safety_es_sleep_impaired', ...
    'safety_is_unsafe','invalid_reason'});
end
