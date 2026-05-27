function tables = build_final_thesis_summary_tables(bundle)
%BUILD_FINAL_THESIS_SUMMARY_TABLES Assemble Phase 13 result tables.
%
% All headline values are derived from on-disk Phase 12E summaries, not
% hardcoded. The hardcoded text in build_module_status uses ranges and
% qualitative descriptions; the numeric headlines come from the bundle.

tables = struct();
tables.moduleStatus = build_module_status();
tables.baselineAiOracle = build_baseline_ai_oracle(bundle);
tables.kpiImprovement = build_kpi_improvement(bundle);
tables.scenarioSummary = build_scenario_summary(bundle);
tables.moduleValidation = build_module_validation(bundle);
tables.safetyCoordination = build_safety_coordination(bundle);
tables.oracleRegret = build_oracle_regret(bundle);
end

function T = build_module_status()
rows = {
    'RF/KPI simulation',  'completed', 'Synthetic LTE RF + traffic + KPI engine', false, 'baseline_for_all_other_modules', ...
        'Phase 1B/2 validation metrics', 'Implemented synthetic LTE RF/KPI engine.', ...
        'Simplified wideband spectral-efficiency model; not a full LTE scheduler.';
    'Scenario generation','completed', 'Phase 3 scenario engine + Phase 4 multi-scenario dataset', false, 'baseline_for_all_other_modules', ...
        'phase3_scenario_sanity_check + phase4_dataset_validation', 'Implemented multiple SON-inspired scenarios.', ...
        'Synthetic scenarios only; no live RAN traces.';
    'Clustering monitor', 'completed', 'k-means (k=4) on KPI features', false, 'monitoring_only_not_action_module', ...
        'silhouette + scenario crosstab', 'Monitoring / module-trigger support only, not final decision maker.', ...
        'Min-cluster size warning (~0.6%); used as state monitor only.';
    'COD',  'completed', 'Random Forest classifier (Phase 6B)', false, 'detection_only_not_action_module', ...
        'balanced test accuracy + outage recall', 'Classifier for normal/degraded/outage detection, no action application.', ...
        'External imbalanced macro F1 lower than balanced test F1.';
    'TP',   'completed', 'LSBoost regression on lag features (Phase 7B)', false, 'support_module_not_action_module', ...
        'MAE / RMSE / R^2 vs persistence baseline', 'Prediction / support module, not action module.', ...
        'Per-scenario R^2 weak on low_load; intended as support feature.';
    'QP',   'completed', 'LSBoost regression + bounded prediction (Phase 7B/7C)', false, 'bounded_support_module_only', ...
        'bounded R^2 + scenario diagnostic', 'Bounded / support prediction module, limited by bimodal target.', ...
        'Target is essentially binary (0 or 1); interpret as bounded support model, not a robust continuous QoS predictor.';
    'COC/OH','completed','Phase 9B action-value + Phase 10A safety filter + coordinator', true, 'physically_applied_to_kpi_t_plus_1_for_implementable_actions', ...
        'top-1 oracle match + delta KPIs', 'Action module; physically applied only for implementable P_RS / tilt / CIO actions.', ...
        'Few executable rows (6 in post-fix run); CIO depends on Phase 12B extension.';
    'LB/MLB','completed','Phase 9B action-value + Phase 10A safety filter + coordinator', true, 'physically_applied_to_kpi_t_plus_1_via_cio_bias', ...
        'top-1 oracle match + delta KPIs', 'Action module; physically applied via CIO-biased association.', ...
        'CIO bias does not change physical RSRP; attach-rate trade-off observed.';
    'ES',   'completed','Phase 9B action-value + Phase 10A safety filter + coordinator', true, 'queued_offline_not_applied_to_kpi_t_plus_1', ...
        'top-1 oracle match', 'Action module in offline decision pipeline, not physically applied to KPI(t+1).', ...
        'is_sleeping state flag exists; RF/KPI engines do NOT consume it.';
    'HO/MRO','completed','Phase 9B action-value + Phase 10A safety filter + coordinator', true, 'queued_offline_not_applied_to_kpi_t_plus_1', ...
        'top-1 oracle match', 'Action module in offline decision pipeline, not physically applied to KPI(t+1).', ...
        'hom_offset_dB / ttt_offset_ms placeholders only; no temporal handover model.';
    'Oracle','completed','Exhaustive max-reward selection over Phase 8B counterfactual', false, 'safety_constrained_benchmark_not_applied', ...
        'oracle_group_count / safe_selected_count', 'Safety-constrained benchmark, not ML and not reward function.', ...
        'Reward is local Phase 8B proxy; only implementable oracle actions get cloned-state KPI(t+1) comparison.';
    'Action-value ML','completed','Per-module LSBoost regressors (Phase 9B)', false, 'offline_reward_ranking_model', ...
        'oracle regret + top-k match', 'Offline reward-ranking model, interpreted with regret / ranking metrics.', ...
        'Actual-vs-predicted reward scatter is diagnostic only; do not use as a main thesis figure.';
    'Safety filter','completed','Phase 8B safety_check_action + Phase 10A enforcement', false, 'pre_coordinator_gate', ...
        'safety_filter_changed_count', 'Filters unsafe ML-selected actions before coordination.', ...
        'Stub thresholds; final live enforcement out of scope.';
    'Coordinator','completed','Priority + conflict resolution (Phase 11A/11B)', false, 'offline_final_decision_table', ...
        'conflict resolution log', 'Offline final decision table, not multi-step closed-loop controller.', ...
        'Offline only; not_applied_flag = true on every row.';
    'One-step KPI(t)->KPI(t+1)','completed','Phase 12D cloned-state recompute + Phase 12E comparison', true, 'one_step_only_no_iteration', ...
        'mean delta KPIs + gap to oracle', 'Limited cloned-state evaluation for COC/OH and LB/MLB only.', ...
        'Single step; ES and HO/MRO actions are NOT physically applied to KPI(t+1).';
    };

