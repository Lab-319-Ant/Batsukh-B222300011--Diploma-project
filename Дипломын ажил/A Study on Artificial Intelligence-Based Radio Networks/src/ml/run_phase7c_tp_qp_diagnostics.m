function phase7c = run_phase7c_tp_qp_diagnostics(cfg)
%RUN_PHASE7C_TP_QP_DIAGNOSTICS Compare TP/QP models with baselines.
%
% This phase is diagnostic only. It does not implement action selection,
% oracle benchmarking, a coordinator, or closed-loop control.

featureTable = readtable(fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_table.csv'));
featureDictionary = readtable(fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_dictionary.csv'));
inputFeatures = cellstr(featureDictionary.column_name(strcmp(featureDictionary.role, 'input_feature_candidate'))');
check_forbidden_inputs(inputFeatures);

[splitPlan, splitSummary] = create_walk_forward_split(featureTable);
featureTable = innerjoin(featureTable, splitPlan(:, {'temporal_sample_id','split'}), 'Keys', 'temporal_sample_id');
featureTable = sortrows(featureTable, 'temporal_sample_id');

trainTable = featureTable(strcmp(featureTable.split, 'train'), :);
validationTable = featureTable(strcmp(featureTable.split, 'validation'), :);
testTable = featureTable(strcmp(featureTable.split, 'test'), :);
evalTable = [validationTable; testTable];

tpPredictions = readtable(fullfile(cfg.tablesDir, 'phase7b_tp_predictions.csv'));
qpPredictions = readtable(fullfile(cfg.tablesDir, 'phase7b_qp_predictions.csv'));

tpComparison = build_tp_baseline_comparison(trainTable, evalTable, tpPredictions);
qpComparison = build_qp_baseline_comparison(trainTable, evalTable, qpPredictions);
[qpBoundedMetrics, qpBoundedPredictions, rawRange] = build_qp_bounded_metrics(qpPredictions);
qpVarianceDiagnostic = build_qp_target_variance_diagnostic(qpPredictions);

qpThroughput = train_qp_throughput_diagnostic(cfg, trainTable, validationTable, testTable, inputFeatures);

writetable(tpComparison, fullfile(cfg.tablesDir, 'phase7c_tp_baseline_comparison.csv'));
writetable(qpComparison, fullfile(cfg.tablesDir, 'phase7c_qp_baseline_comparison.csv'));
writetable(qpBoundedMetrics, fullfile(cfg.tablesDir, 'phase7c_qp_bounded_prediction_metrics.csv'));
writetable(qpBoundedPredictions, fullfile(cfg.tablesDir, 'phase7c_qp_predictions_bounded.csv'));
writetable(qpVarianceDiagnostic, fullfile(cfg.tablesDir, 'phase7c_qp_target_variance_diagnostic.csv'));

plot_phase7c_model_vs_baseline(cfg, tpComparison, 'TP model vs baseline', 'phase7c_tp_model_vs_baseline.png');
plot_phase7c_model_vs_baseline(cfg, qpComparison, 'QP model vs baseline', 'phase7c_qp_model_vs_baseline.png');
plot_regression_actual_vs_predicted(cfg, rename_bounded_for_plot(qpBoundedPredictions), ...
    'QP bounded actual vs predicted', 'phase7c_qp_bounded_actual_vs_predicted.png');
plot_phase7c_qp_target_variance(cfg, qpVarianceDiagnostic);

validationTable = validate_phase7c_tp_qp_diagnostics(cfg, inputFeatures, tpComparison, ...
    qpComparison, qpBoundedMetrics, qpBoundedPredictions, qpVarianceDiagnostic);

phase7c = struct();
phase7c.tpComparison = tpComparison;
phase7c.qpComparison = qpComparison;
phase7c.qpBoundedMetrics = qpBoundedMetrics;
phase7c.qpBoundedPredictions = qpBoundedPredictions;
phase7c.qpVarianceDiagnostic = qpVarianceDiagnostic;
phase7c.qpThroughput = qpThroughput;
phase7c.rawQpPredictionRange = rawRange;
phase7c.splitSummary = splitSummary;
phase7c.validationTable = validationTable;
end

function check_forbidden_inputs(inputFeatures)
forbidden = {'scenario_name','site_id','sector_id','temporal_sample_id','day_id', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB','outage_flag', ...
    'degradation_flag','cod_label'};
bad = unique([intersect(inputFeatures, forbidden), inputFeatures(startsWith(inputFeatures, 'next_'))]);
if ~isempty(bad)
    error('Phase7C:ForbiddenInputs', 'Forbidden diagnostic inputs: %s', strjoin(bad, ', '));
end
end

function comparison = build_tp_baseline_comparison(trainTable, evalTable, modelPredictions)
target = 'next_sector_load_ratio';
modelRows = metrics_from_predictions(modelPredictions, 'TP_model', target);
persistencePredictions = make_prediction_table(evalTable, target, evalTable.sector_load_ratio_lag1, 'TP_persistence');
seasonalPred = seasonal_hour_prediction(trainTable, evalTable, target);
seasonalPredictions = make_prediction_table(evalTable, target, seasonalPred, 'TP_same_hour_mean');
comparison = [modelRows; metrics_from_predictions(persistencePredictions, 'TP_persistence', target); ...
    metrics_from_predictions(seasonalPredictions, 'TP_same_hour_mean', target)];
end

function comparison = build_qp_baseline_comparison(trainTable, evalTable, modelPredictions)
target = 'next_qos_satisfaction_ratio';
modelRows = metrics_from_predictions(modelPredictions, 'QP_model', target);
persistencePredictions = make_prediction_table(evalTable, target, evalTable.qos_satisfaction_ratio_lag1, 'QP_persistence');
meanPred = repmat(mean(trainTable.(target), 'omitnan'), height(evalTable), 1);
meanPredictions = make_prediction_table(evalTable, target, meanPred, 'QP_train_mean');
comparison = [modelRows; metrics_from_predictions(persistencePredictions, 'QP_persistence', target); ...
    metrics_from_predictions(meanPredictions, 'QP_train_mean', target)];
end

function predictions = make_prediction_table(evalTable, target, predicted, modelName)
actual = evalTable.(target);
predictions = table(evalTable.scenario_name, evalTable.site_id, evalTable.sector_id, ...
    evalTable.time_step, actual, predicted, predicted - actual, evalTable.split, ...
    repmat({modelName}, height(evalTable), 1), ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step', ...
    'actual_target','predicted_target','error','split','model_name'});
end

function pred = seasonal_hour_prediction(trainTable, evalTable, target)
pred = zeros(height(evalTable), 1);
globalMean = mean(trainTable.(target), 'omitnan');
hours = unique(evalTable.hour_of_day);
for i = 1:numel(hours)
    hour = hours(i);
    trainIdx = abs(trainTable.hour_of_day - hour) < 1e-9;
    if any(trainIdx)
        hourMean = mean(trainTable.(target)(trainIdx), 'omitnan');
    else
        hourMean = globalMean;
    end
    pred(abs(evalTable.hour_of_day - hour) < 1e-9) = hourMean;
end
end

function metrics = metrics_from_predictions(predictions, modelName, targetName)
rows = {};
splits = unique(predictions.split, 'stable');
for s = 1:numel(splits)
    splitName = splits{s};
    splitRows = predictions(strcmp(predictions.split, splitName), :);
    rows = append_metric_rows(rows, splitRows, modelName, targetName, splitName, 'ALL');
    scenarioNames = unique(splitRows.scenario_name, 'stable');
    for i = 1:numel(scenarioNames)
        idx = strcmp(splitRows.scenario_name, scenarioNames{i});
        rows = append_metric_rows(rows, splitRows(idx, :), modelName, targetName, splitName, scenarioNames{i});
    end
end
metrics = cell2table(rows, 'VariableNames', ...
    {'model_name','target','split','scenario_name','MAE','RMSE','R2','mean_error','median_absolute_error'});
end

function rows = append_metric_rows(rows, tbl, modelName, targetName, splitName, scenarioName)
actual = tbl.actual_target;
pred = tbl.predicted_target;
err = pred - actual;
mae = mean(abs(err), 'omitnan');
rmse = sqrt(mean(err .^ 2, 'omitnan'));
ssRes = sum((actual - pred) .^ 2, 'omitnan');
ssTot = sum((actual - mean(actual, 'omitnan')) .^ 2, 'omitnan');
if ssTot > 0
    r2 = 1 - ssRes / ssTot;
else
    r2 = NaN;
end
rows(end+1, :) = {modelName, targetName, splitName, scenarioName, mae, rmse, r2, ...
    mean(err, 'omitnan'), median(abs(err), 'omitnan')}; %#ok<AGROW>
end

function [metrics, boundedPredictions, rawRange] = build_qp_bounded_metrics(qpPredictions)
bounded = min(max(qpPredictions.predicted_target, 0), 1);
boundedPredictions = table(qpPredictions.scenario_name, qpPredictions.site_id, ...
    qpPredictions.sector_id, qpPredictions.time_step, qpPredictions.actual_target, ...
    qpPredictions.predicted_target, bounded, qpPredictions.predicted_target - qpPredictions.actual_target, ...
    bounded - qpPredictions.actual_target, qpPredictions.split, ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step', ...
    'actual_next_qos_satisfaction_ratio','raw_predicted_qos','bounded_predicted_qos', ...
    'raw_error','bounded_error','split'});

rawPred = table(qpPredictions.scenario_name, qpPredictions.site_id, qpPredictions.sector_id, ...
    qpPredictions.time_step, qpPredictions.actual_target, qpPredictions.predicted_target, ...
    qpPredictions.predicted_target - qpPredictions.actual_target, qpPredictions.split, repmat({'QP_raw'}, height(qpPredictions), 1), ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step','actual_target','predicted_target','error','split','model_name'});
boundedForMetrics = table(qpPredictions.scenario_name, qpPredictions.site_id, qpPredictions.sector_id, ...
    qpPredictions.time_step, qpPredictions.actual_target, bounded, bounded - qpPredictions.actual_target, ...
    qpPredictions.split, repmat({'QP_bounded'}, height(qpPredictions), 1), ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step','actual_target','predicted_target','error','split','model_name'});
metrics = [metrics_from_predictions(rawPred, 'QP_raw', 'next_qos_satisfaction_ratio'); ...
    metrics_from_predictions(boundedForMetrics, 'QP_bounded', 'next_qos_satisfaction_ratio')];
rawRange = [min(qpPredictions.predicted_target), max(qpPredictions.predicted_target)];
end

function diagnostic = build_qp_target_variance_diagnostic(qpPredictions)
testRows = qpPredictions(strcmp(qpPredictions.split, 'test'), :);
scenarioNames = unique(testRows.scenario_name, 'stable');
rows = {};
for i = 1:numel(scenarioNames)
    idx = strcmp(testRows.scenario_name, scenarioNames{i});
    actual = testRows.actual_target(idx);
    pred = testRows.predicted_target(idx);
    err = pred - actual;
    ssRes = sum((actual - pred) .^ 2, 'omitnan');
    ssTot = sum((actual - mean(actual, 'omitnan')) .^ 2, 'omitnan');
    if ssTot > 0
        r2 = 1 - ssRes / ssTot;
    else
        r2 = NaN;
    end
    targetStd = std(actual, 'omitnan');
    note = '';
    if targetStd < 0.05
        note = 'R2 is unstable because target variance is very low.';
    end
    rows(end+1, :) = {scenarioNames{i}, mean(actual, 'omitnan'), targetStd, ...
        min(actual), max(actual), mean(abs(err), 'omitnan'), sqrt(mean(err .^ 2, 'omitnan')), ...
        r2, note}; %#ok<AGROW>
end
diagnostic = cell2table(rows, 'VariableNames', {'scenario_name','target_mean','target_std', ...
    'target_min','target_max','MAE','RMSE','R2','notes'});
end

function result = train_qp_throughput_diagnostic(cfg, trainTable, validationTable, testTable, inputFeatures)
target = 'next_mean_UE_throughput_Mbps';
modelInfo = train_regression_model(cfg, trainTable, inputFeatures, target, 'QP_throughput');
save(fullfile(cfg.modelsDir, 'phase7c_qp_throughput_regression_model.mat'), 'modelInfo');
[valMetrics, valPredictions, ~] = evaluate_regression_model(modelInfo, validationTable, inputFeatures, target, 'validation');
[testMetrics, testPredictions, testSummary] = evaluate_regression_model(modelInfo, testTable, inputFeatures, target, 'test');
metrics = [valMetrics; testMetrics];
predictions = [valPredictions; testPredictions];
writetable(metrics, fullfile(cfg.tablesDir, 'phase7c_qp_throughput_metrics.csv'));
writetable(predictions, fullfile(cfg.tablesDir, 'phase7c_qp_throughput_predictions.csv'));
plot_regression_actual_vs_predicted(cfg, predictions, 'QP throughput actual vs predicted', ...
    'phase7c_qp_throughput_actual_vs_predicted.png');
result = struct('metrics', metrics, 'predictions', predictions, 'testSummary', testSummary);
end

function plotTable = rename_bounded_for_plot(boundedPredictions)
plotTable = table(boundedPredictions.scenario_name, boundedPredictions.site_id, ...
    boundedPredictions.sector_id, boundedPredictions.time_step, ...
    boundedPredictions.actual_next_qos_satisfaction_ratio, boundedPredictions.bounded_predicted_qos, ...
    boundedPredictions.bounded_error, boundedPredictions.split, ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step', ...
    'actual_target','predicted_target','error','split'});
end
