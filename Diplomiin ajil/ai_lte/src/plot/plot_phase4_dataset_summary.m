function plot_phase4_dataset_summary(cfg, networkStateDataset)
%PLOT_PHASE4_DATASET_SUMMARY Plot aggregate Phase 4 dataset KPIs by scenario.

scenarioNames = unique(networkStateDataset.scenario_name, 'stable');
numScenarios = numel(scenarioNames);

meanLoad = zeros(numScenarios, 1);
meanQoS = zeros(numScenarios, 1);
meanOverloaded = zeros(numScenarios, 1);
meanHoRisk = zeros(numScenarios, 1);

for i = 1:numScenarios
    idx = strcmp(networkStateDataset.scenario_name, scenarioNames{i});
    meanLoad(i) = mean(networkStateDataset.mean_sector_load(idx), 'omitnan');
    meanQoS(i) = mean(networkStateDataset.qos_satisfaction_ratio(idx), 'omitnan');
    meanOverloaded(i) = mean(networkStateDataset.overloaded_sector_count(idx), 'omitnan');
    meanHoRisk(i) = mean(networkStateDataset.handover_risk_score(idx), 'omitnan');
end

labels = strrep(scenarioNames, '_', ' ');
cats = categorical(labels);
cats = reordercats(cats, labels);

fig = figure('Color', 'w', 'Name', 'Phase 4 dataset summary');
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
bar(cats, meanLoad);
grid on;
ylabel('Mean sector load');
title('Mean load');
yline(cfg.sectorOverloadThreshold, 'r--', 'Overload threshold');
xtickangle(35);

nexttile;
bar(cats, 100 * meanQoS);
grid on;
ylabel('QoS active UEs [%]');
title('Mean QoS');
ylim([0 100]);
xtickangle(35);

nexttile;
bar(cats, meanOverloaded);
grid on;
ylabel('Overloaded sectors');
title('Mean overload count');
xtickangle(35);

nexttile;
bar(cats, meanHoRisk);
grid on;
ylabel('HO risk score');
title('Mean handover risk');
xtickangle(35);

save_figure(fig, fullfile(cfg.figuresDir, 'phase4_dataset_summary.png'));
end
