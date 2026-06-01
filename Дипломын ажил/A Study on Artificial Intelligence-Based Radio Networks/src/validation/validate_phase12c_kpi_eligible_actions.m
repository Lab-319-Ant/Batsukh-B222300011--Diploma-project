function validationTable = validate_phase12c_kpi_eligible_actions(cfg, executable, postExtensionFeasibility, eligible, excluded, moduleSummary, actionSummary)
%VALIDATE_PHASE12C_KPI_ELIGIBLE_ACTIONS Phase 12C integrity checks.

rows = {};

% (1) post-extension feasibility table exists and non-empty
pf = fullfile(cfg.tablesDir, 'phase12c_post_extension_feasibility.csv');
rows = add_check(rows, 'post_extension_feasibility_exists', 'error', ...
    isfile(pf) && ~isempty(postExtensionFeasibility), ...
    sprintf('%d rows', height(postExtensionFeasibility)), '> 0', ...
    'phase12c_post_extension_feasibility.csv must be written and non-empty.');

% (2) eligible table exists
ef = fullfile(cfg.tablesDir, 'phase12c_kpi_update_eligible_actions.csv');
rows = add_check(rows, 'eligible_table_exists', 'error', isfile(ef), ...
    sprintf('%d rows', height(eligible)), '>= 0', ...
    'phase12c_kpi_update_eligible_actions.csv must be written.');

% (3) excluded table exists
xf = fullfile(cfg.tablesDir, 'phase12c_kpi_update_excluded_actions.csv');
rows = add_check(rows, 'excluded_table_exists', 'error', isfile(xf), ...
    sprintf('%d rows', height(excluded)), '>= 0', ...
    'phase12c_kpi_update_excluded_actions.csv must be written.');

% (4) eligible rows are all executable-safe final actions (already filtered)
nonSafeEligible = 0;
if ~isempty(eligible) && ismember('selected_action_id_safe', eligible.Properties.VariableNames)
    safeIds = executable.selected_action_id_safe(strcmp(executable.final_decision_status, 'final_safe_action') & ...
        logical(executable.executable_flag) & logical(executable.safety_valid));
    nonSafeEligible = sum(~ismember(eligible.selected_action_id_safe, safeIds));
end
rows = add_check(rows, 'eligible_only_from_final_safe_executable', 'error', ...
    nonSafeEligible == 0, sprintf('%d violations', nonSafeEligible), '== 0', ...
    'Every eligible action_id must come from the Phase 11B final_safe_action executable set.');

% (5) eligible rows are all implementable_now
nonImpl = 0;
if ~isempty(eligible)
    nonImpl = sum(~strcmp(eligible.implementability_status, 'implementable_now'));
end
rows = add_check(rows, 'eligible_all_implementable_now', 'error', nonImpl == 0, ...
    sprintf('%d non-impl', nonImpl), '== 0', ...
    'Every eligible action must carry implementability_status = implementable_now.');

% (6) eligible rows contain only COC/OH and LB/MLB
allowedModules = {'COC/OH','LB/MLB'};
if ~isempty(eligible)
    foreignModules = unique(eligible.module_name(~ismember(eligible.module_name, allowedModules)));
else
    foreignModules = {};
end
rows = add_check(rows, 'eligible_modules_are_coc_lb_only', 'error', isempty(foreignModules), ...
    strjoin(foreignModules, ', '), '== empty', ...
    'Only COC/OH and LB/MLB modules may appear in the eligible action set.');

% (7) no ES rows are eligible
esCount = 0;
if ~isempty(eligible), esCount = sum(strcmp(eligible.module_name, 'ES')); end
rows = add_check(rows, 'no_es_rows_eligible', 'error', esCount == 0, ...
    sprintf('%d ES rows', esCount), '== 0', 'No ES row may appear in the eligible action set.');

% (8) no HO/MRO rows are eligible
hoCount = 0;
if ~isempty(eligible), hoCount = sum(strcmp(eligible.module_name, 'HO/MRO')); end
rows = add_check(rows, 'no_homro_rows_eligible', 'error', hoCount == 0, ...
    sprintf('%d HO/MRO rows', hoCount), '== 0', ...
    'No HO/MRO row may appear in the eligible action set (HOM/TTT placeholders not connected).');

% (9) no unresolved fallback rows in eligible (already excluded by Phase 11B filter, but verify)
unresolvedCount = 0;
if ~isempty(eligible) && ismember('selected_action_id_safe', eligible.Properties.VariableNames)
    fallbackIds = executable.selected_action_id_safe(strcmp(executable.final_decision_status, 'unresolved_unsafe_fallback'));
    unresolvedCount = sum(ismember(eligible.selected_action_id_safe, fallbackIds));
end
rows = add_check(rows, 'no_unresolved_fallback_eligible', 'error', unresolvedCount == 0, ...
    sprintf('%d violations', unresolvedCount), '== 0', ...
    'Unresolved unsafe fallback rows must never be eligible.');

