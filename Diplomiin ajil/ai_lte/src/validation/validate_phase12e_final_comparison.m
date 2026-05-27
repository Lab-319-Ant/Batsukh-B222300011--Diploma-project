function validationTable = validate_phase12e_final_comparison(cfg, baselineAi, comparisonTable, oracleLog, moduleSummary, scenarioSummary, tradeoffSummary, limitations, phase12d)
%VALIDATE_PHASE12E_FINAL_COMPARISON Phase 12E integrity checks.

rows = {};

% (1) baseline-vs-AI exists
bf = fullfile(cfg.tablesDir, 'phase12e_baseline_ai_kpi_comparison.csv');
rows = add_check(rows, 'baseline_ai_comparison_exists', 'error', ...
    isfile(bf) && ~isempty(baselineAi), sprintf('%d rows', height(baselineAi)), '> 0', ...
    'phase12e_baseline_ai_kpi_comparison.csv must be written and non-empty.');

% (2) oracle comparison exists
cf = fullfile(cfg.tablesDir, 'phase12e_baseline_ai_oracle_comparison.csv');
rows = add_check(rows, 'baseline_ai_oracle_comparison_exists', 'error', ...
    isfile(cf) && ~isempty(comparisonTable), sprintf('%d rows', height(comparisonTable)), '> 0', ...
    'phase12e_baseline_ai_oracle_comparison.csv must be written.');

% (3) outcome classification exists
oc = fullfile(cfg.tablesDir, 'phase12e_kpi_outcome_classification.csv');
rows = add_check(rows, 'outcome_classification_exists', 'error', isfile(oc), ...
    logical_to_text(isfile(oc)), '== true', ...
    'phase12e_kpi_outcome_classification.csv must be written.');

% (4) summary by module exists
rows = add_check(rows, 'summary_by_module_exists', 'error', ...
    ~isempty(moduleSummary), sprintf('%d rows', height(moduleSummary)), '> 0', ...
    'phase12e_summary_by_module.csv must have rows.');

% (5) summary by scenario exists
rows = add_check(rows, 'summary_by_scenario_exists', 'error', ...
    ~isempty(scenarioSummary), sprintf('%d rows', height(scenarioSummary)), '> 0', ...
    'phase12e_summary_by_scenario.csv must have rows.');

% (6) limitations table exists
rows = add_check(rows, 'limitations_table_exists', 'error', ...
    ~isempty(limitations), sprintf('%d rows', height(limitations)), '> 0', ...
    'phase12e_limitations_table.csv must have rows.');

% (7) only Phase 12D evaluated actions in AI comparison
notIn12d = sum(~ismember(baselineAi.action_id, phase12d.action_id));
rows = add_check(rows, 'only_phase12d_actions_in_ai_compare', 'error', notIn12d == 0, ...
    sprintf('%d not in phase12d', notIn12d), '== 0', ...
    'Every AI/ML comparison row must come from phase12d_one_step_kpi_update_results.csv.');

% (8) no ES in applied KPI comparison
esCount = sum(strcmp(baselineAi.module_name, 'ES'));
rows = add_check(rows, 'no_es_in_applied_comparison', 'error', esCount == 0, ...
    sprintf('%d ES rows', esCount), '== 0', 'No ES action may appear in the applied KPI comparison.');

% (9) no HO/MRO in applied KPI comparison
hoCount = sum(strcmp(baselineAi.module_name, 'HO/MRO'));
rows = add_check(rows, 'no_homro_in_applied_comparison', 'error', hoCount == 0, ...
    sprintf('%d HO/MRO rows', hoCount), '== 0', 'No HO/MRO action may appear in the applied KPI comparison.');

% (10) no unresolved fallback / rejected / no-op in applied comparison
finalDecisionsFile = fullfile(cfg.tablesDir, 'phase11b_final_coordinator_decisions.csv');
forbiddenApplied = 0;
if isfile(finalDecisionsFile)
    fd = readtable(finalDecisionsFile);
    forbiddenIds = fd.selected_action_id_safe(strcmp(fd.final_decision_status, 'unresolved_unsafe_fallback') | ...
        strcmp(fd.final_decision_status, 'rejected_priority_conflict') | ...
        strcmp(fd.final_decision_status, 'rejected_safety_conflict') | ...
        strcmp(fd.final_decision_status, 'final_noop'));
    forbiddenApplied = sum(ismember(baselineAi.action_id, forbiddenIds));
end
rows = add_check(rows, 'no_forbidden_classes_applied', 'error', forbiddenApplied == 0, ...
    sprintf('%d violations', forbiddenApplied), '== 0', ...
    'No unresolved fallback, rejected, or no-op action may appear in the applied KPI comparison.');

% (11) all KPI values finite
[nonFinite, note] = check_finite(baselineAi);
rows = add_check(rows, 'all_kpi_values_finite', 'error', nonFinite == 0, ...
    note, '== 0', 'AI-side KPI values must be finite in the baseline-vs-AI table.');

% (12) KPI ranges valid
[outOfRange, rangeNote] = check_ranges(baselineAi);
rows = add_check(rows, 'kpi_ranges_valid', 'error', outOfRange == 0, rangeNote, '== 0', ...
    'KPI values must lie in physically plausible ranges.');

% (13) oracle KPI computed only for implementable
unmarkedNonImpl = sum(comparisonTable.oracle_implementable_flag == false & ...
    isfinite(comparisonTable.oracle_qos));
rows = add_check(rows, 'oracle_kpi_only_for_implementable', 'error', unmarkedNonImpl == 0, ...
    sprintf('%d non-implementable oracle rows with finite oracle KPI', unmarkedNonImpl), '== 0', ...
    'Oracle KPI must be NaN when oracle action is not implementable.');

