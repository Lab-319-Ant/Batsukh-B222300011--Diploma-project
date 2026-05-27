function plot_phase5_cluster_profiles(cfg, clusterSummary)
%PLOT_PHASE5_CLUSTER_PROFILES Plot major KPI means by cluster.

clusterLabels = categorical("C" + string(clusterSummary.cluster_id));
clusterLabels = reordercats(clusterLabels, cellstr("C" + string(clusterSummary.cluster_id)));

fig = figure('Color', 'w', 'Name', 'Phase 5 cluster profiles');
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
bar(clusterLabels, clusterSummary.mean_sector_load);
yline(cfg.sectorOverloadThreshold, 'r--', 'Load threshold');
grid on;
ylabel('Mean load');
title('Sector load');

nexttile;
bar(clusterLabels, clusterSummary.mean_qos_satisfaction_ratio);
grid on;
ylim([0 1]);
ylabel('QoS ratio');
title('QoS satisfaction');

nexttile;
bar(clusterLabels, clusterSummary.mean_handover_risk_score);
grid on;
ylim([0 max(0.5, max(clusterSummary.mean_handover_risk_score) * 1.15)]);
ylabel('HO risk');
title('Handover-risk indicator');

nexttile;
bar(clusterLabels, clusterSummary.mean_RSRP_dBm);
grid on;
ylabel('RSRP [dBm]');
title('RF strength');

save_figure(fig, fullfile(cfg.figuresDir, 'phase5_cluster_profiles.png'));
end
