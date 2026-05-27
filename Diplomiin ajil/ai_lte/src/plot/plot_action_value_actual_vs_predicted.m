function plot_action_value_actual_vs_predicted(cfg, predictions)
%PLOT_ACTION_VALUE_ACTUAL_VS_PREDICTED Scatter plot per module.
%
% The main plot uses safe test candidates only because Phase 9B trains on
% safe_training_candidate rows. Mixing unsafe penalty-heavy rows into the
% main calibration plot makes the model look worse for a distribution it
% was intentionally not trained to fit.

if isempty(predictions)
    return;
end
modules = unique(string(predictions.module_name));
fig = figure('Visible', 'off', 'Position', [100 100 900 700]);
tl = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
title(tl, 'Phase 9B action-value: safe test actual vs predicted reward');

for k = 1:numel(modules)
    nexttile;
    mod = modules(k);
    mask = string(predictions.module_name) == mod & strcmp(predictions.split, 'test') & ...
        logical(predictions.safe_training_candidate);
    sub = predictions(mask, :);
    if isempty(sub)
        title(sprintf('%s (no test rows)', mod));
        continue;
    end
    scatter(sub.actual_reward, sub.predicted_reward, 6, 'filled', ...
        'MarkerFaceAlpha', 0.35);
    hold on;
    lo = min([sub.actual_reward; sub.predicted_reward]);
    hi = max([sub.actual_reward; sub.predicted_reward]);
    if ~isfinite(lo), lo = -1; end
    if ~isfinite(hi), hi = 1; end
    plot([lo hi], [lo hi], 'k--');
    hold off;
    xlabel('actual reward');
    ylabel('predicted reward');
    title(sprintf('%s (n=%d)', mod, height(sub)));
    grid on;
end

save_figure(fig, fullfile(cfg.figuresDir, 'phase9b_action_value_actual_vs_predicted.png'));
end
