function plot_phase12d_rsrp_sinr_change(cfg, resultRows)
if isempty(resultRows), return; end

fig = figure('Visible', 'off', 'Position', [100 100 900 500]);
hold on;
scatter(resultRows.delta_mean_rsrp_dB, resultRows.delta_mean_sinr_dB, 40, ...
    'filled', 'MarkerFaceAlpha', 0.5);
plot([0 0], ylim, 'k--');
plot(xlim, [0 0], 'k--');
xlabel('\\Delta mean RSRP (dB)');
ylabel('\\Delta mean SINR (dB)');
title(sprintf('Phase 12D: RSRP vs SINR change per applied action (n=%d)', height(resultRows)));
grid on;
hold off;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12d_rsrp_sinr_change.png'));
end
