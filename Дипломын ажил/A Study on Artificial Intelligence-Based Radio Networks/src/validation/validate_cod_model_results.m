function validationTable = validate_cod_model_results(cfg, modelInfo, inputFeatures, ...
    testMetrics, externalMetrics, testConfusion, featureImportance, balancedPredictions, externalPredictions)
%VALIDATE_COD_MODEL_RESULTS Validate Phase 6B COD model outputs.

rows = {};
modelFile = fullfile(cfg.modelsDir, 'phase6b_cod_random_forest_model.mat');
forbiddenInputs = {'scenario_id','scenario_name','scenario_label','traffic_mode', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB', ...
    'outage_flag','degradation_flag','cod_label'};

rows = add_check(rows, 'model_file_exists', 'error', isfile(modelFile), ...
    modelFile, 'COD model MAT file must exist.', '');
leakageInputs = intersect(inputFeatures, forbiddenInputs);
rows = add_check(rows, 'no_forbidden_leakage_feature_used', 'error', isempty(leakageInputs), ...
    strjoin(leakageInputs, ', '), 'Forbidden leakage columns must not be model inputs.', '');

classesInTest = string(testConfusion.actual_label);
rows = add_check(rows, 'test_confusion_contains_all_classes', 'error', ...
    all(ismember(["normal","degraded","outage"], classesInTest)), ...
    strjoin(cellstr(classesInTest'), ', '), 'Balanced test confusion matrix must contain all three classes.', '');

testOutageRecall = metric_value(testMetrics, 'outage_recall');
testMissedDetection = metric_value(testMetrics, 'missed_detection_rate');
testFalseAlarm = metric_value(testMetrics, 'false_alarm_rate');
testAccuracy = metric_value(testMetrics, 'accuracy');
externalOutageRecall = metric_value(externalMetrics, 'outage_recall');
externalMissedDetection = metric_value(externalMetrics, 'missed_detection_rate');

rows = add_check(rows, 'outage_recall_reported', 'error', ~isnan(testOutageRecall), ...
    sprintf('%.4f', testOutageRecall), 'Outage recall must be reported.', '');
rows = add_check(rows, 'missed_detection_rate_reported', 'error', ~isnan(testMissedDetection), ...
    sprintf('%.4f', testMissedDetection), 'Missed detection rate must be reported.', '');
rows = add_check(rows, 'false_alarm_rate_reported', 'error', ~isnan(testFalseAlarm), ...
    sprintf('%.4f', testFalseAlarm), 'False alarm rate must be reported.', '');
rows = add_check(rows, 'external_evaluation_reported', 'error', ...
    ~isnan(externalOutageRecall) && ~isnan(externalMissedDetection), ...
    sprintf('external outage recall=%.4f missed=%.4f', externalOutageRecall, externalMissedDetection), ...
    'External imbalanced evaluation must be reported.', '');

rows = add_check(rows, 'feature_importance_table_exists', 'error', height(featureImportance) > 0, ...
    sprintf('%d features', height(featureImportance)), 'Feature importance table must exist.', '');
hasPredictionColumns = all(ismember({'actual_label','predicted_label'}, balancedPredictions.Properties.VariableNames)) && ...
    all(ismember({'actual_label','predicted_label'}, externalPredictions.Properties.VariableNames));
rows = add_check(rows, 'prediction_tables_have_actual_and_predicted', 'error', hasPredictionColumns, ...
    join_flag(hasPredictionColumns), 'Prediction tables must include actual_label and predicted_label.', '');

rows = add_check(rows, 'test_outage_recall_threshold', 'warning', testOutageRecall >= 0.80, ...
    sprintf('%.4f', testOutageRecall), 'Warn if balanced-test outage recall is below 0.80.', '');
rows = add_check(rows, 'test_missed_detection_threshold', 'warning', testMissedDetection <= 0.20, ...
    sprintf('%.4f', testMissedDetection), 'Warn if balanced-test missed detection rate is above 0.20.', '');
misleadingAccuracy = testAccuracy >= 0.90 && testOutageRecall < 0.80;
rows = add_check(rows, 'accuracy_not_misleading_for_outage', 'warning', ~misleadingAccuracy, ...
    sprintf('accuracy=%.4f outage_recall=%.4f', testAccuracy, testOutageRecall), ...
    'Warn if high accuracy hides poor outage recall.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase6b_cod_model_validation.csv'));
end

function value = metric_value(metricsTable, metricName)
idx = strcmp(metricsTable.metric_name, metricName) & strcmp(metricsTable.metric_scope, 'overall');
if any(idx)
    value = metricsTable.metric_value(find(idx, 1));
else
    value = NaN;
end
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function value = join_flag(flag)
if flag
    value = 'true';
else
    value = 'false';
end
end
