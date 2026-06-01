function kEvaluationTable = evaluate_clustering_k_range(cfg, Xz, kValues)
%EVALUATE_CLUSTERING_K_RANGE Run k-means diagnostics for candidate k values.

rng(cfg.seed + 5000);
numRows = size(Xz, 1);
rows = {};

for k = kValues(:)'
    [clusterId, ~, sumd] = run_kmeans_once(Xz, k, cfg.seed + 5000 + k);
    counts = accumarray(clusterId, 1, [k, 1], @sum, 0);
    emptyClusterCount = sum(counts == 0);
    totalWCSS = sum(sumd);
    meanSilhouette = NaN;
    silhouetteAvailable = exist('silhouette', 'file') == 2;
    if silhouetteAvailable && emptyClusterCount == 0 && numel(unique(clusterId)) > 1
        try
            silValues = silhouette(Xz, clusterId);
            meanSilhouette = mean(silValues, 'omitnan');
        catch
            meanSilhouette = NaN;
            silhouetteAvailable = false;
        end
    end

    rows(end+1, :) = {k, totalWCSS, meanSilhouette, min(counts), max(counts), ...
        emptyClusterCount, min(counts) / max(numRows, 1), silhouetteAvailable}; %#ok<AGROW>
end

kEvaluationTable = cell2table(rows, 'VariableNames', ...
    {'k','total_within_cluster_sum_squares','mean_silhouette', ...
    'cluster_size_min','cluster_size_max','empty_cluster_count', ...
    'min_cluster_fraction','silhouette_available'});
end

function [idx, centroids, sumd] = run_kmeans_once(X, k, seed)
rng(seed);
if exist('kmeans', 'file') == 2
    try
        [idx, centroids, sumd] = kmeans(X, k, 'Replicates', 20, ...
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

for iter = 1:200
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
    if any(idx == c)
        diff = X(idx == c, :) - centroids(c, :);
        sumd(c) = sum(sum(diff .^ 2, 2));
    end
end
end
