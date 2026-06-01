function validationTable = validate_phase13_final_result_package(cfg, packageDir, tables, manifest, limitations, narrativePaths, beforeAfter)
%VALIDATE_PHASE13_FINAL_RESULT_PACKAGE Phase 13 final-package integrity checks (25 checks).

rows = {};

% (1) thesis_package exists
rows = add_check(rows, 'thesis_package_folder_exists', 'error', isfolder(packageDir), ...
    logical_to_text(isfolder(packageDir)), '== true', ...
    'results/thesis_package/ must exist.');

% (2) all required package files exist
requiredFiles = { ...
    'final_result_summary.md', 'final_architecture_summary.md', ...
    'final_module_status_table.csv', 'final_baseline_ai_oracle_summary.csv', ...
    'final_kpi_improvement_summary.csv', 'final_scenario_summary.csv', ...
    'final_module_validation_summary.csv', 'final_safety_coordination_summary.csv', ...
    'final_oracle_regret_summary.csv', 'final_limitations_table.csv', ...
    'final_figure_manifest.csv', 'final_thesis_claims_and_boundaries.md', ...
    'final_before_after_kpi_summary.csv', 'final_before_after_kpi_by_module.csv', ...
    'final_before_after_kpi_by_scenario.csv', 'final_before_after_kpi_interpretation.md', ...
    'final_result_report_draft.md'};
missing = {};
for i = 1:numel(requiredFiles)
    if ~isfile(fullfile(packageDir, requiredFiles{i}))
        missing{end+1} = requiredFiles{i}; %#ok<AGROW>
    end
end
rows = add_check(rows, 'all_required_files_present', 'error', isempty(missing), ...
    strjoin(missing, ', '), '== empty', 'Every required Phase 13 file must be written.');

% (3) package uses corrected post-fix values (not the 104-action stale signature)
applied = headline_applied(tables);
rows = add_check(rows, 'package_uses_corrected_post_fix_values', 'error', ...
    applied ~= 104 && applied > 0, sprintf('applied=%d', applied), '~= 104 and > 0', ...
    'Phase 13 must use corrected post-fix Phase 12E values, not the stale 104-action result.');

% (4) final KPI summary reports a positive applied count
rows = add_check(rows, 'kpi_summary_reports_applied_count', 'error', applied > 0, ...
    sprintf('applied=%d', applied), '> 0', ...
    'Final KPI improvement summary must report a positive applied_action_count.');

% (5) attach-rate degradation reported
dAttach = headline_value(tables, 'delta_attach_rate');
rows = add_check(rows, 'kpi_summary_reports_attach_rate_degradation', 'error', ...
    isfinite(dAttach) && dAttach < 0, sprintf('delta_attach_rate=%+0.4f', dAttach), '< 0', ...
    'Final KPI improvement summary must reflect attach-rate degradation.');

% (6) positive RSRP/SINR/QoS deltas and negative load delta
dRsrp = headline_value(tables, 'delta_mean_rsrp_dB');
dSinr = headline_value(tables, 'delta_mean_sinr_dB');
dLoad = headline_value(tables, 'delta_mean_sector_load');
dQos  = headline_value(tables, 'delta_qos_satisfaction_ratio');
posDeltasOk = dRsrp > 0 && dSinr > 0 && dLoad < 0 && dQos > 0;
rows = add_check(rows, 'kpi_summary_reports_positive_rsrp_sinr_load_qos_deltas', 'error', ...
    posDeltasOk, sprintf('dRsrp=%+0.4f dSinr=%+0.4f dLoad=%+0.4f dQos=%+0.4f', ...
        dRsrp, dSinr, dLoad, dQos), 'rsrp>0, sinr>0, load<0, qos>0', ...
    'Final KPI improvement summary must reflect the expected positive RSRP/SINR/QoS gains and load reduction.');

% (7) final_before_after_kpi_summary.csv exists
beforeAfterFile = fullfile(packageDir, 'final_before_after_kpi_summary.csv');
rows = add_check(rows, 'before_after_kpi_summary_exists', 'error', isfile(beforeAfterFile), ...
    logical_to_text(isfile(beforeAfterFile)), '== true', ...
    'final_before_after_kpi_summary.csv must exist.');

