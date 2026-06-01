function [moduleSummary, scenarioSummary, tradeoffSummary] = summarize_phase12e_final_comparison(baselineAi, comparisonTable)
%SUMMARIZE_PHASE12E_FINAL_COMPARISON Per-module, per-scenario, and tradeoff tallies.

moduleSummary = table();
scenarioSummary = table();
tradeoffSummary = table();
if isempty(baselineAi)
    return;
end

modules = unique(string(baselineAi.module_name), 'stable');
nM = numel(modules);
mRows = cell(nM, 9);
for k = 1:nM
    m = modules(k);
    mask = string(baselineAi.module_name) == m;
    sub = baselineAi(mask, :);
    mRows(k, :) = {char(m), height(sub), ...
        sum(strcmp(sub.outcome_class, 'improved')), ...
        sum(strcmp(sub.outcome_class, 'improved_with_tradeoff')), ...
        sum(strcmp(sub.outcome_class, 'worsened')), ...
        sum(strcmp(sub.outcome_class, 'unchanged')), ...
        sum(strcmp(sub.outcome_class, 'mixed')), ...
        mean(sub.delta_qos_satisfaction_ratio, 'omitnan'), ...
        mean(sub.delta_attach_rate, 'omitnan')};
end
moduleSummary = cell2table(mRows, 'VariableNames', {'module_name','total_actions', ...
    'improved','improved_with_tradeoff','worsened','unchanged','mixed', ...
    'mean_delta_qos','mean_delta_attach'});

scenarios = unique(string(baselineAi.scenario_name), 'stable');
nS = numel(scenarios);
sRows = cell(nS, 9);
for k = 1:nS
    s = scenarios(k);
    mask = string(baselineAi.scenario_name) == s;
    sub = baselineAi(mask, :);
    if ~isempty(comparisonTable)
        subCmp = comparisonTable(string(comparisonTable.scenario_name) == s & ...
            isfinite(comparisonTable.qos_gap_to_oracle), :);
        meanGap = mean(subCmp.qos_gap_to_oracle, 'omitnan');
    else
        meanGap = NaN;
    end
    sRows(k, :) = {char(s), height(sub), ...
        sum(strcmp(sub.outcome_class, 'improved')), ...
        sum(strcmp(sub.outcome_class, 'improved_with_tradeoff')), ...
        sum(strcmp(sub.outcome_class, 'worsened')), ...
        sum(strcmp(sub.outcome_class, 'unchanged')), ...
        mean(sub.delta_qos_satisfaction_ratio, 'omitnan'), ...
        mean(sub.delta_attach_rate, 'omitnan'), ...
        meanGap};
end
scenarioSummary = cell2table(sRows, 'VariableNames', {'scenario_name','total_actions', ...
    'improved','improved_with_tradeoff','worsened','unchanged', ...
    'mean_delta_qos','mean_delta_attach','mean_qos_gap_to_oracle'});

% Tradeoff summary
dq = baselineAi.delta_qos_satisfaction_ratio;
ds = baselineAi.delta_mean_sinr_dB;
dl = baselineAi.delta_mean_sector_load;
da = baselineAi.delta_attach_rate;
dr = baselineAi.delta_mean_rsrp_dB;
scn = string(baselineAi.scenario_name);
tradeoffRows = {
    'qos_up_attach_down',           sum(dq > 1e-3 & da < -1e-3);
    'sinr_up_attach_down',          sum(ds > 1e-3 & da < -1e-3);
    'load_down_attach_down',        sum(dl < -1e-3 & da < -1e-3);
    'qos_down_despite_rsrp_sinr_up', sum(dq < -1e-3 & ds > 1e-3 & dr > 1e-3);
    'overload_qos_improved',        sum(scn == "overload" & dq > 1e-3);
    'degraded_qos_worsened',        sum(scn == "degraded_sector" & dq < -1e-3);
    'handover_stress_qos_worsened', sum(scn == "handover_stress" & dq < -1e-3);
    };
tradeoffSummary = cell2table(tradeoffRows, 'VariableNames', {'tradeoff_pattern','count'});
end
