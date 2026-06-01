function validationTable = validate_phase9b_action_value_results(cfg, moduleResults, allMetrics, allPredictions, allImportance, allSelection, allRegret, stateFeatures, moduleSpecs)
%VALIDATE_PHASE9B_ACTION_VALUE_RESULTS Phase 9B integrity checks.

rows = {};
moduleKeys = fieldnames(moduleResults);
moduleNames = cellfun(@(k) moduleResults.(k).module, moduleKeys, 'UniformOutput', false);

% (1) all four model files exist
missingModels = {};
modelFiles = {'phase9b_coc_action_value_model.mat', ...
    'phase9b_lb_action_value_model.mat', ...
    'phase9b_es_action_value_model.mat', ...
    'phase9b_mro_action_value_model.mat'};
for i = 1:numel(modelFiles)
    p = fullfile(cfg.modelsDir, modelFiles{i});
    if ~isfile(p)
        missingModels{end+1} = modelFiles{i}; %#ok<AGROW>
    end
end
rows = add_check(rows, 'all_module_model_files_exist', 'error', ...
    isempty(missingModels), strjoin(missingModels, ', '), '== empty', ...
    'Phase 9B must save four .mat models.');

% (2) metrics table exists and non-empty
metricsFile = fullfile(cfg.tablesDir, 'phase9b_action_value_metrics.csv');
rows = add_check(rows, 'metrics_table_exists', 'error', ...
    isfile(metricsFile) && ~isempty(allMetrics), ...
    sprintf('%d metric rows', height(allMetrics)), '> 0', ...
    'phase9b_action_value_metrics.csv must be written and populated.');

% (3) prediction table exists
predFile = fullfile(cfg.tablesDir, 'phase9b_action_value_predictions.csv');
rows = add_check(rows, 'predictions_table_exists', 'error', ...
    isfile(predFile) && ~isempty(allPredictions), ...
    sprintf('%d prediction rows', height(allPredictions)), '> 0', ...
    'phase9b_action_value_predictions.csv must be written.');

% (4) feature importance table exists
impFile = fullfile(cfg.tablesDir, 'phase9b_action_value_feature_importance.csv');
rows = add_check(rows, 'feature_importance_table_exists', 'error', ...
    isfile(impFile) && ~isempty(allImportance), ...
    sprintf('%d importance rows', height(allImportance)), '> 0', ...
    'phase9b_action_value_feature_importance.csv must be written.');

% (5..9) no forbidden input features used
forbidden = {'reward','oracle_selected','oracle_reward','oracle_selection_reason', ...
    'safety_valid','safe_training_candidate','unsafe_fallback_group', ...
    'invalid_reason','safety_attach_loss','safety_qos_loss','safety_sinr_loss', ...
    'safety_rsrp_loss','safety_neighbor_overload','safety_handover_risk', ...
    'safety_es_sleep_impaired','safety_is_unsafe','scenario_label','cod_label', ...
    'outage_flag','degradation_flag','kpi_t_plus_1','kpi_next', ...
    'next_state_dataset'};
allUsedFeatures = {};
for i = 1:numel(moduleKeys)
    allUsedFeatures = union(allUsedFeatures, moduleResults.(moduleKeys{i}).inputFeatures);
end
forbiddenHits = intersect(forbidden, allUsedFeatures);
rows = add_check(rows, 'no_forbidden_features_used', 'error', ...
    isempty(forbiddenHits), strjoin(forbiddenHits, ', '), '== empty', ...
    'Forbidden columns must never be used as model input.');

postHits = allUsedFeatures(startsWith(string(allUsedFeatures), 'post_'));
rows = add_check(rows, 'no_post_columns_used', 'error', ...
    isempty(postHits), strjoin(postHits, ', '), '== empty', ...
    'No post-action KPI column may be used as model input.');

rows = add_check(rows, 'reward_not_used_as_input', 'error', ...
    ~ismember('reward', allUsedFeatures), 'reward', '!= used', ...
    'Reward target must not appear in any module input feature list.');

rows = add_check(rows, 'oracle_selected_not_used_as_input', 'error', ...
    ~ismember('oracle_selected', allUsedFeatures), 'oracle_selected', '!= used', ...
    'Oracle-selected flag must not be a model input.');

rows = add_check(rows, 'safety_valid_not_used_as_input', 'error', ...
    ~ismember('safety_valid', allUsedFeatures), 'safety_valid', '!= used', ...
    'safety_valid must not be a model input.');

% (10) each module has train/test rows
zeroSplit = {};
for i = 1:numel(moduleKeys)
    r = moduleResults.(moduleKeys{i});
    if r.trainRows == 0 || r.testRows == 0
        zeroSplit{end+1} = r.module; %#ok<AGROW>
    end
