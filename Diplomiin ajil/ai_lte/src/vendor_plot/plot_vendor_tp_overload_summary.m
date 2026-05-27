function plot_vendor_tp_overload_summary(vcfg, overloadReport, overloadEpisodes, performanceReport, tpTable)
%PLOT_VENDOR_TP_OVERLOAD_SUMMARY Evidence-focused TP overload figure.

if nargin < 3 || isempty(overloadEpisodes)
    overloadEpisodes = overloadReport_to_episode_like(overloadReport);
end
if nargin < 4
    performanceReport = table();
end
if nargin < 5
    tpTable = table();
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1450 850]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_episode_bar(vcfg, overloadEpisodes);

nexttile;
plot_tp_text_summary(overloadEpisodes, performanceReport);

nexttile([1 2]);
plot_tp_episode_evidence(vcfg, overloadEpisodes, tpTable);

sgtitle(fig, 'TP Advisory: Overload Episodes and Prediction Evidence', ...
    'FontWeight', 'bold', 'FontSize', 17);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_overload_summary.png'));
end

function plot_episode_bar(vcfg, episodes)
if isempty(episodes)
    text(0.5, 0.5, 'No predicted overload episode above threshold', ...
        'HorizontalAlignment', 'center', 'FontSize', 14);
    axis off;
    return;
end
n = min(10, height(episodes));
T = episodes(1:n, :);
labels = make_episode_labels(T);
labelsPlot = flip(labels);
valuesPlot = flip(T.interval_count);
cats = categorical(labelsPlot);
cats = reordercats(cats, labelsPlot);
barh(cats, valuesPlot, 'FaceColor', [0.74 0.25 0.18]);
grid on;
set(gca, 'TickLabelInterpreter', 'none');
xlabel('15-minute overload intervals');
title(sprintf('Predicted overload episodes (DL PRB >= %.0f%%)', 100 * vcfg.tpOverloadPrbThreshold));
end

function labels = make_episode_labels(T)
labels = strings(height(T), 1);
for i = 1:height(T)
    labels(i) = sprintf('%s | %s', string(T.display_cell{i}), datestr(T.first_timestamp(i), 'dd-mmm HH:MM'));
end
end

function plot_tp_text_summary(episodes, performanceReport)
axis off;
lines = strings(0, 1);
lines(end+1) = "Engineering interpretation";
if isempty(episodes)
    lines(end+1) = "No sector exceeded the TP overload threshold.";
else
    lines(end+1) = "Top overload episodes:";
    for i = 1:min(4, height(episodes))
        lines(end+1) = sprintf('%s | %s -> %s', string(episodes.display_cell{i}), ...
            datestr(episodes.first_timestamp(i), 'dd-mmm HH:MM'), ...
            datestr(episodes.last_timestamp(i), 'dd-mmm HH:MM'));
        lines(end+1) = sprintf('  peak %s: pred %.1f%%, actual+1h %.1f%% | MAE %.1f%% | R2 %.2f', ...
            datestr(episodes.peak_timestamp(i), 'dd-mmm HH:MM'), ...
            100 * episodes.max_predicted_dl_prb(i), ...
            100 * episodes.actual_dl_prb_at_peak_1h(i), ...
            100 * episodes.mae_dl_prb_1h(i), episodes.r2_dl_prb_1h(i)); %#ok<AGROW>
        lines(end+1) = sprintf('  %s', readable_tp_action(episodes.recommended_tp_action{i})); %#ok<AGROW>
    end
end
if ~isempty(performanceReport)
    usable = sum(performanceReport.r2_dl_prb_1h >= 0.70 & performanceReport.mae_dl_prb_1h <= 0.12);
    weak = sum(performanceReport.r2_dl_prb_1h < 0.45 | performanceReport.mae_dl_prb_1h > 0.18);
    lines(end+1) = sprintf('Model evidence: %d sectors usable, %d weak. Do not overclaim weak sectors.', usable, weak);
end
lines(end+1) = "Claim boundary: one-hour KPI forecast only; no automatic LB/capacity change applied.";

y = 0.96;
for i = 1:numel(lines)
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 9, ...
        'FontWeight', ternary(i <= 2, 'bold', 'normal'), 'Interpreter', 'none');
    y = y - 0.066;
end
end

function plot_tp_episode_evidence(vcfg, episodes, tpTable)
if isempty(episodes) || isempty(tpTable)
    text(0.5, 0.5, 'No TP evidence timeline available', ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    axis off;
    return;
end

E = episodes(1, :);
S = tpTable(tpTable.sim_sector_id == E.sim_sector_id, :);
S = sortrows(S, 'timestamp');
windowStart = E.first_timestamp - hours(3);
windowEnd = E.last_timestamp + hours(3);
if hours(windowEnd - windowStart) > 36
    windowStart = E.peak_timestamp - hours(12);
    windowEnd = E.peak_timestamp + hours(12);
end
S = S(S.timestamp >= windowStart & S.timestamp <= windowEnd, :);

hold on; grid on;
if ~isempty(S)
    plot(S.timestamp, 100 * S.predicted_dl_prb_utilization_1h, '-', ...
        'Color', [0.05 0.35 0.75], 'LineWidth', 1.7);
    actualMask = logical(S.actual_1h_available);
    plot(S.timestamp(actualMask), 100 * S.actual_dl_prb_utilization_1h(actualMask), ':', ...
        'Color', [0.86 0.33 0.10], 'LineWidth', 1.4);
end
yline(100 * vcfg.tpOverloadPrbThreshold, '--k', '80% threshold', 'LineWidth', 1.0);
xline(E.first_timestamp, '-', 'episode start', 'Color', [0.20 0.20 0.20], 'LineWidth', 1.0);
xline(E.last_timestamp, '-', 'episode end', 'Color', [0.20 0.20 0.20], 'LineWidth', 1.0);
scatter(E.peak_timestamp, 100 * E.max_predicted_dl_prb, 54, [0.05 0.35 0.75], ...
    'filled', 'MarkerEdgeColor', 'k');
ylabel('DL PRB (%)');
xlabel('time');
ylim([0 105]);
title(sprintf('Evidence timeline for %s: predicted vs actual +1h', string(E.display_cell{1})), ...
    'Interpreter', 'none');
legend({'predicted +1h DL PRB','actual +1h DL PRB'}, 'Location', 'eastoutside', ...
    'Interpreter', 'none', 'FontSize', 8);
end

function episodes = overloadReport_to_episode_like(overloadReport)
episodes = table();
if isempty(overloadReport)
    return;
end
episodes = overloadReport;
if ismember('overload_event_count', episodes.Properties.VariableNames)
    episodes.interval_count = episodes.overload_event_count;
end
if ~ismember('duration_minutes', episodes.Properties.VariableNames)
    episodes.duration_minutes = episodes.interval_count * 15;
end
end

function label = readable_tp_action(actionCode)
switch string(actionCode)
    case "high_overload_risk_review_LB_or_capacity_help"
        label = "review LB or capacity help";
    case "blocked_by_cod_incident_first"
        label = "blocked: resolve COD incident first";
    case "moderate_overload_risk_monitor"
        label = "monitor moderate overload risk";
    otherwise
        label = strrep(string(actionCode), "_", " ");
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
