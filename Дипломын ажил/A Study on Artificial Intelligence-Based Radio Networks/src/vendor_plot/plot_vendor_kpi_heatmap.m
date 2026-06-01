function plot_vendor_kpi_heatmap(vcfg, cleanKpi, kpiName, fileName)
%PLOT_VENDOR_KPI_HEATMAP Heatmap by simulated sector and timestamp.

T = cleanKpi(cleanKpi.selected_for_21cell_topology, :);
if isempty(T) || ~ismember(kpiName, T.Properties.VariableNames)
    return;
end

times = unique(T.timestamp);
sectors = unique(T.sim_sector_id);
Z = nan(numel(sectors), numel(times));
for i = 1:numel(sectors)
    for j = 1:numel(times)
        mask = T.sim_sector_id == sectors(i) & T.timestamp == times(j);
        if any(mask)
            Z(i, j) = mean(T.(kpiName)(mask), 'omitnan');
        end
    end
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1150 560]);
imagesc(Z);
colorbar;
yticks(1:numel(sectors));
yticklabels(compose('S%d', sectors));
xticks(round(linspace(1, numel(times), min(8, numel(times)))));
xticklabels(string(times(xticks), 'MM-dd HH:mm'));
xtickangle(30);
xlabel('time');
ylabel('simulated sector');
title(sprintf('Vendor KPI heatmap: %s', strrep(kpiName, '_', ' ')), 'Interpreter', 'none');
save_figure(fig, fullfile(vcfg.figuresDir, fileName));
end
