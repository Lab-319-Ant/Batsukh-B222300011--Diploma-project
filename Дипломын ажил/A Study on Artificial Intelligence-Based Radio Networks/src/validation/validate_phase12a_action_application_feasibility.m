function validationTable = validate_phase12a_action_application_feasibility(cfg, finalDecisions, feasibility, mapping, moduleSummary, actionSummary, skipped)
%VALIDATE_PHASE12A_ACTION_APPLICATION_FEASIBILITY Phase 12A integrity checks.

rows = {};

% (1) feasibility table exists and non-empty
fFile = fullfile(cfg.tablesDir, 'phase12a_action_application_feasibility.csv');
rows = add_check(rows, 'feasibility_table_exists', 'error', ...
    isfile(fFile) && ~isempty(feasibility), ...
    sprintf('%d rows', height(feasibility)), '> 0', ...
    'phase12a_action_application_feasibility.csv must be written and non-empty.');

% (2) only Phase 11B executable-safe actions are reviewed
nonExecutableInFeasibility = 0;
if ~isempty(feasibility) && all(ismember({'executable_flag','safety_valid','final_decision_status'}, ...
        feasibility.Properties.VariableNames))
    nonExecutableInFeasibility = sum(~logical(feasibility.executable_flag) | ...
        ~logical(feasibility.safety_valid) | ...
        ~strcmp(feasibility.final_decision_status, 'final_safe_action'));
end
rows = add_check(rows, 'only_executable_safe_reviewed', 'error', ...
    nonExecutableInFeasibility == 0, sprintf('%d violations', nonExecutableInFeasibility), '== 0', ...
    'Feasibility table must contain only executable_flag=true + safety_valid + final_safe_action rows.');

% (3) no unresolved unsafe fallback row is marked applicable
unresolvedApplicable = 0;
if ismember('final_decision_status', feasibility.Properties.VariableNames)
    unresolvedApplicable = sum(strcmp(feasibility.final_decision_status, 'unresolved_unsafe_fallback') & ...
        logical(feasibility.can_apply_in_phase12b));
end
rows = add_check(rows, 'no_unresolved_unsafe_fallback_applicable', 'error', ...
    unresolvedApplicable == 0, sprintf('%d violations', unresolvedApplicable), '== 0', ...
    'No unresolved unsafe fallback row may be marked applicable.');

% (4) no rejected row is marked applicable
rejectedApplicable = 0;
if ismember('final_decision_status', feasibility.Properties.VariableNames)
    rejectedApplicable = sum((strcmp(feasibility.final_decision_status, 'rejected_priority_conflict') | ...
        strcmp(feasibility.final_decision_status, 'rejected_safety_conflict')) & ...
        logical(feasibility.can_apply_in_phase12b));
end
rows = add_check(rows, 'no_rejected_row_applicable', 'error', ...
    rejectedApplicable == 0, sprintf('%d violations', rejectedApplicable), '== 0', ...
    'No rejected row may be marked applicable.');

% (5) no no-op row is marked as parameter-changing applicable action
noopApplicable = 0;
if ismember('noop_selected', feasibility.Properties.VariableNames)
    noopApplicable = sum(logical(feasibility.noop_selected) & ...
        logical(feasibility.can_apply_in_phase12b));
end
rows = add_check(rows, 'no_noop_marked_parameter_changing', 'error', ...
    noopApplicable == 0, sprintf('%d violations', noopApplicable), '== 0', ...
    'No-op rows must not carry can_apply_in_phase12b = true.');

% (6) every executable action has an implementability_status
emptyStatus = sum(cellfun(@isempty, feasibility.implementability_status));
rows = add_check(rows, 'every_action_has_status', 'error', emptyStatus == 0, ...
    sprintf('%d empty', emptyStatus), '== 0', ...
    'Every executable action must carry a non-empty implementability_status.');

