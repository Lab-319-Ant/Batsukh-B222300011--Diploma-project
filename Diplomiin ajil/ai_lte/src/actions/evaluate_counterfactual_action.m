function T = evaluate_counterfactual_action(cfg, actions, sectorState)
%EVALUATE_COUNTERFACTUAL_ACTION Deterministic Phase 8B KPI proxy evaluator.
%
% This is a simplified local counterfactual model. It estimates how a
% candidate action may change source/target sector KPI proxies. It does not
% rerun the RF simulator, does not enforce safety, does not select actions,
% and does not feed post-action KPIs into a next time step.

actions.module_name = string(actions.module_name);
actions.action_type = string(actions.action_type);
actions.scenario_name = string(actions.scenario_name);

targetState = lookup_target_sector_state(actions, sectorState);

n = height(actions);
% Sanitize KPI inputs. Replace NaN/Inf with physically conservative
% defaults from cfg before any arithmetic so the reward stays finite even
% for sectors with no UEs or no signal.
preSourceLoad   = sanitize(actions.source_load_ratio,            cfg.defaultMissingLoad);
preTargetLoad   = sanitize(targetState.sector_load_ratio,        cfg.defaultMissingLoad);
preSourceRsrp   = sanitize(actions.source_mean_RSRP_dBm,         cfg.noSignalRSRP_dBm);
preSourceSinr   = sanitize(actions.source_mean_SINR_dB,          cfg.noSignalSINR_dB);
preSourceQos    = sanitize(actions.source_qos_satisfaction_ratio,cfg.defaultMissingQoS);
preSourceAttach = sanitize(actions.source_attach_rate_sector,    cfg.defaultMissingAttachRate);
preHandoverRisk = sanitize(actions.source_handover_risk_score,   cfg.defaultMissingHandoverRisk);

postSourceLoad = preSourceLoad;
postTargetLoad = preTargetLoad;
postSourceRsrp = preSourceRsrp;
postSourceSinr = preSourceSinr;
postSourceQos = preSourceQos;
postSourceAttach = preSourceAttach;
postHandoverRisk = preHandoverRisk;
energyDeltaProxy = zeros(n, 1);
interferenceDeltaProxy = zeros(n, 1);
actionCostProxy = zeros(n, 1);
evaluationNote = strings(n, 1);

isNoOp = logical(actions.is_no_op);
isCoc = actions.module_name == "COC/OH" & ~isNoOp;
isLb = actions.module_name == "LB/MLB" & ~isNoOp;
isEs = actions.module_name == "ES";
isMro = actions.module_name == "HO/MRO" & ~isNoOp;

% COC/OH: compensation can recover source coverage/QoS when the source
% already has impairment evidence. The proxy scales recovery by pre-action
% KPI deficit; this avoids rewarding compensation on a healthy source just
% because an RF parameter was changed.
cocStrength = normalize01(actions.delta_prs_dB, max(cfg.cocDeltaPRS_dB)) + ...
    0.5 * normalize01(max(-actions.delta_tilt_deg, 0), max(abs(cfg.cocDeltaTilt_deg))) + ...
    0.3 * normalize01(actions.delta_cio_dB, max(cfg.cocDeltaCIO_dB));
rsrpDeficit = clamp01((cfg.cocLowRsrpThreshold_dBm - preSourceRsrp) / 20);
sinrDeficit = clamp01((cfg.minSINR_dB - preSourceSinr) / 10);
attachDeficit = clamp01(1 - preSourceAttach);
% COC/OH is a coverage/outage-compensation module. QoS degradation by
% itself can come from overload or scheduling limits, so it must not create
% COC recovery without RF/attachment evidence. Otherwise the proxy rewards
% COC for LB/QP-like failures and creates misleading high-reward outliers.
cocImpairment = max(max(rsrpDeficit, sinrDeficit), attachDeficit);
cocRecovery = min(0.20, 0.06 * cocStrength .* cocImpairment);
postSourceAttach(isCoc) = preSourceAttach(isCoc) + cocRecovery(isCoc);
postSourceQos(isCoc) = preSourceQos(isCoc) + 0.75 * cocRecovery(isCoc);
postSourceRsrp(isCoc) = preSourceRsrp(isCoc) + 0.45 * actions.delta_prs_dB(isCoc) + ...
    0.20 * max(-actions.delta_tilt_deg(isCoc), 0);
