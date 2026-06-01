function plot_vendor_es_sleep_summary(vcfg, sleepReport, esTable, gateReport)
%PLOT_VENDOR_ES_SLEEP_SUMMARY Evidence-focused ES advisory figure.

if nargin < 4
    gateReport = table();
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1450 850]);

if isempty(sleepReport)
    plot_no_sleep_candidate(vcfg, esTable, gateReport);
else
    plot_sleep_candidates(vcfg, sleepReport, esTable, gateReport);
end

save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_es_sleep_summary.png'));
end

function plot_no_sleep_candidate(vcfg, esTable, gateReport)
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot_gate_counts(vcfg, esTable);

nexttile;
plot_es_text_summary(vcfg, esTable, gateReport, false);

nexttile;
plot_closest_sector_bar(vcfg, gateReport);

nexttile;
plot_closest_sector_timeline(vcfg, esTable, gateReport);

sgtitle('ES Advisory: No Sleep Candidate Passed Safety Gates', ...
    'FontWeight', 'bold', 'FontSize', 17);
end

function plot_sleep_candidates(vcfg, sleepReport, esTable, gateReport)
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
labels = strings(height(sleepReport), 1);
for i = 1:height(sleepReport)
    labels(i) = sprintf('%s | %s', string(sleepReport.display_cell{i}), ...
        datestr(sleepReport.first_timestamp(i), 'dd-mmm HH:MM'));
end
n = min(10, height(sleepReport));
T = sleepReport(1:n, :);
labelsPlot = flip(labels(1:n));
valuesPlot = flip(T.duration_minutes);
cats = categorical(labelsPlot);
cats = reordercats(cats, labelsPlot);
barh(cats, valuesPlot, 'FaceColor', [0.20 0.55 0.35]);
grid on;
set(gca, 'TickLabelInterpreter', 'none');
xlabel('candidate duration (minutes)');
title('Where ES sleep is suggested');

nexttile;
plot_es_text_summary(vcfg, esTable, gateReport, true);

nexttile;
plot_gate_counts(vcfg, esTable);

nexttile;
plot_candidate_timeline(vcfg, sleepReport, esTable);

sgtitle('ES Advisory: Sleep Candidate Review', 'FontWeight', 'bold', 'FontSize', 17);
end

function plot_gate_counts(vcfg, esTable)
if isempty(esTable)
    text(0.5, 0.5, 'No ES table available', 'HorizontalAlignment', 'center');
    axis off;
    return;
end

counts = [ ...
    sum(logical(esTable.low_prb_gate)), ...
    sum(logical(esTable.low_users_gate)), ...
    sum(logical(esTable.low_traffic_gate)), ...
    sum(logical(esTable.instant_low_load_gate)), ...
    sum(logical(esTable.low_load_consecutive_flag)), ...
    sum(strcmp(string(esTable.es_decision), "sleep_candidate_manual_review"))];
labels = categorical({'PRB gate','UE gate','traffic gate','all instant','1h consecutive','sleep'});
labels = reordercats(labels, {'PRB gate','UE gate','traffic gate','all instant','1h consecutive','sleep'});
bar(labels, counts, 'FaceColor', [0.18 0.38 0.56]);
grid on;
ylabel('KPI rows');
title('ES gate pass counts');
xtickangle(22);

subtitle(sprintf('thresholds: PRB <= %.0f%%, users <= %.1f, traffic <= %.0f kbyte, %d consecutive intervals', ...
    100 * vcfg.esLowPredictedDlPrbThreshold, vcfg.esLowActiveUsersThreshold, ...
    vcfg.esLowTrafficDlKbyteThreshold, vcfg.esMinConsecutiveLowLoadSteps));
end

function plot_es_text_summary(vcfg, esTable, gateReport, hasCandidates)
axis off;
lines = strings(0, 1);
if hasCandidates
    lines(end+1) = "Decision: ES SLEEP CANDIDATE(S) FOR MANUAL REVIEW";
else
    lines(end+1) = "Decision: NO ES SLEEP CANDIDATE";
end
lines(end+1) = "ES is last priority: COD/COC and service safety block sleep.";

if ~isempty(esTable)
    sleepRows = sum(strcmp(string(esTable.es_decision), "sleep_candidate_manual_review"));
    codRows = sum(strcmp(string(esTable.es_decision), "blocked_by_cod"));
    siteRows = sum(strcmp(string(esTable.es_decision), "blocked_by_site_incident"));
    nbrRows = sum(strcmp(string(esTable.es_decision), "blocked_neighbor_load"));
    instantRows = sum(logical(esTable.instant_low_load_gate));
    consecutiveRows = sum(logical(esTable.low_load_consecutive_flag));
    lines(end+1) = sprintf('Rows: instant low-load %d, 1h consecutive %d, sleep candidate %d.', ...
        instantRows, consecutiveRows, sleepRows);
    lines(end+1) = sprintf('Post-gate safety blocks: COD %d, site incident %d, neighbor load %d.', ...
        codRows, siteRows, nbrRows);
end

if ~isempty(gateReport)
    T = gateReport(1:min(4, height(gateReport)), :);
    lines(end+1) = "Closest sectors by ES gate:";
    for i = 1:height(T)
        lines(end+1) = sprintf('%s | max low-load run %d/%d intervals | %s', ...
            string(T.display_cell{i}), T.max_consecutive_low_load_count(i), ...
            vcfg.esMinConsecutiveLowLoadSteps, string(T.main_block_reason{i})); %#ok<AGROW>
    end
