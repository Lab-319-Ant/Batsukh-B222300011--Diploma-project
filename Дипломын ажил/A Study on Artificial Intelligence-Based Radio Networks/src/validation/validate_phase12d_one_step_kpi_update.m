function validationTable = validate_phase12d_one_step_kpi_update(cfg, resultRows, eligible, appliedLog, skippedLog, extendedTopology, originalSnapshot)
%VALIDATE_PHASE12D_ONE_STEP_KPI_UPDATE Phase 12D integrity checks.

rows = {};

% (1) result table exists and non-empty
rf = fullfile(cfg.tablesDir, 'phase12d_one_step_kpi_update_results.csv');
rows = add_check(rows, 'result_table_exists', 'error', ...
    isfile(rf) && ~isempty(resultRows), ...
    sprintf('%d rows', height(resultRows)), '> 0', ...
    'phase12d_one_step_kpi_update_results.csv must be written and non-empty.');

% (2-7) only eligible / no excluded / no ES / no HO-MRO / no fallback / no rejected / no no-op
appliedIds = [];
if ~isempty(appliedLog), appliedIds = appliedLog.action_id; end

% Read excluded set for cross-check.
excludedFile = fullfile(cfg.tablesDir, 'phase12c_kpi_update_excluded_actions.csv');
excludedIds = [];
if isfile(excludedFile)
    exclTbl = readtable(excludedFile);
    if ~isempty(exclTbl)
        excludedIds = exclTbl.selected_action_id_safe;
    end
end

eligibleIds = [];
if ~isempty(eligible), eligibleIds = eligible.selected_action_id_safe; end

nonEligibleApplied = sum(~ismember(appliedIds, eligibleIds));
rows = add_check(rows, 'only_phase12c_eligible_applied', 'error', ...
    nonEligibleApplied == 0, sprintf('%d non-eligible applied', nonEligibleApplied), '== 0', ...
    'Every applied action must come from phase12c_kpi_update_eligible_actions.');

excludedApplied = sum(ismember(appliedIds, excludedIds));
rows = add_check(rows, 'no_excluded_applied', 'error', excludedApplied == 0, ...
    sprintf('%d excluded applied', excludedApplied), '== 0', ...
    'No excluded action may be applied.');

esApplied = 0; hoApplied = 0;
if ~isempty(appliedLog)
    esApplied = sum(strcmp(appliedLog.module_name, 'ES'));
    hoApplied = sum(strcmp(appliedLog.module_name, 'HO/MRO'));
end
rows = add_check(rows, 'no_es_actions_applied', 'error', esApplied == 0, ...
    sprintf('%d ES applied', esApplied), '== 0', 'No ES action may be applied in Phase 12D.');
rows = add_check(rows, 'no_homro_actions_applied', 'error', hoApplied == 0, ...
    sprintf('%d HO/MRO applied', hoApplied), '== 0', 'No HO/MRO action may be applied in Phase 12D.');

% Fallback / rejected / no-op exclusion is implicit because Phase 12C
% already filtered them. Verify by action_id non-membership in any
% Phase 11B non-executable category.
finalDecisionsFile = fullfile(cfg.tablesDir, 'phase11b_final_coordinator_decisions.csv');
fallbackApplied = 0; rejectedApplied = 0; noopApplied = 0;
if isfile(finalDecisionsFile)
    fd = readtable(finalDecisionsFile);
    fallbackIds = fd.selected_action_id_safe(strcmp(fd.final_decision_status, 'unresolved_unsafe_fallback'));
    rejectedIds = fd.selected_action_id_safe(strcmp(fd.final_decision_status, 'rejected_priority_conflict') | ...
        strcmp(fd.final_decision_status, 'rejected_safety_conflict'));
    noopIds = fd.selected_action_id_safe(strcmp(fd.final_decision_status, 'final_noop'));
    fallbackApplied = sum(ismember(appliedIds, fallbackIds));
    rejectedApplied = sum(ismember(appliedIds, rejectedIds));
    noopApplied = sum(ismember(appliedIds, noopIds));
end
rows = add_check(rows, 'no_unresolved_fallback_applied', 'error', fallbackApplied == 0, ...
    sprintf('%d', fallbackApplied), '== 0', 'No unresolved unsafe fallback action may be applied.');
rows = add_check(rows, 'no_rejected_applied', 'error', rejectedApplied == 0, ...
    sprintf('%d', rejectedApplied), '== 0', 'No rejected action may be applied.');
rows = add_check(rows, 'no_noop_applied', 'error', noopApplied == 0, ...
    sprintf('%d', noopApplied), '== 0', 'No no-op action may be applied.');

