function phase6b = run_phase6b_cod_training(cfg)
%RUN_PHASE6B_COD_TRAINING Train and validate COD Random Forest classifier.

balancedFile = fullfile(cfg.tablesDir, 'phase6a_cod_balanced_dataset.csv');
featureFile = fullfile(cfg.tablesDir, 'phase6a_cod_feature_list.csv');
splitFile = fullfile(cfg.tablesDir, 'phase6a_cod_split_plan.csv');
externalFile = fullfile(cfg.tablesDir, 'phase4b_sector_features_cod.csv');

balancedTable = readtable(balancedFile);
featureList = read_csv_preserve_headers(featureFile);
splitPlan = readtable(splitFile);
externalTable = readtable(externalFile);

inputFeatures = featureList.feature_name(strcmp(featureList.role, 'input_feature') & ...
    logical(featureList.allowed_as_input))';
inputFeatures = cellstr(inputFeatures);
forbiddenInputs = intersect(inputFeatures, get_forbidden_cod_inputs());
if ~isempty(forbiddenInputs)
    error('Phase6B:ForbiddenCODInput', ...
        'Forbidden COD model inputs requested: %s', strjoin(forbiddenInputs, ', '));
end

balancedTable = join_split_plan(balancedTable, splitPlan);
balancedTable = normalize_cod_eval_table(balancedTable, inputFeatures);
externalTable = normalize_external_cod_table(externalTable, inputFeatures);

trainTable = balancedTable(strcmp(string(balancedTable.split), 'train'), :);
validationTable = balancedTable(strcmp(string(balancedTable.split), 'validation'), :);
testTable = balancedTable(strcmp(string(balancedTable.split), 'test'), :);

modelInfo = train_cod_random_forest(cfg, trainTable, inputFeatures);
modelFile = fullfile(cfg.modelsDir, 'phase6b_cod_random_forest_model.mat');
save(modelFile, 'modelInfo');

[validationMetrics, validationConfusion, validationPredictions, validationSummary] = ...
    evaluate_cod_classifier(modelInfo, validationTable, inputFeatures, 'balanced_validation');
[testMetrics, testConfusion, testPredictions, testSummary] = ...
    evaluate_cod_classifier(modelInfo, testTable, inputFeatures, 'balanced_test');
[externalMetrics, externalConfusion, externalPredictions, externalSummary] = ...
    evaluate_cod_classifier(modelInfo, externalTable, inputFeatures, 'external_phase4b');

featureImportance = table(inputFeatures', modelInfo.featureImportance(:), ...
    'VariableNames', {'feature_name','importance'});
featureImportance = sortrows(featureImportance, 'importance', 'descend');

balancedPredictions = [validationPredictions; testPredictions];

writetable(validationMetrics, fullfile(cfg.tablesDir, 'phase6b_cod_validation_metrics.csv'));
writetable(testMetrics, fullfile(cfg.tablesDir, 'phase6b_cod_test_metrics.csv'));
writetable(externalMetrics, fullfile(cfg.tablesDir, 'phase6b_cod_external_metrics.csv'));
writetable(validationConfusion, fullfile(cfg.tablesDir, 'phase6b_cod_validation_confusion_matrix.csv'));
writetable(testConfusion, fullfile(cfg.tablesDir, 'phase6b_cod_test_confusion_matrix.csv'));
writetable(externalConfusion, fullfile(cfg.tablesDir, 'phase6b_cod_external_confusion_matrix.csv'));
writetable(featureImportance, fullfile(cfg.tablesDir, 'phase6b_cod_feature_importance.csv'));
writetable(balancedPredictions, fullfile(cfg.tablesDir, 'phase6b_cod_predictions_balanced.csv'));
writetable(externalPredictions, fullfile(cfg.tablesDir, 'phase6b_cod_predictions_external.csv'));

plot_cod_confusion_matrix(cfg, testConfusion, 'Phase 6B COD test confusion matrix', ...
    'phase6b_cod_test_confusion_matrix.png');
plot_cod_confusion_matrix(cfg, externalConfusion, 'Phase 6B COD external confusion matrix', ...
    'phase6b_cod_external_confusion_matrix.png');
plot_cod_feature_importance(cfg, featureImportance, 'phase6b_cod_feature_importance.png');

modelValidation = validate_cod_model_results(cfg, modelInfo, inputFeatures, ...
    testMetrics, externalMetrics, testConfusion, featureImportance, ...
    balancedPredictions, externalPredictions);

phase6b = struct();
phase6b.modelInfo = modelInfo;
phase6b.inputFeatures = inputFeatures;
phase6b.trainingRows = height(trainTable);
phase6b.validationRows = height(validationTable);
phase6b.testRows = height(testTable);
phase6b.externalRows = height(externalTable);
phase6b.validationSummary = validationSummary;
phase6b.testSummary = testSummary;
phase6b.externalSummary = externalSummary;
phase6b.featureImportance = featureImportance;
phase6b.validationTable = modelValidation;
end

function tbl = read_csv_preserve_headers(filePath)
opts = detectImportOptions(filePath, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
tbl = readtable(filePath, opts);
end

function tbl = join_split_plan(tbl, splitPlan)
if ismember('split', tbl.Properties.VariableNames)
    tbl.split = [];
end
tbl = innerjoin(tbl, splitPlan(:, {'row_id','split'}), 'Keys', 'row_id');
tbl = sortrows(tbl, 'row_id');
end

function tbl = normalize_cod_eval_table(tbl, inputFeatures)
tbl.cod_label = categorical(string(tbl.cod_label), {'normal','degraded','outage'});
tbl = impute_inputs(tbl, inputFeatures);
end

function tbl = normalize_external_cod_table(tbl, inputFeatures)
if ~ismember('row_id', tbl.Properties.VariableNames)
    tbl.row_id = (1:height(tbl))';
    tbl = movevars(tbl, 'row_id', 'Before', 1);
end
if ~ismember('impaired_sector_id', tbl.Properties.VariableNames)
    tbl.impaired_sector_id = zeros(height(tbl), 1);
end
tbl.cod_label = categorical(string(tbl.cod_label), {'normal','degraded','outage'});
tbl = impute_inputs(tbl, inputFeatures);
end

function tbl = impute_inputs(tbl, inputFeatures)
for i = 1:numel(inputFeatures)
    name = inputFeatures{i};
    values = double(tbl.(name));
    replacement = 0;
    if strcmp(name, 'qos_satisfaction_ratio')
        replacement = 1;
    elseif contains(name, 'RSRP')
        replacement = -125;
    elseif contains(name, 'SINR')
        replacement = -20;
    end
    values(ismissing(values) | isinf(values)) = replacement;
    tbl.(name) = values;
end
end

function forbiddenInputs = get_forbidden_cod_inputs()
forbiddenInputs = {'scenario_id','scenario_name','scenario_label','traffic_mode', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB', ...
    'outage_flag','degradation_flag','cod_label'};
end
