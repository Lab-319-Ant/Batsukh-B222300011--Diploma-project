function comparisonTable = compare_baseline_ai_oracle_kpis(baselineAi, oracleLog)
%COMPARE_BASELINE_AI_ORACLE_KPIS Merge baseline-vs-AI with oracle log and compute gaps.
%
% Inputs:
%   baselineAi - per-action AI-side comparison table (see
%                run_phase12e_one_step_result_validation)
%   oracleLog  - per-action oracle KPI table from evaluate_comparable_oracle_actions
%
% Output:
%   comparisonTable - per-action rows with baseline / AI / oracle / gap.

if isempty(baselineAi)
    comparisonTable = build_empty();
    return;
end

n = height(baselineAi);

% Index oracle log by ai_action_id.
oracleIdx = containers.Map('KeyType', 'double', 'ValueType', 'any');
for i = 1:height(oracleLog)
    oracleIdx(oracleLog.ai_action_id(i)) = oracleLog(i, :);
end

rows = cell(n, 31);
for i = 1:n
    aiRow = baselineAi(i, :);
    aiId = double(aiRow.action_id);

    if oracleIdx.isKey(aiId)
        oRow = oracleIdx(aiId);
        oracleAttach = oRow.oracle_attach_rate;
        oracleRsrp = oRow.oracle_mean_rsrp_dBm;
        oracleSinr = oRow.oracle_mean_sinr_dB;
        oracleLoad = oRow.oracle_mean_sector_load;
        oracleQos = oRow.oracle_qos_satisfaction_ratio;
        oracleTraffic = oRow.oracle_served_traffic_Mbps;
        oracleActionId = oRow.oracle_action_id;
        oracleStatus = oRow.oracle_kpi_comparison_status{1};
        oracleImplFlag = logical(oRow.oracle_implementable_flag);
    else
        oracleAttach = NaN; oracleRsrp = NaN; oracleSinr = NaN;
        oracleLoad = NaN; oracleQos = NaN; oracleTraffic = NaN;
        oracleActionId = NaN; oracleStatus = 'no_oracle_lookup';
        oracleImplFlag = false;
    end

    baselineQos = aiRow.pre_qos_satisfaction_ratio;
    baselineAttach = aiRow.pre_attach_rate;
    baselineSinr = aiRow.pre_mean_sinr_dB;
    baselineLoad = aiRow.pre_mean_sector_load;
    baselineRsrp = aiRow.pre_mean_rsrp_dBm;

    aiDeltaQos = aiRow.delta_qos_satisfaction_ratio;
    aiDeltaAttach = aiRow.delta_attach_rate;
    aiDeltaSinr = aiRow.delta_mean_sinr_dB;
    aiDeltaLoad = aiRow.delta_mean_sector_load;
    aiDeltaRsrp = aiRow.delta_mean_rsrp_dB;

    if isfinite(oracleQos)
        oracleDeltaQos = oracleQos - baselineQos;
        qosGap = oracleQos - aiRow.ai_post_qos_satisfaction_ratio;
    else
        oracleDeltaQos = NaN; qosGap = NaN;
    end
    if isfinite(oracleAttach)
        oracleDeltaAttach = oracleAttach - baselineAttach;
        attachGap = oracleAttach - aiRow.ai_post_attach_rate;
    else
        oracleDeltaAttach = NaN; attachGap = NaN;
    end
    if isfinite(oracleSinr)
        oracleDeltaSinr = oracleSinr - baselineSinr;
        sinrGap = oracleSinr - aiRow.ai_post_mean_sinr_dB;
    else
        oracleDeltaSinr = NaN; sinrGap = NaN;
    end
    if isfinite(oracleLoad)
        oracleDeltaLoad = oracleLoad - baselineLoad;
        loadGap = oracleLoad - aiRow.ai_post_mean_sector_load;
    else
        oracleDeltaLoad = NaN; loadGap = NaN;
    end

    rewardRegret = NaN;
    physicalKpiNote = '';
    if isfinite(qosGap)
        if qosGap > 0.05 && aiDeltaQos > 0
            physicalKpiNote = 'oracle achieves > 5pp QoS over AI despite AI also improving';
        elseif qosGap < -0.05
            physicalKpiNote = 'AI exceeds oracle KPI; possible reward-vs-KPI disagreement';
        end
    end

    rows(i, :) = {char(string(aiRow.scenario_name{1})), aiRow.realization_id, ...
        aiRow.coordinator_group_id, aiRow.module_name{1}, ...
        aiId, oracleActionId, oracleStatus, oracleImplFlag, ...
        baselineQos, aiRow.ai_post_qos_satisfaction_ratio, oracleQos, ...
        aiDeltaQos, oracleDeltaQos, qosGap, ...
        baselineAttach, aiRow.ai_post_attach_rate, oracleAttach, attachGap, ...
        baselineSinr, aiRow.ai_post_mean_sinr_dB, oracleSinr, sinrGap, ...
        baselineLoad, aiRow.ai_post_mean_sector_load, oracleLoad, loadGap, ...
        rewardRegret, physicalKpiNote, ...
        aiDeltaAttach, aiDeltaSinr, aiDeltaLoad};
end

comparisonTable = cell2table(rows, 'VariableNames', ...
    {'scenario_name','realization_id','coordinator_group_id','module_name', ...
    'ai_action_id','oracle_action_id','oracle_kpi_comparison_status','oracle_implementable_flag', ...
    'baseline_qos','ai_qos','oracle_qos','ai_delta_qos','oracle_delta_qos','qos_gap_to_oracle', ...
    'baseline_attach','ai_attach','oracle_attach','attach_gap_to_oracle', ...
    'baseline_sinr','ai_sinr','oracle_sinr','sinr_gap_to_oracle', ...
    'baseline_load','ai_load','oracle_load','load_gap_to_oracle', ...
    'reward_regret_if_available','physical_kpi_gap_note', ...
    'ai_delta_attach','ai_delta_sinr','ai_delta_load'});
end

function T = build_empty()
T = table('Size', [0 31], 'VariableTypes', repmat({'double'}, 1, 31), ...
    'VariableNames', {'scenario_name','realization_id','coordinator_group_id','module_name', ...
    'ai_action_id','oracle_action_id','oracle_kpi_comparison_status','oracle_implementable_flag', ...
    'baseline_qos','ai_qos','oracle_qos','ai_delta_qos','oracle_delta_qos','qos_gap_to_oracle', ...
    'baseline_attach','ai_attach','oracle_attach','attach_gap_to_oracle', ...
    'baseline_sinr','ai_sinr','oracle_sinr','sinr_gap_to_oracle', ...
    'baseline_load','ai_load','oracle_load','load_gap_to_oracle', ...
    'reward_regret_if_available','physical_kpi_gap_note', ...
    'ai_delta_attach','ai_delta_sinr','ai_delta_load'});
end