end

lines(end+1) = sprintf('Gate: PRB <= %.0f%%, active users <= %.1f, traffic <= %.0f kbyte for %d x 15 min.', ...
    100 * vcfg.esLowPredictedDlPrbThreshold, vcfg.esLowActiveUsersThreshold, ...
    vcfg.esLowTrafficDlKbyteThreshold, vcfg.esMinConsecutiveLowLoadSteps);
lines(end+1) = "Claim boundary: advisory only; no live sleep command or LTE parameter change applied.";

y = 0.96;
for i = 1:numel(lines)
    text(0.02, y, lines(i), 'Units', 'normalized', 'FontSize', 9.5, ...
        'FontWeight', ternary(i <= 2, 'bold', 'normal'), 'Interpreter', 'none');
    y = y - 0.068;
end
end

function plot_closest_sector_bar(vcfg, gateReport)
if isempty(gateReport)
    text(0.5, 0.5, 'No ES gate report available', 'HorizontalAlignment', 'center');
    axis off;
    return;
end

n = min(10, height(gateReport));
T = gateReport(1:n, :);
labels = string(T.display_cell);
labelsPlot = flip(labels);
valuesPlot = flip(T.max_consecutive_low_load_count);
cats = categorical(labelsPlot);
cats = reordercats(cats, labelsPlot);
barh(cats, valuesPlot, 'FaceColor', [0.26 0.52 0.42]);
hold on;
xline(vcfg.esMinConsecutiveLowLoadSteps, '--r', 'required', 'LineWidth', 1.2);
grid on;
set(gca, 'TickLabelInterpreter', 'none');
xlabel('max consecutive low-load intervals');
title('Closest sectors to ES sleep gate');
end

function plot_closest_sector_timeline(vcfg, esTable, gateReport)
if isempty(esTable) || isempty(gateReport)
    text(0.5, 0.5, 'No ES evidence timeline available', 'HorizontalAlignment', 'center');
    axis off;
    return;
end

E = gateReport(1, :);
S = esTable(esTable.sim_sector_id == E.sim_sector_id, :);
S = sortrows(S, 'timestamp');
centerTs = E.closest_low_load_timestamp;
windowStart = centerTs - hours(4);
windowEnd = centerTs + hours(4);
S = S(S.timestamp >= windowStart & S.timestamp <= windowEnd, :);

yyaxis left;
hold on; grid on;
plot(S.timestamp, 100 * S.predicted_dl_prb_utilization_1h, '-', ...
    'Color', [0.05 0.35 0.75], 'LineWidth', 1.6);
yline(100 * vcfg.esLowPredictedDlPrbThreshold, '--', 'PRB gate', ...
    'Color', [0.05 0.35 0.75]);
ylabel('predicted DL PRB (%)');

yyaxis right;
plot(S.timestamp, S.predicted_active_users_1h, '-', ...
    'Color', [0.16 0.50 0.25], 'LineWidth', 1.4);
yline(vcfg.esLowActiveUsersThreshold, '--', 'UE gate', ...
    'Color', [0.16 0.50 0.25]);
ylabel('predicted active users');

instantMask = logical(S.instant_low_load_gate);
if any(instantMask)
    yyaxis left;
    scatter(S.timestamp(instantMask), 100 * S.predicted_dl_prb_utilization_1h(instantMask), ...
        42, [0.80 0.18 0.18], 'filled', 'MarkerEdgeColor', 'k');
end

xlabel('time');
title(sprintf('Closest ES evidence timeline: %s', string(E.display_cell{1})), ...
    'Interpreter', 'none');
legend({'predicted DL PRB','PRB gate','predicted users','UE gate','instant all-gate pass'}, ...
    'Location', 'eastoutside', 'Interpreter', 'none', 'FontSize', 8);
end

function plot_candidate_timeline(vcfg, sleepReport, esTable)
if isempty(sleepReport) || isempty(esTable)
    axis off;
    return;
end
E = sleepReport(1, :);
S = esTable(esTable.sim_sector_id == E.sim_sector_id, :);
S = sortrows(S, 'timestamp');
windowStart = E.first_timestamp - hours(4);
windowEnd = E.last_timestamp + hours(4);
S = S(S.timestamp >= windowStart & S.timestamp <= windowEnd, :);

hold on; grid on;
plot(S.timestamp, 100 * S.predicted_dl_prb_utilization_1h, '-', ...
    'Color', [0.05 0.35 0.75], 'LineWidth', 1.6);
plot(S.timestamp, S.predicted_active_users_1h, '-', ...
    'Color', [0.16 0.50 0.25], 'LineWidth', 1.4);
yline(100 * vcfg.esLowPredictedDlPrbThreshold, '--', 'PRB gate', ...
    'Color', [0.05 0.35 0.75]);
yline(vcfg.esLowActiveUsersThreshold, '--', 'UE gate', ...
    'Color', [0.16 0.50 0.25]);
xline(E.first_timestamp, '-', 'candidate start', 'Color', [0.20 0.20 0.20]);
xline(E.last_timestamp, '-', 'candidate end', 'Color', [0.20 0.20 0.20]);
xlabel('time');
ylabel('PRB (%) / users');
title(sprintf('ES candidate evidence: %s', string(E.display_cell{1})), 'Interpreter', 'none');
legend({'predicted DL PRB (%)','predicted users'}, 'Location', 'eastoutside', ...
    'Interpreter', 'none', 'FontSize', 8);
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