postSourceSinr(isCoc) = preSourceSinr(isCoc) + 0.12 * actions.delta_prs_dB(isCoc) + ...
    0.08 * max(-actions.delta_tilt_deg(isCoc), 0) - 0.04 * actions.delta_cio_dB(isCoc);
postTargetLoad(isCoc) = preTargetLoad(isCoc) + 0.012 * cocStrength(isCoc);
interferenceDeltaProxy(isCoc) = 0.002 * actions.delta_prs_dB(isCoc) + 0.001 * max(-actions.delta_tilt_deg(isCoc), 0);
actionCostProxy(isCoc) = 0.005 * actions.delta_prs_dB(isCoc) + 0.003 * abs(actions.delta_tilt_deg(isCoc)) + ...
    0.002 * abs(actions.delta_cio_dB(isCoc));
evaluationNote(isCoc) = "local COC/OH coverage-compensation proxy";

% LB/MLB: positive CIO bias is treated as offloading from source to target.
positiveCio = max(actions.delta_cio_dB, 0);
negativeCio = max(-actions.delta_cio_dB, 0);
overloadExcess = max(preSourceLoad - cfg.lbOverloadThreshold, 0);
offload = min(0.25, overloadExcess .* positiveCio / max(abs(cfg.lbDeltaCIO_dB)));
reverseBiasPenalty = 0.03 * negativeCio / max(abs(cfg.lbDeltaCIO_dB));
postSourceLoad(isLb) = preSourceLoad(isLb) - offload(isLb) + reverseBiasPenalty(isLb);
postTargetLoad(isLb) = preTargetLoad(isLb) + offload(isLb);
postSourceQos(isLb) = preSourceQos(isLb) + 0.35 * offload(isLb) - 0.10 * reverseBiasPenalty(isLb);
postSourceSinr(isLb) = preSourceSinr(isLb) - 0.15 * offload(isLb);
actionCostProxy(isLb) = 0.01 * abs(actions.delta_cio_dB(isLb));
evaluationNote(isLb) = "local LB/MLB CIO offload proxy";

% ES: sleep saves energy but may reduce coverage/QoS. keep_active is a no-op
% counterfactual, wake_up spends energy but can recover service proxies.
isSleep = isEs & actions.action_type == "sleep";
isWake = isEs & actions.action_type == "wake_up";
isKeep = isEs & actions.action_type == "keep_active";
sleepLoss = 0.05 + 0.25 * min(preSourceLoad, 1);
postSourceQos(isSleep) = preSourceQos(isSleep) - sleepLoss(isSleep);
postSourceAttach(isSleep) = preSourceAttach(isSleep) - 0.50 * sleepLoss(isSleep);
postSourceLoad(isSleep) = 0;
energyDeltaProxy(isSleep) = 1;
actionCostProxy(isSleep) = 0.05 + 0.25 * preSourceLoad(isSleep);
evaluationNote(isSleep) = "local ES sleep proxy";

wakeGain = min(0.15, 0.50 * max(1 - preSourceQos, 0));
postSourceQos(isWake) = preSourceQos(isWake) + wakeGain(isWake);
postSourceAttach(isWake) = preSourceAttach(isWake) + 0.50 * wakeGain(isWake);
energyDeltaProxy(isWake) = -0.35;
actionCostProxy(isWake) = 0.08;
evaluationNote(isWake) = "local ES wake-up proxy";
evaluationNote(isKeep) = "local ES keep-active no-op proxy";

