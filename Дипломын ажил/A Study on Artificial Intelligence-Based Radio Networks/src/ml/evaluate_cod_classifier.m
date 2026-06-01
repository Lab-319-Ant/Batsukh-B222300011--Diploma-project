function [metricsTable, confusionTable, predictionsTable, summary] = evaluate_cod_classifier(modelInfo, dataTable, inputFeatures, datasetName)
%EVALUATE_COD_CLASSIFIER Evaluate COD classifier and compute required metrics.

classNames = {'normal','degraded','outage'};
X = table2array(dataTable(:, inputFeatures));
actual = categorical(string(dataTable.cod_label), classNames);
[predicted, scores] = predict_cod_labels(modelInfo, X, classNames);

confMat = confusionmat(cellstr(actual), cellstr(predicted), 'Order', classNames);
confusionTable = array2table(confMat, 'VariableNames', ...
    strcat('predicted_', classNames), 'RowNames', strcat('actual_', classNames));
confusionTable = addvars(confusionTable, classNames', 'Before', 1, 'NewVariableNames', 'actual_label');
confusionTable.Properties.RowNames = {};

[metricsTable, summary] = compute_cod_metrics(confMat, classNames, datasetName);
predictionsTable = build_prediction_table(dataTable, actual, predicted, scores, classNames, datasetName);
end

function [predicted, scoresOut] = predict_cod_labels(modelInfo, X, classNames)
if strcmp(modelInfo.algorithm, 'TreeBagger')
    [predCell, scores] = predict(modelInfo.model, X);
    predicted = categorical(string(predCell), classNames);
    scoresOut = align_scores(scores, modelInfo.classOrder, classNames);
else
    [pred, scores] = predict(modelInfo.model, X);
    predicted = categorical(string(pred), classNames);
    scoresOut = align_scores(scores, modelInfo.classOrder, classNames);
end
end

function scoresOut = align_scores(scores, scoreClassOrder, classNames)
scoresOut = nan(size(scores, 1), numel(classNames));
for i = 1:numel(classNames)
    idx = find(strcmp(scoreClassOrder, classNames{i}), 1);
    if ~isempty(idx)
        scoresOut(:, i) = scores(:, idx);
    end
end
end

function [metricsTable, summary] = compute_cod_metrics(confMat, classNames, datasetName)
tp = diag(confMat);
actualCount = sum(confMat, 2);
predictedCount = sum(confMat, 1)';
precision = safe_divide(tp, predictedCount);
recall = safe_divide(tp, actualCount);
f1 = safe_divide(2 * precision .* recall, precision + recall);
accuracy = sum(tp) / max(sum(confMat(:)), 1);
macroPrecision = mean(precision, 'omitnan');
macroRecall = mean(recall, 'omitnan');
macroF1 = mean(f1, 'omitnan');
weightedF1 = sum(f1 .* actualCount) / max(sum(actualCount), 1);

normalIdx = strcmp(classNames, 'normal');
degradedIdx = strcmp(classNames, 'degraded');
outageIdx = strcmp(classNames, 'outage');
normalTotal = actualCount(normalIdx);
falseAlarmRate = sum(confMat(normalIdx, ~normalIdx)) / max(normalTotal, 1);
impairedRows = degradedIdx | outageIdx;
missedDetectionRate = sum(confMat(impairedRows, normalIdx)) / max(sum(actualCount(impairedRows)), 1);
outageRecall = recall(outageIdx);
degradedRecall = recall(degradedIdx);

rows = {};
rows = add_metric(rows, datasetName, 'overall', '', 'accuracy', accuracy);
rows = add_metric(rows, datasetName, 'overall', '', 'macro_precision', macroPrecision);
rows = add_metric(rows, datasetName, 'overall', '', 'macro_recall', macroRecall);
rows = add_metric(rows, datasetName, 'overall', '', 'macro_f1', macroF1);
rows = add_metric(rows, datasetName, 'overall', '', 'weighted_f1', weightedF1);
rows = add_metric(rows, datasetName, 'overall', '', 'false_alarm_rate', falseAlarmRate);
rows = add_metric(rows, datasetName, 'overall', '', 'missed_detection_rate', missedDetectionRate);
rows = add_metric(rows, datasetName, 'overall', '', 'outage_recall', outageRecall);
rows = add_metric(rows, datasetName, 'overall', '', 'degraded_recall', degradedRecall);

for i = 1:numel(classNames)
    rows = add_metric(rows, datasetName, 'per_class', classNames{i}, 'precision', precision(i));
    rows = add_metric(rows, datasetName, 'per_class', classNames{i}, 'recall', recall(i));
    rows = add_metric(rows, datasetName, 'per_class', classNames{i}, 'f1', f1(i));
    rows = add_metric(rows, datasetName, 'per_class', classNames{i}, 'support', actualCount(i));
end

metricsTable = cell2table(rows, 'VariableNames', ...
    {'dataset_name','metric_scope','class_label','metric_name','metric_value'});

summary = struct();
summary.accuracy = accuracy;
summary.macro_precision = macroPrecision;
summary.macro_recall = macroRecall;
summary.macro_f1 = macroF1;
summary.weighted_f1 = weightedF1;
summary.false_alarm_rate = falseAlarmRate;
summary.missed_detection_rate = missedDetectionRate;
summary.outage_recall = outageRecall;
summary.degraded_recall = degradedRecall;
end

function value = safe_divide(num, den)
value = num ./ den;
value(den == 0) = NaN;
end

function rows = add_metric(rows, datasetName, metricScope, classLabel, metricName, metricValue)
rows(end+1, :) = {datasetName, metricScope, classLabel, metricName, metricValue}; %#ok<AGROW>
end

function predictionsTable = build_prediction_table(dataTable, actual, predicted, scores, classNames, datasetName)
numRows = height(dataTable);
predictionsTable = table(repmat({datasetName}, numRows, 1), ...
    cellstr(actual), cellstr(predicted), ...
    scores(:, 1), scores(:, 2), scores(:, 3), ...
    'VariableNames', {'dataset_name','actual_label','predicted_label', ...
    'score_normal','score_degraded','score_outage'});

metadata = {'row_id','realization_id','scenario_name','site_id','sector_id','impaired_sector_id','split'};
for i = numel(metadata):-1:1
    name = metadata{i};
    if ismember(name, dataTable.Properties.VariableNames)
        predictionsTable = addvars(predictionsTable, dataTable.(name), 'Before', 1, 'NewVariableNames', name);
    end
end
end
