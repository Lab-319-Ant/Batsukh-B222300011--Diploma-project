function validationTable = validate_phase11a_coordination_preparation(cfg, inputTable, conflictLog, resolutionLog, candidateActions, rejectedLog, moduleSummary, scenarioSummary)
%VALIDATE_PHASE11A_COORDINATION_PREPARATION Phase 11A integrity checks.

rows = {};

% (1) coordinator input table exists and non-empty
inputFile = fullfile(cfg.tablesDir, 'phase11a_coordinator_input_actions.csv');
rows = add_check(rows, 'coordinator_input_table_exists', 'error', ...
    isfile(inputFile) && ~isempty(inputTable), ...
    sprintf('%d rows', height(inputTable)), '> 0', ...
    'phase11a_coordinator_input_actions.csv must be written.');

% (2) conflict detection log exists
conflictFile = fullfile(cfg.tablesDir, 'phase11a_conflict_detection_log.csv');
rows = add_check(rows, 'conflict_detection_log_exists', 'error', ...
    isfile(conflictFile), sprintf('%d conflicts', height(conflictLog)), '>= 0', ...
    'phase11a_conflict_detection_log.csv must be written.');

% (3) conflict resolution log exists
resFile = fullfile(cfg.tablesDir, 'phase11a_conflict_resolution_log.csv');
rows = add_check(rows, 'conflict_resolution_log_exists', 'error', ...
    isfile(resFile), sprintf('%d resolutions', height(resolutionLog)), '>= 0', ...
    'phase11a_conflict_resolution_log.csv must be written.');

% (4) coordinator candidate action table exists
candFile = fullfile(cfg.tablesDir, 'phase11a_coordinator_candidate_actions.csv');
rows = add_check(rows, 'coordinator_candidate_table_exists', 'error', ...
    isfile(candFile) && ~isempty(candidateActions), ...
    sprintf('%d rows', height(candidateActions)), '> 0', ...
    'phase11a_coordinator_candidate_actions.csv must be written.');

% (5) rejected action log exists
rejFile = fullfile(cfg.tablesDir, 'phase11a_rejected_action_log.csv');
rows = add_check(rows, 'rejected_action_log_exists', 'error', ...
    isfile(rejFile), sprintf('%d rejections', height(rejectedLog)), '>= 0', ...
    'phase11a_rejected_action_log.csv must be written.');

% (6) every input is accepted, rejected, or no-op/fallback
inputIds = inputTable.selected_action_id_safe;
candIds = candidateActions.accepted_action_id;
missing = setdiff(inputIds, candIds);
rows = add_check(rows, 'every_input_has_coordinator_outcome', 'error', ...
    isempty(missing), sprintf('%d inputs missing from candidates', numel(missing)), '== 0', ...
    'Every input action must appear in the coordinator candidate table.');

acceptedOrRejected = (candidateActions.accepted_flag | candidateActions.rejected_flag);
rows = add_check(rows, 'each_candidate_has_accept_or_reject_flag', 'error', ...
    all(acceptedOrRejected), sprintf('%d rows missing', sum(~acceptedOrRejected)), '== 0', ...
    'Every candidate row must carry accepted or rejected flag.');

% (7) no duplicate accepted action for same application sector and state variable
duplicateGroups = 0;
acceptedCand = candidateActions(candidateActions.accepted_flag, :);
[~, ~, gIdx] = unique(acceptedCand.coordinator_group_id, 'stable');
for g = unique(gIdx)'
    gRows = acceptedCand(gIdx == g, :);
    inputRows = inputTable(ismember(inputTable.selected_action_id_safe, gRows.accepted_action_id), :);
    keyPairs = strings(0, 1);
    for r = 1:height(inputRows)
        vars = string(inputRows.application_state_variable{r});
        if vars == "" || vars == "none", continue; end
        parts = strtrim(split(vars, '|'));
        for p = 1:numel(parts)
            key = sprintf('%d|%s', inputRows.application_affected_sector_id(r), parts(p));
            keyPairs(end+1) = key; %#ok<AGROW>
        end
    end
    if numel(keyPairs) ~= numel(unique(keyPairs))
        duplicateGroups = duplicateGroups + 1;
    end
end
rows = add_check(rows, 'no_duplicate_application_target_parameter_accepted', 'error', ...
    duplicateGroups == 0, sprintf('%d groups with dup application target+state variable', duplicateGroups), '== 0', ...
    'Same application sector + same simulator state variable must not have more than one accepted action.');

% (8) duplicate application target conflicts resolved by priority / predicted reward
samePairConflicts = conflictLog(strcmp(conflictLog.conflict_type, 'duplicate_application_target_parameter'), :);
violations = 0;
for i = 1:height(samePairConflicts)
    c = samePairConflicts(i, :);
    aId = c.action_id_a; bId = c.action_id_b;
    aMod = find_module(inputTable, aId);
    bMod = find_module(inputTable, bId);
    aPrio = priority_for(aMod);
    bPrio = priority_for(bMod);
    aAccepted = is_accepted(candidateActions, aId);
    bAccepted = is_accepted(candidateActions, bId);
    if aPrio < bPrio
        if ~aAccepted || bAccepted, violations = violations + 1; end
    elseif bPrio < aPrio
        if ~bAccepted || aAccepted, violations = violations + 1; end
    end
end
rows = add_check(rows, 'duplicate_application_target_resolved', 'error', ...
    violations == 0, sprintf('%d violations', violations), '== 0', ...
    'For duplicate application target/state conflicts, the configured winner must remain accepted and the loser rejected.');

