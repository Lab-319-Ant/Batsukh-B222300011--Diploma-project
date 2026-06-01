function plot_vendor_qp_degradation_summary(vcfg, qpTable, qpEpisodes)
%PLOT_VENDOR_QP_DEGRADATION_SUMMARY Teacher-facing QP evidence figure.

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1450 850]);

if isempty(qpEpisodes)
    draw_no_qp_action_report(vcfg, qpTable);
    save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_qp_degradation_summary.png'));
    return;
end

tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_qp_episode_bar(qpEpisodes);

nexttile;
plot_qp_text_summary(vcfg, qpEpisodes, qpTable);

nexttile([1 2]);
plot_qp_episode_evidence(vcfg, qpEpisodes, qpTable);

sgtitle(fig, 'QP Advisory: QoS Degradation Risk and Evidence', ...
    'FontWeight', 'bold', 'FontSize', 17);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_qp_degradation_summary.png'));
end

function plot_qp_episode_bar(episodes)
n = min(10, height(episodes));
T = episodes(1:n, :);
labels = strings(height(T), 1);
for i = 1:height(T)
    labels(i) = sprintf('%s | %s', string(T.display_cell{i}), ...
        datestr(T.first_timestamp(i), 'dd-mmm HH:MM'));
end
actualDrop = T.actual_throughput_drop_ratio_at_peak_1h;
actualDrop(~isfinite(actualDrop)) = 0;
labelsPlot = flip(labels);
values = flip([100 * T.predicted_throughput_drop_ratio_at_peak, 100 * actualDrop]);
cats = categorical(labelsPlot);
cats = reordercats(cats, labelsPlot);
b = barh(cats, values);
b(1).FaceColor = [0.05 0.35 0.75];
b(2).FaceColor = [0.86 0.33 0.10];
grid on;
set(gca, 'TickLabelInterpreter', 'none');
xlabel('throughput drop at peak (%)');
title('QP degradation episodes (prediction vs actual +1h)');
legend({'predicted drop','actual +1h drop'}, 'Location', 'southeast', 'Interpreter', 'none');
end

function plot_qp_text_summary(vcfg, episodes, qpTable)
axis off;
lines = strings(0, 1);
lines(end+1) = "Engineering interpretation";
lines(end+1) = "QP flags where throughput degradation is likely enough for review.";
for i = 1:min(4, height(episodes))
    lines(end+1) = sprintf('%s | %s -> %s | %s', string(episodes.display_cell{i}), ...
        datestr(episodes.first_timestamp(i), 'dd-mmm HH:MM'), ...
        datestr(episodes.last_timestamp(i), 'dd-mmm HH:MM'), ...
        readable_qp_action(episodes.recommended_qp_action{i}));
    lines(end+1) = sprintf('  peak %s: risk %.2f, PRB %.1f%%, predicted drop %.1f%%, actual drop %.1f%%', ...
        datestr(episodes.peak_timestamp(i), 'dd-mmm HH:MM'), ...
        episodes.max_qp_risk_score(i), 100 * episodes.predicted_dl_prb_at_peak(i), ...
        100 * episodes.predicted_throughput_drop_ratio_at_peak(i), ...
        100 * episodes.actual_throughput_drop_ratio_at_peak_1h(i)); %#ok<AGROW>
    lines(end+1) = sprintf('  Throughput model evidence: MAE %.2f Mbps, R2 %.2f', ...
        episodes.mae_dl_throughput_mbps_1h(i), episodes.r2_dl_throughput_1h(i)); %#ok<AGROW>
end
if ~isempty(qpTable)
    highRows = sum(ismember(string(qpTable.qp_risk_class), ["degradation_risk","critical_qos_risk"]));
    codBlocked = sum(strcmp(string(qpTable.qp_risk_class), "blocked_by_cod_incident"));
    lines(end+1) = sprintf('Rows needing QP review: %d | rows blocked by COD priority: %d', highRows, codBlocked);
end
lines(end+1) = sprintf('Risk gate: PRB starts %.0f%%, high risk %.0f%%; throughput drop warning %.0f%%.', ...
    100 * vcfg.qpCongestionPrbStartThreshold, 100 * vcfg.qpHighRiskThreshold, ...
    100 * vcfg.qpThroughputDropWarningRatio);