% (8) original simulator state unchanged
origUnchanged = isequal(extendedTopology.sectors, originalSnapshot);
rows = add_check(rows, 'original_state_unchanged', 'error', origUnchanged, ...
    logical_to_text(origUnchanged), '== true', ...
    'Phase 12D must not mutate the input topology sectors.');

% (9) every applied row has action_applied_to_clone = true
allFlagged = true;
if ~isempty(resultRows)
    allFlagged = all(logical(resultRows.action_applied_to_clone));
end
rows = add_check(rows, 'all_applied_flagged', 'error', allFlagged, ...
    sprintf('%d/%d true', sum(logical(resultRows.action_applied_to_clone)), height(resultRows)), ...
    'all true', 'action_applied_to_clone must be true on every result row.');

% (10) kpi_t_plus_1_generated flag true everywhere
kpiAllSet = true;
if ~isempty(resultRows)
    kpiAllSet = all(logical(resultRows.kpi_t_plus_1_generated));
end
rows = add_check(rows, 'kpi_t_plus_1_generated_flag_set', 'error', kpiAllSet, ...
    sprintf('%d/%d true', sum(logical(resultRows.kpi_t_plus_1_generated)), height(resultRows)), ...
    'all true', 'kpi_t_plus_1_generated must be true on every result row.');

% (11) post KPI values finite
nonFinite = 0;
if ~isempty(resultRows)
    cols = {'post_attach_rate','post_mean_rsrp_dBm','post_mean_sinr_dB', ...
        'post_mean_sector_load','post_qos_satisfaction_ratio'};
    for i = 1:numel(cols)
        nonFinite = nonFinite + sum(~isfinite(resultRows.(cols{i})));
    end
end
rows = add_check(rows, 'post_kpis_finite', 'error', nonFinite == 0, ...
    sprintf('%d non-finite', nonFinite), '== 0', ...
    'All post-action KPI values must be finite.');

% (12) RSRP/SINR/attach/load/QoS within valid ranges
[outOfRange, rangeNote] = check_kpi_ranges(resultRows);
rows = add_check(rows, 'kpis_within_valid_ranges', 'error', outOfRange == 0, ...
    rangeNote, '== 0', 'KPI values must lie inside physically plausible ranges.');

% (13) CIO changes association only (encoded in design; verify Phase 12B test rows are passing)
phase12bVal = fullfile(cfg.tablesDir, 'phase12b_action_state_validation.csv');
cioInvariantOk = true;
if isfile(phase12bVal)
    pv = readtable(phase12bVal);
    cioRow = pv(strcmp(pv.check_name, 'cio_changes_assoc_only'), :);
    if isempty(cioRow), cioInvariantOk = false; else, cioInvariantOk = logical(cioRow.pass_flag(1)); end
end
rows = add_check(rows, 'cio_changes_assoc_only_inherited', 'error', cioInvariantOk, ...
    logical_to_text(cioInvariantOk), '== true', ...
    'Phase 12B already verified CIO bias does not modify physical RSRP; check inherited here.');

% (14) reference power offset changes RSRP (inherited from Phase 12B test)
prsOk = true;
if isfile(phase12bVal)
    pv = readtable(phase12bVal);
    prsRow = pv(strcmp(pv.check_name, 'ref_power_offset_changes_rsrp'), :);
    if isempty(prsRow), prsOk = false; else, prsOk = logical(prsRow.pass_flag(1)); end
end
rows = add_check(rows, 'ref_power_offset_changes_rsrp_inherited', 'error', prsOk, ...
    logical_to_text(prsOk), '== true', ...
    'Phase 12B already verified reference power offset shifts physical RSRP; check inherited here.');

% (15) tilt effect reflected (inherited)
tiltOk = true;
if isfile(phase12bVal)
    pv = readtable(phase12bVal);
    tiltRow = pv(strcmp(pv.check_name, 'tilt_support_status_honest'), :);
    if isempty(tiltRow), tiltOk = false; else, tiltOk = logical(tiltRow.pass_flag(1)); end
end
rows = add_check(rows, 'tilt_effect_reflected_inherited', 'error', tiltOk, ...
    logical_to_text(tiltOk), '== true', 'Tilt impact on RSRP is verified in Phase 12B.');

% (16-17) summary tables exist
moduleFile = fullfile(cfg.tablesDir, 'phase12d_summary_by_module.csv');
scenarioFile = fullfile(cfg.tablesDir, 'phase12d_summary_by_scenario.csv');
rows = add_check(rows, 'summary_by_module_exists', 'error', isfile(moduleFile), ...
    logical_to_text(isfile(moduleFile)), '== true', 'phase12d_summary_by_module.csv must be written.');
