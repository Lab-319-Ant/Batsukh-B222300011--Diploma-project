function plot_cod_state_timeline(vcfg, codTable)
%PLOT_COD_STATE_TIMELINE COD state timeline by simulated sector.

if isempty(codTable)
    return;
end

times = unique(codTable.timestamp);
sectors = unique(codTable.sim_sector_id);
Z = nan(numel(sectors), numel(times));
for i = 1:numel(sectors)
    for j = 1:numel(times)
        mask = codTable.sim_sector_id == sectors(i) & codTable.timestamp == times(j);
        if any(mask)
            Z(i, j) = state_code(string(codTable.cod_state(find(mask, 1))));
        end
    end
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1150 560]);
imagesc(Z);
colormap([0.2 0.65 0.3; 0.95 0.65 0.15; 0.85 0.15 0.15; 0.55 0.55 0.55]);
c = colorbar;
c.Ticks = 1:4;
c.TickLabels = {'normal','degraded','outage-like','insufficient'};
yticks(1:numel(sectors));
yticklabels(compose('S%d', sectors));
xticks(round(linspace(1, numel(times), min(8, numel(times)))));
xticklabels(string(times(xticks), 'MM-dd HH:mm'));
xtickangle(30);
xlabel('time');
ylabel('simulated sector');
title('Vendor KPI COD state timeline');
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_cod_state_timeline.png'));
end

function c = state_code(s)
switch s
    case "normal"
        c = 1;
    case "degraded_kpi"
        c = 2;
    case "outage_like"
        c = 3;
    otherwise
        c = 4;
end
end