% (8) before values are finite
[beforeFinite, baNote1] = check_finite_column(beforeAfter.summary, 'baseline_kpi_t');
rows = add_check(rows, 'before_values_finite', 'error', beforeFinite, baNote1, '== true', ...
    'baseline_kpi_t values must be finite.');

% (9) after values are finite
[afterFinite, baNote2] = check_finite_column(beforeAfter.summary, 'ai_ml_kpi_t_plus_1');
rows = add_check(rows, 'after_values_finite', 'error', afterFinite, baNote2, '== true', ...
    'ai_ml_kpi_t_plus_1 values must be finite.');

% (10) delta == after - before within tolerance
[deltaConsistent, baNote3] = check_delta_consistency(beforeAfter.summary);
rows = add_check(rows, 'delta_matches_after_minus_before', 'error', deltaConsistent, ...
    baNote3, '|err| < 1e-6 per row', ...
    'Each delta value must equal ai_ml_kpi_t_plus_1 - baseline_kpi_t within tolerance.');

% (11) final_result_summary.md contains the Before-and-After section header
summaryText = read_file_text(narrativePaths.summary_md);
rows = add_check(rows, 'summary_contains_before_after_section', 'error', ...
    contains(summaryText, 'Before-and-After KPI(t)->KPI(t+1) Result'), ...
    logical_to_text(contains(summaryText, 'Before-and-After KPI(t)->KPI(t+1) Result')), '== true', ...
    'final_result_summary.md must include the section "Before-and-After KPI(t)->KPI(t+1) Result".');

% (12) final module table contains all required modules
expectedModules = {'RF/KPI simulation','Scenario generation','Clustering monitor','COD','TP','QP', ...
    'COC/OH','LB/MLB','ES','HO/MRO','Oracle','Action-value ML','Safety filter','Coordinator','One-step KPI(t)->KPI(t+1)'};
moduleNames = {};
if ~isempty(tables.moduleStatus)
    moduleNames = tables.moduleStatus.module_name;
end
missingMods = setdiff(expectedModules, moduleNames);
rows = add_check(rows, 'module_status_contains_expected_modules', 'error', ...
    isempty(missingMods), strjoin(missingMods, ', '), '== empty', ...
    'final_module_status_table.csv must list every expected module.');

% (13) ES marked not physically applied to KPI(t+1)
[esOk, esStatus] = check_module_status_phrase(tables.moduleStatus, 'ES', 'not_applied_to_kpi_t_plus_1');
rows = add_check(rows, 'es_marked_not_physically_applied', 'error', esOk, esStatus, ...
    'contains not_applied_to_kpi_t_plus_1', 'ES row must carry not-applied-to-KPI(t+1) status.');

% (14) HO/MRO marked not physically applied to KPI(t+1)
[hoOk, hoStatus] = check_module_status_phrase(tables.moduleStatus, 'HO/MRO', 'not_applied_to_kpi_t_plus_1');
rows = add_check(rows, 'homro_marked_not_physically_applied', 'error', hoOk, hoStatus, ...
    'contains not_applied_to_kpi_t_plus_1', 'HO/MRO row must carry not-applied-to-KPI(t+1) status.');

% (15) QP marked bounded/support with limitation
qpLimitOk = false;
if ~isempty(tables.moduleStatus)
    qpRow = tables.moduleStatus(strcmp(tables.moduleStatus.module_name, 'QP'), :);
    if ~isempty(qpRow)
        text = lower(string(qpRow.limitation{1}));
        qpLimitOk = contains(text, 'bimodal') || contains(text, 'binary') || contains(text, 'bounded');
    end
end
rows = add_check(rows, 'qp_limitation_documented', 'error', qpLimitOk, ...
    logical_to_text(qpLimitOk), '== true', ...
    'QP row must document the bimodal/bounded-support limitation.');

% (16) QP raw scatter not marked main_thesis_figure
[qpRawOk, qpRawNote] = check_figure_role_not_main(manifest, 'qp_raw_actual_vs_predicted');
rows = add_check(rows, 'qp_raw_scatter_not_main_thesis_figure', 'error', qpRawOk, qpRawNote, ...
    '!= main_thesis_figure', 'Raw Phase 7C QP actual-vs-predicted must NOT be a main thesis figure.');

