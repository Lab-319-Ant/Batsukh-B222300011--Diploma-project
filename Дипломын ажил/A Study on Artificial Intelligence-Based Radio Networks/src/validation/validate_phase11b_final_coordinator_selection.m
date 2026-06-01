function validationTable = validate_phase11b_final_coordinator_selection(cfg, finalDecisions, candidateActions, inputTable, moduleSummary, scenarioSummary)
%VALIDATE_PHASE11B_FINAL_COORDINATOR_SELECTION Final coordinator integrity checks.

rows = {};

% (1) final decision table non-empty
df = fullfile(cfg.tablesDir, 'phase11b_final_coordinator_decisions.csv');
rows = add_check(rows, 'final_decision_table_exists', 'error', ...
    isfile(df) && ~isempty(finalDecisions), ...
    sprintf('%d rows', height(finalDecisions)), '> 0', ...
    'phase11b_final_coordinator_decisions.csv must be written and non-empty.');

% (2) executable action table exists
ef = fullfile(cfg.tablesDir, 'phase11b_final_executable_actions.csv');
nExec = sum(finalDecisions.executable_flag);
rows = add_check(rows, 'executable_action_table_exists', 'error', ...
    isfile(ef), sprintf('%d executable rows', nExec), '>= 0', ...
    'phase11b_final_executable_actions.csv must be written.');

% (3) unresolved fallback diagnostic table exists
uf = fullfile(cfg.tablesDir, 'phase11b_unresolved_fallback_diagnostics.csv');
nUnres = sum(finalDecisions.unresolved_fallback_flag);
rows = add_check(rows, 'unresolved_fallback_diagnostic_table_exists', 'error', ...
    isfile(uf), sprintf('%d unresolved rows', nUnres), '>= 0', ...
    'phase11b_unresolved_fallback_diagnostics.csv must be written.');

% (4) rejected action table exists
rf = fullfile(cfg.tablesDir, 'phase11b_final_rejected_actions.csv');
nRej = sum(strcmp(finalDecisions.final_decision_status, 'rejected_priority_conflict') | ...
    strcmp(finalDecisions.final_decision_status, 'rejected_safety_conflict'));
rows = add_check(rows, 'rejected_action_table_exists', 'error', ...
    isfile(rf), sprintf('%d rejected rows', nRej), '>= 0', ...
    'phase11b_final_rejected_actions.csv must be written.');

% (5) every Phase 11A candidate appears in Phase 11B final decision table
inputIds = inputTable.selected_action_id_safe;
finalIds = finalDecisions.selected_action_id_safe;
missingIds = setdiff(inputIds, finalIds);
rows = add_check(rows, 'every_phase11a_candidate_present', 'error', ...
    isempty(missingIds), sprintf('%d missing', numel(missingIds)), '== 0', ...
    'Every Phase 11A candidate must appear in the Phase 11B final decision table.');

% (6) every final decision has exactly one final_decision_status (non-empty)
emptyStatus = sum(cellfun(@isempty, finalDecisions.final_decision_status));
rows = add_check(rows, 'every_decision_has_status', 'error', emptyStatus == 0, ...
    sprintf('%d empty', emptyStatus), '== 0', ...
    'final_decision_status must be set on every row.');

statuses = string(finalDecisions.final_decision_status);
allowed = ["final_safe_action","final_noop","rejected_priority_conflict", ...
    "rejected_safety_conflict","unresolved_unsafe_fallback","diagnostic_only"];
unknownStatus = sum(~ismember(statuses, allowed));
rows = add_check(rows, 'status_values_are_known', 'error', unknownStatus == 0, ...
    sprintf('%d unknown', unknownStatus), '== 0', ...
    'final_decision_status must be one of the six allowed values.');

% (7) executable_flag is false for no-op rows
noopExec = sum(strcmp(finalDecisions.final_decision_status, 'final_noop') & ...
    finalDecisions.executable_flag);
rows = add_check(rows, 'noop_rows_not_executable', 'error', noopExec == 0, ...
    sprintf('%d violations', noopExec), '== 0', ...
    'final_noop rows must have executable_flag = false.');

% (8) executable_flag is false for unresolved unsafe fallback rows
unresExec = sum(finalDecisions.unresolved_fallback_flag & finalDecisions.executable_flag);
rows = add_check(rows, 'unresolved_fallback_not_executable', 'error', unresExec == 0, ...
    sprintf('%d violations', unresExec), '== 0', ...
    'unresolved_unsafe_fallback rows must have executable_flag = false.');

% (9) executable_flag is false for rejected rows
rejExec = sum((strcmp(finalDecisions.final_decision_status, 'rejected_priority_conflict') | ...
    strcmp(finalDecisions.final_decision_status, 'rejected_safety_conflict')) & ...
    finalDecisions.executable_flag);
rows = add_check(rows, 'rejected_rows_not_executable', 'error', rejExec == 0, ...
    sprintf('%d violations', rejExec), '== 0', ...
    'rejected rows must have executable_flag = false.');