% HO/MRO: parameter changes reduce handover-risk proxy if risk is high, but
% aggressive changes incur continuity cost.
homStrength = abs(actions.delta_hom_dB) / max(abs(cfg.mroDeltaHOM_dB));
tttStrength = abs(actions.delta_ttt_ms) / max(abs(cfg.mroDeltaTTT_ms));
cioStrength = abs(actions.delta_cio_dB) / max(abs(cfg.mroDeltaCIO_dB));
mroStrength = 0.45 * homStrength + 0.35 * tttStrength + 0.20 * cioStrength;
riskReduction = min(0.20, 0.20 * mroStrength) .* min(1, preHandoverRisk / max(cfg.mroHandoverRiskThreshold, eps));
postHandoverRisk(isMro) = preHandoverRisk(isMro) - riskReduction(isMro);
postSourceQos(isMro) = preSourceQos(isMro) + 0.10 * riskReduction(isMro);
postSourceSinr(isMro) = preSourceSinr(isMro) + 0.05 * riskReduction(isMro);
actionCostProxy(isMro) = 0.03 * mroStrength(isMro);
evaluationNote(isMro) = "local HO/MRO handover-risk proxy";

evaluationNote(isNoOp & evaluationNote == "") = "no-op counterfactual baseline";
evaluationNote(evaluationNote == "") = "local deterministic counterfactual proxy";

% Re-sanitize post values: clamp() does not handle NaN/Inf, so a single
% non-finite intermediate term in a module formula would still propagate
% into the reward without this guard.
postSourceLoad   = max(sanitize(postSourceLoad,   cfg.defaultMissingLoad),         0);
postTargetLoad   = max(sanitize(postTargetLoad,   cfg.defaultMissingLoad),         0);
postSourceRsrp   = sanitize(postSourceRsrp,       cfg.noSignalRSRP_dBm);
postSourceSinr   = sanitize(postSourceSinr,       cfg.noSignalSINR_dB);
postSourceQos    = clamp01(sanitize(postSourceQos,    cfg.defaultMissingQoS));
postSourceAttach = clamp01(sanitize(postSourceAttach, cfg.defaultMissingAttachRate));
postHandoverRisk = clamp01(sanitize(postHandoverRisk, cfg.defaultMissingHandoverRisk));
energyDeltaProxy       = sanitize(energyDeltaProxy,       0);
interferenceDeltaProxy = sanitize(interferenceDeltaProxy, 0);
actionCostProxy        = sanitize(actionCostProxy,        0);

[reward, coverageTerm, qosTerm, loadTerm, handoverTerm, energyTerm, penaltyTerm] = ...
    compute_counterfactual_reward(cfg, actions.module_name, preSourceLoad, postSourceLoad, ...
    preTargetLoad, postTargetLoad, preSourceRsrp, postSourceRsrp, preSourceSinr, postSourceSinr, ...
    preSourceQos, postSourceQos, preSourceAttach, postSourceAttach, preHandoverRisk, ...
    postHandoverRisk, energyDeltaProxy, interferenceDeltaProxy, actionCostProxy);

% Carry the candidate-action parameter columns through to the Phase 8B
% output table. These columns are required by the semantic duplicate-key
% check in validate_phase8b_counterfactuals.m and by any downstream
% analysis that needs to inspect which exact action was evaluated.
deltaPrs   = read_action_column(actions, 'delta_prs_dB');
deltaTilt  = read_action_column(actions, 'delta_tilt_deg');
deltaCio   = read_action_column(actions, 'delta_cio_dB');
deltaHom   = read_action_column(actions, 'delta_hom_dB');
deltaTtt   = read_action_column(actions, 'delta_ttt_ms');
sleepFlag  = read_action_column(actions, 'sleep_flag');

