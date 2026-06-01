function validationTable = validate_phase7b_tp_qp_results(cfg, inputFeatures, splitPlan, tpMetrics, qpMetrics, tpPredictions, qpPredictions)
%VALIDATE_PHASE7B_TP_QP_RESULTS Validate TP/QP regression outputs.

rows = {};
tpModelFile = fullfile(cfg.modelsDir, 'phase7b_tp_regression_model.mat');
qpModelFile = fullfile(cfg.modelsDir, 'phase7b_qp_regression_model.mat');

rows = add_check(rows, 'tp_model_file_exists', 'error', isfile(tpModelFile), tpModelFile, ...
    'TP model file must exist.', '');
rows = add_check(rows, 'qp_model_file_exists', 'error', isfile(qpModelFile), qpModelFile, ...
    'QP model file must exist.', '');
rows = add_check(rows, 'tp_predictions_table_exists', 'error', ...
    isfile(fullfile(cfg.tablesDir, 'phase7b_tp_predictions.csv')), 'phase7b_tp_predictions.csv', ...
    'TP predictions table must exist.', '');
rows = add_check(rows, 'qp_predictions_table_exists', 'error', ...
    isfile(fullfile(cfg.tablesDir, 'phase7b_qp_predictions.csv')), 'phase7b_qp_predictions.csv', ...
    'QP predictions table must exist.', '');

forbiddenInputs = detect_forbidden_inputs(inputFeatures);
rows = add_check(rows, 'no_forbidden_columns_used_as_inputs', 'error', isempty(forbiddenInputs), ...
    strjoin(forbiddenInputs, ', '), 'Forbidden metadata, scenario, sector, status, or target columns must not be inputs.', '');

walkForwardValid = validate_walk_forward_order(splitPlan);
rows = add_check(rows, 'walk_forward_order_valid', 'error', walkForwardValid, join_flag(walkForwardValid), ...
    'Walk-forward split must train on earlier samples and test on later samples.', '');

testScenarios = unique(tpPredictions.scenario_name(strcmp(tpPredictions.split, 'test')));
rows = add_check(rows, 'test_rows_exist_for_every_scenario', 'error', ...
    numel(testScenarios) == numel(cfg.phase7ScenarioTypes), sprintf('%d scenarios', numel(testScenarios)), ...
    'Test rows must exist for every configured Phase 7 scenario.', '');

rows = add_metric_checks(rows, tpMetrics, 'TP');
rows = add_metric_checks(rows, qpMetrics, 'QP');

rows = add_check(rows, 'tp_actual_vs_predicted_figure_exists', 'error', ...
    isfile(fullfile(cfg.figuresDir, 'phase7b_tp_actual_vs_predicted.png')), ...
    'phase7b_tp_actual_vs_predicted.png', 'TP actual-vs-predicted figure must exist.', '');
rows = add_check(rows, 'qp_actual_vs_predicted_figure_exists', 'error', ...
    isfile(fullfile(cfg.figuresDir, 'phase7b_qp_actual_vs_predicted.png')), ...
    'phase7b_qp_actual_vs_predicted.png', 'QP actual-vs-predicted figure must exist.', '');

nextInputs = inputFeatures(startsWith(inputFeatures, 'next_'));
rows = add_check(rows, 'next_targets_not_inputs', 'error', isempty(nextInputs), ...
    strjoin(nextInputs, ', '), 'next_* target columns must not be used as inputs.', '');
rows = add_check(rows, 'scenario_name_not_input', 'error', ~any(strcmp(inputFeatures, 'scenario_name')), ...
    join_flag(~any(strcmp(inputFeatures, 'scenario_name'))), 'scenario_name must not be used as input.', '');

tpTestR2 = get_metric(tpMetrics, 'test', 'overall', 'ALL', 'R2');
qpTestR2 = get_metric(qpMetrics, 'test', 'overall', 'ALL', 'R2');
rows = add_check(rows, 'tp_test_r2_threshold', 'warning', tpTestR2 >= 0.50, sprintf('%.4f', tpTestR2), ...
    'Warn if TP test R2 is below 0.50.', '');
rows = add_check(rows, 'qp_test_r2_threshold', 'warning', qpTestR2 >= 0.50, sprintf('%.4f', qpTestR2), ...
    'Warn if QP test R2 is below 0.50.', '');

rows = add_scenario_performance_warning(rows, tpMetrics, 'TP');
rows = add_scenario_performance_warning(rows, qpMetrics, 'QP');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase7b_tp_qp_validation.csv'));
end

function forbidden = detect_forbidden_inputs(inputFeatures)
hardForbidden = {'scenario_name','site_id','sector_id','temporal_sample_id','day_id', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB', ...
    'outage_flag','degradation_flag','cod_label'};
targetForbidden = inputFeatures(startsWith(inputFeatures, 'next_'));
forbidden = unique([intersect(inputFeatures, hardForbidden), targetForbidden]);
end

function isValid = validate_walk_forward_order(splitPlan)
isValid = true;
scenarioNames = unique(splitPlan.scenario_name, 'stable');
for s = 1:numel(scenarioNames)
    sectorIds = unique(splitPlan.sector_id(strcmp(splitPlan.scenario_name, scenarioNames{s})));
    for sec = sectorIds(:)'
        idx = strcmp(splitPlan.scenario_name, scenarioNames{s}) & splitPlan.sector_id == sec;
        trainMax = max(splitPlan.time_step(idx & strcmp(splitPlan.split, 'train')));
        valMin = min(splitPlan.time_step(idx & strcmp(splitPlan.split, 'validation')));
        valMax = max(splitPlan.time_step(idx & strcmp(splitPlan.split, 'validation')));
        testMin = min(splitPlan.time_step(idx & strcmp(splitPlan.split, 'test')));
        if ~(trainMax < valMin && valMax < testMin)
            isValid = false;
            return;
        end
    end
end
end

function rows = add_metric_checks(rows, metricsTable, modelName)
required = {'MAE','RMSE','R2'};
for i = 1:numel(required)
    value = get_metric(metricsTable, 'test', 'overall', 'ALL', required{i});
    rows = add_check(rows, lower(sprintf('%s_test_%s_reported', modelName, required{i})), 'error', ...
        ~isnan(value), sprintf('%.4f', value), sprintf('%s test %s must be reported.', modelName, required{i}), '');
end
end

function rows = add_scenario_performance_warning(rows, metricsTable, modelName)
for scenarioName = ["overload","mixed_conflict"]
    r2Value = get_metric(metricsTable, 'test', 'scenario', char(scenarioName), 'R2');
    rows = add_check(rows, lower(sprintf('%s_%s_test_r2_not_poor', modelName, scenarioName)), ...
        'warning', isnan(r2Value) || r2Value >= 0.30, sprintf('%.4f', r2Value), ...
        sprintf('Warn if %s test R2 for %s is below 0.30.', modelName, scenarioName), ...
        'Scenario-wise metric is for interpretation only; scenario_name was not an input.');
end
end

function value = get_metric(metricsTable, splitName, scope, scenarioName, metricName)
idx = strcmp(metricsTable.split, splitName) & strcmp(metricsTable.metric_scope, scope) & ...
    strcmp(metricsTable.scenario_name, scenarioName) & strcmp(metricsTable.metric_name, metricName);
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
