function plot_vendor_coc_target_safety_summary(vcfg, cocMlRanking, cocMlSelected)
%PLOT_VENDOR_COC_TARGET_SAFETY_SUMMARY Summarize COC target safety gates.

if isempty(cocMlRanking)
    return;
end

R = cocMlRanking(strcmp(string(cocMlRanking.action_type), "compensate_neighbor") & ...
    isfinite(cocMlRanking.target_sim_sector_id), :);
if isempty(R)
    return;
end

summary = build_target_summary(R);
timeline = build_selection_timeline(cocMlSelected);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1450 860]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_target_counts(summary);

nexttile;
plot_target_load_ranges(vcfg, summary);

nexttile([1 2]);
plot_selected_timeline(timeline);

sgtitle(fig, 'COC Target Safety: All-Week Candidate Summary and ML Selection Outcome', ...
    'FontWeight', 'bold', 'FontSize', 17);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_target_safety_summary.png'));
end

function summary = build_target_summary(R)
[groups, targetSector, targetUid] = findgroups(R.target_sim_sector_id, string(R.target_cell_uid));
n = max(groups);
rows = cell(n, 12);
for i = 1:n
    G = R(groups == i, :);
    safe = strcmp(string(G.target_overload_safety_status), "target_load_headroom_ok");
    reject = strcmp(string(G.target_overload_safety_status), "projected_target_overload_reject") | ...
        strcmp(string(G.target_overload_safety_status), "target_current_load_not_safe");
    selected = logical(G.ml_selected) & safe;
    rows(i, :) = {sprintf('S%d | cell %s', targetSector(i), char(targetUid(i))), ...
        targetSector(i), char(targetUid(i)), height(G), sum(safe), sum(reject), ...
        sum(selected), min(G.target_sector_load, [], 'omitnan'), ...
        max(G.target_sector_load, [], 'omitnan'), ...
        min(G.estimated_target_load_after_coc, [], 'omitnan'), ...
        max(G.estimated_target_load_after_coc, [], 'omitnan'), ...
        mean(G.predicted_reward, 'omitnan')};
end
summary = cell2table(rows, 'VariableNames', {'display_cell','target_sim_sector_id', ...
    'target_cell_uid','candidate_rows','safe_rows','rejected_rows','selected_rows', ...
    'min_current_prb','max_current_prb','min_estimated_after_coc_prb', ...
    'max_estimated_after_coc_prb','mean_predicted_reward'});
summary = sortrows(summary, {'selected_rows','safe_rows','target_sim_sector_id'}, {'descend','descend','ascend'});
end

function timeline = build_selection_timeline(cocMlSelected)
timeline = table();
if isempty(cocMlSelected)
    return;
end
S = cocMlSelected;
S.target_label = repmat("no-op", height(S), 1);
hasTarget = isfinite(S.target_sim_sector_id);
S.target_label(hasTarget) = "S" + string(S.target_sim_sector_id(hasTarget));
[groups, ts, label, action] = findgroups(S.timestamp, S.target_label, string(S.action_type));
count = splitapply(@numel, S.timestamp, groups);
timeline = table(ts, label, action, count, 'VariableNames', ...
    {'timestamp','target_label','action_type','row_count'});
timeline = sortrows(timeline, 'timestamp');
end

function plot_target_counts(summary)
labels = string(summary.display_cell);
n = min(12, height(summary));
T = summary(1:n, :);
labelsPlot = flip(labels(1:n));
cats = categorical(labelsPlot);
cats = reordercats(cats, labelsPlot);
values = flip([T.safe_rows, T.rejected_rows, T.selected_rows]);
b = barh(cats, values, 'stacked');
b(1).FaceColor = [0.20 0.55 0.35];
b(2).FaceColor = [0.75 0.25 0.20];
b(3).FaceColor = [0.05 0.30 0.80];
grid on;
set(gca, 'TickLabelInterpreter', 'none');
xlabel('candidate rows');
title('All-week candidate targets: safe vs rejected vs selected');
legend({'safe headroom','projected overload reject','ML selected'}, ...
    'Location', 'southeast', 'Interpreter', 'none');
end

function plot_target_load_ranges(vcfg, summary)
labels = string(summary.display_cell);
n = min(12, height(summary));
T = summary(1:n, :);
labelsPlot = flip(labels(1:n));
y = 1:n;
hold on; grid on;
for i = 1:n
    srcIdx = n - i + 1;
    plot([100*T.min_current_prb(srcIdx), 100*T.max_current_prb(srcIdx)], [i i], ...
        '-', 'Color', [0.12 0.38 0.68], 'LineWidth', 5);
    plot([100*T.min_estimated_after_coc_prb(srcIdx), 100*T.max_estimated_after_coc_prb(srcIdx)], ...
        [i+0.18 i+0.18], '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 5);
end
xline(100 * vcfg.cocNeighborLoadSafeThreshold, '--', 'safe candidate limit', ...
    'Color', [0.20 0.55 0.35], 'LineWidth', 1.2);
xline(100 * vcfg.cocNeighborLoadHardRejectThreshold, '--', 'hard reject limit', ...
    'Color', [0.75 0.10 0.10], 'LineWidth', 1.2);
set(gca, 'YTick', y, 'YTickLabel', labelsPlot, 'TickLabelInterpreter', 'none');
xlabel('DL PRB (%)');
title('All-week target current PRB range vs estimated after-COC PRB');
legend({'current PRB range','estimated after-COC PRB range'}, ...
    'Location', 'southeast', 'Interpreter', 'none');
end

function plot_selected_timeline(timeline)
if isempty(timeline)
    text(0.5, 0.5, 'No selected COC action timeline available', ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    axis off;
    return;
end

hold on; grid on;
labels = unique(string(timeline.target_label), 'stable');
labels = sort(labels);
for i = 1:numel(labels)
    T = timeline(string(timeline.target_label) == labels(i), :);
    isNoOp = strcmp(string(T.action_type), "no_op");
    scatter(T.timestamp(~isNoOp), repmat(i, sum(~isNoOp), 1), ...
        35 + 12 * T.row_count(~isNoOp), [0.05 0.35 0.75], 'filled', ...
        'MarkerEdgeColor', 'k');
    scatter(T.timestamp(isNoOp), repmat(i, sum(isNoOp), 1), ...
        26 + 7 * T.row_count(isNoOp), [0.55 0.55 0.55], 'filled', ...
        'MarkerEdgeColor', 'k');
end
set(gca, 'YTick', 1:numel(labels), 'YTickLabel', labels, 'TickLabelInterpreter', 'none');
xlabel('time');
ylabel('selected target');
title({'Selected COC action timeline: target sector or no-op after safety gate', ...
    'Note: target list above is all-week; a sector can be a candidate at one time and outage-like at another.'});
legend({'selected compensation','no-op after safety'}, 'Location', 'eastoutside', ...
    'Interpreter', 'none');
end