% (17) Phase 9B actual-vs-predicted reward scatter not marked main
[p9bOk, p9bNote] = check_figure_role_not_main(manifest, 'phase9b_action_value_actual_vs_predicted');
rows = add_check(rows, 'phase9b_actual_vs_predicted_not_main_thesis_figure', 'error', p9bOk, p9bNote, ...
    '!= main_thesis_figure', 'Phase 9B actual-vs-predicted reward scatter must NOT be a main thesis figure.');

% (18) no "full closed-loop" / "multi-step closed-loop control" claimed as achieved
hasForbiddenClosed = contains(summaryText, 'achieved full closed-loop') || ...
    contains(summaryText, 'is a closed-loop SON controller') || ...
    contains(summaryText, 'demonstrates closed-loop control');
rows = add_check(rows, 'no_full_closed_loop_achievement_claim', 'error', ~hasForbiddenClosed, ...
    logical_to_text(hasForbiddenClosed), '== false', ...
    'final_result_summary.md must not claim full closed-loop control as an achieved result.');

% (19) no commercial AI-RAN deployment claim
hasForbiddenComm = contains(summaryText, 'commercial AI-RAN deployment was') || ...
    contains(summaryText, 'achieves commercial AI-RAN') || ...
    contains(summaryText, 'deployed in a commercial');
rows = add_check(rows, 'no_commercial_ai_ran_claim', 'error', ~hasForbiddenComm, ...
    logical_to_text(hasForbiddenComm), '== false', ...
    'final_result_summary.md must not claim commercial AI-RAN deployment.');

% (20) no "all modules physically applied" claim
hasAllAppliedClaim = contains(summaryText, 'all modules were physically applied') || ...
    contains(summaryText, 'every module was physically applied');
rows = add_check(rows, 'no_all_modules_applied_claim', 'error', ~hasAllAppliedClaim, ...
    logical_to_text(hasAllAppliedClaim), '== false', ...
    'final_result_summary.md must not claim that all modules were physically applied.');

% (21) limitations table non-empty
rows = add_check(rows, 'limitations_table_nonempty', 'error', ~isempty(limitations), ...
    sprintf('%d rows', height(limitations)), '> 0', ...
    'final_limitations_table.csv must contain limitation statements.');

% (22) figure manifest references at least one available figure
nAvail = 0;
if ~isempty(manifest), nAvail = sum(logical(manifest.available_flag)); end
rows = add_check(rows, 'figure_manifest_references_available_figures', 'error', ...
    ~isempty(manifest) && nAvail >= 1, sprintf('%d / %d available', nAvail, height(manifest)), ...
    '>= 1 available', 'Figure manifest must reference at least one available figure.');

% (23) no new model training in Phase 13 source (structural)
[trainHit, trainEv] = scan_for_training_or_application();
rows = add_check(rows, 'no_new_training_in_phase13', 'error', ~trainHit, trainEv, ...
    '== false', 'Phase 13 source must not call ML training functions.');

% (24) no new action application in Phase 13 source (structural)
[appHit, appEv] = scan_for_action_application();
rows = add_check(rows, 'no_new_action_application_in_phase13', 'error', ~appHit, appEv, ...
    '== false', 'Phase 13 must not apply actions to the live simulator.');

