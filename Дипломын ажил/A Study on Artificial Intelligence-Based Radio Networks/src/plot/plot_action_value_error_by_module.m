function plot_action_value_error_by_module(cfg, predictions)
%PLOT_ACTION_VALUE_ERROR_BY_MODULE Boxplot of |error| by module (test split).

if isempty(predictions)
    return;
end
testMask = strcmp(predictions.split, 'test');
sub = predictions(testMask, :);
if isempty(sub)
    return;
end

fig = figure('Visible', 'off', 'Position', [100 100 800 500]);
modules = unique(string(sub.module_name), 'stable');
absErr = abs(sub.error);

if exist('boxchart', 'file') == 2
    boxchart(categorical(string(sub.module_name)), absErr);
else
    boxplot(absErr, sub.module_name);
end
ylabel('|predicted - actual| reward');
title(sprintf('Phase 9B action-value: absolute error by module (test, n=%d)', height(sub)));
grid on;

save_figure(fig, fullfile(cfg.figuresDir, 'phase9b_action_value_error_by_module.png'));

modules = modules; %#ok<NASGU,ASGSL>
end
