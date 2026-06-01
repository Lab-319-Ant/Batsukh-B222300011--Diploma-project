function plot_vendor_coc_episode_overview(vcfg, episodeSummary, decisionTable)
%PLOT_VENDOR_COC_EPISODE_OVERVIEW All-week COD/COC episode audit figure.

if isempty(episodeSummary)
    return;
end

E = sortrows(episodeSummary, 'first_timestamp');
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1450 850]);
tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_episode_timeline(E);

nexttile;
plot_episode_table(E, decisionTable);

sgtitle(fig, 'All-Week COD + COC Episode Overview', 'FontWeight', 'bold', 'FontSize', 17);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_all_week_episode_overview.png'));
end

function plot_episode_timeline(E)
hold on; grid on;
x = E.first_timestamp;
y = E.max_affected_sector_count;
hasComp = E.selected_compensation_rows > 0;

scatter(x(~hasComp), y(~hasComp), 90, [0.55 0.55 0.55], 'o', 'filled', ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'COD episode, COC no-op');
scatter(x(hasComp), y(hasComp), 120, [0.05 0.35 0.75], 's', 'filled', ...
    'MarkerEdgeColor', 'k', 'DisplayName', 'COD episode with COC compensation');
for i = 1:height(E)
    labelOffset = 0.25 + 0.22 * mod(i, 2);
    text(x(i), y(i) + labelOffset, sprintf('E%d', E.episode_id(i)), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

ylabel('max affected sectors');
xlabel('episode start time');
title('Every COD abnormal period across the 7-day KPI file');
legend('Location', 'northwest');
ylim([0, max([y; 1]) + 1.2]);
end

function plot_episode_table(E, decisionTable)
axis off;
title('Episode-specific interpretation: do not mix candidate targets across different times');

cols = ["Episode", "Time window", "Affected sectors", "COC result", "Selected targets"];
x = [0.02 0.12 0.33 0.67 0.84];
for c = 1:numel(cols)
    text(x(c), 0.95, cols(c), 'Units', 'normalized', 'FontWeight', 'bold', ...
        'FontSize', 10, 'Interpreter', 'none');
end

maxRows = min(height(E), 10);
y = 0.86;
for i = 1:maxRows
    row = E(i, :);
    if row.selected_compensation_rows > 0
        result = sprintf('%d compensation rows, %d no-op rows', ...
            row.selected_compensation_rows, row.selected_no_op_rows);
    else
        result = sprintf('no-op (%d rows)', row.selected_no_op_rows);
    end
    if ismember('affected_sector_cells', E.Properties.VariableNames)
        affected = shorten_text(string(row.affected_sector_cells{1}), 60);
    else
        affected = shorten_text(string(row.affected_sectors{1}), 60);
    end
    targets = string(row.selected_targets{1});
    if targets == ""
        targets = "none";
    else
        targets = add_target_cell_uids(targets, row.episode_id, decisionTable);
    end
    text(x(1), y, sprintf('E%d', row.episode_id), 'Units', 'normalized', 'FontSize', 9, ...
        'FontWeight', 'bold', 'Interpreter', 'none');
    text(x(2), y, sprintf('%s - %s', datestr(row.first_timestamp, 'dd-mmm HH:MM'), ...
        datestr(row.last_timestamp, 'HH:MM')), 'Units', 'normalized', 'FontSize', 9, ...
        'Interpreter', 'none');
    text(x(3), y, affected, 'Units', 'normalized', 'FontSize', 9, 'Interpreter', 'none');
    text(x(4), y, result, 'Units', 'normalized', 'FontSize', 9, 'Interpreter', 'none');
    text(x(5), y, shorten_text(targets, 28), 'Units', 'normalized', 'FontSize', 9, ...
        'Interpreter', 'none');
    y = y - 0.082;
end

text(0.02, 0.04, ...
    'Rule: COD is evaluated for all selected 7-day rows. COC ranks only same-timestamp normal target sectors and rejects targets with projected overload.', ...
    'Units', 'normalized', 'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
end

function out = add_target_cell_uids(targets, episodeId, decisionTable)
if isempty(decisionTable) || ~ismember('target_cell_uid', decisionTable.Properties.VariableNames)
    out = targets;
    return;
end
D = decisionTable(decisionTable.episode_id == episodeId & ...
    strcmp(string(decisionTable.decision), "selected_compensation"), :);
if isempty(D)
    out = targets;
    return;
end
out = strjoin(unique(string(D.target_label), 'stable'), ', ');
end

function txt = shorten_text(txt, maxChars)
txt = char(txt);
if strlength(string(txt)) <= maxChars
    return;
end
txt = [extractBefore(string(txt), maxChars - 2) '...'];
txt = char(txt);
end
