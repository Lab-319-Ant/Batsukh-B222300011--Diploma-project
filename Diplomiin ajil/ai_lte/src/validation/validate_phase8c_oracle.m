function validationTable = validate_phase8c_oracle(cfg, selectedTable, joinedTable, moduleSummary, scenarioSummary)
%VALIDATE_PHASE8C_ORACLE Phase 8C oracle correctness checks.
%
% Checks:
%   1) Oracle selected action table exists and is non-empty.
%   2) Every oracle group has exactly one selected action.
%   3) No duplicate (group, action) row.
%   4) Selected action_id exists in the Phase 8B counterfactual table.
%   5) Reward is finite for every selected action.
%   6) Safety-valid rows are preferred where a safe candidate existed.
%   7) Unsafe fallback count is reported.
%   8) No oracle-selected action uses missing action parameters.
%   9) Oracle summary by module exists.
%  10) Oracle summary by scenario exists.
%  11) Oracle does not train ML  (structural: no model fit code path).
%  12) Oracle does not apply actions to KPI(t+1) (structural: no post-write).

rows = {};

rows = add_check(rows, 'oracle_selected_table_exists', 'error', ...
    ~isempty(selectedTable), sprintf('%d rows', height(selectedTable)), ...
    'Oracle must produce at least one selected action.', '');

% (2) one selected action per oracle group
nGroups = numel(unique(selectedTable.oracle_group_id));
rows = add_check(rows, 'one_selected_action_per_group', 'error', ...
    nGroups == height(selectedTable), ...
    sprintf('%d groups / %d rows', nGroups, height(selectedTable)), ...
    'Each oracle group must produce exactly one selected action.', '');

% (3) no duplicate (group, action)
dupKey = strcat(string(selectedTable.oracle_group_id), "|", ...
    string(selectedTable.selected_action_id));
dupCount = numel(dupKey) - numel(unique(dupKey));
rows = add_check(rows, 'no_duplicate_group_action_pair', 'error', ...
    dupCount == 0, sprintf('%d duplicates', dupCount), '== 0', ...
    'A (group_id, action_id) pair must appear at most once.');

% (4) selected action_id exists in Phase 8B table (the join guarantees this
% by construction; verify the picked id is in the joined table)
phase8bIds = joinedTable.action_id;
missingIds = setdiff(selectedTable.selected_action_id, phase8bIds);
rows = add_check(rows, 'selected_action_id_in_phase8b', 'error', ...
    isempty(missingIds), sprintf('%d missing', numel(missingIds)), ...
    'Selected action_id must exist in the Phase 8B counterfactual table.', '');

% (5) reward finite
nanReward = sum(~isfinite(selectedTable.reward));
rows = add_check(rows, 'selected_reward_is_finite', 'error', ...
    nanReward == 0, sprintf('%d non-finite', nanReward), '== 0', ...
    'Selected reward must be a finite real number.');

% (6) safe preference: for each group that had at least one safe candidate
% in the join, the selected row must be safety_valid = true.
groupsWithSafe = compute_groups_with_safe(joinedTable);
selectedGroupKey = build_group_key(selectedTable);
selectedHasSafeAvailable = ismember(selectedGroupKey, groupsWithSafe);
violations = selectedHasSafeAvailable & ~selectedTable.safety_valid;
rows = add_check(rows, 'safe_preference_respected', 'error', ...
    ~any(violations), sprintf('%d groups picked unsafe despite safe option', sum(violations)), '== 0', ...
    'If any safe candidate existed in a group, the oracle must pick a safe candidate.');

% (7) unsafe fallback count diagnostic
unsafeFallback = sum(~selectedTable.safety_valid);
rows = add_check(rows, 'unsafe_fallback_count', 'diagnostic', true, ...
    sprintf('%d', unsafeFallback), 'n/a', ...
    'Oracle groups with no safe candidate where fallback selection was used.');

% (8) action parameter columns present and finite for selected rows
paramCols = {'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms'};
missingCols = setdiff(paramCols, selectedTable.Properties.VariableNames);
rows = add_check(rows, 'oracle_action_parameter_columns_present', 'error', ...
    isempty(missingCols), strjoin(missingCols, ', '), '== empty', ...
    'Selected oracle rows must expose action parameter columns.');