dupRejected = 0;
if ~isempty(rejectedLog) && height(rejectedLog) > 0
    dupRejected = sum(strcmp(rejectedLog.rejection_type, 'duplicate_application_target_parameter'));
end
rows = add_check(rows, 'duplicate_application_target_rejections_logged', 'diagnostic', ...
    true, sprintf('%d duplicate-target rejections', dupRejected), 'n/a', ...
    'Rejected duplicate application target/parameter rows must be visible in phase11a_rejected_action_log.csv.');

% (9) ES sleep not accepted when higher-priority action affects same sector
esSleepViolations = 0;
esRows = candidateActions(strcmp(candidateActions.module_name, 'ES') & ...
    candidateActions.accepted_flag, :);
for i = 1:height(esRows)
    esActionId = esRows.accepted_action_id(i);
    inputIdx = find(inputTable.selected_action_id_safe == esActionId, 1);
    if isempty(inputIdx), continue; end
    if ~strcmp(inputTable.es_action{inputIdx}, 'sleep'), continue; end
    src = inputTable.source_sector_id(inputIdx);
    gid = inputTable.coordinator_group_id(inputIdx);
    overlap = candidateActions(candidateActions.coordinator_group_id == gid & ...
        candidateActions.accepted_flag & ...
        ismember(candidateActions.module_name, {'COC/OH','LB/MLB','HO/MRO'}) & ...
        (candidateActions.source_sector_id == src | candidateActions.target_sector_id == src), :);
    if height(overlap) > 0
        esSleepViolations = esSleepViolations + 1;
    end
end
rows = add_check(rows, 'es_sleep_not_accepted_with_higher_priority_overlap', 'error', ...
    esSleepViolations == 0, sprintf('%d violations', esSleepViolations), '== 0', ...
    'ES sleep must be rejected when another higher-priority module touches the same sector.');

% (10) unsafe non-fallback actions are rejected
unsafeRetained = sum(~inputTable.safe_selected_safety_valid & ~inputTable.fallback_used & ...
    candidateActions.accepted_flag);
rows = add_check(rows, 'unsafe_non_fallback_rejected', 'error', ...
    unsafeRetained == 0, sprintf('%d retained', unsafeRetained), '== 0', ...
    'Every unsafe non-fallback action must be rejected by the coordinator.');

% (11) fallback unsafe actions remain explicitly marked
fallbackUnsafeKept = sum(inputTable.fallback_used & ~inputTable.safe_selected_safety_valid & ...
    candidateActions.accepted_flag);
rows = add_check(rows, 'fallback_unsafe_actions_marked', 'diagnostic', true, ...
    sprintf('%d retained fallback-unsafe', fallbackUnsafeKept), 'n/a', ...
    'Phase 11A retains fallback-unsafe actions as honest diagnostics.');

% (12) no action applied to simulator (structural check)
[appliedFlag, evidence] = scan_for_simulator_application();
rows = add_check(rows, 'no_action_applied_to_simulator', 'error', ~appliedFlag, evidence, ...
    '== false', 'Phase 11A source must not write simulator state.');

% (13) no KPI(t+1) column exists in outputs
kpiNextCols = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    inputTable.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_in_inputs', 'error', isempty(kpiNextCols), ...
    strjoin(kpiNextCols, ', '), '== empty', 'No KPI(t+1) column may appear in coordinator inputs.');

kpiNextCands = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    candidateActions.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_in_candidates', 'error', isempty(kpiNextCands), ...
    strjoin(kpiNextCands, ', '), '== empty', 'No KPI(t+1) column may appear in coordinator candidates.');

% (14) no closed-loop state update column / flag in candidate table
forbidden = intersect({'applied','executed_at_simulator','closed_loop_state_update'}, ...
    candidateActions.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(forbidden), ...
    strjoin(forbidden, ', '), '== empty', 'No closed-loop columns may exist.');

allNotApplied = all(candidateActions.not_applied_flag);
rows = add_check(rows, 'all_actions_marked_not_applied', 'error', allNotApplied, ...
    sprintf('%d not_applied flags true', sum(candidateActions.not_applied_flag)), ...
    sprintf('== %d', height(candidateActions)), ...
    'Every candidate action must carry not_applied_flag = true.');

% (15) module summary exists
rows = add_check(rows, 'module_summary_exists', 'error', ...
    ~isempty(moduleSummary), sprintf('%d module rows', height(moduleSummary)), '> 0', ...
    'phase11a_summary_by_module.csv must contain rows.');

% (16) scenario summary exists
rows = add_check(rows, 'scenario_summary_exists', 'error', ...
    ~isempty(scenarioSummary), sprintf('%d scenario rows', height(scenarioSummary)), '> 0', ...
    'phase11a_summary_by_scenario.csv must contain rows.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase11a_coordination_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function p = priority_for(moduleName)
switch moduleName
    case 'COC/OH', p = 2;
    case 'LB/MLB', p = 3;
    case 'HO/MRO', p = 4;
    case 'ES',     p = 6;
    otherwise,     p = 99;
end
end

function m = find_module(inputTable, actionId)
hit = find(inputTable.selected_action_id_safe == actionId, 1);
if isempty(hit)
    m = '';
else
    m = inputTable.module_name{hit};
end
end

function tf = is_accepted(candidateActions, actionId)
hit = find(candidateActions.accepted_action_id == actionId, 1);
if isempty(hit)
    tf = false;
else
    tf = candidateActions.accepted_flag(hit);
end
end

function [hit, evidence] = scan_for_simulator_application()
hit = false;
evidence = 'no simulator-application calls found';
src = which('run_phase11a_decision_coordinator_preparation');
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
