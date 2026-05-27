function phase12e = run_phase12e_one_step_result_validation(cfg, baseTopology)
%RUN_PHASE12E_ONE_STEP_RESULT_VALIDATION Phase 12D validation + baseline/AI/oracle comparison.
%
% Phase 12E is OFFLINE final-comparison only:
%   1) validates Phase 12D applied only eligible COC/OH and LB/MLB actions
%   2) builds baseline vs AI/ML comparison from Phase 12D pre/post columns
%   3) classifies each AI row's outcome (improved / worsened / tradeoff)
%   4) for each AI row, looks up the Phase 8C oracle action; if the oracle
%      action is implementable by Phase 12B mapping, runs the same cloned-
%      state KPI evaluation for the oracle action
%   5) computes baseline / AI / oracle gaps and writes thesis-ready tables
%
% No simulator state is mutated globally. No multi-step loop. No full
% closed-loop claim.

requiredFiles = { ...
    'phase12d_one_step_kpi_update_results.csv', ...
    'phase11b_final_coordinator_decisions.csv', ...
    'phase8c_oracle_selected_actions.csv', ...
    'phase4_scenario_plan.csv'};
for i = 1:numel(requiredFiles)
    p = fullfile(cfg.tablesDir, requiredFiles{i});
    if ~isfile(p)
        error('Phase 12E: missing input %s', p);
    end
end

phase12d = readtable(fullfile(cfg.tablesDir, 'phase12d_one_step_kpi_update_results.csv'));
oracleTable = readtable(fullfile(cfg.tablesDir, 'phase8c_oracle_selected_actions.csv'));
scenarioPlan = readtable(fullfile(cfg.tablesDir, 'phase4_scenario_plan.csv'));

% (1) Build baseline vs AI table from Phase 12D.
baselineAi = build_baseline_ai_table(phase12d);

% (2) Outcome classification.
outcomes = classify_phase12e_kpi_outcomes(baselineAi);
baselineAi.outcome_class = outcomes.outcome_class;
baselineAi.tradeoff_flag = outcomes.tradeoff_flag;

% (3) Oracle comparable evaluation.
extendedBase = baseTopology;
if ~ismember('cio_dB', extendedBase.sectors.Properties.VariableNames)
    extendedBase = initialize_action_state_columns(extendedBase);
end
oracleLog = evaluate_comparable_oracle_actions(cfg, extendedBase, phase12d, oracleTable, scenarioPlan);

% (4) Combined baseline / AI / oracle comparison + gaps.
comparisonTable = compare_baseline_ai_oracle_kpis(baselineAi, oracleLog);

% (5) Summaries.
[moduleSummary, scenarioSummary, tradeoffSummary] = ...
    summarize_phase12e_final_comparison(baselineAi, comparisonTable);

% (6) Limitations table.
limitations = build_limitations_table(cfg, phase12d);

writetable(baselineAi,           fullfile(cfg.tablesDir, 'phase12e_baseline_ai_kpi_comparison.csv'));
writetable(comparisonTable,      fullfile(cfg.tablesDir, 'phase12e_baseline_ai_oracle_comparison.csv'));
writetable(oracleLog,            fullfile(cfg.tablesDir, 'phase12e_oracle_comparable_action_log.csv'));
outcomeTable = table(baselineAi.action_id, baselineAi.scenario_name, baselineAi.realization_id, ...
    baselineAi.module_name, baselineAi.outcome_class, baselineAi.tradeoff_flag, ...
    'VariableNames', {'action_id','scenario_name','realization_id','module_name','outcome_class','tradeoff_flag'});
writetable(outcomeTable,         fullfile(cfg.tablesDir, 'phase12e_kpi_outcome_classification.csv'));
writetable(moduleSummary,        fullfile(cfg.tablesDir, 'phase12e_summary_by_module.csv'));
writetable(scenarioSummary,      fullfile(cfg.tablesDir, 'phase12e_summary_by_scenario.csv'));
writetable(tradeoffSummary,      fullfile(cfg.tablesDir, 'phase12e_tradeoff_summary.csv'));
writetable(limitations,          fullfile(cfg.tablesDir, 'phase12e_limitations_table.csv'));