if isempty(missingCols)
    nonFiniteParams = 0;
    for i = 1:numel(paramCols)
        nonFiniteParams = nonFiniteParams + sum(~isfinite(selectedTable.(paramCols{i})));
    end
    rows = add_check(rows, 'oracle_action_parameters_finite', 'error', ...
        nonFiniteParams == 0, sprintf('%d non-finite param cells', nonFiniteParams), '== 0', ...
        'Selected action parameter cells must be finite numbers.');
end

% (9) module summary exists
rows = add_check(rows, 'oracle_summary_by_module_present', 'error', ...
    ~isempty(moduleSummary), sprintf('%d module rows', height(moduleSummary)), ...
    'Module-level oracle summary must not be empty.', '');

% (10) scenario summary exists
rows = add_check(rows, 'oracle_summary_by_scenario_present', 'error', ...
    ~isempty(scenarioSummary), sprintf('%d scenario rows', height(scenarioSummary)), ...
    'Scenario-level oracle summary must not be empty.', '');

% (11) structural: oracle code path contains no ML training calls
[oracleHasMlTraining, mlEvidence] = scan_for_ml_training_calls();
rows = add_check(rows, 'oracle_does_not_train_ml', 'error', ...
    ~oracleHasMlTraining, mlEvidence, '== false', ...
    'Phase 8C oracle source must not call any ML training function.');

% (12) structural: oracle does not write KPI(t+1) state
[oracleAppliesKpi, kpiEvidence] = scan_for_kpi_application();
rows = add_check(rows, 'oracle_does_not_apply_kpi_t_plus_1', 'error', ...
    ~oracleAppliesKpi, kpiEvidence, '== false', ...
    'Phase 8C oracle source must not write a new KPI(t+1) state table.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase8c_oracle_validation.csv'));
end

function key = build_group_key(T)
key = strcat(string(T.scenario_name), "|", string(T.realization_id), "|", ...
    string(T.source_sector_id), "|", string(T.module_name));
end

function groupKeys = compute_groups_with_safe(joined)
gk = strcat(string(joined.scenario_name), "|", string(joined.realization_id), "|", ...
    string(joined.source_sector_id), "|", string(joined.module_name));
safe = ~logical(joined.safety_is_unsafe);
groupKeys = unique(gk(safe));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [hasMlTraining, evidence] = scan_for_ml_training_calls()
%SCAN_FOR_ML_TRAINING_CALLS Structural check on the Phase 8C source file.
hasMlTraining = false;
evidence = 'no ml training calls found';

oraclePath = which('run_phase8c_safety_constrained_oracle');
if isempty(oraclePath) || ~isfile(oraclePath)
    evidence = 'oracle source file not located';
    hasMlTraining = true;
    return;
end

contents = fileread(oraclePath);
forbidden = {'fitcensemble','fitcsvm','fitctree','fitcnb','fitcknn', ...
    'fitrtree','fitrensemble','fitlinear','fitrlinear','fitnet', ...
    'TreeBagger','trainNetwork','trainSoftmaxLayer'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    hasMlTraining = true;
    evidence = sprintf('found: %s', strjoin(found, ', '));
end
end

function [appliesKpi, evidence] = scan_for_kpi_application()
%SCAN_FOR_KPI_APPLICATION Structural check that Phase 8C does not write KPI(t+1).
appliesKpi = false;
evidence = 'no KPI(t+1) writes detected';

oraclePath = which('run_phase8c_safety_constrained_oracle');
if isempty(oraclePath) || ~isfile(oraclePath)
    evidence = 'oracle source file not located';
    appliesKpi = true;
    return;
end

contents = fileread(oraclePath);
forbidden = {'apply_action','KPI_t_plus_1','kpi_t_plus_1','kpi_next', ...
    'phase9_kpi','next_state_dataset'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    appliesKpi = true;
    evidence = sprintf('found: %s', strjoin(found, ', '));
end
end
