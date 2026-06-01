function plot_vendor_tp_es_summary(vcfg, tpTable, esTable)
%PLOT_VENDOR_TP_ES_SUMMARY Teacher-facing TP and ES advisory summary.

if isempty(tpTable)
    return;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1300 620]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_tp_actual_vs_predicted(tpTable);

nexttile;
plot_tp_error_by_sector(tpTable);

nexttile;
plot_es_decisions(esTable);

nexttile;
axis off;
lines = [
    "TP: one-hour-ahead rolling KPI baseline from 15-minute vendor samples.";
    "ES: manual-review only. Blocked by COD abnormality or site-level incident.";
    sprintf("Low-load ES threshold: predicted DL PRB <= %.0f%%, active users <= %.1f.", ...
        100 * vcfg.esLowPredictedDlPrbThreshold, vcfg.esLowActiveUsersThreshold);
    "No sleep command is applied. No real energy saving is claimed.";
    "This is usage/load advisory evidence, not closed-loop AI-RAN control."];
y = 0.85;
for i = 1:numel(lines)
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 12, ...
        'FontWeight', ternary(i == 1, 'bold', 'normal'), 'Interpreter', 'none');
    y = y - 0.13;
end

sgtitle(fig, 'Vendor KPI TP + ES Advisory Summary', 'FontWeight', 'bold', 'FontSize', 17);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_tp_es_advisory_summary.png'));
end

function plot_tp_actual_vs_predicted(tpTable)
T = tpTable(logical(tpTable.actual_1h_available), :);
if isempty(T)
    text(0.5, 0.5, 'No one-hour-ahead actual rows available', 'HorizontalAlignment', 'center');
    axis off;
    return;
end
sampleStep = max(1, floor(height(T) / 2500));
T = T(1:sampleStep:end, :);
scatter(T.actual_dl_prb_utilization_1h, T.predicted_dl_prb_utilization_1h, 12, ...
    [0.10 0.35 0.75], 'filled', 'MarkerFaceAlpha', 0.35);
hold on; grid on;
plot([0 1], [0 1], '--k', 'LineWidth', 1.0);
xlabel('actual DL PRB in 1h');
ylabel('predicted DL PRB in 1h');
title('TP one-hour prediction check');
xlim([0 1]); ylim([0 1]);
end

function plot_tp_error_by_sector(tpTable)
T = tpTable(logical(tpTable.actual_1h_available), :);
if isempty(T)
    axis off;
    return;
end
[groups, sector] = findgroups(T.sim_sector_id);
mae = splitapply(@(a,p) mean(abs(a-p), 'omitnan'), ...
    T.actual_dl_prb_utilization_1h, T.predicted_dl_prb_utilization_1h, groups);
bar(categorical(compose('S%d', sector)), mae, 'FaceColor', [0.25 0.45 0.70]);
grid on;
xlabel('sector');
ylabel('MAE');
title('TP DL PRB prediction error by sector');
xtickangle(45);
end

function plot_es_decisions(esTable)
if isempty(esTable)
    text(0.5, 0.5, 'No ES rows generated', 'HorizontalAlignment', 'center');
    axis off;
    return;
end
[groups, decision] = findgroups(string(esTable.es_decision));
counts = splitapply(@numel, esTable.es_decision, groups);
[counts, order] = sort(counts, 'descend');
decision = decision(order);
barh(categorical(decision, flip(decision)), flip(counts), 'FaceColor', [0.20 0.55 0.35]);
grid on;
xlabel('rows');
title('ES advisory decisions');
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