% (10) executable_flag is true only for safety-valid accepted non-noop rows
execStatuses = string(finalDecisions.final_decision_status(finalDecisions.executable_flag));
badExec = sum(execStatuses ~= "final_safe_action");
rows = add_check(rows, 'executable_only_for_final_safe_action', 'error', badExec == 0, ...
    sprintf('%d violations', badExec), '== 0', ...
    'executable_flag = true must occur only on final_safe_action rows.');

execSafetyOk = all(finalDecisions.safety_valid(finalDecisions.executable_flag));
rows = add_check(rows, 'every_executable_row_is_safety_valid', 'error', execSafetyOk, ...
    sprintf('all_safe=%d', execSafetyOk), '== true', ...
    'Every executable row must carry safety_valid = true.');

% (11) not_applied_flag is true for every row
allNotApplied = all(finalDecisions.not_applied_flag);
rows = add_check(rows, 'all_rows_marked_not_applied', 'error', allNotApplied, ...
    sprintf('%d/%d not_applied', sum(finalDecisions.not_applied_flag), height(finalDecisions)), ...
    sprintf('== %d', height(finalDecisions)), ...
    'Every Phase 11B row must carry not_applied_flag = true.');

% (12) no unsafe fallback row is marked executable (redundant with #8)
unsafeFallbackExec = sum(finalDecisions.fallback_used & ~finalDecisions.safety_valid & ...
    finalDecisions.executable_flag);
rows = add_check(rows, 'no_unsafe_fallback_executable', 'error', unsafeFallbackExec == 0, ...
    sprintf('%d violations', unsafeFallbackExec), '== 0', ...
    'No unsafe fallback row may be marked executable.');

% (13) no duplicate executable action for same application sector/state variable within a coordinator group
duplicateGroups = 0;
execRows = finalDecisions(finalDecisions.executable_flag, :);
[~, ~, gIdx] = unique(execRows.coordinator_group_id, 'stable');
for g = unique(gIdx)'
    gRows = execRows(gIdx == g, :);
    keys = strings(0, 1);
    for r = 1:height(gRows)
        stateStr = string(gRows.application_state_variable{r});
        if stateStr == "" || stateStr == "none", continue; end
        parts = strtrim(split(stateStr, '|'));
        for p = 1:numel(parts)
            keys(end+1) = sprintf('%d|%s', gRows.application_affected_sector_id(r), parts(p)); %#ok<AGROW>
        end
    end
    if numel(keys) ~= numel(unique(keys))
        duplicateGroups = duplicateGroups + 1;
    end
end
rows = add_check(rows, 'no_duplicate_executable_application_target_parameter', 'error', ...
    duplicateGroups == 0, sprintf('%d groups with duplicates', duplicateGroups), '== 0', ...
    'No two executable actions may write the same application sector/state variable in one coordinator group.');

duplicateLogged = 0;
if ~isempty(finalDecisions)
    duplicateLogged = sum(strcmp(finalDecisions.conflict_type, 'duplicate_application_target_parameter'));
end
rows = add_check(rows, 'duplicate_application_target_conflicts_resolved_before_executable', 'error', ...
    duplicateGroups == 0, sprintf('%d duplicate conflict rows logged', duplicateLogged), 'duplicates == 0', ...
    'Duplicate application target/parameter conflicts must be resolved before final executable table.');

% (14) no action application function is called (structural)
[appliedFlag, evidence] = scan_for_simulator_application();
rows = add_check(rows, 'no_action_applied_to_simulator', 'error', ~appliedFlag, evidence, ...
    '== false', 'Phase 11B source must not write simulator state.');

% (15) no KPI(t+1) column
kpiCols = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    finalDecisions.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_columns', 'error', isempty(kpiCols), ...
    strjoin(kpiCols, ', '), '== empty', 'No KPI(t+1) column may exist.');

% (16) no closed-loop state update columns
closedLoopCols = intersect({'applied','executed_at_simulator','closed_loop_state_update'}, ...
    finalDecisions.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(closedLoopCols), ...
    strjoin(closedLoopCols, ', '), '== empty', 'No closed-loop columns may exist.');

% (17) summary by module exists
rows = add_check(rows, 'summary_by_module_exists', 'error', ...
    ~isempty(moduleSummary), sprintf('%d module rows', height(moduleSummary)), '> 0', ...
    'phase11b_summary_by_module.csv must contain rows.');

% (18) summary by scenario exists
rows = add_check(rows, 'summary_by_scenario_exists', 'error', ...
    ~isempty(scenarioSummary), sprintf('%d scenario rows', height(scenarioSummary)), '> 0', ...
    'phase11b_summary_by_scenario.csv must contain rows.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase11b_final_coordination_validation.csv'));

candidateActions = candidateActions; %#ok<ASGSL,NASGU>
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [hit, evidence] = scan_for_simulator_application()
hit = false;
evidence = 'no simulator-application calls found';
src = which('run_phase11b_final_coordinator_selection');
if isempty(src) || ~isfile(src)
    hit = true;
    evidence = 'orchestrator source not located';
    return;
end
contents = fileread(src);
forbidden = {'apply_action','calc_rsrp_sinr','allocate_sector_throughput', ...
    'compute_sector_kpis','generate_ues','kpi_t_plus_1','next_state_dataset'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    hit = true;
    evidence = sprintf('found: %s', strjoin(found, ', '));
end
end