% (14) non-implementable oracle rows marked not_comparable / not fabricated
nonImplFabricated = sum(~strcmp(oracleLog.oracle_kpi_comparison_status, 'comparable_oracle_action') & ...
    ~strcmp(oracleLog.oracle_kpi_comparison_status, 'oracle_is_noop_baseline') & ...
    isfinite(oracleLog.oracle_qos_satisfaction_ratio));
rows = add_check(rows, 'non_implementable_oracle_not_fabricated', 'error', ...
    nonImplFabricated == 0, sprintf('%d fabricated rows', nonImplFabricated), '== 0', ...
    'Non-implementable oracle rows must carry NaN KPI, not fabricated numbers.');

% (15) attach-rate degradation reported if present
meanDeltaAttach = mean(baselineAi.delta_attach_rate, 'omitnan');
if meanDeltaAttach < -0.01
    rows = add_check(rows, 'attach_rate_degradation_reported', 'warning', false, ...
        sprintf('mean delta_attach = %.4f', meanDeltaAttach), 'mean >= 0', ...
        'Mean attach rate dropped after AI/ML actions; reported honestly.');
else
    rows = add_check(rows, 'attach_rate_degradation_reported', 'diagnostic', true, ...
        sprintf('mean delta_attach = %.4f', meanDeltaAttach), 'n/a', ...
        'Mean attach rate not significantly negative.');
end

% (16) KPI worsening rows reported, not hidden
worseningRows = sum(strcmp(baselineAi.outcome_class, 'worsened') | ...
    strcmp(baselineAi.outcome_class, 'improved_with_tradeoff'));
rows = add_check(rows, 'kpi_worsening_reported', 'diagnostic', true, ...
    sprintf('%d worsening/tradeoff rows', worseningRows), 'n/a', ...
    'Worsening or tradeoff rows are exposed via outcome_class and tradeoff_flag.');

% (17) no global state mutation (structural)
[hit, evidence] = scan_for_simulator_mutation();
rows = add_check(rows, 'no_global_state_mutation', 'error', ~hit, evidence, ...
    '== false', 'Phase 12E source must not mutate live simulator state outside cloned topologies.');

% (18) no multi-step loop
[loopHit, loopEv] = scan_for_loop_constructs();
rows = add_check(rows, 'no_multi_step_loop', 'error', ~loopHit, loopEv, ...
    '== false', 'Phase 12E orchestrator must not implement multi-step KPI loops.');

% (19) no full closed-loop claim columns
clCols = intersect({'applied_to_simulator','closed_loop_state_update','final_closed_loop_flag'}, ...
    baselineAi.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(clCols), ...
    strjoin(clCols, ', '), '== empty', 'No closed-loop column may appear in Phase 12E outputs.');

% (20) tradeoff summary populated
rows = add_check(rows, 'tradeoff_summary_exists', 'error', ...
    ~isempty(tradeoffSummary), sprintf('%d rows', height(tradeoffSummary)), '> 0', ...
    'phase12e_tradeoff_summary.csv must have rows.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase12e_final_comparison_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function s = logical_to_text(v), if v, s = 'true'; else, s = 'false'; end, end

function [nonFinite, note] = check_finite(T)
nonFinite = 0;
cols = {'ai_post_attach_rate','ai_post_mean_rsrp_dBm','ai_post_mean_sinr_dB', ...
    'ai_post_mean_sector_load','ai_post_qos_satisfaction_ratio'};
for i = 1:numel(cols)
    if ismember(cols{i}, T.Properties.VariableNames)
        nonFinite = nonFinite + sum(~isfinite(T.(cols{i})));
    end
end
note = sprintf('%d non-finite values', nonFinite);
end

function [outOfRange, note] = check_ranges(T)
outOfRange = 0;
if isempty(T), note = '0'; return; end
bad = (T.ai_post_attach_rate < 0 | T.ai_post_attach_rate > 1) | ...
    (T.ai_post_qos_satisfaction_ratio < 0 | T.ai_post_qos_satisfaction_ratio > 1.001) | ...
    (T.ai_post_mean_sector_load < 0 | T.ai_post_mean_sector_load > 100) | ...
    (T.ai_post_mean_rsrp_dBm < -200 | T.ai_post_mean_rsrp_dBm > 0) | ...
    (T.ai_post_mean_sinr_dB < -50 | T.ai_post_mean_sinr_dB > 100);
outOfRange = sum(bad);
note = sprintf('%d out-of-range rows', outOfRange);
end

function [hit, evidence] = scan_for_simulator_mutation()
hit = false; evidence = 'no live-state mutation found';
src = which('run_phase12e_one_step_result_validation');
if isempty(src) || ~isfile(src), hit = true; evidence = 'orchestrator source not located'; return; end
contents = fileread(src);
forbidden = {'kpi_t_plus_1','next_state_dataset','closed_loop','apply_action_to_simulator'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i}), found{end+1} = forbidden{i}; end %#ok<AGROW>
end
if ~isempty(found), hit = true; evidence = sprintf('found: %s', strjoin(found, ', ')); end
end

function [hit, evidence] = scan_for_loop_constructs()
hit = false; evidence = 'no multi-step loop constructs';
src = which('run_phase12e_one_step_result_validation');
if isempty(src) || ~isfile(src), hit = true; evidence = 'orchestrator source not located'; return; end
contents = fileread(src);
forbidden = {'for kpi_step','for time_step','iterate_kpi','for tt = 1','closed_loop_iteration'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i}), found{end+1} = forbidden{i}; end %#ok<AGROW>
end
if ~isempty(found), hit = true; evidence = sprintf('found: %s', strjoin(found, ', ')); end
end