try_plot('plot_phase12e_baseline_ai_oracle_kpis', cfg, comparisonTable);
try_plot('plot_phase12e_kpi_delta_by_scenario', cfg, baselineAi);
try_plot('plot_phase12e_tradeoff_attach_vs_qos', cfg, baselineAi);
try_plot('plot_phase12e_oracle_gap_by_module', cfg, comparisonTable);
try_plot('plot_phase12e_final_outcome_counts', cfg, baselineAi);

validationTable = validate_phase12e_final_comparison(cfg, baselineAi, comparisonTable, ...
    oracleLog, moduleSummary, scenarioSummary, tradeoffSummary, limitations, phase12d);

phase12e = struct();
phase12e.baselineAi = baselineAi;
phase12e.comparisonTable = comparisonTable;
phase12e.oracleLog = oracleLog;
phase12e.moduleSummary = moduleSummary;
phase12e.scenarioSummary = scenarioSummary;
phase12e.tradeoffSummary = tradeoffSummary;
phase12e.limitations = limitations;
phase12e.validationTable = validationTable;

phase12e.numAiEvaluated = height(baselineAi);
phase12e.numOracleComparable = sum(strcmp(oracleLog.oracle_kpi_comparison_status, 'comparable_oracle_action') | ...
    strcmp(oracleLog.oracle_kpi_comparison_status, 'oracle_is_noop_baseline'));
phase12e.numOracleNotComparable = height(oracleLog) - phase12e.numOracleComparable;
phase12e.meanAiDeltaQos = mean(baselineAi.delta_qos_satisfaction_ratio, 'omitnan');
phase12e.meanAiDeltaAttach = mean(baselineAi.delta_attach_rate, 'omitnan');
phase12e.meanAiDeltaRsrp = mean(baselineAi.delta_mean_rsrp_dB, 'omitnan');
phase12e.meanAiDeltaSinr = mean(baselineAi.delta_mean_sinr_dB, 'omitnan');
phase12e.meanAiDeltaLoad = mean(baselineAi.delta_mean_sector_load, 'omitnan');
gapMask = isfinite(comparisonTable.qos_gap_to_oracle);
if any(gapMask)
    phase12e.meanQosGapToOracle = mean(comparisonTable.qos_gap_to_oracle(gapMask), 'omitnan');
else
    phase12e.meanQosGapToOracle = NaN;
end
phase12e.numTradeoffRows = sum(baselineAi.tradeoff_flag);
end

function T = build_baseline_ai_table(phase12d)
n = height(phase12d);
if n == 0
    T = build_empty_baseline_ai();
    return;
end
T = table( ...
    cellstr(string(phase12d.scenario_name)), phase12d.realization_id, ...
    phase12d.coordinator_group_id, cellstr(string(phase12d.module_name)), ...
    cellstr(string(phase12d.action_type)), phase12d.action_id, ...
    phase12d.pre_attach_rate, phase12d.post_attach_rate, phase12d.delta_attach_rate, ...
    phase12d.pre_mean_rsrp_dBm, phase12d.post_mean_rsrp_dBm, phase12d.delta_mean_rsrp_dB, ...
    phase12d.pre_mean_sinr_dB, phase12d.post_mean_sinr_dB, phase12d.delta_mean_sinr_dB, ...
    phase12d.pre_mean_sector_load, phase12d.post_mean_sector_load, phase12d.delta_mean_sector_load, ...
    phase12d.pre_qos_satisfaction_ratio, phase12d.post_qos_satisfaction_ratio, phase12d.delta_qos_satisfaction_ratio, ...
    phase12d.pre_total_served_traffic_Mbps, phase12d.post_total_served_traffic_Mbps, phase12d.delta_served_traffic_Mbps, ...
    'VariableNames', {'scenario_name','realization_id','coordinator_group_id', ...
    'module_name','action_type','action_id', ...
    'pre_attach_rate','ai_post_attach_rate','delta_attach_rate', ...
    'pre_mean_rsrp_dBm','ai_post_mean_rsrp_dBm','delta_mean_rsrp_dB', ...
    'pre_mean_sinr_dB','ai_post_mean_sinr_dB','delta_mean_sinr_dB', ...
    'pre_mean_sector_load','ai_post_mean_sector_load','delta_mean_sector_load', ...
    'pre_qos_satisfaction_ratio','ai_post_qos_satisfaction_ratio','delta_qos_satisfaction_ratio', ...
    'pre_served_traffic_Mbps','ai_post_served_traffic_Mbps','delta_served_traffic_Mbps'});
