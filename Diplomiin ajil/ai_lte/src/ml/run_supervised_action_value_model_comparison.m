function result = run_supervised_action_value_model_comparison(cfg)
%RUN_SUPERVISED_ACTION_VALUE_MODEL_COMPARISON Compare supervised regressors.
%
% This is a thesis-facing model comparison only. It uses the existing
% leakage-controlled Phase 9A action-value datasets and the existing reward
% target. It does not change rewards, safety logic, coordinator logic, or
% KPI(t+1) outputs.

moduleSpecs = build_module_specs();
modelSpecs = build_model_specs();
stateFeatures = {'source_sector_load','target_sector_load', ...
    'source_mean_RSRP_dBm','source_mean_SINR_dB', ...
    'source_qos_satisfaction_ratio','source_handover_risk_score', ...
    'source_attach_rate_sector'};

allMetrics = table();
allPredictions = table();
allSplit = table();
allRanking = table();
allFeatureUse = table();

moduleKeys = fieldnames(moduleSpecs);
for m = 1:numel(moduleKeys)
    spec = moduleSpecs.(moduleKeys{m});
    datasetFile = fullfile(cfg.tablesDir, spec.dataset);
    if ~isfile(datasetFile)
        error('Missing action-value dataset for supervised comparison: %s', datasetFile);
    end

    T = readtable(datasetFile);
    inputFeatures = [stateFeatures, spec.actionFeatures];
    assert_required_features(T, inputFeatures, spec.module);

    splitLabels = create_action_value_split(T);
    safeMask = logical(T.safe_training_candidate);
    trainMask = strcmp(splitLabels, 'train') & safeMask;
    testMask = strcmp(splitLabels, 'test');

    splitSummary = summarize_split(spec.module, T, splitLabels, safeMask);
    allSplit = [allSplit; splitSummary]; %#ok<AGROW>

    featureUse = table(repmat({spec.module}, numel(inputFeatures), 1), inputFeatures(:), ...
        repmat({'input_feature'}, numel(inputFeatures), 1), ...
        'VariableNames', {'module_name','feature_name','feature_role'});
    allFeatureUse = [allFeatureUse; featureUse]; %#ok<AGROW>

    for j = 1:numel(modelSpecs)
        modelSpec = modelSpecs(j);
        model = train_supervised_model(T(trainMask, :), inputFeatures, 'reward', modelSpec, cfg);

        [predTrain, metricTrain] = evaluate_supervised_model(model, T(trainMask, :), inputFeatures, 'reward', 'train');
        [predTest, metricTest] = evaluate_supervised_model(model, T(testMask, :), inputFeatures, 'reward', 'test');

        predAll = [stamp_predictions(predTrain, spec.module, modelSpec.name); ...
            stamp_predictions(predTest, spec.module, modelSpec.name)];
        metricAll = [stamp_metrics(metricTrain, spec.module, modelSpec.name); ...
            stamp_metrics(metricTest, spec.module, modelSpec.name)];

        ranking = compute_ranking_audit(T, predAll, spec.module, modelSpec.name);
        metricAll = [metricAll; ranking_to_metrics(ranking, spec.module, modelSpec.name)]; %#ok<AGROW>
        metricAll = [metricAll; compute_safety_subset_metrics(predAll, spec.module, modelSpec.name)]; %#ok<AGROW>

        allPredictions = [allPredictions; predAll]; %#ok<AGROW>
        allMetrics = [allMetrics; metricAll]; %#ok<AGROW>
        allRanking = [allRanking; ranking]; %#ok<AGROW>
    end
end

writetable(allMetrics, fullfile(cfg.tablesDir, 'supervised_action_value_model_metrics.csv'));
writetable(allPredictions, fullfile(cfg.tablesDir, 'supervised_action_value_model_predictions.csv'));
writetable(allSplit, fullfile(cfg.tablesDir, 'supervised_action_value_model_split_summary.csv'));
writetable(allRanking, fullfile(cfg.tablesDir, 'supervised_action_value_model_ranking.csv'));
writetable(allFeatureUse, fullfile(cfg.tablesDir, 'supervised_action_value_model_feature_use.csv'));

plot_supervised_actual_vs_predicted(cfg, allPredictions);
plot_coc_supervised_actual_vs_predicted(cfg, allPredictions);
plot_supervised_metric_comparison(cfg, allMetrics, 'R2', 'supervised_action_value_test_r2_by_module.png');
plot_supervised_metric_comparison(cfg, allMetrics, 'MAE', 'supervised_action_value_test_mae_by_module.png');
plot_coc_supervised_model_comparison(cfg, allMetrics);

