function plot_vendor_coc_episode_decision_detail(vcfg, codTable, episodeSummary, decisionTable)
%PLOT_VENDOR_COC_EPISODE_DECISION_DETAIL Main per-incident COD/COC figure.

if isempty(episodeSummary) || isempty(decisionTable)
    return;
end

E = select_episode_for_display(episodeSummary);
D = decisionTable(decisionTable.episode_id == E.episode_id, :);
if isempty(D)
    return;
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1500 900]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile([1 2]);
plot_episode_cod_timeline(codTable, E);

nexttile;
plot_episode_decision_matrix(D);

nexttile;
plot_episode_text(vcfg, E, D);

sgtitle(fig, sprintf('COD + COC Incident Episode Detail: %s to %s', ...
    datestr(E.first_timestamp, 'dd-mmm-yyyy HH:MM'), datestr(E.last_timestamp, 'dd-mmm-yyyy HH:MM')), ...
    'FontWeight', 'bold', 'FontSize', 17);

save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_episode_decision_detail.png'));
end

function plot_episode_cod_timeline(codTable, E)
T = codTable(codTable.timestamp >= E.first_timestamp & codTable.timestamp <= E.last_timestamp, :);
[groups, ts] = findgroups(T.timestamp);
outage = splitapply(@(x) sum(strcmp(string(x), "outage_like")), T.cod_state, groups);
degraded = splitapply(@(x) sum(strcmp(string(x), "degraded_kpi")), T.cod_state, groups);
plot(ts, outage, '-', 'LineWidth', 1.8, 'Color', [0.78 0.12 0.12]);
hold on; grid on;
plot(ts, degraded, '-', 'LineWidth', 1.5, 'Color', [0.90 0.55 0.10]);
ylabel('affected sectors');
xlabel('time');
title('COD detections inside selected incident episode');
legend({'outage-like sectors','degraded KPI sectors'}, 'Location', 'northwest');
ylim([0, max([outage; degraded; 1]) + 1]);
end

function plot_episode_decision_matrix(D)
hold on; grid on;
times = unique(D.timestamp);
labels = unique(string(D.target_label), 'stable');
noOpIdx = find(labels == "no-op", 1);
if ~isempty(noOpIdx)
    labels = [labels(labels ~= "no-op"); "no-op"];
end

hSelected = scatter(NaN, NaN, 95, [0.05 0.35 0.75], 's', 'filled', ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'selected target');
hSafe = scatter(NaN, NaN, 65, [0.20 0.55 0.35], 'o', 'filled', ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'safe but not selected');
hRejected = scatter(NaN, NaN, 80, [0.78 0.12 0.12], 'x', ...
    'LineWidth', 2.0, 'DisplayName', 'rejected by overload');
hNoOp = scatter(NaN, NaN, 80, [0.55 0.55 0.55], 'o', 'filled', ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'no-op');

for i = 1:height(D)
    x = find(times == D.timestamp(i), 1);
    y = find(labels == string(D.target_label{i}), 1);
    decision = string(D.decision{i});
    switch decision
        case "selected_compensation"
            scatter(x, y, 95, [0.05 0.35 0.75], 's', 'filled', 'MarkerEdgeColor', 'k');
        case "safe_not_selected"
            scatter(x, y, 65, [0.20 0.55 0.35], 'o', 'filled', 'MarkerEdgeColor', 'k');
        case "rejected_projected_overload"
            scatter(x, y, 80, [0.78 0.12 0.12], 'x', 'LineWidth', 2.0);
        case "selected_no_op"
            scatter(x, y, 80, [0.55 0.55 0.55], 'o', 'filled', 'MarkerEdgeColor', 'k');
    end
end
set(gca, 'XTick', 1:numel(times), 'XTickLabel', cellstr(datestr(times, 'HH:MM')), ...
    'YTick', 1:numel(labels), 'YTickLabel', labels, 'TickLabelInterpreter', 'none');
xtickangle(45);
xlabel('timestamp in episode');
ylabel('target at same timestamp');
title('COC target decision by timestamp: same-episode only');
legend([hSelected hSafe hRejected hNoOp], 'Location', 'eastoutside', 'Interpreter', 'none');
end

