function phase9b = run_phase9b_action_value_training(cfg)
%RUN_PHASE9B_ACTION_VALUE_TRAINING Train module-specific reward regressors.
%
% Phase 9B is OFFLINE action-value regression and oracle-regret preview
% only. It does NOT apply actions, NOT touch the simulator, NOT generate
% KPI(t+1), and NOT constitute closed-loop control.
%
% Trains one regression-tree ensemble (LSBoost, fallback TreeBagger) per
% module on safe candidate rows (safe_training_candidate == true),
% evaluates on train/test groups (group-aware split by scenario/realization),
% and produces a top-1/top-2 oracle-match preview with regret.

modules = build_module_specs();
stateFeatures = {'source_sector_load','target_sector_load', ...
    'source_mean_RSRP_dBm','source_mean_SINR_dB', ...
    'source_qos_satisfaction_ratio','source_handover_risk_score', ...
    'source_attach_rate_sector'};

allMetrics = table();
allPredictions = table();
allImportance = table();
allSplit = table();
allSelection = table();
allRegret = table();
moduleResults = struct();

moduleNames = fieldnames(modules);
for k = 1:numel(moduleNames)
    key = moduleNames{k};
    spec = modules.(key);

    datasetFile = fullfile(cfg.tablesDir, spec.dataset);
    if ~isfile(datasetFile)
        error('Phase 9B missing dataset: %s', datasetFile);
    end
    T = readtable(datasetFile);
    inputFeatures = [stateFeatures, spec.actionFeatures];

    splitLabels = create_action_value_split(T);
    safeMask = logical(T.safe_training_candidate);
    trainMask = strcmp(splitLabels, 'train') & safeMask;
    testMask = strcmp(splitLabels, 'test');

    model = train_action_value_regressor(T(trainMask, :), inputFeatures, 'reward', cfg);
    save(fullfile(cfg.modelsDir, spec.modelFile), 'model', 'inputFeatures');

    [predTrain, metricsTrain] = evaluate_action_value_regressor(model, T(trainMask, :), inputFeatures, 'reward', 'train');
    [predTest, metricsTest] = evaluate_action_value_regressor(model, T(testMask, :), inputFeatures, 'reward', 'test');

    metricsAll = [stamp(metricsTrain, spec.module, model); ...
        stamp(metricsTest, spec.module, model)];
    predictionsAll = [stampPred(predTrain, spec.module, model); ...
        stampPred(predTest, spec.module, model)];

    impTable = table(repmat({spec.module}, numel(inputFeatures), 1), ...
        inputFeatures(:), model.featureImportance, ...
        'VariableNames', {'module_name','feature_name','importance'});
    impTable = sortrows(impTable, 'importance', 'descend');

    [selectionPreview, regretPreview] = select_best_predicted_actions(T, predictionsAll, spec.module);

    rankingMetrics = compute_ranking_metrics(spec.module, selectionPreview, regretPreview);
    metricsAll = [metricsAll; rankingMetrics];

    allMetrics = [allMetrics; metricsAll];
    allPredictions = [allPredictions; predictionsAll];
    allImportance = [allImportance; impTable];
    allSplit = [allSplit; table({spec.module}, sum(trainMask), sum(testMask), ...
        sum(safeMask & strcmp(splitLabels, 'train')), sum(~safeMask & strcmp(splitLabels, 'train')), ...
        'VariableNames', {'module_name','train_rows','test_rows', ...
        'train_safe_rows','train_unsafe_rows_excluded'})];
    allSelection = [allSelection; selectionPreview];
    allRegret = [allRegret; regretPreview];

    moduleResults.(key) = struct('module', spec.module, ...
        'inputFeatures', {inputFeatures}, ...
        'trainRows', sum(trainMask), 'testRows', sum(testMask), ...
        'metrics', struct('train', metricsTrain, 'test', metricsTest), ...
        'rankingMetrics', rankingMetrics, 'selectionPreview', selectionPreview, ...
        'regretPreview', regretPreview);
end

writetable(allMetrics,     fullfile(cfg.tablesDir, 'phase9b_action_value_metrics.csv'));
writetable(allPredictions, fullfile(cfg.tablesDir, 'phase9b_action_value_predictions.csv'));
writetable(allImportance,  fullfile(cfg.tablesDir, 'phase9b_action_value_feature_importance.csv'));
writetable(allSplit,       fullfile(cfg.tablesDir, 'phase9b_action_value_split_summary.csv'));
writetable(allSelection,   fullfile(cfg.tablesDir, 'phase9b_action_selection_preview.csv'));
writetable(allRegret,      fullfile(cfg.tablesDir, 'phase9b_oracle_regret_preview.csv'));

