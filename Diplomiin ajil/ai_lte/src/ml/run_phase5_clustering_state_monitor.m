function phase5 = run_phase5_clustering_state_monitor(cfg)
%RUN_PHASE5_CLUSTERING_STATE_MONITOR Unsupervised sector-state monitoring.
%
% Phase 5 uses leakage-controlled sector KPI features only. Scenario labels
% are used after clustering for interpretation, not as clustering inputs.

inputFile = fullfile(cfg.tablesDir, 'phase4b_sector_features_clustering.csv');
if ~isfile(inputFile)
    error('Phase5:MissingInputTable', 'Missing Phase 4B clustering table: %s', inputFile);
end

featureTable = readtable(inputFile);
[requestedFeatures, forbiddenFeatures] = select_clustering_features();
leakageInputs = intersect(requestedFeatures, forbiddenFeatures);
if ~isempty(leakageInputs)
    error('Phase5:ForbiddenInputFeature', ...
        'Forbidden clustering inputs requested: %s', strjoin(leakageInputs, ', '));
end

[Xz, selectedFeatureTable, standardizationInfo] = ...
    standardize_clustering_features(featureTable, requestedFeatures);
writetable(selectedFeatureTable, fullfile(cfg.tablesDir, 'phase5_clustering_input_features.csv'));

kValues = 2:8;
kEvaluationTable = evaluate_clustering_k_range(cfg, Xz, kValues);
writetable(kEvaluationTable, fullfile(cfg.tablesDir, 'phase5_clustering_k_evaluation.csv'));

selectedK = choose_cluster_count(kEvaluationTable, height(featureTable));
[clusterId, ~, ~] = run_final_kmeans(Xz, selectedK, cfg.seed + 6000);

assignments = featureTable;
assignments.cluster_id = clusterId;
writetable(assignments, fullfile(cfg.tablesDir, 'phase5_sector_cluster_assignments.csv'));

[clusterSummary, scenarioCrosstab, triggerSupport] = summarize_cluster_states(assignments);
writetable(clusterSummary, fullfile(cfg.tablesDir, 'phase5_cluster_summary.csv'));
writetable(scenarioCrosstab, fullfile(cfg.tablesDir, 'phase5_cluster_scenario_crosstab.csv'));
writetable(triggerSupport, fullfile(cfg.tablesDir, 'phase5_cluster_trigger_support.csv'));

validationTable = validate_phase5_clustering(cfg, assignments, selectedFeatureTable, ...
    requestedFeatures, forbiddenFeatures, kEvaluationTable, selectedK, clusterSummary, scenarioCrosstab);

try
    plot_phase5_cluster_pca(cfg, Xz, assignments, standardizationInfo.usedFeatureNames);
catch ME
    warning('Phase5:PlotPCAFailed', 'Could not generate Phase 5 PCA plot: %s', ME.message);
end
try
    plot_phase5_cluster_scenario_heatmap(cfg, scenarioCrosstab);
catch ME
    warning('Phase5:PlotHeatmapFailed', 'Could not generate Phase 5 scenario heatmap: %s', ME.message);
end
try
    plot_phase5_cluster_profiles(cfg, clusterSummary);
catch ME
    warning('Phase5:PlotProfilesFailed', 'Could not generate Phase 5 profile plot: %s', ME.message);
end

selectedEval = kEvaluationTable(kEvaluationTable.k == selectedK, :);
phase5 = struct();
phase5.inputRows = height(featureTable);
phase5.selectedFeatures = standardizationInfo.usedFeatureNames;
phase5.removedZeroVarianceFeatures = standardizationInfo.removedZeroVarianceFeatures;
phase5.kEvaluationTable = kEvaluationTable;
phase5.selectedK = selectedK;
phase5.meanSilhouette = selectedEval.mean_silhouette;
phase5.clusterSizes = accumarray(clusterId, 1, [selectedK, 1], @sum, 0);
phase5.assignments = assignments;
phase5.clusterSummary = clusterSummary;
phase5.scenarioCrosstab = scenarioCrosstab;
phase5.triggerSupport = triggerSupport;
phase5.validationTable = validationTable;
end

function selectedK = choose_cluster_count(kEvaluationTable, numRows)
minClusterRows = ceil(0.02 * numRows);
valid = kEvaluationTable.empty_cluster_count == 0 & ...
    kEvaluationTable.cluster_size_min >= minClusterRows;

% A pure silhouette choice can collapse this monitoring task to k=2, which
% separates only broad load states. Phase 5 needs multiple unsupervised
% state groups for monitoring, so k=4 is used when it has no empty clusters;
% small clusters are reported as validation warnings rather than hidden.
if any(kEvaluationTable.k == 4 & kEvaluationTable.empty_cluster_count == 0)
    selectedK = 4;
elseif any(valid & ~isnan(kEvaluationTable.mean_silhouette))
    candidates = kEvaluationTable(valid & ~isnan(kEvaluationTable.mean_silhouette), :);
    [~, bestIdx] = max(candidates.mean_silhouette);
    selectedK = candidates.k(bestIdx);
elseif any(valid)
    candidates = kEvaluationTable(valid, :);
    [~, bestIdx] = min(candidates.total_within_cluster_sum_squares);
    selectedK = candidates.k(bestIdx);
else
    selectedK = 4;
end
end

function [idx, centroids, sumd] = run_final_kmeans(X, k, seed)
rng(seed);
if exist('kmeans', 'file') == 2
    try
        [idx, centroids, sumd] = kmeans(X, k, 'Replicates', 50, ...
            'MaxIter', 500, 'Display', 'off', 'Start', 'plus');
        return;
    catch
        [idx, centroids, sumd] = local_kmeans(X, k, seed);
        return;
    end
end
[idx, centroids, sumd] = local_kmeans(X, k, seed);
end

function [idx, centroids, sumd] = local_kmeans(X, k, seed)
rng(seed);
[numRows, ~] = size(X);
startIdx = randperm(numRows, k);
centroids = X(startIdx, :);
idx = ones(numRows, 1);
for iter = 1:250
    distances = zeros(numRows, k);
    for c = 1:k
        diff = X - centroids(c, :);
        distances(:, c) = sum(diff .^ 2, 2);
    end
    [~, newIdx] = min(distances, [], 2);
    if iter > 1 && all(newIdx == idx)
        break;
    end
    idx = newIdx;
    for c = 1:k
        if any(idx == c)
            centroids(c, :) = mean(X(idx == c, :), 1);
        else
            centroids(c, :) = X(randi(numRows), :);
        end
    end
end
sumd = zeros(k, 1);
for c = 1:k
    diff = X(idx == c, :) - centroids(c, :);
    sumd(c) = sum(sum(diff .^ 2, 2));
end
end
