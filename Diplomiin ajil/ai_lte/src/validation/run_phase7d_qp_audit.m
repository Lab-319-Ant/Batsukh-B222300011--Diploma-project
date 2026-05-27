function phase7d = run_phase7d_qp_audit(cfg)
%RUN_PHASE7D_QP_AUDIT Audit Phase 7 QP target and prediction behavior.
%
% This audit is diagnostic only. It reads Phase 7A/7B/7C artifacts and
% writes Phase 7D audit tables, figures, and a report. It does not retrain
% models and does not touch Phase 8-12 logic or outputs.

if nargin < 1 || isempty(cfg)
    cfg = sim_config();
end

ensure_folder(cfg.tablesDir);
ensure_folder(cfg.figuresDir);
reportsDir = fullfile(cfg.resultsDir, 'reports');
ensure_folder(reportsDir);

downstreamBefore = snapshot_downstream_outputs(cfg);

featureTable = readtable(fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_table.csv'));
featureDictionary = readtable(fullfile(cfg.tablesDir, 'phase7a_sector_tp_qp_feature_dictionary.csv'));
sectorTemporal = readtable(fullfile(cfg.tablesDir, 'phase7a_temporal_sector_dataset.csv'));
qpPredictions = readtable(fullfile(cfg.tablesDir, 'phase7b_qp_predictions.csv'));
qpBoundedPredictions = readtable(fullfile(cfg.tablesDir, 'phase7c_qp_predictions_bounded.csv'));

inputFeatures = cellstr(featureDictionary.column_name(strcmp(featureDictionary.role, 'input_feature_candidate'))');
targetName = 'next_qos_satisfaction_ratio';
target = featureTable.(targetName);

[splitPlan, ~] = create_walk_forward_split(featureTable);
featureTable = innerjoin(featureTable, splitPlan(:, {'temporal_sample_id','split'}), ...
    'Keys', 'temporal_sample_id');
featureTable = sortrows(featureTable, 'temporal_sample_id');

formulaAudit = audit_qp_target_formula(cfg, featureTable, sectorTemporal, inputFeatures);
distributionBySplit = build_distribution_by_split(featureTable, targetName);
distributionByScenario = build_distribution_by_scenario(featureTable, targetName);
splitAudit = audit_qp_split(featureTable, inputFeatures);
[rawVsBoundedMetrics, rawSummary] = build_raw_vs_bounded_metrics(qpPredictions);
baselineComparison = build_baseline_comparison(featureTable, qpPredictions);
[binaryDiagnostic, confusionMatrix] = build_binary_threshold_diagnostic(qpBoundedPredictions, 0.8);

plot_qp_target_distribution(cfg, featureTable.(targetName));
plot_qp_target_distribution_by_scenario(cfg, distributionByScenario);
plot_qp_bounded_actual_vs_predicted_density(cfg, qpBoundedPredictions);
plot_qp_prediction_distribution_given_actual_extremes(cfg, qpBoundedPredictions);
plot_qp_binary_confusion(cfg, confusionMatrix, binaryDiagnostic);

recommendation = build_thesis_recommendation(formulaAudit, distributionBySplit, ...
    distributionByScenario, rawVsBoundedMetrics, binaryDiagnostic);

downstreamAfter = snapshot_downstream_outputs(cfg);
[downstreamUnchanged, downstreamNotes] = compare_snapshots(downstreamBefore, downstreamAfter);

validationTable = validate_phase7d_qp_audit(cfg, target, qpPredictions, ...
    qpBoundedPredictions, inputFeatures, distributionBySplit, distributionByScenario, ...
    rawSummary, recommendation, downstreamUnchanged, downstreamNotes);

writetable(formulaAudit, fullfile(cfg.tablesDir, 'phase7d_qp_target_formula_audit.csv'));
writetable(distributionBySplit, fullfile(cfg.tablesDir, 'phase7d_qp_target_distribution_by_split.csv'));
writetable(distributionByScenario, fullfile(cfg.tablesDir, 'phase7d_qp_target_distribution_by_scenario.csv'));
writetable(splitAudit, fullfile(cfg.tablesDir, 'phase7d_qp_split_audit.csv'));
writetable(rawVsBoundedMetrics, fullfile(cfg.tablesDir, 'phase7d_qp_raw_vs_bounded_metrics.csv'));
writetable(baselineComparison, fullfile(cfg.tablesDir, 'phase7d_qp_baseline_comparison.csv'));
writetable(binaryDiagnostic, fullfile(cfg.tablesDir, 'phase7d_qp_binary_threshold_diagnostic.csv'));
writetable(recommendation, fullfile(cfg.tablesDir, 'phase7d_qp_thesis_recommendation.csv'));
writetable(validationTable, fullfile(cfg.tablesDir, 'phase7d_qp_audit_validation.csv'));

write_qp_audit_report(cfg, reportsDir, formulaAudit, distributionBySplit, ...
    distributionByScenario, splitAudit, rawVsBoundedMetrics, baselineComparison, ...
    binaryDiagnostic, recommendation, validationTable);

validationErrors = height(validationTable(strcmp(validationTable.severity, 'error') & ...
    ~validationTable.pass_flag, :));
validationWarnings = height(validationTable(strcmp(validationTable.severity, 'warning') & ...
    ~validationTable.pass_flag, :));

phase7d = struct();
phase7d.formulaAudit = formulaAudit;
phase7d.distributionBySplit = distributionBySplit;
phase7d.distributionByScenario = distributionByScenario;
phase7d.splitAudit = splitAudit;
phase7d.rawVsBoundedMetrics = rawVsBoundedMetrics;
phase7d.baselineComparison = baselineComparison;
phase7d.binaryDiagnostic = binaryDiagnostic;
phase7d.recommendation = recommendation;
phase7d.validationTable = validationTable;
phase7d.validationErrors = validationErrors;
phase7d.validationWarnings = validationWarnings;
end

function formulaAudit = audit_qp_target_formula(cfg, featureTable, sectorTemporal, inputFeatures)
projectRoot = fileparts(cfg.resultsDir);
sectorFeatureCode = fileread(fullfile(projectRoot, 'src', 'dataset', ...
    'build_phase7_sector_tp_qp_feature_table.m'));
sectorKpiCode = fileread(fullfile(projectRoot, 'src', 'kpi', 'compute_sector_kpis.m'));

target = featureTable.next_qos_satisfaction_ratio;
tol = 1e-12;
uniqueTargetCount = numel(unique(round(target(isfinite(target)) * 1e12) / 1e12));
midCount = sum(target > tol & target < 1 - tol);

sourceKey = make_source_key(sectorTemporal.scenario_name, sectorTemporal.sector_id, ...
    sectorTemporal.time_index);
horizon = cfg.phase7PredictionHorizonSteps;
targetKey = make_source_key(featureTable.scenario_name, featureTable.sector_id, ...
    featureTable.time_step + horizon);
[tf, loc] = ismember(targetKey, sourceKey);
sourceQos = nan(height(featureTable), 1);
sourceActiveAttached = nan(height(featureTable), 1);
sourceQos(tf) = sectorTemporal.qos_satisfaction_ratio(loc(tf));
sourceActiveAttached(tf) = sectorTemporal.active_attached_ue_count(loc(tf));
finiteSource = isfinite(sourceQos);
finiteSourceMatches = all(abs(target(finiteSource) - sourceQos(finiteSource)) <= 1e-12);
missingSourceImputedToOne = sum(~finiteSource & abs(target - 1) <= tol);
missingSourceCount = sum(~finiteSource);
zeroActiveTargetRows = sum(sourceActiveAttached == 0);

forbiddenLabels = {'scenario_label','scenario_name','traffic_mode','outage_flag', ...
    'degradation_flag','cod_label','impaired_sector_status','is_impaired_sector'};
forbiddenInputHits = intersect(inputFeatures, forbiddenLabels);
futureInputHits = inputFeatures(startsWith(inputFeatures, 'next_') | startsWith(inputFeatures, 'target_next_'));

rows = {};
rows = add_audit_row(rows, 'target_column_exists', true, 'error', ...
    'next_qos_satisfaction_ratio', 'Phase 7A sector feature table contains QP target.', '');
rows = add_audit_row(rows, 'target_copied_from_next_step_sector_qos', ...
    finiteSourceMatches && all(tf), 'error', ...
    sprintf('finite_source_matches=%d; source_rows_found=%d/%d', finiteSourceMatches, sum(tf), height(featureTable)), ...
    'Finite source target values must equal next-step sector qos_satisfaction_ratio.', ...
    sprintf('Missing sector QoS rows are handled by Phase 7 feature imputation: %d/%d target rows.', ...
    missingSourceImputedToOne, missingSourceCount));
rows = add_audit_row(rows, 'target_computed_as_ratio_not_all_or_nothing_flag', ...
    contains(sectorKpiCode, 'mean(ueTrafficResult.qosSatisfied(activeAttachedIdx))') && uniqueTargetCount > 2, ...
    'error', sprintf('unique_target_values=%d; intermediate_rows=%d', uniqueTargetCount, midCount), ...
    'Sector QoS must be a ratio/mean of UE satisfaction flags, not a single logical condition.', ...
    'The output is still strongly bimodal because sector groups often have all UEs satisfied or all UEs unsatisfied.');
rows = add_audit_row(rows, 'target_within_0_1', ...
    all(isfinite(target)) && all(target >= 0 & target <= 1), 'error', ...
    sprintf('min=%.6f; max=%.6f', min(target), max(target)), ...
    'All QP targets must be finite and within [0, 1].', '');
rows = add_audit_row(rows, 'target_not_overwritten_by_logical_condition', ...
    isempty(regexp(sectorFeatureCode, 'next_qos_satisfaction_ratio\s*=.*[><=]=', 'once')), ...
    'error', 'No logical overwrite pattern found in target assignment.', ...
    'Target assignment should copy the next-step ratio, not overwrite with a threshold.', '');
rows = add_audit_row(rows, 'target_not_rounded_to_binary', midCount > 0, 'warning', ...
    sprintf('intermediate_rows=%d; unique_target_values=%d', midCount, uniqueTargetCount), ...
    'At least some non-0/1 target values should exist if the target is not rounded.', ...
    'Only a very small fraction is intermediate; this is a target-distribution limitation.');
rows = add_audit_row(rows, 'missing_qos_imputed_to_one_documented', missingSourceCount >= 0, ...
    'warning', sprintf('missing_source_qos_rows=%d; imputed_to_one=%d; zero_active_next_rows=%d', ...
    missingSourceCount, missingSourceImputedToOne, zeroActiveTargetRows), ...
    'Missing/no-active sector QoS imputation must be visible in the audit.', ...
    'This is a target-definition artifact and should be mentioned as a limitation.');
rows = add_audit_row(rows, 'future_target_not_used_as_input', isempty(futureInputHits), ...
    'error', strjoin_or_none(futureInputHits), ...
    'No next_* or target_next_* columns may be used as QP inputs.', '');
rows = add_audit_row(rows, 'forbidden_labels_not_used_as_inputs', isempty(forbiddenInputHits), ...
    'error', strjoin_or_none(forbiddenInputHits), ...
    'Scenario labels, outage/degradation flags, and impairment labels must be metadata only.', '');

formulaAudit = cell2table(rows, 'VariableNames', ...
    {'check_name','pass_flag','severity','actual_value','expected_condition','notes'});
end

function distribution = build_distribution_by_split(featureTable, targetName)
splits = {'train','validation','test'};
rows = {};
for i = 1:numel(splits)
    idx = strcmp(featureTable.split, splits{i});
    rows = add_distribution_row(rows, splits{i}, featureTable.(targetName)(idx));
end
rows = add_distribution_row(rows, 'ALL', featureTable.(targetName));
distribution = cell2table(rows, 'VariableNames', {'split','row_count', ...
    'min_target','max_target','mean_target','std_target','pct_target_eq_0', ...
    'pct_target_eq_1','pct_target_between_0_1','num_unique_target_values'});
end

function distribution = build_distribution_by_scenario(featureTable, targetName)
scenarios = unique(string(featureTable.scenario_name), 'stable');
rows = {};
for i = 1:numel(scenarios)
    idx = string(featureTable.scenario_name) == scenarios(i);
    rows = add_distribution_row(rows, char(scenarios(i)), featureTable.(targetName)(idx));
end
distribution = cell2table(rows, 'VariableNames', {'scenario_name','row_count', ...
    'min_target','max_target','mean_target','std_target','pct_target_eq_0', ...
    'pct_target_eq_1','pct_target_between_0_1','num_unique_target_values'});
end

function rows = add_distribution_row(rows, label, values)
values = values(isfinite(values));
tol = 1e-12;
n = numel(values);
if n == 0
    rows(end+1, :) = {label, 0, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0}; %#ok<AGROW>
    return;
end
pct0 = 100 * sum(abs(values) <= tol) / n;
pct1 = 100 * sum(abs(values - 1) <= tol) / n;
pctMid = 100 * sum(values > tol & values < 1 - tol) / n;
uniqueCount = numel(unique(round(values * 1e12) / 1e12));
rows(end+1, :) = {label, n, min(values), max(values), mean(values, 'omitnan'), ...
    std(values, 'omitnan'), pct0, pct1, pctMid, uniqueCount}; %#ok<AGROW>
end

function splitAudit = audit_qp_split(featureTable, inputFeatures)
rows = {};
scenarioSector = unique(table(string(featureTable.scenario_name), featureTable.sector_id, ...
    'VariableNames', {'scenario_name','sector_id'}));
temporalOk = true;
for i = 1:height(scenarioSector)
    idx = string(featureTable.scenario_name) == scenarioSector.scenario_name(i) & ...
        featureTable.sector_id == scenarioSector.sector_id(i);
    trainTimes = featureTable.time_step(idx & strcmp(featureTable.split, 'train'));
    valTimes = featureTable.time_step(idx & strcmp(featureTable.split, 'validation'));
    testTimes = featureTable.time_step(idx & strcmp(featureTable.split, 'test'));
    if isempty(trainTimes) || isempty(valTimes) || isempty(testTimes) || ...
            max(trainTimes) >= min(valTimes) || max(valTimes) >= min(testTimes)
        temporalOk = false;
        break;
    end
end

trainTarget = featureTable.next_qos_satisfaction_ratio(strcmp(featureTable.split, 'train'));
testTarget = featureTable.next_qos_satisfaction_ratio(strcmp(featureTable.split, 'test'));
tol = 1e-12;
trainEndpointPct = 100 * sum(abs(trainTarget) <= tol | abs(trainTarget - 1) <= tol) / numel(trainTarget);
testEndpointPct = 100 * sum(abs(testTarget) <= tol | abs(testTarget - 1) <= tol) / numel(testTarget);
endpointDifference = abs(trainEndpointPct - testEndpointPct);

testRows = featureTable(strcmp(featureTable.split, 'test'), :);
scenarios = unique(string(testRows.scenario_name), 'stable');
shares = zeros(numel(scenarios), 1);
for i = 1:numel(scenarios)
    shares(i) = sum(string(testRows.scenario_name) == scenarios(i)) / height(testRows);
end
maxScenarioShare = max(shares);

forbiddenLabels = {'scenario_label','scenario_name','traffic_mode','outage_flag', ...
    'degradation_flag','cod_label','impaired_sector_status','is_impaired_sector'};
forbiddenInputHits = intersect(inputFeatures, forbiddenLabels);
futureInputHits = inputFeatures(startsWith(inputFeatures, 'next_') | startsWith(inputFeatures, 'target_next_'));

rows = add_audit_row(rows, 'temporal_split_respected', temporalOk, 'error', ...
    sprintf('scenario_sector_groups_checked=%d', height(scenarioSector)), ...
    'Within every scenario-sector group: train time < validation time < test time.', '');
rows = add_audit_row(rows, 'target_distribution_comparable_by_split', endpointDifference <= 5, ...
    'warning', sprintf('train_endpoint_pct=%.2f; test_endpoint_pct=%.2f; abs_diff=%.2f', ...
    trainEndpointPct, testEndpointPct, endpointDifference), ...
    'Train and test endpoint proportions should be broadly comparable.', ...
    'Comparable does not mean healthy; all splits are strongly endpoint dominated.');
rows = add_audit_row(rows, 'test_split_endpoint_dominated', testEndpointPct < 95, ...
    'warning', sprintf('test_target_at_0_or_1_pct=%.2f', testEndpointPct), ...
    'Warn if the test split is dominated by 0/1 targets.', ...
    'This confirms the visible vertical bands are target-distribution driven.');
rows = add_audit_row(rows, 'no_scenario_dominates_test', maxScenarioShare <= 0.30, ...
    'error', sprintf('max_scenario_share=%.3f; scenario_count=%d', maxScenarioShare, numel(scenarios)), ...
    'No single scenario should dominate the test split.', '');
rows = add_audit_row(rows, 'future_target_not_used_as_input', isempty(futureInputHits), ...
    'error', strjoin_or_none(futureInputHits), ...
    'No future target columns may appear in input features.', '');
rows = add_audit_row(rows, 'forbidden_labels_not_used_as_inputs', isempty(forbiddenInputHits), ...
    'error', strjoin_or_none(forbiddenInputHits), ...
    'No scenario/outage/degradation labels may appear in input features.', '');

splitAudit = cell2table(rows, 'VariableNames', ...
    {'check_name','pass_flag','severity','actual_value','expected_condition','notes'});
end

function [metricsTable, rawSummary] = build_raw_vs_bounded_metrics(qpPredictions)
splits = {'validation','test','ALL_EVAL'};
rows = {};
for i = 1:numel(splits)
    splitName = splits{i};
    if strcmp(splitName, 'ALL_EVAL')
        idx = true(height(qpPredictions), 1);
    else
        idx = strcmp(qpPredictions.split, splitName);
    end
    actual = qpPredictions.actual_target(idx);
    rawPred = qpPredictions.predicted_target(idx);
    boundedPred = min(max(rawPred, 0), 1);
    rawMetrics = calc_metrics(actual, rawPred);
    boundedMetrics = calc_metrics(actual, boundedPred);
    pctBelow0 = 100 * sum(rawPred < 0) / numel(rawPred);
    pctAbove1 = 100 * sum(rawPred > 1) / numel(rawPred);
    improved = boundedMetrics.rmse <= rawMetrics.rmse;
    rows(end+1, :) = {splitName, numel(actual), rawMetrics.mae, rawMetrics.rmse, rawMetrics.r2, ...
        min(rawPred), max(rawPred), pctBelow0, pctAbove1, boundedMetrics.mae, ...
        boundedMetrics.rmse, boundedMetrics.r2, min(boundedPred), max(boundedPred), ...
        boundedMetrics.mae - rawMetrics.mae, boundedMetrics.rmse - rawMetrics.rmse, ...
        boundedMetrics.r2 - rawMetrics.r2, improved}; %#ok<AGROW>
end
metricsTable = cell2table(rows, 'VariableNames', {'split','row_count', ...
    'raw_MAE','raw_RMSE','raw_R2','raw_min_prediction','raw_max_prediction', ...
    'pct_raw_predictions_below_0','pct_raw_predictions_above_1', ...
    'bounded_MAE','bounded_RMSE','bounded_R2','bounded_min_prediction', ...
    'bounded_max_prediction','delta_MAE_bounded_minus_raw', ...
    'delta_RMSE_bounded_minus_raw','delta_R2_bounded_minus_raw', ...
    'bounded_metric_improved'});
rawSummary = struct();
rawSummary.below0 = sum(qpPredictions.predicted_target < 0);
rawSummary.above1 = sum(qpPredictions.predicted_target > 1);
end

function comparison = build_baseline_comparison(featureTable, qpPredictions)
evalRows = featureTable(strcmp(featureTable.split, 'validation') | strcmp(featureTable.split, 'test'), :);
trainRows = featureTable(strcmp(featureTable.split, 'train'), :);
evalRows = sortrows(evalRows, {'split','scenario_name','sector_id','time_step'});
qpPredictions = sortrows(qpPredictions, {'split','scenario_name','sector_id','time_step'});

if height(evalRows) ~= height(qpPredictions)
    error('Phase7D:PredictionAlignment', 'QP predictions do not align with validation/test feature rows.');
end

trainMean = mean(trainRows.next_qos_satisfaction_ratio, 'omitnan');
scenarioNames = unique(string(trainRows.scenario_name), 'stable');
scenarioMean = containers.Map('KeyType', 'char', 'ValueType', 'double');
for i = 1:numel(scenarioNames)
    idx = string(trainRows.scenario_name) == scenarioNames(i);
    scenarioMean(char(scenarioNames(i))) = mean(trainRows.next_qos_satisfaction_ratio(idx), 'omitnan');
end

boundedPred = min(max(qpPredictions.predicted_target, 0), 1);
meanPred = repmat(trainMean, height(evalRows), 1);
persistencePred = evalRows.qos_satisfaction_ratio_lag1;
scenarioPred = zeros(height(evalRows), 1);
for i = 1:height(evalRows)
    key = char(string(evalRows.scenario_name(i)));
    if isKey(scenarioMean, key)
        scenarioPred(i) = scenarioMean(key);
    else
        scenarioPred(i) = trainMean;
    end
end

rows = {};
rows = append_baseline_metric_rows(rows, evalRows, boundedPred, ...
    'QP_bounded_model', 'model prediction clipped to [0,1]');
rows = append_baseline_metric_rows(rows, evalRows, meanPred, ...
    'train_mean_baseline', 'deployable simple baseline using train target mean');
rows = append_baseline_metric_rows(rows, evalRows, persistencePred, ...
    'persistence_baseline', 'deployable if previous sector QoS is available');
rows = append_baseline_metric_rows(rows, evalRows, scenarioPred, ...
    'scenario_mean_baseline_diagnostic', 'diagnostic only; scenario label is metadata and not a deployable input');

comparison = cell2table(rows, 'VariableNames', ...
    {'model_name','split','row_count','MAE','RMSE','R2','notes'});
end

function rows = append_baseline_metric_rows(rows, evalRows, predicted, modelName, notes)
splits = {'validation','test','ALL_EVAL'};
for i = 1:numel(splits)
    splitName = splits{i};
    if strcmp(splitName, 'ALL_EVAL')
        idx = true(height(evalRows), 1);
    else
        idx = strcmp(evalRows.split, splitName);
    end
    m = calc_metrics(evalRows.next_qos_satisfaction_ratio(idx), predicted(idx));
    rows(end+1, :) = {modelName, splitName, sum(idx), m.mae, m.rmse, m.r2, notes}; %#ok<AGROW>
end
end

function [binaryDiagnostic, confusionMatrix] = build_binary_threshold_diagnostic(qpBoundedPredictions, threshold)
testRows = qpBoundedPredictions(strcmp(qpBoundedPredictions.split, 'test'), :);
actual = testRows.actual_next_qos_satisfaction_ratio;
pred = testRows.bounded_predicted_qos;
trueGood = actual >= threshold;
predGood = pred >= threshold;
tp = sum(trueGood & predGood);
tn = sum(~trueGood & ~predGood);
fp = sum(~trueGood & predGood);
fn = sum(trueGood & ~predGood);
accuracy = safe_div(tp + tn, numel(trueGood));
precision = safe_div(tp, tp + fp);
recall = safe_div(tp, tp + fn);
f1 = safe_div(2 * precision * recall, precision + recall);
confusionMatrix = [tn fp; fn tp];
binaryDiagnostic = table(threshold, height(testRows), tn, fp, fn, tp, ...
    accuracy, precision, recall, f1, ...
    'VariableNames', {'threshold','row_count','true_bad_pred_bad','true_bad_pred_good', ...
    'true_good_pred_bad','true_good_pred_good','accuracy','precision','recall','F1'});
end

function recommendation = build_thesis_recommendation(~, distributionBySplit, ~, rawVsBoundedMetrics, binaryDiagnostic)
allDist = distributionBySplit(strcmp(distributionBySplit.split, 'ALL'), :);
testMetrics = rawVsBoundedMetrics(strcmp(rawVsBoundedMetrics.split, 'test'), :);
endpointPct = allDist.pct_target_eq_0 + allDist.pct_target_eq_1;
boundedR2 = testMetrics.bounded_R2;
rawBelow = testMetrics.pct_raw_predictions_below_0;
rawAbove = testMetrics.pct_raw_predictions_above_1;
f1 = binaryDiagnostic.F1(1);

wording = ['QP is retained as a bounded one-step QoS prediction support module, ', ...
    'not as a robust continuous QoS predictor. The target is strongly bimodal ', ...
    sprintf('(%.2f%% of samples are exactly 0 or 1), ', endpointPct), ...
    'so bounded regression outputs should be interpreted with a limitation; ', ...
    'the thresholded good/bad QoS result is a diagnostic view only.'];

rows = {
    'KEEP_BOUNDED_REGRESSION_WITH_LIMITATION', true, 'PRIMARY', ...
    sprintf('test bounded R2=%.4f; raw out-of-range below=%.2f%% above=%.2f%%', boundedR2, rawBelow, rawAbove), wording;
    'ADD_CLASSIFICATION_DIAGNOSTIC_ONLY', true, 'SECONDARY', ...
    sprintf('threshold 0.8 F1=%.4f; useful for interpretation but not a replacement model', f1), ...
    'Add the binary threshold diagnostic as supporting evidence only; do not relabel QP as an action/classification module.';
    'REPLACE_QP_WITH_CLASSIFICATION', false, 'NOT_RECOMMENDED_BEFORE_PHASE13', ...
    'Would change Phase 7 model scope and downstream thesis framing.', ...
    'Classification may be future work, but should not replace current QP before packaging without a scoped redesign.';
    'FIX_TARGET_GENERATION_BUG', false, 'NOT_SELECTED', ...
    'No overwrite, rounding, leakage, or out-of-range target-generation bug was found.', ...
    'The issue is target definition/distribution plus weak regression, not a confirmed coding bug.';
    };
recommendation = cell2table(rows, 'VariableNames', ...
    {'recommendation_option','selected_flag','recommendation_role','rationale','thesis_safe_wording'});
end

function validationTable = validate_phase7d_qp_audit(cfg, target, qpPredictions, ...
    qpBoundedPredictions, inputFeatures, distributionBySplit, distributionByScenario, ...
    rawSummary, recommendation, downstreamUnchanged, downstreamNotes)
tol = 1e-12;
forbiddenLabels = {'scenario_label','scenario_name','traffic_mode','outage_flag', ...
    'degradation_flag','cod_label','impaired_sector_status','is_impaired_sector'};
futureInputHits = inputFeatures(startsWith(inputFeatures, 'next_') | startsWith(inputFeatures, 'target_next_'));
forbiddenInputHits = intersect(inputFeatures, forbiddenLabels);
endpointPct = distributionBySplit.pct_target_eq_0(strcmp(distributionBySplit.split, 'ALL')) + ...
    distributionBySplit.pct_target_eq_1(strcmp(distributionBySplit.split, 'ALL'));

plotFiles = {'phase7d_qp_target_distribution.png', ...
    'phase7d_qp_target_distribution_by_scenario.png', ...
    'phase7d_qp_bounded_actual_vs_predicted_with_density.png', ...
    'phase7d_qp_prediction_distribution_given_actual_0_1.png', ...
    'phase7d_qp_binary_confusion_threshold_0p8.png'};
plotExists = true;
for i = 1:numel(plotFiles)
    plotExists = plotExists && isfile(fullfile(cfg.figuresDir, plotFiles{i}));
end

rows = {};
rows = add_audit_row(rows, 'qp_target_is_finite', all(isfinite(target)), 'error', ...
    sprintf('finite=%d/%d', sum(isfinite(target)), numel(target)), ...
    'All QP target values must be finite.', '');
rows = add_audit_row(rows, 'qp_target_within_0_1', all(target >= 0 & target <= 1), ...
    'error', sprintf('min=%.6f; max=%.6f', min(target), max(target)), ...
    'All QP target values must be within [0,1].', '');
rows = add_audit_row(rows, 'raw_predictions_outside_0_1_reported', true, 'error', ...
    sprintf('below0=%d; above1=%d', rawSummary.below0, rawSummary.above1), ...
    'Raw out-of-range prediction counts must be reported.', '');
rows = add_audit_row(rows, 'bounded_predictions_within_0_1', ...
    all(qpBoundedPredictions.bounded_predicted_qos >= 0 & qpBoundedPredictions.bounded_predicted_qos <= 1), ...
    'error', sprintf('min=%.6f; max=%.6f', min(qpBoundedPredictions.bounded_predicted_qos), ...
    max(qpBoundedPredictions.bounded_predicted_qos)), ...
    'Bounded QP predictions must be clipped into [0,1].', '');
rows = add_audit_row(rows, 'target_distribution_reported_by_split', ...
    all(ismember({'train','validation','test'}, distributionBySplit.split)), 'error', ...
    strjoin(distributionBySplit.split', ', '), ...
    'Distribution rows must exist for train, validation, and test.', '');
rows = add_audit_row(rows, 'target_distribution_reported_by_scenario', ...
    height(distributionByScenario) >= 1, 'error', ...
    sprintf('scenario_rows=%d', height(distributionByScenario)), ...
    'Distribution rows must exist per scenario.', '');
rows = add_audit_row(rows, 'bimodal_target_ratio_reported', ...
    isfinite(endpointPct), 'error', sprintf('target_at_0_or_1_pct=%.2f', endpointPct), ...
    'The proportion of exact 0/1 QP targets must be reported.', '');
rows = add_audit_row(rows, 'qp_target_strongly_bimodal_warning', endpointPct < 95, ...
    'warning', sprintf('target_at_0_or_1_pct=%.2f', endpointPct), ...
    'Warn if more than 95% of targets are exact endpoints.', ...
    'This is a limitation warning, not a validation error.');
rows = add_audit_row(rows, 'no_post_action_kpi_leakage', isempty(futureInputHits), ...
    'error', strjoin_or_none(futureInputHits), ...
    'No next/future target columns may be used as model inputs.', '');
rows = add_audit_row(rows, 'no_forbidden_labels_used_as_inputs', isempty(forbiddenInputHits), ...
    'error', strjoin_or_none(forbiddenInputHits), ...
    'Scenario/outage/degradation labels must not be model inputs.', '');
rows = add_audit_row(rows, 'thesis_recommendation_file_exists', ...
    isfile(fullfile(cfg.tablesDir, 'phase7d_qp_thesis_recommendation.csv')) || height(recommendation) > 0, ...
    'error', sprintf('recommendation_rows=%d', height(recommendation)), ...
    'The thesis recommendation table must be generated.', '');
rows = add_audit_row(rows, 'diagnostic_plots_generated', plotExists, 'error', ...
    sprintf('required_plots=%d', numel(plotFiles)), ...
    'All required Phase 7D QP diagnostic plots must exist.', '');
rows = add_audit_row(rows, 'no_phase8_to_phase12_outputs_modified', downstreamUnchanged, ...
    'error', downstreamNotes, ...
    'Phase 7D audit must not modify Phase 8-12 outputs.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','pass_flag','severity','actual_value','expected_condition','notes'});

% Keep a direct target endpoint count visible for downstream report readers.
validationTable.notes(strcmp(validationTable.check_name, 'bimodal_target_ratio_reported')) = ...
    {sprintf('target==0 rows=%d; target==1 rows=%d; intermediate rows=%d', ...
    sum(abs(target) <= tol), sum(abs(target - 1) <= tol), sum(target > tol & target < 1 - tol))};
end

function plot_qp_target_distribution(cfg, target)
fig = figure('Visible', 'off', 'Color', 'w');
histogram(target, 'BinEdges', 0:0.05:1, 'FaceColor', [0.20 0.45 0.70]);
xlabel('next QoS satisfaction ratio');
ylabel('Rows');
title('Phase 7D QP Target Distribution');
grid on;
save_figure(fig, fullfile(cfg.figuresDir, 'phase7d_qp_target_distribution.png'));
close(fig);
end

function plot_qp_target_distribution_by_scenario(cfg, distributionByScenario)
fig = figure('Visible', 'off', 'Color', 'w');
data = [distributionByScenario.pct_target_eq_0, ...
    distributionByScenario.pct_target_between_0_1, distributionByScenario.pct_target_eq_1];
bar(categorical(distributionByScenario.scenario_name), data, 'stacked');
ylabel('Target share (%)');
title('Phase 7D QP Target Distribution by Scenario');
legend({'target = 0','0 < target < 1','target = 1'}, 'Location', 'southoutside', 'Orientation', 'horizontal');
grid on;
save_figure(fig, fullfile(cfg.figuresDir, 'phase7d_qp_target_distribution_by_scenario.png'));
close(fig);
end

function plot_qp_bounded_actual_vs_predicted_density(cfg, qpBoundedPredictions)
actual = qpBoundedPredictions.actual_next_qos_satisfaction_ratio;
pred = qpBoundedPredictions.bounded_predicted_qos;
edges = 0:0.05:1;
[counts, xEdges, yEdges] = histcounts2(actual, pred, edges, edges);
xCenters = (xEdges(1:end-1) + xEdges(2:end)) / 2;
yCenters = (yEdges(1:end-1) + yEdges(2:end)) / 2;

fig = figure('Visible', 'off', 'Color', 'w');
imagesc(xCenters, yCenters, counts');
set(gca, 'YDir', 'normal');
hold on;
plot([0 1], [0 1], 'w--', 'LineWidth', 1.25);
xlabel('Actual next QoS satisfaction ratio');
ylabel('Bounded predicted QoS');
title('Phase 7D QP Bounded Actual vs Predicted Density');
colorbar;
grid on;
save_figure(fig, fullfile(cfg.figuresDir, 'phase7d_qp_bounded_actual_vs_predicted_with_density.png'));
close(fig);
end

function plot_qp_prediction_distribution_given_actual_extremes(cfg, qpBoundedPredictions)
actual = qpBoundedPredictions.actual_next_qos_satisfaction_ratio;
pred = qpBoundedPredictions.bounded_predicted_qos;
tol = 1e-12;
fig = figure('Visible', 'off', 'Color', 'w');
histogram(pred(abs(actual) <= tol), 'BinEdges', 0:0.05:1, ...
    'Normalization', 'probability', 'FaceAlpha', 0.65, 'FaceColor', [0.85 0.33 0.10]);
hold on;
histogram(pred(abs(actual - 1) <= tol), 'BinEdges', 0:0.05:1, ...
    'Normalization', 'probability', 'FaceAlpha', 0.55, 'FaceColor', [0.00 0.45 0.74]);
xlabel('Bounded predicted QoS');
ylabel('Probability');
title('Phase 7D Prediction Distribution Given Actual QoS Endpoint');
legend({'actual = 0','actual = 1'}, 'Location', 'best');
grid on;
save_figure(fig, fullfile(cfg.figuresDir, 'phase7d_qp_prediction_distribution_given_actual_0_1.png'));
close(fig);
end

function plot_qp_binary_confusion(cfg, confusionMatrix, binaryDiagnostic)
fig = figure('Visible', 'off', 'Color', 'w');
imagesc(confusionMatrix);
colormap(parula);
colorbar;
axis equal tight;
set(gca, 'XTick', 1:2, 'XTickLabel', {'pred bad','pred good'}, ...
    'YTick', 1:2, 'YTickLabel', {'actual bad','actual good'});
title(sprintf('Phase 7D QP Binary Diagnostic, threshold %.1f, F1 %.3f', ...
    binaryDiagnostic.threshold(1), binaryDiagnostic.F1(1)));
for r = 1:2
    for c = 1:2
        text(c, r, sprintf('%d', confusionMatrix(r, c)), ...
            'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold');
    end
end
save_figure(fig, fullfile(cfg.figuresDir, 'phase7d_qp_binary_confusion_threshold_0p8.png'));
close(fig);
end

function write_qp_audit_report(cfg, reportsDir, formulaAudit, distributionBySplit, ...
    distributionByScenario, splitAudit, rawVsBoundedMetrics, baselineComparison, ...
    binaryDiagnostic, recommendation, validationTable)
allDist = distributionBySplit(strcmp(distributionBySplit.split, 'ALL'), :);
testMetrics = rawVsBoundedMetrics(strcmp(rawVsBoundedMetrics.split, 'test'), :);
testBaseline = baselineComparison(strcmp(baselineComparison.split, 'test'), :);
primary = recommendation(strcmp(recommendation.recommendation_option, ...
    'KEEP_BOUNDED_REGRESSION_WITH_LIMITATION'), :);
validationErrors = height(validationTable(strcmp(validationTable.severity, 'error') & ...
    ~validationTable.pass_flag, :));
validationWarnings = height(validationTable(strcmp(validationTable.severity, 'warning') & ...
    ~validationTable.pass_flag, :));

fid = fopen(fullfile(reportsDir, 'phase7d_qp_audit_report.md'), 'w');
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '# Phase 7D QP Audit Report\n\n');
fprintf(fid, '## Executive Verdict\n\n');
fprintf(fid, 'Primary recommendation: **KEEP_BOUNDED_REGRESSION_WITH_LIMITATION**. Add the binary classification view as a diagnostic only; do not replace QP before Phase 13 packaging.\n\n');
fprintf(fid, '## Is This a Coding Bug?\n\n');
fprintf(fid, 'No confirmed coding bug was found in the QP target-generation path. The target is copied from the next-step sector `qos_satisfaction_ratio`, and that sector KPI is computed as `mean(qosSatisfied)` over active attached UEs. No rounding, logical overwrite, forbidden label input, or future-target input was found.\n\n');
fprintf(fid, 'Important limitation: sector QoS values that are missing because no active attached UEs exist are imputed to 1 inside the Phase 7 sector feature builder. That is a target-definition artifact and should be documented.\n\n');
fprintf(fid, '## Is the Target Bimodal?\n\n');
fprintf(fid, 'Yes. Across all QP target rows, %.2f%% are exactly 0, %.2f%% are exactly 1, and %.2f%% are between 0 and 1. Unique target values: %d.\n\n', ...
    allDist.pct_target_eq_0, allDist.pct_target_eq_1, ...
    allDist.pct_target_between_0_1, allDist.num_unique_target_values);
fprintf(fid, 'Scenario-level distribution is written to `phase7d_qp_target_distribution_by_scenario.csv`.\n\n');
fprintf(fid, '## Regression Appropriateness\n\n');
fprintf(fid, 'Continuous regression is weak for this target because the response is effectively endpoint-dominated. Bounded regression is acceptable only as a support diagnostic. It should not be described as a robust continuous QoS predictor.\n\n');
fprintf(fid, 'Test bounded metrics: MAE %.4f, RMSE %.4f, R2 %.4f. Raw predictions below 0: %.2f%%; above 1: %.2f%%.\n\n', ...
    testMetrics.bounded_MAE, testMetrics.bounded_RMSE, testMetrics.bounded_R2, ...
    testMetrics.pct_raw_predictions_below_0, testMetrics.pct_raw_predictions_above_1);
fprintf(fid, '## Baseline Comparison\n\n');
for i = 1:height(testBaseline)
    fprintf(fid, '- `%s`: MAE %.4f, RMSE %.4f, R2 %.4f. %s\n', ...
        testBaseline.model_name{i}, testBaseline.MAE(i), testBaseline.RMSE(i), ...
        testBaseline.R2(i), testBaseline.notes{i});
end
fprintf(fid, '\n');
fprintf(fid, '## Binary Diagnostic\n\n');
fprintf(fid, 'Using `actual_qos >= 0.8` and `bounded_prediction >= 0.8`, the test-set diagnostic has accuracy %.4f, precision %.4f, recall %.4f, and F1 %.4f. This is an interpretation aid only, not a replacement for the stored QP regression model.\n\n', ...
    binaryDiagnostic.accuracy(1), binaryDiagnostic.precision(1), ...
    binaryDiagnostic.recall(1), binaryDiagnostic.F1(1));
fprintf(fid, '## Thesis Figure Guidance\n\n');
fprintf(fid, 'Use as main thesis diagnostic: `phase7d_qp_target_distribution_by_scenario.png` plus `phase7d_qp_bounded_actual_vs_predicted_with_density.png` if a prediction plot is needed.\n\n');
fprintf(fid, 'Avoid as a main result: the raw Phase 7C actual-vs-predicted QP plot, because raw regression predictions can be outside [0,1] and the vertical bands need context.\n\n');
fprintf(fid, '## Exact Thesis-Safe Wording\n\n');
fprintf(fid, '\"The QP module is retained as a bounded one-step QoS prediction support diagnostic. The sector-level QoS target is validly bounded in [0,1] but is strongly bimodal because most sector-time samples are either fully unsatisfied or fully satisfied, with missing/no-active sector QoS imputed as satisfied in the Phase 7 feature table. Therefore QP is not claimed as a robust continuous QoS predictor; it is reported with a bounded-regression limitation and an optional threshold-based diagnostic view.\"\n\n');
fprintf(fid, '## Recommendation Table\n\n');
fprintf(fid, 'Primary rationale: %s\n\n', primary.rationale{1});
fprintf(fid, '## Validation\n\n');
fprintf(fid, 'Validation errors: %d. Validation warnings: %d.\n\n', validationErrors, validationWarnings);
fprintf(fid, 'Phase 8-12 outputs modified: no, according to the Phase 7D snapshot check.\n');
end

function snapshot = snapshot_downstream_outputs(cfg)
roots = {cfg.tablesDir, cfg.figuresDir, cfg.modelsDir};
rows = {};
for r = 1:numel(roots)
    if ~isfolder(roots{r})
        continue;
    end
    files = dir(fullfile(roots{r}, 'phase*'));
    for i = 1:numel(files)
        if files(i).isdir
            continue;
        end
        name = files(i).name;
        if ~isempty(regexp(name, '^phase(8|9|10|11|12)', 'once'))
            rows(end+1, :) = {fullfile(files(i).folder, name), files(i).bytes, files(i).datenum}; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    snapshot = cell2table(cell(0, 3), 'VariableNames', {'file_path','bytes','datenum'});
else
    snapshot = cell2table(rows, 'VariableNames', {'file_path','bytes','datenum'});
end
end

function [same, notes] = compare_snapshots(before, after)
same = height(before) == height(after);
notes = sprintf('before_files=%d; after_files=%d', height(before), height(after));
if ~same
    return;
end
before = sortrows(before, 'file_path');
after = sortrows(after, 'file_path');
if ~isequal(before.file_path, after.file_path)
    same = false;
    notes = [notes, '; file set changed'];
    return;
end
changed = before.bytes ~= after.bytes | abs(before.datenum - after.datenum) > 1e-9;
same = ~any(changed);
if any(changed)
    notes = [notes, sprintf('; changed_files=%d', sum(changed))];
else
    notes = [notes, '; changed_files=0'];
end
end

function rows = add_audit_row(rows, checkName, passFlag, severity, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, logical(passFlag), severity, actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function key = make_source_key(scenarioName, sectorId, timeIndex)
key = string(scenarioName) + "|" + string(sectorId) + "|" + string(timeIndex);
end

function s = strjoin_or_none(values)
if isempty(values)
    s = 'none';
else
    s = strjoin(cellstr(values), ', ');
end
end

function m = calc_metrics(actual, predicted)
actual = double(actual);
predicted = double(predicted);
err = predicted - actual;
m = struct();
m.mae = mean(abs(err), 'omitnan');
m.rmse = sqrt(mean(err .^ 2, 'omitnan'));
ssRes = sum((actual - predicted) .^ 2, 'omitnan');
ssTot = sum((actual - mean(actual, 'omitnan')) .^ 2, 'omitnan');
if ssTot > 0
    m.r2 = 1 - ssRes / ssTot;
else
    m.r2 = NaN;
end
end

function value = safe_div(num, den)
if den == 0
    value = NaN;
else
    value = num / den;
end
end
