function plot_action_value_oracle_regret_preview(cfg, regretPreview)
%PLOT_ACTION_VALUE_ORACLE_REGRET_PREVIEW Per-module regret distribution.

if isempty(regretPreview)
    return;
end

fig = figure('Visible', 'off', 'Position', [100 100 800 500]);
if exist('boxchart', 'file') == 2
    boxchart(categorical(string(regretPreview.module_name)), regretPreview.regret);
else
    boxplot(regretPreview.regret, regretPreview.module_name);
end
ylabel('oracle regret (oracle reward - top1 predicted true reward)');
title(sprintf('Phase 9B oracle regret preview (test groups = %d)', height(regretPreview)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase9b_action_value_oracle_regret.png'));
end
