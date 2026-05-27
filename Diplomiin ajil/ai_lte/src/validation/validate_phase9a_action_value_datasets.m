function validationTable = validate_phase9a_action_value_datasets(cfg, datasetAll, moduleTables, dictionary, leakageAudit, summary, featureSets)
%VALIDATE_PHASE9A_ACTION_VALUE_DATASETS Phase 9A dataset integrity checks.

rows = {};

requiredFiles = { ...
    'phase9a_action_value_dataset_all.csv', ...
    'phase9a_action_value_dataset_coc.csv', ...
    'phase9a_action_value_dataset_lb.csv', ...
    'phase9a_action_value_dataset_es.csv', ...
    'phase9a_action_value_dataset_mro.csv', ...
    'phase9a_action_value_feature_dictionary.csv', ...
    'phase9a_action_value_leakage_audit.csv', ...
    'phase9a_action_value_dataset_summary.csv'};
missingFiles = {};
for i = 1:numel(requiredFiles)
    p = fullfile(cfg.tablesDir, requiredFiles{i});
    if ~isfile(p)
        missingFiles{end+1} = requiredFiles{i}; %#ok<AGROW>
    end
end
rows = add_check(rows, 'all_required_datasets_exist', 'error', ...
    isempty(missingFiles), strjoin(missingFiles, ', '), '== empty', ...
    'All required Phase 9A files must be written.');

moduleNames = {'COC_OH','LB_MLB','ES','HO_MRO'};
emptyModules = {};
for k = 1:numel(moduleNames)
    if isempty(moduleTables.(moduleNames{k})) || height(moduleTables.(moduleNames{k})) == 0
        emptyModules{end+1} = moduleNames{k}; %#ok<AGROW>
    end
end
rows = add_check(rows, 'all_module_datasets_non_empty', 'error', ...
    isempty(emptyModules), strjoin(emptyModules, ', '), '== empty', ...
    'Every per-module dataset must contain at least one row.');

% Reward target finite.
rewardCol = datasetAll.reward;
nanRewards = sum(~isfinite(rewardCol));
rows = add_check(rows, 'reward_target_exists_and_finite', 'error', ...
    nanRewards == 0 && ismember('reward', datasetAll.Properties.VariableNames), ...
    sprintf('%d non-finite rewards', nanRewards), '== 0', ...
    'Reward target column must exist and be finite for every row.');

% action_id uniqueness in all-dataset.
ids = datasetAll.action_id;
dupCount = numel(ids) - numel(unique(ids));
rows = add_check(rows, 'action_id_unique_in_all_dataset', 'error', ...
    dupCount == 0, sprintf('%d duplicates', dupCount), '== 0', ...
    'action_id must be unique in the all-dataset table.');
rows = add_check(rows, 'no_action_id_duplicates', 'error', ...
    dupCount == 0, sprintf('%d duplicate ids', dupCount), '== 0', ...
    'No duplicate action_id rows.');

% Oracle-selected rows exist.
oracleSel = sum(datasetAll.oracle_selected);
rows = add_check(rows, 'oracle_selected_rows_exist', 'error', ...
    oracleSel > 0, sprintf('%d rows', oracleSel), '> 0', ...
    'At least one row must be flagged oracle_selected.');

% safety_valid + safe_training_candidate present.
hasSV = ismember('safety_valid', datasetAll.Properties.VariableNames);
hasST = ismember('safe_training_candidate', datasetAll.Properties.VariableNames);
rows = add_check(rows, 'safety_valid_column_exists', 'error', hasSV, ...
    logical_to_text(hasSV), '== true', 'safety_valid column required.');
rows = add_check(rows, 'safe_training_candidate_column_exists', 'error', hasST, ...
    logical_to_text(hasST), '== true', 'safe_training_candidate column required.');

% Leakage audit results.
leakageHits = sum(logical(leakageAudit.leakage_risk));
rows = add_check(rows, 'no_forbidden_columns_marked_input', 'error', ...
    leakageHits == 0, sprintf('%d leakage-risk columns', leakageHits), '== 0', ...
    'No column may be both forbidden and an input feature candidate.');