T = table(actions.action_id, actions.dataset_id, actions.scenario_id, actions.realization_id, ...
    cellstr(actions.scenario_name), cellstr(actions.module_name), cellstr(actions.action_type), ...
    actions.source_sector_id, actions.target_sector_id, actions.is_no_op, ...
    deltaPrs, deltaTilt, deltaCio, deltaHom, deltaTtt, sleepFlag, ...
    preSourceLoad, postSourceLoad, postSourceLoad - preSourceLoad, ...
    preTargetLoad, postTargetLoad, postTargetLoad - preTargetLoad, ...
    preSourceRsrp, postSourceRsrp, postSourceRsrp - preSourceRsrp, ...
    preSourceSinr, postSourceSinr, postSourceSinr - preSourceSinr, ...
    preSourceQos, postSourceQos, postSourceQos - preSourceQos, ...
    preSourceAttach, postSourceAttach, postSourceAttach - preSourceAttach, ...
    preHandoverRisk, postHandoverRisk, postHandoverRisk - preHandoverRisk, ...
    energyDeltaProxy, interferenceDeltaProxy, actionCostProxy, ...
    coverageTerm, qosTerm, loadTerm, handoverTerm, energyTerm, penaltyTerm, reward, ...
    cellstr(evaluationNote), ...
    'VariableNames', {'action_id','dataset_id','scenario_id','realization_id', ...
    'scenario_name','module_name','action_type','source_sector_id','target_sector_id', ...
    'is_no_op', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms','sleep_flag', ...
    'pre_source_load_ratio','post_source_load_ratio','delta_source_load_ratio', ...
    'pre_target_load_ratio','post_target_load_ratio','delta_target_load_ratio', ...
    'pre_source_RSRP_dBm','post_source_RSRP_dBm','delta_source_RSRP_dB', ...
    'pre_source_SINR_dB','post_source_SINR_dB','delta_source_SINR_dB', ...
    'pre_source_qos_satisfaction_ratio','post_source_qos_satisfaction_ratio', ...
    'delta_source_qos_satisfaction_ratio','pre_source_attach_rate', ...
    'post_source_attach_rate','delta_source_attach_rate', ...
    'pre_source_handover_risk_score','post_source_handover_risk_score', ...
    'delta_source_handover_risk_score','energy_delta_proxy','interference_delta_proxy', ...
    'action_cost_proxy','reward_coverage_term','reward_qos_term','reward_load_term', ...
    'reward_handover_term','reward_energy_term','reward_penalty_term','reward', ...
    'evaluation_note'});
end

function v = read_action_column(actions, colName)
%READ_ACTION_COLUMN Return a numeric column from the candidate action
% table, or a zero column if the candidate table predates the schema.
n = height(actions);
if ismember(colName, actions.Properties.VariableNames)
    v = actions.(colName);
    if ~isnumeric(v)
        v = double(v);
    end
else
    v = zeros(n, 1);
end
end

function targetState = lookup_target_sector_state(actions, sectorState)
stateKey = make_key(sectorState.dataset_id, sectorState.scenario_id, ...
    sectorState.realization_id, sectorState.sector_id);
targetKey = make_key(actions.dataset_id, actions.scenario_id, ...
    actions.realization_id, actions.target_sector_id);
[matched, loc] = ismember(targetKey, stateKey);

n = height(actions);
targetState.sector_load_ratio = actions.source_load_ratio;
targetState.mean_RSRP_dBm = actions.source_mean_RSRP_dBm;
targetState.mean_SINR_dB = actions.source_mean_SINR_dB;
targetState.qos_satisfaction_ratio = actions.source_qos_satisfaction_ratio;
if any(matched)
    targetState.sector_load_ratio(matched) = sectorState.sector_load_ratio(loc(matched));
    targetState.mean_RSRP_dBm(matched) = sectorState.mean_RSRP_dBm(loc(matched));
    targetState.mean_SINR_dB(matched) = sectorState.mean_SINR_dB(loc(matched));
    targetState.qos_satisfaction_ratio(matched) = sectorState.qos_satisfaction_ratio(loc(matched));
end
targetState.lookup_matched = matched;
targetState.lookup_matched = reshape(targetState.lookup_matched, n, 1);
end

function key = make_key(datasetId, scenarioId, realizationId, sectorId)
key = strcat(string(datasetId), "_", string(scenarioId), "_", string(realizationId), "_", string(sectorId));
end

function y = clamp01(x)
y = min(max(x, 0), 1);
end

function y = normalize01(x, scale)
if scale <= 0
    y = zeros(size(x));
else
    y = x ./ scale;
end
end

function y = sanitize(x, fallback)
%SANITIZE Replace NaN and +/-Inf with the fallback value.
y = x;
mask = ~isfinite(y);
if any(mask)
    y(mask) = fallback;
end
end