validationTable = validate_supervised_comparison(cfg, allMetrics, allPredictions, allSplit, ...
    allRanking, allFeatureUse);
writetable(validationTable, fullfile(cfg.tablesDir, 'supervised_action_value_model_validation.csv'));

result = struct();
result.metrics = allMetrics;
result.predictions = allPredictions;
result.splitSummary = allSplit;
result.ranking = allRanking;
result.featureUse = allFeatureUse;
result.validationTable = validationTable;
end

function moduleSpecs = build_module_specs()
moduleSpecs.COC_OH = struct('module', 'COC/OH', ...
    'dataset', 'phase9a_action_value_dataset_coc.csv', ...
    'actionFeatures', {{'delta_prs_dB','delta_tilt_deg','delta_cio_dB','is_no_op'}});
moduleSpecs.LB_MLB = struct('module', 'LB/MLB', ...
    'dataset', 'phase9a_action_value_dataset_lb.csv', ...
    'actionFeatures', {{'delta_cio_dB','is_no_op'}});
moduleSpecs.ES = struct('module', 'ES', ...
    'dataset', 'phase9a_action_value_dataset_es.csv', ...
    'actionFeatures', {{'sleep_flag','es_action_code'}});
moduleSpecs.HO_MRO = struct('module', 'HO/MRO', ...
    'dataset', 'phase9a_action_value_dataset_mro.csv', ...
    'actionFeatures', {{'delta_hom_dB','delta_ttt_ms','delta_cio_dB','is_no_op'}});
end

function modelSpecs = build_model_specs()
modelSpecs = struct('name', {}, 'kind', {});
modelSpecs(1).name = 'Linear_Ridge';
modelSpecs(1).kind = 'linear';
modelSpecs(2).name = 'Random_Forest';
modelSpecs(2).kind = 'bagged_trees';
modelSpecs(3).name = 'LSBoost';
modelSpecs(3).kind = 'lsboost';
end