end

function T = build_empty_baseline_ai()
T = table('Size', [0 26], 'VariableTypes', repmat({'double'}, 1, 26), ...
    'VariableNames', {'scenario_name','realization_id','coordinator_group_id', ...
    'module_name','action_type','action_id', ...
    'pre_attach_rate','ai_post_attach_rate','delta_attach_rate', ...
    'pre_mean_rsrp_dBm','ai_post_mean_rsrp_dBm','delta_mean_rsrp_dB', ...
    'pre_mean_sinr_dB','ai_post_mean_sinr_dB','delta_mean_sinr_dB', ...
    'pre_mean_sector_load','ai_post_mean_sector_load','delta_mean_sector_load', ...
    'pre_qos_satisfaction_ratio','ai_post_qos_satisfaction_ratio','delta_qos_satisfaction_ratio', ...
    'pre_served_traffic_Mbps','ai_post_served_traffic_Mbps','delta_served_traffic_Mbps', ...
    'outcome_class','tradeoff_flag'});
end

function T = build_limitations_table(cfg, phase12d)
appliedCoc = 0;
appliedLb = 0;
appliedTotal = height(phase12d);
executableTotal = NaN;

if ~isempty(phase12d) && ismember('module_name', phase12d.Properties.VariableNames)
    appliedCoc = sum(strcmp(string(phase12d.module_name), "COC/OH"));
    appliedLb = sum(strcmp(string(phase12d.module_name), "LB/MLB"));
end

execFile = fullfile(cfg.tablesDir, 'phase11b_final_executable_actions.csv');
if isfile(execFile)
    execTable = readtable(execFile);
    executableTotal = height(execTable);
end
if isnan(executableTotal)
    appliedText = sprintf('Only COC/OH and LB/MLB actions are applied; %d + %d = %d applied rows.', ...
        appliedCoc, appliedLb, appliedTotal);
else
    appliedText = sprintf('Only COC/OH and LB/MLB actions are applied; %d + %d = %d of %d executable rows.', ...
        appliedCoc, appliedLb, appliedTotal, executableTotal);
end
rows = {
    'one_step_only',                'Single-shot KPI(t)->KPI(t+1); no temporal evolution.';
    'cloned_state_only',            'Actions never mutate the live simulator state.';
    'only_coc_lb_applied',          appliedText;
    'es_sleep_excluded',            'ES sleep actions are not applied (state flag exists, RF/KPI hookup pending).';
    'homro_excluded',               'HO/MRO HOM/TTT actions are not applied (state placeholders, no temporal HO model).';
    'attach_rate_drop_observed',    'CIO-only association bias can move UEs below the -105 dBm attach threshold.';
    'oracle_only_comparable_when_implementable', 'Oracle KPI(t+1) is computed only for COC/OH or LB/MLB oracle picks; HO/MRO oracle picks are marked not_comparable.';
    'single_step_only_no_kpi_feedback',  'Multi-step iteration, action application to live state, and KPI(t+1) feedback to next decision are not implemented.';
    };
T = cell2table(rows, 'VariableNames', {'limitation_id','description'});
end

function try_plot(fnName, cfg, T)
if exist(fnName, 'file') ~= 2 || isempty(T)
    return;
end
try
    feval(fnName, cfg, T);
catch ME
    warning('Phase 12E plot %s failed: %s', fnName, ME.message);
end
end