function plot_episode_text(vcfg, E, D)
axis off;
selectedRows = D(strcmp(string(D.decision), "selected_compensation"), :);
noOpRows = D(strcmp(string(D.decision), "selected_no_op"), :);
rejectedRows = D(strcmp(string(D.decision), "rejected_projected_overload"), :);
safeRows = D(strcmp(string(D.decision), "safe_not_selected"), :);
selectedActionRows = sum(selectedRows.selected_rows, 'omitnan');
noOpActionRows = sum(noOpRows.selected_rows, 'omitnan');

lines = strings(0, 1);
lines(end+1) = "How to read this figure";
lines(end+1) = "This is one COD incident episode, not all-week aggregation.";
lines(end+1) = sprintf('Affected sites: %s', string(E.affected_sites{1}));
if ismember('affected_sector_cells', E.Properties.VariableNames)
    lines = append_wrapped_line(lines, 'Affected sectors in episode: ', ...
        string(E.affected_sector_cells{1}), 86);
else
    lines = append_wrapped_line(lines, 'Affected sectors in episode: ', ...
        string(E.affected_sectors{1}), 86);
end
lines(end+1) = sprintf('Selected COC action rows: %d | no-op source rows: %d', ...
    selectedActionRows, noOpActionRows);
lines(end+1) = sprintf('Selected target timestamps: %d | safe-but-not-selected: %d | overload-rejected: %d', ...
    height(selectedRows), height(safeRows), height(rejectedRows));
lines(end+1) = sprintf('Safe candidate rows: %d | rejected candidate rows: %d', ...
    sum(safeRows.safe_candidate_rows, 'omitnan'), sum(rejectedRows.rejected_candidate_rows, 'omitnan'));

if ~isempty(selectedRows)
    lines(end+1) = "Selected COC targets:";
    targetLabels = unique(string(selectedRows.target_label), 'stable');
    for i = 1:numel(targetLabels)
        T = selectedRows(string(selectedRows.target_label) == targetLabels(i), :);
        lines(end+1) = sprintf('%s: %s to %s, after-COC PRB mean %.1f%%', ...
            targetLabels(i), datestr(min(T.timestamp), 'HH:MM'), datestr(max(T.timestamp), 'HH:MM'), ...
            100 * mean(T.mean_estimated_target_prb_after_coc, 'omitnan')); %#ok<AGROW>
    end
end

lines(end+1) = sprintf('Safety rule: current target PRB <= %.0f%% and estimated after-COC PRB <= %.0f%%.', ...
    100 * vcfg.cocNeighborLoadSafeThreshold, 100 * vcfg.cocNeighborLoadHardRejectThreshold);
lines(end+1) = "COC target candidates are same-timestamp normal sectors only.";
lines(end+1) = "A sector that is outage-like at a timestamp is not used as target at that timestamp.";
lines(end+1) = "Claim boundary: KPI advisory only; no live parameter or attachment change is proven.";

y = 0.96;
for i = 1:numel(lines)
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 9.2, ...
        'FontWeight', ternary(i <= 2, 'bold', 'normal'), 'Interpreter', 'none');
    y = y - 0.057;
end
end

function lines = append_wrapped_line(lines, prefix, value, maxChars)
parts = split(value, ', ');
current = string(prefix);
for i = 1:numel(parts)
    candidate = current + parts(i);
    if strlength(candidate) > maxChars && current ~= string(prefix)
        lines(end+1) = current; %#ok<AGROW>
        current = "  " + parts(i);
    else
        current = candidate;
    end
    if i < numel(parts)
        current = current + ", ";
    end
end
lines(end+1) = current;
end

function E = select_episode_for_display(episodeSummary)
withComp = episodeSummary(episodeSummary.selected_compensation_rows > 0, :);
if ~isempty(withComp)
    withComp = sortrows(withComp, {'selected_compensation_rows','duration_minutes', ...
        'max_affected_sector_count'}, {'descend','descend','descend'});
    E = withComp(1, :);
else
    E = episodeSummary(1, :);
end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
