function plot_sector_load(cfg, topology, sectorLoadTable)
%PLOT_SECTOR_LOAD Plot number of attached UEs per sector.

fig = figure('Color', 'w', 'Name', 'Sector load');
bar(sectorLoadTable.sectorId, sectorLoadTable.attachedUE);
grid on;
xlabel('Sector ID');
ylabel('Attached UE count');
title(sprintf('%d-sector load from best-RSRP association', height(topology.sectors)));
xticks(sectorLoadTable.sectorId);
xticklabels(compose('S%d\n%d deg', sectorLoadTable.sectorId, sectorLoadTable.azimuth_deg));
xtickangle(45);

for i = 1:height(sectorLoadTable)
    text(sectorLoadTable.sectorId(i), sectorLoadTable.attachedUE(i) + 2, ...
        sprintf('%d', sectorLoadTable.attachedUE(i)), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

save_figure(fig, fullfile(cfg.figuresDir, 'phase1b_sector_load.png'));
end
