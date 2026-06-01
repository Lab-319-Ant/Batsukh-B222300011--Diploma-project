function [predictionTable, metricsTable] = evaluate_action_value_regressor(model, T, inputFeatures, targetName, splitName)
%EVALUATE_ACTION_VALUE_REGRESSOR Predict and score one split.
%
% Returns:
%   predictionTable - per-row predictions with key metadata for later
%                     oracle-regret evaluation.
%   metricsTable    - long-form (model, split, metric_name, metric_value)
%                     overall and per-scenario rows.

predictionTable = table();
metricsTable = table();
if isempty(T)
    return;
end

X = T(:, inputFeatures);
y = T.(targetName);

switch model.modelType
    case 'LSBoost'
        yhat = predict(model.model, X);
    case 'TreeBagger'
        yhat = predict(model.model, table2array(X));
    otherwise
        error('Unknown model type: %s', model.modelType);
end
yhat = double(yhat);

predictionTable = table(T.action_id, T.scenario_name, T.realization_id, ...
    T.source_sector_id, T.target_sector_id, T.module_name, T.action_type, ...
    T.oracle_group_id, logical(T.oracle_selected), logical(T.safety_valid), ...
    logical(T.safe_training_candidate), y, yhat, yhat - y, ...
    repmat({splitName}, height(T), 1), ...
    'VariableNames', {'action_id','scenario_name','realization_id', ...
    'source_sector_id','target_sector_id','module_name','action_type', ...
    'oracle_group_id','oracle_selected','safety_valid','safe_training_candidate', ...
    'actual_reward','predicted_reward','error','split'});

metricsTable = compute_metrics(y, yhat, splitName, 'ALL');
scenarios = unique(string(T.scenario_name));
for i = 1:numel(scenarios)
    mask = string(T.scenario_name) == scenarios(i);
    if any(mask)
        m = compute_metrics(y(mask), yhat(mask), splitName, char(scenarios(i)));
        metricsTable = [metricsTable; m]; %#ok<AGROW>
    end
end
end

function metrics = compute_metrics(actual, predicted, splitName, scenarioLabel)
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

spearman = NaN;
finite = isfinite(actual) & isfinite(predicted);
if sum(finite) >= 3 && exist('corr', 'file') == 2
    try
        spearman = corr(actual(finite), predicted(finite), 'Type', 'Spearman');
    catch
        spearman = NaN;
    end
end

names = {'MAE','RMSE','R2','mean_error','median_absolute_error','spearman_rho'};
values = [mae, rmse, r2, meanError, medianAbsErr, spearman];
n = numel(names);
metrics = table(repmat({splitName}, n, 1), repmat({scenarioLabel}, n, 1), ...
    names(:), values(:), ...
    'VariableNames', {'split','scenario_name','metric_name','metric_value'});
end