% No post_* marked as input.
postInputs = dictionary.column_name(strcmp(dictionary.role, 'input_feature_candidate') & ...
    startsWith(string(dictionary.column_name), 'post_'));
rows = add_check(rows, 'no_post_columns_as_input_feature', 'error', ...
    isempty(postInputs), strjoin(postInputs, ', '), '== empty', ...
    'No post-action column may be classified as input feature candidate.');

% Reward is target only.
rewardRoles = dictionary.role(strcmp(dictionary.column_name, 'reward'));
rewardIsTargetOnly = ~isempty(rewardRoles) && all(strcmp(rewardRoles, 'target'));
rows = add_check(rows, 'reward_is_target_only', 'error', rewardIsTargetOnly, ...
    strjoin(rewardRoles, ', '), '== target', ...
    'reward must be classified exclusively as target.');

% Oracle-selected flag is evaluation metadata only.
osRole = dictionary.role(strcmp(dictionary.column_name, 'oracle_selected'));
osIsEvalOnly = ~isempty(osRole) && all(strcmp(osRole, 'evaluation_metadata'));
rows = add_check(rows, 'oracle_selected_is_evaluation_metadata_only', 'error', ...
    osIsEvalOnly, strjoin(osRole, ', '), '== evaluation_metadata', ...
    'oracle_selected must be evaluation_metadata, not input.');

% Module action parameter columns present.
moduleParams = featureSets.moduleRelevantActionInputs;
missingParams = {};
for k = 1:numel(moduleNames)
    m = moduleNames{k};
    needed = moduleParams.(m);
    available = moduleTables.(m).Properties.VariableNames;
    miss = setdiff(needed, available);
    if ~isempty(miss)
        missingParams{end+1} = sprintf('%s:{%s}', m, strjoin(miss, ',')); %#ok<AGROW>
    end
end
rows = add_check(rows, 'module_action_parameters_present', 'error', ...
    isempty(missingParams), strjoin(missingParams, '; '), '== empty', ...
    'Each module dataset must expose its relevant action parameter columns.');

% Safe rows non-zero per module.
zeroSafeModules = {};
for k = 1:numel(moduleNames)
    m = moduleNames{k};
    if sum(moduleTables.(m).safety_valid) == 0
        zeroSafeModules{end+1} = m; %#ok<AGROW>
    end
end
rows = add_check(rows, 'safe_rows_present_per_module', 'error', ...
    isempty(zeroSafeModules), strjoin(zeroSafeModules, ', '), '== empty', ...
    'Each module dataset must contain at least one safety-valid row.');

% LB/MLB unsafe ratio diagnostic.
lbRows = moduleTables.LB_MLB;
lbUnsafeRatio = NaN;
if ~isempty(lbRows)
    lbUnsafeRatio = 1 - mean(lbRows.safety_valid);
end
rows = add_check(rows, 'lb_unsafe_ratio_diagnostic', 'diagnostic', true, ...
    sprintf('%.4f', lbUnsafeRatio), 'n/a', ...
    'LB/MLB unsafe ratio reported as diagnostic.');

% No closed-loop columns.
closedLoopCols = {'kpi_t_plus_1','kpi_next','next_state_dataset'};
clHits = intersect(closedLoopCols, datasetAll.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns_present', 'error', ...
    isempty(clHits), strjoin(clHits, ', '), '== empty', ...
    'Closed-loop state columns must not exist in Phase 9A.');

% Confirm dataset summary populated.
rows = add_check(rows, 'dataset_summary_populated', 'error', ...
    ~isempty(summary) && height(summary) == numel(moduleNames), ...
    sprintf('%d rows', height(summary)), sprintf('== %d', numel(moduleNames)), ...
    'Dataset summary must contain one row per module.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase9a_action_value_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function s = logical_to_text(v)
if v
    s = 'true';
else
    s = 'false';
end
end
