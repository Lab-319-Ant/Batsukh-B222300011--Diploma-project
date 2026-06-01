function [reward, coverageTerm, qosTerm, loadTerm, handoverTerm, energyTerm, penaltyTerm] = ...
    compute_counterfactual_reward(cfg, moduleName, preSourceLoad, postSourceLoad, ...
    preTargetLoad, postTargetLoad, preSourceRsrp, postSourceRsrp, preSourceSinr, postSourceSinr, ...
    preSourceQos, postSourceQos, preSourceAttach, postSourceAttach, preHandoverRisk, ...
    postHandoverRisk, energyDeltaProxy, interferenceDeltaProxy, actionCostProxy)
%COMPUTE_COUNTERFACTUAL_REWARD Normalized Phase 8B proxy reward.
%
% reward = w_cov*coverage + w_qos*qos + w_load*load + w_ho*handover
%          + w_es*energy - w_penalty*(new_safety_risk + cost)
%
% Each KPI term is counted exactly once. No module-specific bonus is added
% on top of the weighted sum, so a module cannot reward the same KPI twice
% (the previous version added e.g. +0.50*loadTerm to LB on top of
% w_load*loadTerm).
%
% Safety/cost penalty weight (cfg.phase8bPenaltyWeight) is configured to be
% larger than any single gain weight so unsafe candidates cannot win on
% optimization gains alone. See docs/phase8b_reward_formula.md for the
% full derivation and weight rationale.
%
% This reward is used only to create counterfactual training/evaluation
% data. It is not an oracle and does not imply an action has been selected.

deltaRsrpNorm = (postSourceRsrp - preSourceRsrp) / 10;
deltaSinrNorm = (postSourceSinr - preSourceSinr) / 10;
deltaAttach = postSourceAttach - preSourceAttach;
deltaQos = postSourceQos - preSourceQos;
sourceLoadImprovement = max(preSourceLoad - cfg.lbOverloadThreshold, 0) - ...
    max(postSourceLoad - cfg.lbOverloadThreshold, 0);

% Penalize only overload risk introduced or worsened by the action. The
% previous formula penalized absolute post-action overload, which made a
% no-op receive negative reward in an already overloaded state. That trains
% the model on baseline badness rather than action value.
targetOverloadPenalty = max( ...
    max(postTargetLoad - cfg.phase8bOverloadPenaltyThreshold, 0) - ...
    max(preTargetLoad - cfg.phase8bOverloadPenaltyThreshold, 0), 0);
sourceOverloadPenalty = max( ...
    max(postSourceLoad - cfg.phase8bOverloadPenaltyThreshold, 0) - ...
    max(preSourceLoad - cfg.phase8bOverloadPenaltyThreshold, 0), 0);
riskReduction = preHandoverRisk - postHandoverRisk;

coverageTerm = deltaAttach + 0.25 * deltaRsrpNorm + 0.25 * deltaSinrNorm;
qosTerm = deltaQos;
loadTerm = sourceLoadImprovement - 0.50 * targetOverloadPenalty;
handoverTerm = riskReduction;
energyTerm = energyDeltaProxy;

negativeKpiPenalty = max(-deltaAttach, 0) + max(-deltaQos, 0) + 0.25 * max(-deltaSinrNorm, 0);
penaltyTerm = targetOverloadPenalty + 0.50 * sourceOverloadPenalty + ...
    interferenceDeltaProxy + actionCostProxy + negativeKpiPenalty;

reward = cfg.phase8bRewardCoverageWeight * coverageTerm + ...
    cfg.phase8bRewardQosWeight * qosTerm + ...
    cfg.phase8bRewardLoadWeight * loadTerm + ...
    cfg.phase8bRewardHandoverWeight * handoverTerm + ...
    cfg.phase8bRewardEnergyWeight * energyTerm - ...
    cfg.phase8bPenaltyWeight * penaltyTerm;

% Suppress unused-argument warnings; moduleName is retained in the
% signature for traceability and future module-specific reward shaping
% that does NOT double-count KPI gains.
moduleName = moduleName; %#ok<ASGSL>
end