% (7) every implementable action has a mapped simulator_state_variable
implMask = strcmp(feasibility.implementability_status, 'implementable_now');
implMissing = sum(implMask & cellfun(@isempty, feasibility.simulator_state_variable));
rows = add_check(rows, 'implementable_actions_have_state_variable', 'error', ...
    implMissing == 0, sprintf('%d missing', implMissing), '== 0', ...
    'Every implementable_now action must reference a simulator_state_variable.');

% (8) unsupported action types explicitly marked (not silently ignored)
allowedStatuses = {'implementable_now','partially_implementable', ...
    'not_implemented_in_simulator','no_parameter_change_required'};
unknownStatus = sum(~ismember(feasibility.implementability_status, allowedStatuses));
rows = add_check(rows, 'all_statuses_in_allowed_set', 'error', unknownStatus == 0, ...
    sprintf('%d unknown', unknownStatus), '== 0', ...
    'implementability_status must be one of the four allowed values.');

% (9) dry_run_only_flag == true for every row
allDryRun = all(logical(feasibility.dry_run_only_flag));
rows = add_check(rows, 'all_rows_dry_run_only', 'error', allDryRun, ...
    sprintf('%d / %d dry_run', sum(logical(feasibility.dry_run_only_flag)), height(feasibility)), ...
    sprintf('== %d', height(feasibility)), ...
    'Every Phase 12A row must carry dry_run_only_flag = true.');

% (10) no topology/RF/KPI state was modified (structural)
[hit, evidence] = scan_for_simulator_mutation();
rows = add_check(rows, 'no_simulator_state_mutation', 'error', ~hit, evidence, ...
    '== false', 'Phase 12A source must not mutate topology, RF, traffic, or KPI state.');

% (11) no KPI(t+1) column exists in feasibility output
kpiCols = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    feasibility.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_columns', 'error', isempty(kpiCols), ...
    strjoin(kpiCols, ', '), '== empty', 'No KPI(t+1) column may exist in feasibility output.');

% (12) no closed-loop claim columns
closedLoop = intersect({'applied','executed_at_simulator','closed_loop_state_update'}, ...
    feasibility.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(closedLoop), ...
    strjoin(closedLoop, ', '), '== empty', 'No closed-loop columns may exist.');

% (13) summary by module exists
rows = add_check(rows, 'summary_by_module_exists', 'error', ...
    ~isempty(moduleSummary), sprintf('%d module rows', height(moduleSummary)), '> 0', ...
    'phase12a_implementability_summary_by_module.csv must contain rows.');

% (14) summary by action type exists
rows = add_check(rows, 'summary_by_action_type_exists', 'error', ...
    ~isempty(actionSummary), sprintf('%d action-type rows', height(actionSummary)), '> 0', ...
    'phase12a_implementability_summary_by_action_type.csv must contain rows.');

% Bonus: skipped non-executable accounting matches Phase 11B
totalDecisions = height(finalDecisions);
expectedSkipped = totalDecisions - height(feasibility);
rows = add_check(rows, 'skipped_count_matches_non_executable', 'error', ...
    height(skipped) == expectedSkipped, ...
    sprintf('skipped=%d expected=%d', height(skipped), expectedSkipped), ...
    'skipped == total - executable', ...
    'Skipped table must cover every non-executable Phase 11B row.');

mapping = mapping; %#ok<ASGSL,NASGU>

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase12a_feasibility_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [hit, evidence] = scan_for_simulator_mutation()
hit = false;
evidence = 'no simulator-mutation calls found';
src = which('run_phase12a_action_application_feasibility');
if isempty(src) || ~isfile(src)
    hit = true;
    evidence = 'orchestrator source not located';
    return;
end
contents = fileread(src);
forbidden = {'apply_action','calc_rsrp_sinr','allocate_sector_throughput', ...
    'compute_sector_kpis','generate_ues','kpi_t_plus_1','next_state_dataset', ...
    'apply_scenario_to_network'};
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