if exist('plot_action_value_actual_vs_predicted', 'file') == 2
    try
        plot_action_value_actual_vs_predicted(cfg, allPredictions);
    catch ME
        warning('Phase 9B plot (actual vs predicted) failed: %s', ME.message);
    end
end
if exist('plot_action_value_error_by_module', 'file') == 2
    try
        plot_action_value_error_by_module(cfg, allPredictions);
    catch ME
        warning('Phase 9B plot (error by module) failed: %s', ME.message);
    end
end
if exist('plot_action_value_oracle_regret_preview', 'file') == 2
    try
        plot_action_value_oracle_regret_preview(cfg, allRegret);
    catch ME
        warning('Phase 9B plot (regret) failed: %s', ME.message);
    end
end

validationTable = validate_phase9b_action_value_results(cfg, ...
    moduleResults, allMetrics, allPredictions, allImportance, ...
    allSelection, allRegret, stateFeatures, modules);

phase9b = struct();
phase9b.metrics = allMetrics;
phase9b.predictions = allPredictions;
phase9b.featureImportance = allImportance;
phase9b.splitSummary = allSplit;
phase9b.actionSelectionPreview = allSelection;
phase9b.oracleRegretPreview = allRegret;
phase9b.moduleResults = moduleResults;
phase9b.validationTable = validationTable;
end

function modules = build_module_specs()
modules.COC_OH = struct('module', 'COC/OH', ...
    'dataset', 'phase9a_action_value_dataset_coc.csv', ...
    'modelFile', 'phase9b_coc_action_value_model.mat', ...
    'actionFeatures', {{'delta_prs_dB','delta_tilt_deg','delta_cio_dB','is_no_op'}});
modules.LB_MLB = struct('module', 'LB/MLB', ...
    'dataset', 'phase9a_action_value_dataset_lb.csv', ...
    'modelFile', 'phase9b_lb_action_value_model.mat', ...
    'actionFeatures', {{'delta_cio_dB','is_no_op'}});
modules.ES = struct('module', 'ES', ...
    'dataset', 'phase9a_action_value_dataset_es.csv', ...
    'modelFile', 'phase9b_es_action_value_model.mat', ...
    'actionFeatures', {{'sleep_flag','es_action_code'}});
modules.HO_MRO = struct('module', 'HO/MRO', ...
    'dataset', 'phase9a_action_value_dataset_mro.csv', ...
    'modelFile', 'phase9b_mro_action_value_model.mat', ...
    'actionFeatures', {{'delta_hom_dB','delta_ttt_ms','delta_cio_dB','is_no_op'}});
end

function out = stamp(metrics, moduleName, model)
n = height(metrics);
if n == 0
    out = metrics;
    out.module_name = cell(0, 1);
    out.model_type = cell(0, 1);
    return;
end
out = metrics;
out.module_name = repmat({moduleName}, n, 1);
out.model_type = repmat({model.modelType}, n, 1);
end

function out = stampPred(pred, moduleName, model)
if isempty(pred)
    out = pred;
    return;
end
out = pred;
out.module_name = repmat({moduleName}, height(out), 1);
out.model_type = repmat({model.modelType}, height(out), 1);
end

function metrics = compute_ranking_metrics(moduleName, selectionPreview, regretPreview)
if isempty(selectionPreview)
    metrics = table();
    return;
end
top1 = mean(selectionPreview.oracle_match_top1, 'omitnan');
top2 = mean(selectionPreview.oracle_match_top2, 'omitnan');
unsafeCount = sum(~selectionPreview.selected_action_safety_valid);
if isempty(regretPreview)
    meanRegret = NaN;
    maxRegret = NaN;
    medianRegret = NaN;
else
    meanRegret = mean(regretPreview.regret, 'omitnan');
    maxRegret = max(regretPreview.regret, [], 'omitnan');
    medianRegret = median(regretPreview.regret, 'omitnan');
end
names = {'top1_oracle_match','top2_oracle_match','mean_oracle_regret', ...
    'median_oracle_regret','max_oracle_regret','test_groups_with_unsafe_top1'};
values = [top1, top2, meanRegret, medianRegret, maxRegret, unsafeCount];
n = numel(names);
metrics = table(repmat({'test'}, n, 1), repmat({'ALL'}, n, 1), names(:), values(:), ...
    repmat({moduleName}, n, 1), repmat({'ranking'}, n, 1), ...
    'VariableNames', {'split','scenario_name','metric_name','metric_value','module_name','model_type'});
end
