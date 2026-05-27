function validationTable = validate_phase5_clustering(cfg, assignments, selectedFeatureTable, ...
    inputFeatures, forbiddenFeatures, kEvaluationTable, selectedK, clusterSummary, scenarioCrosstab)
%VALIDATE_PHASE5_CLUSTERING Validate leakage and clustering sanity.

rows = {};

forbiddenInputs = intersect(inputFeatures, forbiddenFeatures);
rows = add_check(rows, 'input_features_no_forbidden_leakage', 'error', isempty(forbiddenInputs), ...
    strjoin(forbiddenInputs, ', '), 'No forbidden leakage feature may be used as clustering input.', '');

rows = validate_numeric_inputs(rows, selectedFeatureTable);

hasClusterForEveryRow = ismember('cluster_id', assignments.Properties.VariableNames) && ...
    height(assignments) == numel(assignments.cluster_id) && all(~ismissing(assignments.cluster_id));
rows = add_check(rows, 'cluster_assignment_for_every_row', 'error', hasClusterForEveryRow, ...
    sprintf('%d assignments for %d rows', numel(assignments.cluster_id), height(assignments)), ...
    'Every sector row must have one cluster assignment.', '');

rows = add_check(rows, 'selected_k_between_2_and_8', 'error', selectedK >= 2 && selectedK <= 8, ...
    sprintf('k=%d', selectedK), 'Selected cluster count must be between 2 and 8.', '');

clusterSizes = accumarray(assignments.cluster_id, 1, [selectedK, 1], @sum, 0);
emptyClusters = sum(clusterSizes == 0);
minClusterFraction = min(clusterSizes) / max(height(assignments), 1);
rows = add_check(rows, 'no_empty_clusters', 'error', emptyClusters == 0, ...
    sprintf('%d empty clusters', emptyClusters), 'Final clustering must not contain empty clusters.', '');
rows = add_check(rows, 'minimum_cluster_size_at_least_2_percent', 'warning', minClusterFraction >= 0.02, ...
    sprintf('%.4f', minClusterFraction), 'Minimum cluster size should be at least 2% of rows.', '');

labelInputs = intersect(inputFeatures, {'scenario_id','scenario_name','traffic_mode'});
rows = add_check(rows, 'scenario_labels_interpretation_only', 'error', isempty(labelInputs), ...
    strjoin(labelInputs, ', '), 'Scenario labels and traffic mode must not be clustering inputs.', '');

rows = add_check(rows, 'cluster_summary_one_row_per_cluster', 'error', ...
    height(clusterSummary) == selectedK, sprintf('%d summary rows for k=%d', height(clusterSummary), selectedK), ...
    'Cluster summary must contain one row per selected cluster.', '');

handoverClusters = clusterSummary.cluster_id(strcmp(clusterSummary.suggested_state_name, 'handover_risk'));
if isempty(handoverClusters)
    rows = add_check(rows, 'handover_stress_concentrates_in_handover_cluster', 'warning', false, ...
        'no handover_risk cluster', 'If a handover-risk cluster exists, handover_stress should exceed normal in that cluster.', ...
        'No cluster met the rule-based handover-risk profile.');
else
    normalFraction = scenario_fraction_in_clusters(assignments, 'normal', handoverClusters);
    hoFraction = scenario_fraction_in_clusters(assignments, 'handover_stress', handoverClusters);
    rows = add_check(rows, 'handover_stress_concentrates_in_handover_cluster', 'warning', hoFraction > normalFraction, ...
        sprintf('handover=%.3f normal=%.3f', hoFraction, normalFraction), ...
        'handover_stress fraction in handover-risk cluster should exceed normal.', '');
end

highLoadClusters = clusterSummary.cluster_id(clusterSummary.mean_sector_load > 0.50);
highLoadFraction = scenario_fraction_in_clusters(assignments, {'overload','mixed_conflict'}, highLoadClusters);
rows = add_check(rows, 'overload_scenarios_concentrate_in_high_load_clusters', 'warning', highLoadFraction > 0.50, ...
    sprintf('%.3f', highLoadFraction), 'Overload and mixed_conflict rows should mostly fall in high-load clusters.', '');

lowLoadClusters = clusterSummary.cluster_id(clusterSummary.mean_sector_load < 0.10 & ...
    clusterSummary.mean_qos_satisfaction_ratio > 0.70);
lowLoadFraction = scenario_fraction_in_clusters(assignments, {'low_load','low_load_energy_saving_candidate'}, lowLoadClusters);
rows = add_check(rows, 'low_load_scenarios_concentrate_in_low_load_clusters', 'warning', lowLoadFraction > 0.50, ...
    sprintf('%.3f', lowLoadFraction), 'Low-load rows should mostly fall in low-load clusters.', '');

selectedEvalRows = kEvaluationTable(kEvaluationTable.k == selectedK, :);
rows = add_check(rows, 'selected_k_was_evaluated', 'error', height(selectedEvalRows) == 1, ...
    sprintf('%d matching rows', height(selectedEvalRows)), 'Selected k must exist in k-evaluation table.', '');

rows = add_check(rows, 'scenario_crosstab_has_rows', 'error', height(scenarioCrosstab) > 0, ...
    sprintf('%d scenario rows', height(scenarioCrosstab)), 'Scenario-by-cluster crosstab must not be empty.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase5_clustering_validation.csv'));
end

function rows = validate_numeric_inputs(rows, selectedFeatureTable)
vars = selectedFeatureTable.Properties.VariableNames;
nonNumeric = {};
missingCount = 0;
infCount = 0;
for i = 1:numel(vars)
    values = selectedFeatureTable.(vars{i});
    if ~(isnumeric(values) || islogical(values))
        nonNumeric{end+1} = vars{i}; %#ok<AGROW>
        continue;
    end
    values = double(values);
    missingCount = missingCount + sum(ismissing(values));
    infCount = infCount + sum(isinf(values));
end
rows = add_check(rows, 'selected_inputs_numeric_only', 'error', isempty(nonNumeric), ...
    strjoin(nonNumeric, ', '), 'All selected clustering inputs must be numeric.', '');
rows = add_check(rows, 'selected_inputs_no_missing_values', 'error', missingCount == 0, ...
    sprintf('%d missing values', missingCount), 'Selected clustering inputs must not contain missing values.', '');
rows = add_check(rows, 'selected_inputs_no_infinite_values', 'error', infCount == 0, ...
    sprintf('%d infinite values', infCount), 'Selected clustering inputs must not contain infinite values.', '');
end

function fraction = scenario_fraction_in_clusters(assignments, scenarioNames, clusterIds)
if isempty(clusterIds)
    fraction = 0;
    return;
end
scenarioMask = false(height(assignments), 1);
scenarioValues = string(assignments.scenario_name);
if ischar(scenarioNames) || isstring(scenarioNames)
    scenarioNames = cellstr(scenarioNames);
end
for i = 1:numel(scenarioNames)
    scenarioMask = scenarioMask | scenarioValues == string(scenarioNames{i});
end
if sum(scenarioMask) == 0
    fraction = 0;
    return;
end
fraction = sum(scenarioMask & ismember(assignments.cluster_id, clusterIds)) / sum(scenarioMask);
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end
