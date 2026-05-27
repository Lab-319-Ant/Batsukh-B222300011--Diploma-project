function plot_vendor_coc_ml_ranking(vcfg, selectedActions)
%PLOT_VENDOR_COC_ML_RANKING Teacher-facing vendor COC ML advisory summary.

if isempty(selectedActions)
    return;
end

[simpleActions, simpleSummary] = build_vendor_coc_ml_readable_report(selectedActions);

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1250 720]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
decisionOrder = ["COC ML compensation advisory"; ...
    "COC conditional review"; ...
    "No COC action"];
decisionCounts = zeros(numel(decisionOrder), 1);
for i = 1:numel(decisionOrder)
    decisionCounts(i) = sum(string(simpleActions.decision) == decisionOrder(i));
end
cats = categorical(decisionOrder, decisionOrder, 'Ordinal', true);
b = barh(cats, decisionCounts, 0.55);
b.FaceColor = 'flat';
b.CData = [0.20 0.55 0.30; 0.90 0.55 0.15; 0.45 0.45 0.45];
grid on;
xlabel('selected events');
title('COD -> COC decision summary');
xlim([0, max(decisionCounts) * 1.18 + 1]);
for i = 1:numel(decisionCounts)
    text(decisionCounts(i) + 1, i, sprintf('%d', decisionCounts(i)), ...
        'VerticalAlignment', 'middle', 'FontWeight', 'bold');
end

nexttile;
reviewRows = simpleSummary(ismember(string(simpleSummary.decision), ...
    ["COC ML compensation advisory", "COC conditional review"]), :);
if isempty(reviewRows)
    text(0.5, 0.5, 'No COC neighbor compensation candidates', ...
        'HorizontalAlignment', 'center', 'FontSize', 13);
    axis off;
else
    labels = strcat(string(reviewRows.affected_sector), " -> ", string(reviewRows.target_sector));
    x = 1:height(reviewRows);
    bar(x, reviewRows.event_count, 0.60, 'FaceColor', [0.20 0.55 0.30]);
    grid on;
    xticks(x);
    xticklabels(labels);
    xtickangle(30);
    xlabel('affected sector -> target sector');
    ylabel('event count');
    title('ML-ranked COC candidates for engineering review');
    ylim([0, max(reviewRows.event_count) + 1]);
end

nexttile([1 2]);
axis off;
lines = build_summary_text(simpleActions, simpleSummary);
y = 0.96;
for i = 1:numel(lines)
    if i == 1
        fontSize = 15;
        weight = 'bold';
    elseif startsWith(lines(i), "Safe COC")
        fontSize = 12;
        weight = 'bold';
    else
        fontSize = 11;
        weight = 'normal';
    end
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontName', 'Consolas', ...
        'FontSize', fontSize, 'FontWeight', weight, 'Interpreter', 'none');
    y = y - 0.085;
end

sgtitle(fig, 'Vendor KPI COD + COC ML Advisory Summary', ...
    'FontWeight', 'bold', 'FontSize', 18);
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_ml_selected_actions.png'));
save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_coc_ml_teacher_summary.png'));
end

function lines = build_summary_text(simpleActions, simpleSummary)
reviewRows = simpleSummary(ismember(string(simpleSummary.decision), ...
    ["COC ML compensation advisory", "COC conditional review"]), :);
checkCount = sum(string(simpleActions.decision) == "COC conditional review");
noopCount = sum(string(simpleActions.decision) == "No COC action");
reviewCount = sum(string(simpleActions.decision) == "COC ML compensation advisory");

lines = strings(0, 1);
lines(end+1) = "Engineering interpretation";
lines(end+1) = sprintf("COC ML advisory events: %d | Conditional review: %d | No COC action: %d", ...
    reviewCount, checkCount, noopCount);
lines(end+1) = "Selected action is calculated per event from ML-ranked target sector, RS-power delta, and eTilt delta.";
lines(end+1) = "Action space now includes +1, +3, and +6 dB RS power plus eTilt variants.";
lines(end+1) = "Claim boundary: advisory only, simulation-trained ML estimate, no live action and no real before/after proof.";

if ~isempty(reviewRows)
    lines(end+1) = "COC ML review groups:";
    maxRows = min(height(reviewRows), 8);
    for i = 1:maxRows
        lines(end+1) = sprintf("  %s -> %s | events=%d | %s to %s", ...
            string(reviewRows.affected_sector{i}), string(reviewRows.target_sector{i}), ...
            reviewRows.event_count(i), char(reviewRows.first_timestamp(i)), ...
            char(reviewRows.last_timestamp(i)));
    end
end
end