% (25) package has no unexpected stale files at top level
[staleOk, staleNote] = check_no_stale_at_top_level(packageDir);
rows = add_check(rows, 'no_stale_files_at_top_level', 'error', staleOk, staleNote, ...
    '== true', 'Any pre-fix files must be archived into thesis_package/stale_<timestamp>/, not at top level.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function s = logical_to_text(v), if v, s = 'true'; else, s = 'false'; end, end

function applied = headline_applied(tables)
applied = 0;
if isempty(tables.kpiImprovement), return; end
KI = tables.kpiImprovement;
mask = strcmp(KI.metric, 'applied_action_count');
if any(mask), applied = round(KI.value(find(mask, 1, 'first'))); end
end

function v = headline_value(tables, metricName)
v = NaN;
if isempty(tables.kpiImprovement), return; end
KI = tables.kpiImprovement;
mask = strcmp(KI.metric, metricName);
if any(mask), v = KI.value(find(mask, 1, 'first')); end
end

function [ok, note] = check_finite_column(T, colName)
ok = true; note = 'ok';
if isempty(T) || ~ismember(colName, T.Properties.VariableNames)
    ok = false; note = sprintf('missing column %s', colName); return;
end
nNonFinite = sum(~isfinite(T.(colName)));
if nNonFinite > 0
    ok = false; note = sprintf('%d non-finite in %s', nNonFinite, colName); return;
end
end

function [ok, note] = check_delta_consistency(T)
ok = true; note = 'ok';
if isempty(T), ok = false; note = 'no before/after rows'; return; end
err = T.delta - (T.ai_ml_kpi_t_plus_1 - T.baseline_kpi_t);
worst = max(abs(err(isfinite(err))));
if isempty(worst), ok = false; note = 'no finite rows'; return; end
ok = worst < 1e-6;
note = sprintf('max |err| = %.3g', worst);
end

function txt = read_file_text(filePath)
txt = '';
if ~isfile(filePath), return; end
try
    fid = fopen(filePath, 'r');
    raw = fread(fid, '*char')';
    fclose(fid);
    txt = raw;
catch
    txt = '';
end
end

function [ok, status] = check_module_status_phrase(moduleStatus, moduleName, phrase)
ok = false; status = '(missing module row)';
if isempty(moduleStatus), return; end
row = moduleStatus(strcmp(moduleStatus.module_name, moduleName), :);
if isempty(row), return; end
status = row.physical_KPI_update_status{1};
ok = contains(string(status), phrase);
end

function [ok, note] = check_figure_role_not_main(manifest, figureKey)
ok = true; note = sprintf('%s not present', figureKey);
if isempty(manifest), return; end
idx = find(strcmp(manifest.figure_key, figureKey), 1, 'first');
if isempty(idx), return; end
note = sprintf('%s role=%s', figureKey, manifest.figure_role{idx});
ok = ~strcmp(manifest.figure_role{idx}, 'main_thesis_figure');
end

function [hit, evidence] = scan_for_training_or_application()
hit = false; evidence = 'no training/application calls found';
src = which('run_phase13_final_result_package');
if isempty(src) || ~isfile(src), hit = true; evidence = 'orchestrator source not located'; return; end
contents = fileread(src);
forbidden = {'fitrensemble','TreeBagger','train_regression_model', ...
    'kpi_t_plus_1_data','next_state_dataset'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i}), found{end+1} = forbidden{i}; end %#ok<AGROW>
end
if ~isempty(found), hit = true; evidence = sprintf('found: %s', strjoin(found, ', ')); end
end

function [hit, evidence] = scan_for_action_application()
hit = false; evidence = 'no action-application calls in phase 13';
src = which('run_phase13_final_result_package');
if isempty(src) || ~isfile(src), hit = true; evidence = 'orchestrator source not located'; return; end
contents = fileread(src);
forbidden = {'apply_eligible_actions_to_cloned_state','apply_single_action_to_cloned_state', ...
    'apply_action_to_simulator','recompute_kpis_after_action'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i}), found{end+1} = forbidden{i}; end %#ok<AGROW>
end
if ~isempty(found), hit = true; evidence = sprintf('found: %s', strjoin(found, ', ')); end
end

function [ok, note] = check_no_stale_at_top_level(packageDir)
ok = true; note = 'ok';
listing = dir(packageDir);
listing = listing(~[listing.isdir]);
expected = {'final_result_summary.md', 'final_architecture_summary.md', ...
    'final_module_status_table.csv', 'final_baseline_ai_oracle_summary.csv', ...
    'final_kpi_improvement_summary.csv', 'final_scenario_summary.csv', ...
    'final_module_validation_summary.csv', 'final_safety_coordination_summary.csv', ...
    'final_oracle_regret_summary.csv', 'final_limitations_table.csv', ...
    'final_figure_manifest.csv', 'final_thesis_claims_and_boundaries.md', ...
    'final_before_after_kpi_summary.csv', 'final_before_after_kpi_by_module.csv', ...
    'final_before_after_kpi_by_scenario.csv', 'final_before_after_kpi_interpretation.md', ...
    'final_result_report_draft.md', 'final_before_after_kpi_comparison.png', ...
    'final_result_package_validation.csv'};
unexpected = {};
for i = 1:numel(listing)
    if ~ismember(listing(i).name, expected)
        unexpected{end+1} = listing(i).name; %#ok<AGROW>
    end
end
if ~isempty(unexpected)
    ok = false;
    note = sprintf('unexpected top-level files: %s', strjoin(unexpected, ', '));
end
end
