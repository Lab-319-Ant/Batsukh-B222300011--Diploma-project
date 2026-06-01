function phase7b = run_phase7b_tp_qp_training(cfg)
%RUN_PHASE7B_TP_QP_TRAINING Train TP/QP regressors with walk-forward split.

featureFile = fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_table.csv');
dictionaryFile = fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_dictionary.csv');
featureTable = readtable(featureFile);
featureDictionary = readtable(dictionaryFile);

inputFeatures = featureDictionary.column_name(strcmp(featureDictionary.role, 'input_feature_candidate'))';
inputFeatures = cellstr(inputFeatures);
forbiddenInputs = get_forbidden_phase7b_inputs(inputFeatures);
if ~isempty(forbiddenInputs)
    error('Phase7B:ForbiddenInputs', 'Forbidden Phase 7B inputs: %s', strjoin(forbiddenInputs, ', '));
end

[splitPlan, splitSummary] = create_walk_forward_split(featureTable);
featureTable = innerjoin(featureTable, splitPlan(:, {'temporal_sample_id','split'}), 'Keys', 'temporal_sample_id');
featureTable = sortrows(featureTable, 'temporal_sample_id');

trainTable = featureTable(strcmp(featureTable.split, 'train'), :);
validationTable = featureTable(strcmp(featureTable.split, 'validation'), :);
testTable = featureTable(strcmp(featureTable.split, 'test'), :);

tpTarget = 'next_sector_load_ratio';
qpTarget = 'next_qos_satisfaction_ratio';

tpModel = train_regression_model(cfg, trainTable, inputFeatures, tpTarget, 'TP');
qpModel = train_regression_model(cfg, trainTable, inputFeatures, qpTarget, 'QP');
save(fullfile(cfg.modelsDir, 'phase7b_tp_regression_model.mat'), 'tpModel');
save(fullfile(cfg.modelsDir, 'phase7b_qp_regression_model.mat'), 'qpModel');

[tpValidationMetrics, tpValidationPredictions, tpValidationSummary] = ...
    evaluate_regression_model(tpModel, validationTable, inputFeatures, tpTarget, 'validation');
[tpTestMetrics, tpTestPredictions, tpTestSummary] = ...
    evaluate_regression_model(tpModel, testTable, inputFeatures, tpTarget, 'test');
[qpValidationMetrics, qpValidationPredictions, qpValidationSummary] = ...
    evaluate_regression_model(qpModel, validationTable, inputFeatures, qpTarget, 'validation');
[qpTestMetrics, qpTestPredictions, qpTestSummary] = ...
    evaluate_regression_model(qpModel, testTable, inputFeatures, qpTarget, 'test');

tpMetrics = [tpValidationMetrics; tpTestMetrics];
qpMetrics = [qpValidationMetrics; qpTestMetrics];
tpPredictions = [tpValidationPredictions; tpTestPredictions];
qpPredictions = [qpValidationPredictions; qpTestPredictions];

tpImportance = build_importance_table(inputFeatures, tpModel.featureImportance);
qpImportance = build_importance_table(inputFeatures, qpModel.featureImportance);

writetable(tpMetrics, fullfile(cfg.tablesDir, 'phase7b_tp_metrics.csv'));
writetable(qpMetrics, fullfile(cfg.tablesDir, 'phase7b_qp_metrics.csv'));
writetable(tpPredictions, fullfile(cfg.tablesDir, 'phase7b_tp_predictions.csv'));
writetable(qpPredictions, fullfile(cfg.tablesDir, 'phase7b_qp_predictions.csv'));
writetable(tpImportance, fullfile(cfg.tablesDir, 'phase7b_tp_feature_importance.csv'));
writetable(qpImportance, fullfile(cfg.tablesDir, 'phase7b_qp_feature_importance.csv'));
writetable(splitSummary, fullfile(cfg.tablesDir, 'phase7b_tp_qp_split_summary.csv'));

plot_regression_actual_vs_predicted(cfg, tpPredictions, 'TP: next sector load', 'phase7b_tp_actual_vs_predicted.png');
plot_regression_actual_vs_predicted(cfg, qpPredictions, 'QP: next QoS satisfaction', 'phase7b_qp_actual_vs_predicted.png');
plot_regression_error_by_scenario(cfg, tpPredictions, 'TP error by scenario', 'phase7b_tp_error_by_scenario.png');
plot_regression_error_by_scenario(cfg, qpPredictions, 'QP error by scenario', 'phase7b_qp_error_by_scenario.png');

validationResults = validate_phase7b_tp_qp_results(cfg, inputFeatures, splitPlan, ...
    tpMetrics, qpMetrics, tpPredictions, qpPredictions);

phase7b = struct();
phase7b.inputRows = height(featureTable);
phase7b.inputFeatures = inputFeatures;
phase7b.trainRows = height(trainTable);
phase7b.validationRows = height(validationTable);
phase7b.testRows = height(testTable);
phase7b.tpTarget = tpTarget;
phase7b.qpTarget = qpTarget;
phase7b.tpValidationSummary = tpValidationSummary;
phase7b.tpTestSummary = tpTestSummary;
phase7b.qpValidationSummary = qpValidationSummary;
phase7b.qpTestSummary = qpTestSummary;
phase7b.tpImportance = tpImportance;
phase7b.qpImportance = qpImportance;
phase7b.splitSummary = splitSummary;
phase7b.validationTable = validationResults;
end

function forbidden = get_forbidden_phase7b_inputs(inputFeatures)
hardForbidden = {'scenario_name','site_id','sector_id','temporal_sample_id', ...
    'day_id','sector_status','impaired_sector_id','impaired_site_id', ...
    'impaired_sector_status','is_impaired_sector','referencePowerOffset_dB', ...
    'txPowerOffset_dB','outage_flag','degradation_flag','cod_label'};
targetForbidden = inputFeatures(startsWith(inputFeatures, 'next_'));
forbidden = unique([intersect(inputFeatures, hardForbidden), targetForbidden]);
end

function importanceTable = build_importance_table(inputFeatures, importance)
importanceTable = table(inputFeatures(:), importance(:), ...
    'VariableNames', {'feature_name','importance'});
importanceTable = sortrows(importanceTable, 'importance', 'descend');
end
