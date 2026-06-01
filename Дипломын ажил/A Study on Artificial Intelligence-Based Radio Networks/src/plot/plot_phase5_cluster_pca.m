function plot_phase5_cluster_pca(cfg, Xz, assignments, featureNames)
%PLOT_PHASE5_CLUSTER_PCA Plot first two principal components by cluster.

if size(Xz, 2) < 2
    warning('Phase5:PCAFeatureCount', 'Need at least two standardized features for PCA plot.');
    return;
end

Xcentered = Xz - mean(Xz, 1);
[~, ~, V] = svd(Xcentered, 'econ');
score = Xcentered * V;
latent = var(score, 0, 1);
explained = 100 * latent / sum(latent);

fig = figure('Color', 'w', 'Name', 'Phase 5 cluster PCA');
hold on;
clusterIds = unique(assignments.cluster_id);
colors = lines(numel(clusterIds));
for i = 1:numel(clusterIds)
    idx = assignments.cluster_id == clusterIds(i);
    scatter(score(idx, 1), score(idx, 2), 18, colors(i, :), 'filled', ...
        'DisplayName', sprintf('Cluster %d', clusterIds(i)));
end
hold off;
grid on;
xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
title({'Phase 5 sector-state clusters', ...
    sprintf('%d input KPI features, metadata excluded', numel(featureNames))});
legend('Location', 'bestoutside');
save_figure(fig, fullfile(cfg.figuresDir, 'phase5_cluster_pca.png'));
end
