function plot_phase12e_tradeoff_attach_vs_qos(cfg, baselineAi)
if isempty(baselineAi), return; end

fig = figure('Visible', 'off', 'Position', [100 100 900 520]);
scatter(baselineAi.delta_attach_rate, baselineAi.delta_qos_satisfaction_ratio, ...
    50, 'filled', 'MarkerFaceAlpha', 0.5);
hold on;
plot([0 0], ylim, 'k--');
plot(xlim, [0 0], 'k--');
xlabel('\\Delta attach rate');
ylabel('\\Delta QoS satisfaction ratio');
title(sprintf('Phase 12E: AI/ML tradeoff - attach vs QoS (n=%d)', height(baselineAi)));
grid on;
hold off;

save_figure(fig, fullfile(cfg.figuresDir, 'phase12e_tradeoff_attach_vs_qos.png'));
end