lines(end+1) = "Claim boundary: KPI advisory only; no live QoS/capacity action applied.";

y = 0.96;
for i = 1:numel(lines)
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 9, ...
        'FontWeight', ternary(i <= 2, 'bold', 'normal'), 'Interpreter', 'none');
    y = y - 0.061;
end
end

function plot_qp_episode_evidence(vcfg, episodes, qpTable)
if isempty(qpTable)
    text(0.5, 0.5, 'No QP evidence timeline available', ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    axis off;
    return;
end

E = episodes(1, :);
S = qpTable(qpTable.sim_sector_id == E.sim_sector_id, :);
S = sortrows(S, 'timestamp');
windowStart = E.first_timestamp - hours(3);
windowEnd = E.last_timestamp + hours(3);
if hours(windowEnd - windowStart) > 36
    windowStart = E.peak_timestamp - hours(12);
    windowEnd = E.peak_timestamp + hours(12);
end
S = S(S.timestamp >= windowStart & S.timestamp <= windowEnd, :);

yyaxis left;
hold on; grid on;
plot(S.timestamp, S.current_dl_throughput_mbps, '-', ...
    'Color', [0.15 0.15 0.15], 'LineWidth', 1.3);
plot(S.timestamp, S.predicted_dl_throughput_mbps_1h, '-', ...
    'Color', [0.05 0.35 0.75], 'LineWidth', 1.8);
actualMask = logical(S.actual_1h_available);
plot(S.timestamp(actualMask), S.actual_dl_throughput_mbps_1h(actualMask), ':', ...
    'Color', [0.86 0.33 0.10], 'LineWidth', 1.5);
ylabel('DL throughput (Mbps)');

yyaxis right;
plot(S.timestamp, S.qp_risk_score, '-', 'Color', [0.72 0.20 0.24], 'LineWidth', 1.6);
yline(vcfg.qpModerateRiskThreshold, '--', 'moderate risk', 'Color', [0.50 0.20 0.20]);
yline(vcfg.qpHighRiskThreshold, '--', 'high risk', 'Color', [0.35 0.05 0.05]);
scatter(E.peak_timestamp, E.max_qp_risk_score, 54, [0.72 0.20 0.24], ...
    'filled', 'MarkerEdgeColor', 'k');
ylabel('QP risk score');
ylim([0 1]);

yyaxis left;
if E.first_timestamp == E.last_timestamp
    xline(E.peak_timestamp, '-', 'Color', [0.20 0.20 0.20], 'LineWidth', 1.0);
else
    xline(E.first_timestamp, '-', 'Color', [0.20 0.20 0.20], 'LineWidth', 1.0);
    xline(E.last_timestamp, '-', 'Color', [0.20 0.20 0.20], 'LineWidth', 1.0);
end
xlabel('time');
title(sprintf('Evidence timeline for %s: throughput prediction and QP risk', ...
    string(E.display_cell{1})), 'Interpreter', 'none');
legend({'current DL throughput','predicted +1h DL throughput','actual +1h DL throughput', ...
    'QP risk score'}, 'Location', 'eastoutside', 'Interpreter', 'none', 'FontSize', 8);
end

function draw_no_qp_action_report(vcfg, qpTable)
ax = axes('Position', [0 0 1 1]); %#ok<LAXES>
axis(ax, 'off');
xlim(ax, [0 1]);
ylim(ax, [0 1]);

normalRows = count_class(qpTable, "normal");
monitorRows = count_class(qpTable, "monitor");
reviewRows = sum(ismember(string(qpTable.qp_risk_class), ["degradation_risk","critical_qos_risk"]));
codBlocked = count_class(qpTable, "blocked_by_cod_incident");

rectangle(ax, 'Position', [0 0.86 1 0.14], 'FaceColor', [0.08 0.15 0.22], ...
    'EdgeColor', 'none');
text(ax, 0.04, 0.94, 'QoS Prediction Advisory Report', 'Color', 'w', ...
    'FontWeight', 'bold', 'FontSize', 22, 'Interpreter', 'none');
text(ax, 0.04, 0.895, 'Vendor KPI suggestion-only mode | No live QoS action applied', ...
    'Color', [0.82 0.88 0.92], 'FontSize', 11, 'Interpreter', 'none');

rectangle(ax, 'Position', [0.04 0.70 0.92 0.105], 'Curvature', 0.02, ...
    'FaceColor', [0.93 0.97 0.94], 'EdgeColor', [0.18 0.50 0.24], 'LineWidth', 1.2);
text(ax, 0.065, 0.755, 'Decision: NO QP DEGRADATION ACTION', ...
    'Color', [0.10 0.38 0.16], 'FontWeight', 'bold', 'FontSize', 16, 'Interpreter', 'none');
text(ax, 0.065, 0.718, 'Reason: no non-COD QoS degradation episode crossed the configured risk gate.', ...
    'Color', [0.20 0.20 0.20], 'FontSize', 11, 'Interpreter', 'none');

draw_metric_card(ax, 0.04, 0.53, 'Normal rows', normalRows, [0.20 0.45 0.28]);
draw_metric_card(ax, 0.365, 0.53, 'Monitor rows', monitorRows, [0.74 0.50 0.16]);
draw_metric_card(ax, 0.69, 0.53, 'QP review rows', reviewRows, [0.62 0.10 0.10]);

barAx = axes('Position', [0.15 0.23 0.32 0.20]); %#ok<LAXES>
barLabels = categorical({'Normal','Monitor','QP review','COD block'});
barLabels = reordercats(barLabels, {'Normal','Monitor','QP review','COD block'});
barh(barAx, barLabels, [normalRows monitorRows reviewRows codBlocked], ...
    'FaceColor', [0.20 0.38 0.52]);
grid(barAx, 'on');
xlabel(barAx, 'KPI rows');
title(barAx, 'QP decision distribution');

text(ax, 0.52, 0.44, 'QP safety interpretation', 'FontWeight', 'bold', 'FontSize', 13, 'Interpreter', 'none');
text(ax, 0.52, 0.395, sprintf('Risk score >= %.2f starts degradation review.', vcfg.qpModerateRiskThreshold), ...
    'FontSize', 11, 'Interpreter', 'none');
text(ax, 0.52, 0.355, 'COD abnormal rows are handled by COD/COC first.', ...
    'FontSize', 11, 'Interpreter', 'none');
text(ax, 0.52, 0.315, 'No automatic QoS, LB, or scheduler parameter change is applied.', ...
    'FontSize', 11, 'Interpreter', 'none');

text(ax, 0.04, 0.06, 'Claim boundary: advisory output only; no live LTE parameter was changed.', ...
    'FontSize', 10, 'Color', [0.35 0.35 0.35], 'Interpreter', 'none');
end

function draw_metric_card(ax, x, y, label, value, color)
rectangle(ax, 'Position', [x y 0.27 0.13], 'FaceColor', [1 1 1], ...
    'EdgeColor', [0.70 0.74 0.78], 'LineWidth', 1.0);
text(ax, x + 0.02, y + 0.085, label, 'FontSize', 10, ...
    'FontWeight', 'bold', 'Color', [0.25 0.25 0.25], 'Interpreter', 'none');
text(ax, x + 0.02, y + 0.035, sprintf('%d rows', value), 'FontSize', 17, ...
    'FontWeight', 'bold', 'Color', color, 'Interpreter', 'none');
end

function count = count_class(qpTable, classCode)
if isempty(qpTable) || ~ismember('qp_risk_class', qpTable.Properties.VariableNames)
    count = 0;
    return;
end
count = sum(strcmp(string(qpTable.qp_risk_class), classCode));
end

function label = readable_qp_action(actionCode)
switch string(actionCode)
    case "resolve_cod_coc_before_qp"
        label = "COD/COC first";
    case "review_capacity_lb_scheduler"
        label = "review capacity/LB/scheduler";
    case "prepare_lb_capacity_help"
        label = "prepare LB or capacity help";
    case "review_radio_quality_before_capacity"
        label = "review radio quality first";
    case "monitor_qos_kpi_trend"
        label = "monitor QoS KPI trend";
    otherwise
        label = strrep(string(actionCode), "_", " ");
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