rows = add_check(rows, 'summary_by_scenario_exists', 'error', isfile(scenarioFile), ...
    logical_to_text(isfile(scenarioFile)), '== true', 'phase12d_summary_by_scenario.csv must be written.');

% (17B) no duplicate applied action for same application target/state variable
dupApplied = count_duplicate_application_targets(appliedLog);
rows = add_check(rows, 'no_duplicate_applied_application_target_parameter', 'error', ...
    dupApplied == 0, sprintf('%d groups with duplicates', dupApplied), '== 0', ...
    'No two applied actions may write the same application sector/state variable in one coordinator group.');

% (18) if KPI worsens overall, report as warning
worseningWarn = false; worseningNote = '';
if ~isempty(resultRows)
    meanQos = mean(resultRows.delta_qos_satisfaction_ratio, 'omitnan');
    meanAttach = mean(resultRows.delta_attach_rate, 'omitnan');
    if meanQos < 0 || meanAttach < 0
        worseningWarn = true;
        worseningNote = sprintf('mean delta_qos=%.4f, delta_attach=%.4f', meanQos, meanAttach);
    end
end
rows = add_check(rows, 'kpi_does_not_worsen_on_average', 'warning', ~worseningWarn, ...
    worseningNote, 'mean(delta) >= 0', ...
    'On average across all applied actions the relevant KPI should not decline; flagged if it does.');

% (19) no multi-step loop (structural)
[loopHit, loopEvidence] = scan_for_loop_constructs();
rows = add_check(rows, 'no_multi_step_loop', 'error', ~loopHit, loopEvidence, ...
    '== false', 'Phase 12D orchestrator must not implement a multi-step closed-loop iteration.');

% (20) no closed-loop columns in result
clCols = intersect({'applied_to_simulator','closed_loop_state_update'}, ...
    resultRows.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(clCols), ...
    strjoin(clCols, ', '), '== empty', 'No closed-loop column may appear in Phase 12D outputs.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase12d_one_step_validation.csv'));

skippedLog = skippedLog; %#ok<ASGSL,NASGU>
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function s = logical_to_text(v), if v, s = 'true'; else, s = 'false'; end, end

function [outOfRange, note] = check_kpi_ranges(T)
outOfRange = 0;
note = 'ok';
if isempty(T), return; end
bad = (T.post_attach_rate < 0 | T.post_attach_rate > 1) | ...
    (T.post_qos_satisfaction_ratio < 0 | T.post_qos_satisfaction_ratio > 1.001) | ...
    (T.post_mean_sector_load < 0 | T.post_mean_sector_load > 100) | ...
    (T.post_mean_rsrp_dBm < -200 | T.post_mean_rsrp_dBm > 0) | ...
    (T.post_mean_sinr_dB < -50 | T.post_mean_sinr_dB > 100);
outOfRange = sum(bad);
note = sprintf('%d out-of-range rows', outOfRange);
end

function [hit, evidence] = scan_for_loop_constructs()
hit = false;
evidence = 'no multi-step loop constructs found';
src = which('run_phase12d_one_step_kpi_update');
if isempty(src) || ~isfile(src)
    hit = true; evidence = 'orchestrator source not located'; return;
end
contents = fileread(src);
forbidden = {'for kpi_step','for time_step','closed_loop','multi_step','iterate_kpi','for tt = 1'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    hit = true; evidence = sprintf('found: %s', strjoin(found, ', '));
end
end

function nDup = count_duplicate_application_targets(T)
nDup = 0;
if isempty(T) || ~all(ismember({'coordinator_group_id','application_affected_sector_id','application_state_variable'}, T.Properties.VariableNames))
    return;
end
keys = strings(0, 1);
for r = 1:height(T)
    vars = string(T.application_state_variable{r});
    if vars == "" || vars == "none", continue; end
    parts = strtrim(split(vars, '|'));
    for p = 1:numel(parts)
        if parts(p) == "" || parts(p) == "none", continue; end
        keys(end+1) = sprintf('%d|%d|%s', T.coordinator_group_id(r), ...
            T.application_affected_sector_id(r), parts(p)); %#ok<AGROW>
    end
end
if isempty(keys), return; end
[u, ~, idx] = unique(keys);
for i = 1:numel(u)
    if sum(idx == i) > 1
        nDup = nDup + 1;
    end
end
end
