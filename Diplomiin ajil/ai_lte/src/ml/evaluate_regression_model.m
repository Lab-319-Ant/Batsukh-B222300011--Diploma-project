function [metricsTable, predictionsTable, summary] = evaluate_regression_model(modelInfo, evalTable, inputFeatures, targetName, splitName)
%EVALUATE_REGRESSION_MODEL Predict and compute regression metrics.

X = table2array(evalTable(:, inputFeatures));
actual = evalTable.(targetName);
predicted = predict_regression(modelInfo, X);
err = predicted - actual;

predictionsTable = table(evalTable.scenario_name, evalTable.site_id, evalTable.sector_id, ...
    evalTable.time_step, actual, predicted, err, repmat({splitName}, height(evalTable), 1), ...
    'VariableNames', {'scenario_name','site_id','sector_id','time_step', ...
    'actual_target','predicted_target','error','split'});

metricsTable = build_metrics_table(predictionsTable, splitName, modelInfo.modelName);
overallRows = metricsTable(strcmp(metricsTable.metric_scope, 'overall'), :);
summary = struct();
summary.mae = metric_value(overallRows, 'MAE');
summary.rmse = metric_value(overallRows, 'RMSE');
summary.r2 = metric_value(overallRows, 'R2');
summary.mape = metric_value(overallRows, 'MAPE');
summary.mean_error = metric_value(overallRows, 'mean_error');
summary.median_absolute_error = metric_value(overallRows, 'median_absolute_error');
end

function y = predict_regression(modelInfo, X)
switch modelInfo.algorithm
    case {'fitrensemble_LSBoost','TreeBagger_regression'}
        y = predict(modelInfo.model, X);
    otherwise
        y = [ones(size(X, 1), 1), X] * modelInfo.model.beta;
end
y = double(y);
end

function metricsTable = build_metrics_table(predictionsTable, splitName, modelName)
rows = {};
rows = add_metric_block(rows, predictionsTable, splitName, modelName, 'overall', 'ALL');
scenarioNames = unique(predictionsTable.scenario_name, 'stable');
for i = 1:numel(scenarioNames)
    idx = strcmp(predictionsTable.scenario_name, scenarioNames{i});
    rows = add_metric_block(rows, predictionsTable(idx, :), splitName, modelName, 'scenario', scenarioNames{i});
end
metricsTable = cell2table(rows, 'VariableNames', ...
    {'model_name','split','metric_scope','scenario_name','metric_name','metric_value'});
end

function rows = add_metric_block(rows, tbl, splitName, modelName, metricScope, scenarioName)
actual = tbl.actual_target;
predicted = tbl.predicted_target;
err = predicted - actual;
absErr = abs(err);
mae = mean(absErr, 'omitnan');
rmse = sqrt(mean(err .^ 2, 'omitnan'));
ssRes = sum((actual - predicted) .^ 2, 'omitnan');
ssTot = sum((actual - mean(actual, 'omitnan')) .^ 2, 'omitnan');
if ssTot > 0
    r2 = 1 - ssRes / ssTot;
else
    r2 = NaN;
end
safeDen = abs(actual) > 1e-6;
if any(safeDen)
    mape = mean(absErr(safeDen) ./ abs(actual(safeDen)), 'omitnan') * 100;
else
    mape = NaN;
end
meanError = mean(err, 'omitnan');
medianAbsError = median(absErr, 'omitnan');

rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'MAE', mae);
rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'RMSE', rmse);
rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'R2', r2);
rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'MAPE', mape);
rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'mean_error', meanError);
rows = add_metric(rows, modelName, splitName, metricScope, scenarioName, 'median_absolute_error', medianAbsError);
end

function rows = add_metric(rows, modelName, splitName, scope, scenarioName, metricName, metricValue)
rows(end+1, :) = {modelName, splitName, scope, scenarioName, metricName, metricValue}; %#ok<AGROW>
end

function value = metric_value(metricsTable, metricName)
idx = strcmp(metricsTable.metric_name, metricName);
if any(idx)
    value = metricsTable.metric_value(find(idx, 1));
else
    value = NaN;
end
end