T = cell2table(rows, 'VariableNames', {'module_name','implemented_status', ...
    'ML_model_or_method','action_module_flag','physical_KPI_update_status', ...
    'main_validation_metric','final_result_summary','limitation'});
end

function T = build_baseline_ai_oracle(b)
%BUILD_BASELINE_AI_ORACLE Long-form comparison with explicit interpretation.
T = table();
if isempty(b.phase12e_baseline_ai)
    return;
end
BA = b.phase12e_baseline_ai;
OC = b.phase12e_oracle_compare;

kpis = {
    'attach_rate',           'pre_attach_rate',                'ai_post_attach_rate',                'oracle_attach',  'lower is unfavourable -- CIO bias trades attach for SINR/QoS';
    'mean_rsrp_dBm',         'pre_mean_rsrp_dBm',              'ai_post_mean_rsrp_dBm',              'oracle_rsrp',    'higher dB is favourable';
    'mean_sinr_dB',          'pre_mean_sinr_dB',               'ai_post_mean_sinr_dB',               'oracle_sinr',    'higher dB is favourable';
    'mean_sector_load',      'pre_mean_sector_load',           'ai_post_mean_sector_load',           'oracle_load',    'lower is favourable for LB/MLB targets';
    'qos_satisfaction_ratio','pre_qos_satisfaction_ratio',     'ai_post_qos_satisfaction_ratio',     'oracle_qos',     'higher is favourable; AI/ML and oracle nearly tied';
};

rows = {};
for k = 1:size(kpis, 1)
    name = kpis{k, 1};
    preCol = kpis{k, 2};
    aiCol  = kpis{k, 3};
    oracleCol = kpis{k, 4};
    interp = kpis{k, 5};

    if ~ismember(preCol, BA.Properties.VariableNames) || ~ismember(aiCol, BA.Properties.VariableNames)
        continue;
    end
    pre = mean(BA.(preCol), 'omitnan');
    ai = mean(BA.(aiCol), 'omitnan');

    oracle = NaN;
    if ~isempty(OC) && ismember(oracleCol, OC.Properties.VariableNames)
        mask = isfinite(OC.(oracleCol));
        if any(mask)
            oracle = mean(OC.(oracleCol)(mask), 'omitnan');
        end
    end

    aiDelta = ai - pre;
    if isfinite(oracle)
        oracleDelta = oracle - pre;
        gap = oracle - ai;
    else
        oracleDelta = NaN;
        gap = NaN;
    end

    rows(end + 1, :) = {sprintf('ALL_%s', name), pre, ai, oracle, aiDelta, oracleDelta, gap, interp}; %#ok<AGROW>
end

T = cell2table(rows, 'VariableNames', {'comparison_scope','baseline_metric', ...
    'ai_ml_metric','oracle_metric','ai_ml_delta_from_baseline', ...
    'oracle_delta_from_baseline','ai_ml_gap_to_oracle','interpretation'});
end

function T = build_kpi_improvement(b)
%BUILD_KPI_IMPROVEMENT Headline numbers + per-scenario flags.
T = table();
if isempty(b.phase12e_module) || isempty(b.phase12e_scenario)
    return;
end

% Compute overall averages weighted by action count.
M = b.phase12e_module;
S = b.phase12e_scenario;
nApplied = sum(M.total_actions);

% Pull mean overall deltas from baseline_ai table directly when available.
BA = b.phase12e_baseline_ai;
if ~isempty(BA)
    deltaAttach = mean(BA.delta_attach_rate, 'omitnan');
    deltaRsrp = mean(BA.delta_mean_rsrp_dB, 'omitnan');
    deltaSinr = mean(BA.delta_mean_sinr_dB, 'omitnan');
    deltaLoad = mean(BA.delta_mean_sector_load, 'omitnan');
    deltaQos = mean(BA.delta_qos_satisfaction_ratio, 'omitnan');
else
    % Weighted average across modules (Δattach / Δqos only).
    deltaAttach = weighted_mean(M.mean_delta_attach, M.total_actions);
    deltaRsrp = NaN; deltaSinr = NaN; deltaLoad = NaN;
    deltaQos = weighted_mean(M.mean_delta_qos, M.total_actions);