end
rows = add_check(rows, 'each_module_has_train_test_rows', 'error', ...
    isempty(zeroSplit), strjoin(zeroSplit, ', '), '== empty', ...
    'Every module must produce non-empty train and test splits.');

% (11) finite predictions per module
nonFiniteModules = {};
for i = 1:numel(moduleKeys)
    mPred = allPredictions(strcmp(allPredictions.module_name, moduleResults.(moduleKeys{i}).module), :);
    if any(~isfinite(mPred.predicted_reward))
        nonFiniteModules{end+1} = moduleResults.(moduleKeys{i}).module; %#ok<AGROW>
    end
end
rows = add_check(rows, 'finite_predictions_per_module', 'error', ...
    isempty(nonFiniteModules), strjoin(nonFiniteModules, ', '), '== empty', ...
    'Predictions must be finite for every module.');

% (12) oracle-regret preview rows per module
missingRegret = {};
for i = 1:numel(moduleKeys)
    if isempty(allRegret) || ~any(strcmp(string(allRegret.module_name), moduleResults.(moduleKeys{i}).module))
        missingRegret{end+1} = moduleResults.(moduleKeys{i}).module; %#ok<AGROW>
    end
end
rows = add_check(rows, 'regret_preview_rows_per_module', 'error', ...
    isempty(missingRegret), strjoin(missingRegret, ', '), '== empty', ...
    'Each module must have at least one oracle-regret preview row.');

% (13) top-1 match rate reported
top1Rows = allMetrics(strcmp(allMetrics.metric_name, 'top1_oracle_match'), :);
rows = add_check(rows, 'top1_match_rate_reported', 'error', ...
    height(top1Rows) >= numel(moduleNames), ...
    sprintf('%d top-1 rows', height(top1Rows)), sprintf('>= %d', numel(moduleNames)), ...
    'Top-1 oracle match rate must be reported per module.');

% (14) regret finite
nonFiniteRegret = 0;
if ~isempty(allRegret)
    nonFiniteRegret = sum(~isfinite(allRegret.regret));
end
rows = add_check(rows, 'regret_values_are_finite', 'error', ...
    nonFiniteRegret == 0, sprintf('%d non-finite regret', nonFiniteRegret), '== 0', ...
    'Regret values must be finite numbers.');

% (15) module R2 warning
r2Warns = {};
for i = 1:numel(moduleKeys)
    m = moduleResults.(moduleKeys{i}).module;
    r2Row = allMetrics(strcmp(allMetrics.module_name, m) & ...
        strcmp(allMetrics.split, 'test') & ...
        strcmp(allMetrics.scenario_name, 'ALL') & ...
        strcmp(allMetrics.metric_name, 'R2'), :);
    if ~isempty(r2Row) && r2Row.metric_value(1) < 0.20
        r2Warns{end+1} = sprintf('%s:%.3f', m, r2Row.metric_value(1)); %#ok<AGROW>
    end
end
rows = add_check(rows, 'module_test_r2_above_0_20', 'warning', ...
    isempty(r2Warns), strjoin(r2Warns, ', '), '>= 0.20', ...
    'Modules with test R2 below 0.20 are flagged for review.');

% (16) high mean regret warning
regretWarns = {};
for i = 1:numel(moduleKeys)
    m = moduleResults.(moduleKeys{i}).module;
    if isempty(allRegret), continue; end
    mr = mean(allRegret.regret(strcmp(string(allRegret.module_name), m)), 'omitnan');
    if isfinite(mr) && mr > 1.0
        regretWarns{end+1} = sprintf('%s:%.3f', m, mr); %#ok<AGROW>
    end
end
rows = add_check(rows, 'mean_regret_not_high', 'warning', ...
    isempty(regretWarns), strjoin(regretWarns, ', '), '<= 1.0', ...
    'Modules with mean oracle regret above 1.0 are flagged for review.');

% (17) unsafe selected count in preview
unsafeWarns = {};
if ~isempty(allSelection)
    selModules = unique(string(allSelection.module_name));
    for i = 1:numel(selModules)
        mask = string(allSelection.module_name) == selModules(i);
        unsafeCount = sum(~allSelection.selected_action_safety_valid(mask));
        if unsafeCount > 0
            unsafeWarns{end+1} = sprintf('%s:%d', char(selModules(i)), unsafeCount); %#ok<AGROW>
        end
    end
end
rows = add_check(rows, 'no_unsafe_top1_selections', 'warning', ...
    isempty(unsafeWarns), strjoin(unsafeWarns, ', '), '== 0', ...
    'Top-1 predicted action is unsafe for the listed modules and group counts.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase9b_action_value_validation.csv'));

% Suppress unused inputs for static analysis.
stateFeatures = stateFeatures; %#ok<ASGSL>
moduleSpecs = moduleSpecs;     %#ok<ASGSL>
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end