function assert_required_features(T, inputFeatures, moduleName)
missing = setdiff(inputFeatures, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing input features for %s: %s', moduleName, strjoin(missing, ', '));
end
end

function model = train_supervised_model(trainTable, inputFeatures, targetName, modelSpec, cfg)
X = trainTable(:, inputFeatures);
y = trainTable.(targetName);

model = struct();
model.modelName = modelSpec.name;
model.kind = modelSpec.kind;
model.inputFeatures = inputFeatures;

switch modelSpec.kind
    case 'linear'
        if exist('fitrlinear', 'file') == 2
            try
                model.object = fitrlinear(X, y, 'Learner', 'leastsquares', ...
                    'Regularization', 'ridge', 'Lambda', 1e-4, 'Standardize', true);
                model.backend = 'fitrlinear_ridge';
            catch
                model.object = fitrlinear(X, y, 'Learner', 'leastsquares', ...
                    'Regularization', 'ridge', 'Lambda', 1e-4);
                model.backend = 'fitrlinear_ridge';
            end
        elseif exist('fitlm', 'file') == 2
            model.object = fitlm(X, y, 'linear');
            model.backend = 'fitlm_linear';
        else
            Xmat = [ones(height(X), 1), table2array(X)];
            beta = pinv(Xmat) * y;
            model.object = beta;
            model.backend = 'normal_equation_pinv';
        end
    case 'bagged_trees'
        numTrees = get_or_default(cfg, 'phase9bNumLearningCycles', 200);
        maxSplits = get_or_default(cfg, 'phase9bMaxNumSplits', 32);
        if exist('TreeBagger', 'class') == 8
            model.object = TreeBagger(numTrees, table2array(X), y, ...
                'Method', 'regression', 'OOBPrediction', 'on', ...
                'OOBPredictorImportance', 'on', 'MaxNumSplits', maxSplits);
            model.backend = 'TreeBagger_regression';
        elseif exist('fitrensemble', 'file') == 2
            template = templateTree('MaxNumSplits', maxSplits, 'Surrogate', 'off');
            model.object = fitrensemble(X, y, 'Method', 'Bag', ...
                'NumLearningCycles', numTrees, 'Learners', template);
            model.backend = 'fitrensemble_bag';
        else
            error('Random Forest/Bagged Trees unavailable: TreeBagger or fitrensemble required.');
        end
    case 'lsboost'
        if exist('fitrensemble', 'file') ~= 2
            error('LSBoost unavailable: fitrensemble required.');
        end
        numCycles = get_or_default(cfg, 'phase9bNumLearningCycles', 200);
        learnRate = get_or_default(cfg, 'phase9bLearnRate', 0.05);
        maxSplits = get_or_default(cfg, 'phase9bMaxNumSplits', 32);
        template = templateTree('MaxNumSplits', maxSplits, 'Surrogate', 'off');
        model.object = fitrensemble(X, y, 'Method', 'LSBoost', ...
            'NumLearningCycles', numCycles, 'LearnRate', learnRate, ...
            'Learners', template);
        model.backend = 'fitrensemble_lsboost';
    otherwise
        error('Unknown supervised model kind: %s', modelSpec.kind);
end
end

function [predictionTable, metricsTable] = evaluate_supervised_model(model, T, inputFeatures, targetName, splitName)
predictionTable = table();
metricsTable = table();
if isempty(T)
    return;
end

X = T(:, inputFeatures);
y = T.(targetName);
yhat = predict_supervised_model(model, X);

predictionTable = table(T.action_id, T.scenario_name, T.realization_id, ...
    T.source_sector_id, T.target_sector_id, T.module_name, T.action_type, ...
    T.oracle_group_id, logical(T.oracle_selected), logical(T.safety_valid), ...
    logical(T.safe_training_candidate), y, yhat, yhat - y, ...
    repmat({splitName}, height(T), 1), ...
    'VariableNames', {'action_id','scenario_name','realization_id', ...
    'source_sector_id','target_sector_id','module_name','action_type', ...
    'oracle_group_id','oracle_selected','safety_valid','safe_training_candidate', ...
    'actual_reward','predicted_reward','error','split'});

metricsTable = compute_regression_metrics(y, yhat, splitName, 'ALL');
scenarios = unique(string(T.scenario_name));
for i = 1:numel(scenarios)
    mask = string(T.scenario_name) == scenarios(i);
    metricsTable = [metricsTable; compute_regression_metrics(y(mask), yhat(mask), splitName, char(scenarios(i)))]; %#ok<AGROW>
end
end

function yhat = predict_supervised_model(model, X)
switch model.kind
    case 'linear'
        if strcmp(model.backend, 'normal_equation_pinv')
            yhat = [ones(height(X), 1), table2array(X)] * model.object;
        else
            yhat = predict(model.object, X);
        end
    case 'bagged_trees'
        if strcmp(model.backend, 'TreeBagger_regression')
            yhat = predict(model.object, table2array(X));
        else
            yhat = predict(model.object, X);
        end
    case 'lsboost'
        yhat = predict(model.object, X);
    otherwise
        error('Unknown supervised model kind: %s', model.kind);
end
yhat = double(yhat);
end

function metrics = compute_regression_metrics(actual, predicted, splitName, scenarioLabel)
err = predicted - actual;
absErr = abs(err);
mae = mean(absErr, 'omitnan');
rmse = sqrt(mean(err .^ 2, 'omitnan'));
yMean = mean(actual, 'omitnan');
ssRes = sum((actual - predicted) .^ 2, 'omitnan');
ssTot = sum((actual - yMean) .^ 2, 'omitnan');
if ssTot <= 0
    r2 = NaN;
else
    r2 = 1 - ssRes / ssTot;
end
meanError = mean(err, 'omitnan');
medianAbsErr = median(absErr, 'omitnan');
within001 = mean(absErr <= 0.01, 'omitnan');
within005 = mean(absErr <= 0.05, 'omitnan');
within010 = mean(absErr <= 0.10, 'omitnan');

pearson = NaN;
spearman = NaN;
finite = isfinite(actual) & isfinite(predicted);
if sum(finite) >= 3 && exist('corr', 'file') == 2
    try
        pearson = corr(actual(finite), predicted(finite), 'Type', 'Pearson');
        spearman = corr(actual(finite), predicted(finite), 'Type', 'Spearman');
    catch
        pearson = NaN;
        spearman = NaN;
    end
end

names = {'MAE','RMSE','R2','mean_error','median_absolute_error', ...
    'pearson_r','spearman_rho','within_0p01','within_0p05','within_0p10'};
values = [mae, rmse, r2, meanError, medianAbsErr, pearson, spearman, ...
    within001, within005, within010];
n = numel(names);
metrics = table(repmat({splitName}, n, 1), repmat({scenarioLabel}, n, 1), ...
    names(:), values(:), ...
    'VariableNames', {'split','scenario_name','metric_name','metric_value'});
end

function out = stamp_predictions(pred, moduleName, modelName)
if isempty(pred)
    out = pred;
    return;
end
out = pred;
out.module_name = repmat({moduleName}, height(out), 1);
out.model_name = repmat({modelName}, height(out), 1);
end

function out = stamp_metrics(metrics, moduleName, modelName)
if isempty(metrics)
    out = metrics;
    out.module_name = cell(0, 1);
    out.model_name = cell(0, 1);
    return;
end
out = metrics;
out.module_name = repmat({moduleName}, height(out), 1);
out.model_name = repmat({modelName}, height(out), 1);
end

function splitSummary = summarize_split(moduleName, T, splitLabels, safeMask)
[groups, splitName] = findgroups(splitLabels);
rowCount = splitapply(@numel, T.action_id, groups);
safeCount = splitapply(@sum, double(safeMask), groups);
uniqueRealizations = splitapply(@(x) numel(unique(x)), T.realization_id, groups);
splitSummary = table(repmat({moduleName}, numel(splitName), 1), splitName(:), ...
    rowCount(:), safeCount(:), uniqueRealizations(:), ...
    'VariableNames', {'module_name','split','row_count','safe_training_candidate_count', ...
    'unique_realization_count'});
end

function ranking = compute_ranking_audit(T, predictions, moduleName, modelName)
testPred = predictions(strcmp(predictions.split, 'test'), :);
testPred = testPred(~isnan(testPred.oracle_group_id), :);
if isempty(testPred)
    ranking = table();
    return;
end

groups = unique(testPred.oracle_group_id);
rows = cell(numel(groups), 13);
for i = 1:numel(groups)
    gid = groups(i);
    G = testPred(testPred.oracle_group_id == gid, :);
    safeG = G(logical(G.safety_valid), :);
    if ~isempty(safeG)
        G = safeG;
    end
    [~, order] = sort(G.predicted_reward, 'descend');
    G = G(order, :);
    top1 = G(1, :);
    top2Ids = G.action_id(1:min(2, height(G)));
    [~, oracleIdx] = max(G.actual_reward);
    oracle = G(oracleIdx, :);
    regret = oracle.actual_reward - top1.actual_reward;
    rows(i, :) = {moduleName, modelName, gid, char(string(top1.scenario_name)), ...
        top1.realization_id, top1.source_sector_id, top1.action_id, oracle.action_id, ...
        double(top1.action_id == oracle.action_id), double(any(top2Ids == oracle.action_id)), ...
        oracle.actual_reward, top1.actual_reward, regret};
end

ranking = cell2table(rows, 'VariableNames', {'module_name','model_name','oracle_group_id', ...
    'scenario_name','realization_id','source_sector_id','top1_predicted_action_id', ...
    'oracle_selected_action_id','oracle_match_top1','oracle_match_top2', ...
    'oracle_reward','selected_true_reward','regret'});
end

function metrics = ranking_to_metrics(ranking, moduleName, modelName)
if isempty(ranking)
    metrics = table();
    return;
end
names = {'top1_oracle_match','top2_oracle_match','mean_oracle_regret', ...
    'median_oracle_regret','max_oracle_regret','regret_le_0p01','regret_le_0p05'};
values = [mean(ranking.oracle_match_top1, 'omitnan'), ...
    mean(ranking.oracle_match_top2, 'omitnan'), ...
    mean(ranking.regret, 'omitnan'), ...
    median(ranking.regret, 'omitnan'), ...
    max(ranking.regret, [], 'omitnan'), ...
    mean(ranking.regret <= 0.01, 'omitnan'), ...
    mean(ranking.regret <= 0.05, 'omitnan')];
metrics = table(repmat({'test'}, numel(names), 1), repmat({'ALL'}, numel(names), 1), ...
    names(:), values(:), repmat({moduleName}, numel(names), 1), ...
    repmat({modelName}, numel(names), 1), ...
    'VariableNames', {'split','scenario_name','metric_name','metric_value', ...
    'module_name','model_name'});
end

function plot_supervised_actual_vs_predicted(cfg, predictions)
if isempty(predictions)
    return;
end
testRows = predictions(strcmp(predictions.split, 'test'), :);
safeRows = testRows(logical(testRows.safe_training_candidate), :);
unsafeRows = testRows(~logical(testRows.safe_training_candidate), :);

bestSafeRows = select_best_model_rows_for_plot(safeRows);
plot_simple_actual_vs_predicted_modules(cfg, bestSafeRows, ...
    'supervised_action_value_actual_vs_predicted_test.png');
plot_simple_actual_vs_predicted_modules(cfg, bestSafeRows, ...
    'supervised_action_value_actual_vs_predicted_test_safe.png');
plot_supervised_actual_vs_predicted_subset(cfg, unsafeRows, ...
    'Supervised action-value regression: unsafe test candidates diagnostic only', ...
    'supervised_action_value_actual_vs_predicted_test_unsafe_diagnostic.png');
plot_supervised_actual_vs_predicted_subset(cfg, testRows, ...
    'Supervised action-value regression: mixed safe+unsafe test diagnostic only', ...
    'supervised_action_value_actual_vs_predicted_test_mixed_diagnostic.png');
end

function out = select_best_model_rows_for_plot(T)
%SELECT_BEST_MODEL_ROWS_FOR_PLOT Keep one readable model per module.
%
% Prefer the lowest safe-test MAE. This keeps the main actual-vs-predicted
% plot understandable while the separate model-comparison figure still
% reports all three models.
out = table();
if isempty(T)
    return;
end
modules = ["COC/OH", "ES", "HO/MRO", "LB/MLB"];
for i = 1:numel(modules)
    sub = T(strcmp(string(T.module_name), modules(i)), :);
    if isempty(sub)
        continue;
    end
    models = unique(string(sub.model_name), 'stable');
    mae = nan(numel(models), 1);
    for j = 1:numel(models)
        m = sub(strcmp(string(sub.model_name), models(j)), :);
        mae(j) = mean(abs(m.predicted_reward - m.actual_reward), 'omitnan');
    end
    [~, bestIdx] = min(mae);
    out = [out; sub(strcmp(string(sub.model_name), models(bestIdx)), :)]; %#ok<AGROW>
end
end

function plot_simple_actual_vs_predicted_modules(cfg, rows, fileName)
if isempty(rows)
    return;
end
moduleOrder = ["COC/OH", "ES", "HO/MRO", "LB/MLB"];

fig = figure('Visible', 'off', 'Position', [100 100 970 760]);
for i = 1:numel(moduleOrder)
    subplot(2, 2, i);
    mod = moduleOrder(i);
    sub = rows(strcmp(string(rows.module_name), mod), :);
    if isempty(sub)
        title(sprintf('%s (n=0)', mod), 'Interpreter', 'none');
        grid on;
        continue;
    end

    actual = sub.actual_reward;
    predicted = sub.predicted_reward;
    scatter(actual, predicted, 7, [0.0000 0.4470 0.7410], 'filled', ...
        'MarkerFaceAlpha', 0.45, 'MarkerEdgeAlpha', 0.45);
    hold on;
    lo = min([actual; predicted], [], 'omitnan');
    hi = max([actual; predicted], [], 'omitnan');
    pad = 0.05 * max(hi - lo, eps);
    lo = lo - pad;
    hi = hi + pad;
    plot([lo hi], [lo hi], 'k--', 'LineWidth', 0.8);
    hold off;
    xlim([lo hi]);
    ylim([lo hi]);
    grid on;
    xlabel('actual reward');
    ylabel('predicted reward');
    title(sprintf('%s (n=%d)', mod, height(sub)), 'Interpreter', 'none', 'FontWeight', 'bold');
end
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end

function plot_supervised_actual_vs_predicted_subset(cfg, testRows, plotTitle, fileName)
if isempty(testRows)
    return;
end
modules = unique(string(testRows.module_name), 'stable');
models = unique(string(testRows.model_name), 'stable');

fig = figure('Visible', 'off', 'Position', [50 50 1200 900]);
tl = tiledlayout(fig, numel(modules), numel(models), 'Padding', 'compact', 'TileSpacing', 'compact');
title(tl, plotTitle);
for i = 1:numel(modules)
    for j = 1:numel(models)
        nexttile;
        mask = string(testRows.module_name) == modules(i) & string(testRows.model_name) == models(j);
        sub = testRows(mask, :);
        if isempty(sub)
            title(sprintf('%s | %s', modules(i), models(j)));
            continue;
        end
        scatter(sub.actual_reward, sub.predicted_reward, 5, 'filled', 'MarkerFaceAlpha', 0.25);
        hold on;
        lo = min([sub.actual_reward; sub.predicted_reward], [], 'omitnan');
        hi = max([sub.actual_reward; sub.predicted_reward], [], 'omitnan');
        if ~isfinite(lo), lo = -1; end
        if ~isfinite(hi), hi = 1; end
        if lo == hi
            lo = lo - 0.1;
            hi = hi + 0.1;
        end
        plot([lo hi], [lo hi], 'k--', 'LineWidth', 0.8);
        hold off;
        title(sprintf('%s | %s', modules(i), strrep(models(j), '_', ' ')), 'Interpreter', 'none');
        xlabel('Actual reward');
        ylabel('Predicted reward');
        grid on;
    end
end
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end

function plot_coc_supervised_actual_vs_predicted(cfg, predictions)
%PLOT_COC_SUPERVISED_ACTUAL_VS_PREDICTED Dedicated COC three-model line plot.
%
% Uses safe test candidates only, because the supervised models are trained
% on safe candidates. Unsafe candidates remain diagnostic in the all-module
% plots and metrics.

mask = strcmp(predictions.split, 'test') & ...
    strcmp(predictions.module_name, 'COC/OH') & ...
    logical(predictions.safe_training_candidate);
T = predictions(mask, :);
if isempty(T)
    return;
end

models = unique(string(T.model_name), 'stable');
base = T(strcmp(string(T.model_name), models(1)), :);
base = sortrows(base, {'actual_reward','action_id'});
actionIds = base.action_id;
actual = base.actual_reward;

maxPoints = 1000;
if numel(actionIds) > maxPoints
    keep = unique(round(linspace(1, numel(actionIds), maxPoints)));
    actionIds = actionIds(keep);
    actual = actual(keep);
end

fig = figure('Visible', 'off', 'Position', [80 80 1100 520]);
plot(1:numel(actionIds), actual, 'k-', 'LineWidth', 1.4, 'DisplayName', 'Actual reward');
hold on;
for i = 1:numel(models)
    sub = T(strcmp(string(T.model_name), models(i)), :);
    [matched, loc] = ismember(actionIds, sub.action_id);
    yhat = nan(numel(actionIds), 1);
    yhat(matched) = sub.predicted_reward(loc(matched));
    plot(1:numel(actionIds), yhat, 'LineWidth', 1.0, ...
        'DisplayName', strrep(char(models(i)), '_', ' '));
end
hold off;
grid on;
xlabel('COC/OH safe test candidates sorted by actual reward');
ylabel('Reward');
title('COC/OH supervised actual vs predicted reward by model', 'Interpreter', 'none');
legend('Location', 'best', 'Interpreter', 'none');
save_figure(fig, fullfile(cfg.figuresDir, 'supervised_coc_actual_vs_predicted_by_model.png'));
end

function metrics = compute_safety_subset_metrics(predictions, moduleName, modelName)
metrics = table();
subsetDefs = {
    'test_safe',         strcmp(predictions.split, 'test') & logical(predictions.safe_training_candidate);
    'test_unsafe',       strcmp(predictions.split, 'test') & ~logical(predictions.safe_training_candidate);
    };
for i = 1:size(subsetDefs, 1)
    splitName = subsetDefs{i, 1};
    mask = subsetDefs{i, 2};
    if ~any(mask)
        continue;
    end
    sub = predictions(mask, :);
    m = compute_regression_metrics(sub.actual_reward, sub.predicted_reward, splitName, 'ALL');
    metrics = [metrics; stamp_metrics(m, moduleName, modelName)]; %#ok<AGROW>
end
end

function plot_supervised_metric_comparison(cfg, metrics, metricName, fileName)
mask = strcmp(metrics.split, 'test') & strcmp(metrics.scenario_name, 'ALL') & ...
    strcmp(metrics.metric_name, metricName);
sub = metrics(mask, :);
if isempty(sub)
    return;
end
modules = unique(string(sub.module_name), 'stable');
models = unique(string(sub.model_name), 'stable');
Y = nan(numel(modules), numel(models));
for i = 1:numel(modules)
    for j = 1:numel(models)
        idx = string(sub.module_name) == modules(i) & string(sub.model_name) == models(j);
        if any(idx)
            Y(i, j) = sub.metric_value(find(idx, 1, 'first'));
        end
    end
end
fig = figure('Visible', 'off', 'Position', [100 100 850 420]);
bar(categorical(cellstr(modules)), Y);
legend(cellstr(strrep(models, '_', ' ')), 'Location', 'bestoutside', 'Interpreter', 'none');
ylabel(metricName, 'Interpreter', 'none');
title(sprintf('Test %s by supervised model and module', metricName), 'Interpreter', 'none');
grid on;
save_figure(fig, fullfile(cfg.figuresDir, fileName));
end

function plot_coc_supervised_model_comparison(cfg, metrics)
mask = strcmp(metrics.split, 'test') & strcmp(metrics.scenario_name, 'ALL') & ...
    strcmp(metrics.module_name, 'COC/OH') & ...
    ismember(metrics.metric_name, {'R2','MAE','RMSE','top1_oracle_match','mean_oracle_regret'});
sub = metrics(mask, :);
if isempty(sub)
    return;
end

models = unique(string(sub.model_name), 'stable');
metricNames = {'R2','top1_oracle_match','MAE','RMSE','mean_oracle_regret'};
Y = nan(numel(metricNames), numel(models));
for i = 1:numel(metricNames)
    for j = 1:numel(models)
        row = sub(strcmp(sub.metric_name, metricNames{i}) & strcmp(string(sub.model_name), models(j)), :);
        if ~isempty(row)
            Y(i, j) = row.metric_value(1);
        end
    end
end

fig = figure('Visible', 'off', 'Position', [100 100 900 480]);
x = 1:numel(models);
plot(x, Y(1, :), '-o', 'LineWidth', 1.4, 'DisplayName', 'R2');
hold on;
plot(x, Y(2, :), '-s', 'LineWidth', 1.4, 'DisplayName', 'Top-1 oracle match');
plot(x, Y(3, :), '-^', 'LineWidth', 1.4, 'DisplayName', 'MAE');
plot(x, Y(4, :), '-d', 'LineWidth', 1.4, 'DisplayName', 'RMSE');
plot(x, Y(5, :), '-x', 'LineWidth', 1.4, 'DisplayName', 'Mean regret');
hold off;
grid on;
xticks(x);
xticklabels(strrep(cellstr(models), '_', ' '));
xlabel('Supervised model');
ylabel('Metric value');
title('COC/OH supervised model comparison on test split', 'Interpreter', 'none');
legend('Location', 'bestoutside', 'Interpreter', 'none');
save_figure(fig, fullfile(cfg.figuresDir, 'supervised_coc_model_comparison.png'));
end

function validationTable = validate_supervised_comparison(cfg, metrics, predictions, splitSummary, ranking, featureUse)
rows = {};

rows = add_check(rows, 'prediction_table_exists', 'error', ...
    isfile(fullfile(cfg.tablesDir, 'supervised_action_value_model_predictions.csv')) && ~isempty(predictions), ...
    sprintf('%d rows', height(predictions)), '> 0', 'Prediction table must exist and be non-empty.');
rows = add_check(rows, 'metrics_table_exists', 'error', ...
    isfile(fullfile(cfg.tablesDir, 'supervised_action_value_model_metrics.csv')) && ~isempty(metrics), ...
    sprintf('%d rows', height(metrics)), '> 0', 'Metrics table must exist and be non-empty.');
rows = add_check(rows, 'split_table_exists', 'error', ...
    isfile(fullfile(cfg.tablesDir, 'supervised_action_value_model_split_summary.csv')) && ~isempty(splitSummary), ...
    sprintf('%d rows', height(splitSummary)), '> 0', 'Split table must exist and be non-empty.');

requiredModels = ["Linear_Ridge"; "Random_Forest"; "LSBoost"];
presentModels = unique(string(predictions.model_name));
missingModels = setdiff(requiredModels, presentModels);
rows = add_check(rows, 'three_supervised_models_compared', 'error', isempty(missingModels), ...
    strjoin(cellstr(missingModels), ', '), 'none missing', ...
    'Linear/Ridge, Random Forest/Bagged Trees, and LSBoost must all be compared.');

requiredSplits = ["train"; "test"];
presentSplits = unique(string(predictions.split));
missingSplits = setdiff(requiredSplits, presentSplits);
rows = add_check(rows, 'train_test_present', 'error', isempty(missingSplits), ...
    strjoin(cellstr(missingSplits), ', '), 'none missing', ...
    'Predictions must include train and test splits.');

nonFiniteActual = sum(~isfinite(predictions.actual_reward));
nonFinitePred = sum(~isfinite(predictions.predicted_reward));
rows = add_check(rows, 'actual_reward_finite', 'error', nonFiniteActual == 0, ...
    sprintf('%d non-finite', nonFiniteActual), '0', 'Actual rewards must be finite.');
rows = add_check(rows, 'predicted_reward_finite', 'error', nonFinitePred == 0, ...
    sprintf('%d non-finite', nonFinitePred), '0', 'Predicted rewards must be finite.');

forbidden = {'reward','actual_reward','oracle_selected','oracle_reward','oracle_selection_reason', ...
    'safety_valid','safe_training_candidate','unsafe_fallback_group','post_source_load_ratio', ...
    'post_target_load_ratio','post_source_RSRP_dBm','post_source_SINR_dB', ...
    'post_source_qos_satisfaction_ratio','post_source_attach_rate','post_source_handover_risk_score', ...
    'kpi_t_plus_1','kpi_next','scenario_label','cod_label','outage_flag','degradation_flag', ...
    'safety_attach_loss','safety_qos_loss','safety_sinr_loss','safety_rsrp_loss', ...
    'safety_neighbor_overload','safety_handover_risk','safety_es_sleep_impaired','safety_is_unsafe'};
usedFeatures = unique(string(featureUse.feature_name));
forbiddenHits = intersect(string(forbidden), usedFeatures);
postHits = usedFeatures(startsWith(usedFeatures, "post_"));
rows = add_check(rows, 'no_forbidden_input_features', 'error', isempty(forbiddenHits), ...
    strjoin(cellstr(forbiddenHits), ', '), 'none', 'Forbidden leakage columns must not be model inputs.');
rows = add_check(rows, 'no_post_action_input_features', 'error', isempty(postHits), ...
    strjoin(cellstr(postHits), ', '), 'none', 'Post-action KPI columns must not be model inputs.');

rankRows = height(ranking);
rows = add_check(rows, 'ranking_regret_reported', 'error', rankRows > 0, ...
    sprintf('%d rows', rankRows), '> 0', 'Ranking/regret rows must be reported.');

plotFile = fullfile(cfg.figuresDir, 'supervised_action_value_actual_vs_predicted_test.png');
safePlotFile = fullfile(cfg.figuresDir, 'supervised_action_value_actual_vs_predicted_test_safe.png');
unsafePlotFile = fullfile(cfg.figuresDir, 'supervised_action_value_actual_vs_predicted_test_unsafe_diagnostic.png');
mixedPlotFile = fullfile(cfg.figuresDir, 'supervised_action_value_actual_vs_predicted_test_mixed_diagnostic.png');
meanLinePlotFile = fullfile(cfg.figuresDir, 'supervised_coc_actual_vs_predicted_by_model.png');
comparisonPlotFile = fullfile(cfg.figuresDir, 'supervised_coc_model_comparison.png');
rows = add_check(rows, 'actual_vs_predicted_safe_plot_exists', 'error', ...
    isfile(plotFile) && isfile(safePlotFile), plotFile, 'file exists', ...
    'The main supervised actual-vs-predicted figure must use safe test candidates only.');
rows = add_check(rows, 'actual_vs_predicted_unsafe_diagnostic_plot_exists', 'error', ...
    isfile(unsafePlotFile) && isfile(mixedPlotFile), unsafePlotFile, 'file exists', ...
    'Unsafe and mixed safe+unsafe diagnostic figures must be generated separately.');
rows = add_check(rows, 'coc_supervised_comparison_plots_exist', 'error', ...
    isfile(meanLinePlotFile) && isfile(comparisonPlotFile), ...
    sprintf('%s | %s', meanLinePlotFile, comparisonPlotFile), 'files exist', ...
    'COC/OH must have a dedicated three-model actual-vs-predicted and metric-comparison figure.');

subsetRows = metrics(ismember(metrics.split, {'test_safe','test_unsafe'}) & ...
    strcmp(metrics.scenario_name, 'ALL') & strcmp(metrics.metric_name, 'R2'), :);
rows = add_check(rows, 'safe_unsafe_test_metrics_reported', 'error', height(subsetRows) >= 2, ...
    sprintf('%d R2 subset rows', height(subsetRows)), '>= 2', ...
    'Safe and unsafe test metrics must be reported separately.');

weak = metrics(strcmp(metrics.split, 'test') & strcmp(metrics.scenario_name, 'ALL') & ...
    strcmp(metrics.metric_name, 'R2') & metrics.metric_value < 0.20, :);
weakNotes = "";
if ~isempty(weak)
    labels = strings(height(weak), 1);
    for i = 1:height(weak)
        labels(i) = sprintf('%s/%s R2=%.3f', string(weak.module_name(i)), ...
            string(weak.model_name(i)), weak.metric_value(i));
    end
    weakNotes = strjoin(cellstr(labels), '; ');
end
rows = add_check(rows, 'weak_mixed_test_r2_reported_as_warning', 'warning', isempty(weak), ...
    char(weakNotes), 'R2 >= 0.20', ...
    'Mixed safe+unsafe test calibration is diagnostic only; the main calibration figure uses safe test candidates.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function v = get_or_default(cfg, name, default)
if isfield(cfg, name)
    v = cfg.(name);
else
    v = default;
end
end