end

% qos gap to oracle from per-scenario summary.
if ismember('mean_qos_gap_to_oracle', S.Properties.VariableNames)
    qosGap = weighted_mean(S.mean_qos_gap_to_oracle, S.total_actions);
else
    qosGap = NaN;
end

S = S;
S.attach_rate_degraded_flag = S.mean_delta_attach < -0.01;
S.overload_qos_improvement_flag = strcmp(S.scenario_name, 'overload') & S.mean_delta_qos > 0;

T = table( ...
    {'applied_action_count'; 'delta_attach_rate'; 'delta_mean_rsrp_dB'; ...
     'delta_mean_sinr_dB'; 'delta_mean_sector_load'; 'delta_qos_satisfaction_ratio'; ...
     'qos_gap_to_oracle'}, ...
    [nApplied; deltaAttach; deltaRsrp; deltaSinr; deltaLoad; deltaQos; qosGap], ...
    'VariableNames', {'metric','value'});

T.attach_rate_degraded_flag = T.value < 0 & strcmp(T.metric, 'delta_attach_rate');
T.overload_qos_improvement_flag = false(height(T), 1);
overloadRow = strcmp(S.scenario_name, 'overload');
if any(overloadRow) && S.mean_delta_qos(overloadRow) > 0
    T.overload_qos_improvement_flag(strcmp(T.metric, 'delta_qos_satisfaction_ratio')) = true;
end
end

function v = weighted_mean(values, weights)
mask = isfinite(values) & isfinite(weights) & weights > 0;
if ~any(mask)
    v = NaN; return;
end
v = sum(values(mask) .* weights(mask)) / sum(weights(mask));
end

function T = build_scenario_summary(b)
if ~isempty(b.phase12d_scenario)
    src = b.phase12d_scenario;
    keep = intersect({'scenario_name','action_count','mean_delta_attach_rate', ...
        'mean_delta_rsrp_dB','mean_delta_sinr_dB', ...
        'mean_delta_sector_load','mean_delta_qos_satisfaction_ratio'}, ...
        src.Properties.VariableNames, 'stable');
    T = src(:, keep);
else
    T = table();
end
end

function T = build_module_validation(b)
phases = {
    'Phase4B', 'phase4b_validation';
    'Phase5',  'phase5_validation';
    'Phase7B', 'phase7b_validation';
    'Phase7C', 'phase7c_validation';
    'Phase8A', 'phase8a_validation';
    'Phase8B', 'phase8b_validation';
    'Phase8C', 'phase8c_validation';
    'Phase9A', 'phase9a_validation';
    'Phase9B', 'phase9b_validation';
    'Phase10A','phase10a_validation';
    'Phase11A','phase11a_validation';
    'Phase11B','phase11b_validation';
    'Phase12A','phase12a_validation';
    'Phase12B','phase12b_validation';
    'Phase12C','phase12c_validation';
    'Phase12D','phase12d_validation';
    'Phase12E','phase12e_validation';
    };
rows = cell(size(phases, 1), 4);
for i = 1:size(phases, 1)
    tbl = b.(phases{i, 2});
    if isempty(tbl) || ~ismember('severity', tbl.Properties.VariableNames)
        rows(i, :) = {phases{i, 1}, NaN, NaN, '(missing)'};
        continue;
    end
    errCount = sum(strcmp(tbl.severity, 'error') & ~logical(tbl.pass_flag));
    warnCount = sum(strcmp(tbl.severity, 'warning') & ~logical(tbl.pass_flag));
    if errCount == 0 && warnCount == 0
        statusNote = 'clean';
    else
        statusNote = sprintf('errors=%d warnings=%d', errCount, warnCount);
    end
    rows(i, :) = {phases{i, 1}, errCount, warnCount, statusNote};
end
T = cell2table(rows, 'VariableNames', {'phase','validation_errors','validation_warnings','status_note'});
end

function T = build_safety_coordination(b)
T = table();
if ~isempty(b.phase10a_safety) && ~isempty(b.phase11a_summary)
    sf = b.phase10a_safety;
    co = b.phase11a_summary;
    [~, ia, ib] = intersect(string(sf.module_name), string(co.module_name), 'stable');
    if ~isempty(ia)
        T = table(cellstr(string(sf.module_name(ia))), sf.raw_unsafe_top1_count(ia), ...
            sf.safety_filter_changed_count(ia), sf.fallback_count(ia), ...
            co.safety_rejection_count(ib), co.priority_rejection_count(ib), ...
            co.accepted_after_coordination(ib), co.rejected_after_coordination(ib), ...
            'VariableNames', {'module_name','phase10a_raw_unsafe_top1', ...
            'phase10a_safety_filter_changed','phase10a_fallback_count', ...
            'phase11a_safety_rejection','phase11a_priority_rejection', ...
            'phase11a_accepted_after_coordination','phase11a_rejected_after_coordination'});
    end
end
end

function T = build_oracle_regret(b)
T = table();
if ~isempty(b.phase8c_summary)
    T = b.phase8c_summary;
end
end