% (10) no rejected rows in eligible
rejCount = 0;
if ~isempty(eligible) && ismember('selected_action_id_safe', eligible.Properties.VariableNames)
    rejIds = executable.selected_action_id_safe(strcmp(executable.final_decision_status, 'rejected_priority_conflict') | ...
        strcmp(executable.final_decision_status, 'rejected_safety_conflict'));
    rejCount = sum(ismember(eligible.selected_action_id_safe, rejIds));
end
rows = add_check(rows, 'no_rejected_rows_eligible', 'error', rejCount == 0, ...
    sprintf('%d violations', rejCount), '== 0', ...
    'Rejected rows must never be eligible.');

% (11) no no-op rows in eligible
noopCount = 0;
if ~isempty(eligible) && ismember('action_type', eligible.Properties.VariableNames)
    noopCount = sum(strcmp(eligible.action_type, 'no_op'));
end
rows = add_check(rows, 'no_noop_rows_eligible', 'error', noopCount == 0, ...
    sprintf('%d violations', noopCount), '== 0', ...
    'No-op rows must never be eligible.');

% (12) every excluded row has exclusion_reason
emptyReasons = 0;
if ~isempty(excluded)
    emptyReasons = sum(cellfun(@isempty, excluded.exclusion_reason));
end
rows = add_check(rows, 'every_excluded_has_reason', 'error', emptyReasons == 0, ...
    sprintf('%d empty', emptyReasons), '== 0', ...
    'Every excluded row must carry an exclusion_reason string.');

% (13) no simulator state mutated (structural)
[hit, evidence] = scan_for_simulator_mutation();
rows = add_check(rows, 'no_simulator_state_mutation', 'error', ~hit, evidence, ...
    '== false', 'Phase 12C source must not mutate simulator state.');

% (14) no KPI(t+1) column in eligible
kpiCols = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    eligible.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_in_eligible', 'error', isempty(kpiCols), ...
    strjoin(kpiCols, ', '), '== empty', 'No KPI(t+1) column may exist in the eligible action table.');

% (15) no closed-loop columns in eligible
closedLoop = intersect({'applied','executed_at_simulator','closed_loop_state_update'}, ...
    eligible.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(closedLoop), ...
    strjoin(closedLoop, ', '), '== empty', 'No closed-loop columns may exist in eligible table.');

% (15B) no duplicate eligible action for same application target/state variable
duplicateEligibleGroups = count_duplicate_application_targets(eligible);
rows = add_check(rows, 'no_duplicate_eligible_application_target_parameter', 'error', ...
    duplicateEligibleGroups == 0, sprintf('%d groups with duplicates', duplicateEligibleGroups), '== 0', ...
    'No two eligible actions may write the same application sector/state variable in one coordinator group.');

% Every eligible row carries kpi_t_plus_1_not_generated_flag = true
allFlagged = true;
if ~isempty(eligible) && ismember('kpi_t_plus_1_not_generated_flag', eligible.Properties.VariableNames)
    allFlagged = all(logical(eligible.kpi_t_plus_1_not_generated_flag));
end
rows = add_check(rows, 'kpi_t_plus_1_not_generated_flag_set', 'error', allFlagged, ...
    sprintf('%d/%d rows flagged', sum(logical(eligible.kpi_t_plus_1_not_generated_flag)), height(eligible)), ...
    'all rows true', 'Every eligible row must carry kpi_t_plus_1_not_generated_flag = true.');

% (16) summary by module exists
rows = add_check(rows, 'summary_by_module_exists', 'error', ...
    ~isempty(moduleSummary), sprintf('%d rows', height(moduleSummary)), '> 0', ...
    'phase12c_eligible_summary_by_module.csv must contain rows.');

% (17) summary by action type exists
rows = add_check(rows, 'summary_by_action_type_exists', 'error', ...
    ~isempty(actionSummary), sprintf('%d rows', height(actionSummary)), '> 0', ...
    'phase12c_eligible_summary_by_action_type.csv must contain rows.');

% Bonus: eligible + excluded == executable reviewed
totalAccounted = height(eligible) + height(excluded);
rows = add_check(rows, 'eligible_plus_excluded_equals_reviewed', 'error', ...
    totalAccounted == height(executable), ...
    sprintf('%d eligible + %d excluded = %d (executable=%d)', ...
    height(eligible), height(excluded), totalAccounted, height(executable)), ...
    'eligible + excluded == executable', ...
    'Every executable row must be classified as either eligible or excluded.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase12c_kpi_eligible_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [hit, evidence] = scan_for_simulator_mutation()
hit = false;
evidence = 'no simulator-mutation calls found';
src = which('run_phase12c_post_extension_feasibility_refresh');
if isempty(src) || ~isfile(src)
    hit = true;
    evidence = 'orchestrator source not located';
    return;
end
contents = fileread(src);
forbidden = {'apply_action','calc_rsrp_sinr','allocate_sector_throughput', ...
    'compute_sector_kpis','generate_ues','kpi_t_plus_1','next_state_dataset', ...
    'apply_scenario_to_network','apply_single_action_to_cloned_state'};
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
