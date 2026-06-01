function plot_vendor_baseline_coverage_time_monitor(vcfg, codTable, cocMlSelected)
%PLOT_VENDOR_BASELINE_COVERAGE_TIME_MONITOR Baseline coverage monitor.
%
% Shows when and where COD detects degraded/outage-like cells, then overlays
% COC ML advisory arrows for manual-review compensation suggestions.

if isempty(codTable)
    return;
end

layout = build_vendor_monitor_layout(vcfg);
selectedTimes = choose_monitor_times(codTable, cocMlSelected);
if isempty(selectedTimes)
    selectedTimes = codTable.timestamp(1);
end

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1500 1040]);
tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile([1 3]);
plot_time_monitor(codTable, cocMlSelected, selectedTimes);

numPanels = min(3, numel(selectedTimes));
snapshotInfo = cell(numPanels, 1);
for i = 1:numPanels
    nexttile(3 + i);
    snapshotInfo{i} = plot_one_snapshot(layout, codTable, cocMlSelected, selectedTimes(i));
end

for i = 1:numPanels
    nexttile(6 + i);
    plot_snapshot_text_box(vcfg, snapshotInfo{i}, selectedTimes(i));
end

sgtitle(fig, 'Vendor KPI Coverage Time Monitor: COD + COC Advisory', ...
    'FontWeight', 'bold', 'FontSize', 17);

save_figure(fig, fullfile(vcfg.figuresDir, 'vendor_baseline_coverage_time_monitor.png'));
end

function layout = build_vendor_monitor_layout(vcfg)
siteIds = (1:7).';
bearing = [0; 0; 60; 120; 180; 240; 300];
radius = [0; 0.82 * ones(6, 1)];
siteX = radius .* sind(bearing);
siteY = radius .* cosd(bearing);

siteMap = vcfg.siteMap(:, {'sim_site_id','sim_position','vendor_site_key'});
siteBase = table(siteIds, siteX, siteY, 'VariableNames', {'sim_site_id','site_x','site_y'});
sites = innerjoin(siteBase, siteMap, 'Keys', 'sim_site_id');
sites = sortrows(sites, 'sim_site_id');

sectorOffset = 0.10;
n = height(vcfg.cellMap);
sectorX = zeros(n, 1);
sectorY = zeros(n, 1);
for i = 1:n
    siteRow = sites(sites.sim_site_id == vcfg.cellMap.sim_site_id(i), :);
    az = vcfg.cellMap.sim_azimuth_deg(i);
    sectorX(i) = siteRow.site_x + sectorOffset * sind(az);
    sectorY(i) = siteRow.site_y + sectorOffset * cosd(az);
end

sectors = vcfg.cellMap;
sectors.sector_x = sectorX;
sectors.sector_y = sectorY;
sectors = innerjoin(sectors, siteMap, 'Keys', 'sim_site_id');
layout = struct('sites', sites, 'sectors', sectors);
end

function selectedTimes = choose_monitor_times(codTable, cocMlSelected)
selectedTimes = [];
if ~isempty(cocMlSelected)
    status = string(cocMlSelected.ml_safety_status);
    reviewRows = cocMlSelected(contains(status, "candidate_for_manual_review") | ...
        contains(status, "site_outage_coc_ml_advisory") | contains(status, "conditional"), :);
    if ~isempty(reviewRows)
        [groups, ts] = findgroups(reviewRows.timestamp);
        counts = splitapply(@numel, reviewRows.timestamp, groups);
        [~, order] = sort(counts, 'descend');
        selectedTimes = ts(order);
    end
end

if isempty(selectedTimes)
    abnormal = codTable(~strcmp(string(codTable.cod_state), 'normal'), :);
    if ~isempty(abnormal)
        [groups, ts] = findgroups(abnormal.timestamp);
        counts = splitapply(@numel, abnormal.timestamp, groups);
        [~, order] = sort(counts, 'descend');
        selectedTimes = ts(order);
    end
end

selectedTimes = selectedTimes(1:min(3, numel(selectedTimes)));
selectedTimes = sort(selectedTimes);
end

function plot_time_monitor(codTable, cocMlSelected, selectedTimes)
[groups, ts] = findgroups(codTable.timestamp);
degraded = splitapply(@(x) sum(strcmp(string(x), 'degraded_kpi')), codTable.cod_state, groups);
outage = splitapply(@(x) sum(strcmp(string(x), 'outage_like')), codTable.cod_state, groups);

reviewCounts = zeros(size(ts));
if ~isempty(cocMlSelected)
    status = string(cocMlSelected.ml_safety_status);
    reviewRows = cocMlSelected(contains(status, "candidate_for_manual_review") | ...
        contains(status, "site_outage_coc_ml_advisory") | contains(status, "conditional"), :);
    if ~isempty(reviewRows)
        [g2, ts2] = findgroups(reviewRows.timestamp);
        c2 = splitapply(@numel, reviewRows.timestamp, g2);
        [hit, loc] = ismember(ts, ts2);
        reviewCounts(hit) = c2(loc(hit));
    end
end

plot(ts, degraded, '-', 'LineWidth', 1.5, 'Color', [0.90 0.55 0.10]);
hold on; grid on;
plot(ts, outage, '-', 'LineWidth', 1.8, 'Color', [0.78 0.12 0.12]);
stem(ts, reviewCounts, 'Color', [0.10 0.45 0.20], 'LineWidth', 1.1, 'Marker', 'none');

yl = ylim;
for i = 1:numel(selectedTimes)
    xline(selectedTimes(i), '--k', 'LineWidth', 1.0);
end
ylim([0, max([yl(2), max(degraded) + max(outage), 3])]);
xlabel('time');
ylabel('number of affected cells');
title('Time monitor: COD degraded/outage detections and COC review suggestions');
legend({'degraded KPI cells','outage-like cells','COC review suggestions'}, ...
    'Location', 'northwest');
end

function snapshotInfo = plot_one_snapshot(layout, codTable, cocMlSelected, timestamp)
hold on; grid on; axis equal;
draw_baseline_sites(layout);
snapshotInfo = struct('isIncident', false, 'text', "No incident text.", ...
    'suggestionLines', strings(0, 1));

T = codTable(codTable.timestamp == timestamp, :);
if isempty(T)
    title(sprintf('No KPI rows at %s', datestr(timestamp, 'dd-mmm HH:MM')));
    return;
end

draw_sector_states(layout, T);
snapshotInfo.suggestionLines = draw_coc_review_markers(layout, cocMlSelected, timestamp);
incident = detect_snapshot_incident(T, cocMlSelected, timestamp);
if incident.isIncident
    snapshotInfo.isIncident = true;
    snapshotInfo.text = sprintf('%s\n%s', incident.affectedText, incident.suggestionText);
else
    if isempty(snapshotInfo.suggestionLines)
        snapshotInfo.text = "No COC compensation suggestion at this timestamp.";
    else
        snapshotInfo.text = "COC manual-review suggestions:" + newline + ...
            strjoin(snapshotInfo.suggestionLines, newline);
    end
end

xlim([-1.22, 1.22]);
ylim([-1.18, 1.18]);
title(sprintf('%s | highlighted cells and COC suggestions', datestr(timestamp, 'dd-mmm-yyyy HH:MM')));
set(gca, 'XTick', [], 'YTick', [], 'XColor', 'none', 'YColor', 'none');
box off;
end

function incident = detect_snapshot_incident(T, cocMlSelected, timestamp)
incident = struct('isIncident', false, 'affectedText', '', 'suggestionText', '');
siteIds = unique(T.sim_site_id);
affectedSites = strings(0, 1);
affectedSectors = strings(0, 1);
for i = 1:numel(siteIds)
    siteRows = T(T.sim_site_id == siteIds(i), :);
    isOut = strcmp(string(siteRows.cod_state), 'outage_like');
    isAbnormal = isOut | strcmp(string(siteRows.cod_state), 'degraded_kpi');
    if sum(isOut) >= 2 || sum(isAbnormal) >= height(siteRows)
        affectedSites(end+1) = sprintf('Site %d', siteIds(i)); %#ok<AGROW>
        affectedSectors(end+1) = strjoin(compose('S%d', siteRows.sim_sector_id(isAbnormal)), ', '); %#ok<AGROW>
    end
end

if ~isempty(affectedSites)
    incident.isIncident = true;
    affectedText = "Detected: " + strjoin(affectedSites, " + ") + ...
        " outage/degradation (" + strjoin(affectedSectors, " + ") + ")";
    incident.affectedText = char(affectedText);
    mlText = build_ml_coc_incident_text(cocMlSelected, timestamp);
    incident.suggestionText = sprintf('%s\nRule: keep this same COC action until COD recovery.\nAdvisory only: verify RF/config before real change.', ...
        char(mlText));
end
end

function txt = build_ml_coc_incident_text(cocMlSelected, timestamp)
action = choose_episode_coc_action(cocMlSelected, timestamp);
if ~action.hasAction
    txt = "No positive-reward COC action selected for this episode.";
    return;
end
txt = sprintf(['COC action: target S%d, RS power %+g dB, eTilt %+g deg\n' ...
    'Affected sectors: %s\n' ...
    'Target load check: current PRB %.1f%%, estimated after COC %.1f%%, hard limit %.0f%%\n' ...
    'Target users check: current %.1f, estimated after COC %.1f\n' ...
    'ML evidence: %d positive rows, mean reward %.3f\n' ...
    'Episode window: %s to %s'], ...
    action.targetSector, action.deltaPrs, action.deltaTilt, char(action.affectedSectors), ...
    100 * action.targetLoad, 100 * action.estimatedTargetLoad, 100 * action.hardLoadLimit, ...
    action.targetUsers, action.estimatedTargetUsers, ...
    action.eventCount, action.meanReward, datestr(action.firstTimestamp, 'dd-mmm HH:MM'), ...
    datestr(action.lastTimestamp, 'dd-mmm HH:MM'));
end

function plot_snapshot_text_box(~, snapshotInfo, timestamp)
axis off;
if snapshotInfo.isIncident
    color = [0.62 0.10 0.10];
    edge = [0.78 0.12 0.12];
else
    color = [0.04 0.22 0.65];
    edge = [0.05 0.35 0.85];
end
boxText = sprintf('%s\n%s', datestr(timestamp, 'dd-mmm-yyyy HH:MM'), char(string(snapshotInfo.text)));
text(0.02, 0.95, boxText, 'Units', 'normalized', 'FontSize', 8, ...
    'Color', [0.18 0.18 0.18], 'FontWeight', 'bold', 'Interpreter', 'none', ...
    'BackgroundColor', 'w', 'Margin', 4, 'EdgeColor', edge, ...
    'VerticalAlignment', 'top');
end

function draw_baseline_sites(layout)
th = linspace(0, 2*pi, 121);
coverageRadius = 0.62;
for i = 1:height(layout.sites)
    x = layout.sites.site_x(i);
    y = layout.sites.site_y(i);
    patch(x + coverageRadius*cos(th), y + coverageRadius*sin(th), [0.86 0.93 0.92], ...
        'FaceAlpha', 0.28, 'EdgeColor', 'none');
    plot(x + 0.74*coverageRadius*cos(th), y + 0.74*coverageRadius*sin(th), ...
        '--', 'Color', [0.20 0.20 0.20], 'LineWidth', 0.9);
    scatter(x, y, 85, [0.10 0.35 0.75], '^', 'filled');
    text(x, y + 0.08, sprintf('Site %d', layout.sites.sim_site_id(i)), ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'FontSize', 8, 'FontWeight', 'bold', ...
        'Interpreter', 'none', 'BackgroundColor', 'w', 'Margin', 1);
end
end

function draw_sector_states(layout, T)
for i = 1:height(T)
    sectorId = T.sim_sector_id(i);
    loc = layout.sectors(layout.sectors.sim_sector_id == sectorId, :);
    if isempty(loc)
        continue;
    end
    state = string(T.cod_state{i});
    switch state
        case 'outage_like'
            c = [0.78 0.12 0.12];
            marker = 'o';
            sz = 95;
        case 'degraded_kpi'
            c = [0.93 0.58 0.12];
            marker = 'o';
            sz = 80;
        otherwise
            c = [0.38 0.70 0.38];
            marker = '.';
            sz = 45;
    end
    scatter(loc.sector_x, loc.sector_y, sz, c, marker, 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
    if state ~= "normal"
        text(loc.sector_x + 0.04, loc.sector_y + 0.04, sprintf('S%d', sectorId), ...
            'FontSize', 8, 'FontWeight', 'bold', 'Color', c, ...
            'Interpreter', 'none', 'BackgroundColor', 'w', 'Margin', 1);
    end
end
end

function suggestionLines = draw_coc_review_markers(layout, cocMlSelected, timestamp)
suggestionLines = strings(0, 1);
action = choose_episode_coc_action(cocMlSelected, timestamp);
if ~action.hasAction
    return;
end
tgt = layout.sectors(layout.sectors.sim_sector_id == action.targetSector, :);
if isempty(tgt)
    return;
end
scatter(tgt.sector_x, tgt.sector_y, 145, [0.05 0.35 0.85], 's', ...
    'LineWidth', 1.6, 'MarkerFaceColor', 'none');
text(tgt.sector_x + 0.05, tgt.sector_y - 0.07, sprintf('COC target S%d', action.targetSector), ...
    'FontSize', 8, 'FontWeight', 'bold', 'Color', [0.05 0.24 0.70], ...
    'Interpreter', 'none', 'BackgroundColor', 'w', 'Margin', 1);
suggestionLines = sprintf('Target S%d: %+g dB RS, %+g deg eTilt', ...
    action.targetSector, action.deltaPrs, action.deltaTilt);
end

function action = choose_episode_coc_action(cocMlSelected, timestamp)
action = struct('hasAction', false, 'targetSector', NaN, 'deltaPrs', NaN, ...
    'deltaTilt', NaN, 'eventCount', 0, 'meanReward', NaN, ...
    'firstTimestamp', NaT, 'lastTimestamp', NaT, 'affectedSectors', "", ...
    'targetLoad', NaN, 'estimatedTargetLoad', NaN, 'hardLoadLimit', 0.90, ...
    'targetUsers', NaN, 'estimatedTargetUsers', NaN);

if isempty(cocMlSelected)
    return;
end
status = string(cocMlSelected.ml_safety_status);
rows = cocMlSelected(isfinite(cocMlSelected.target_sim_sector_id) & ...
    cocMlSelected.predicted_reward > 0 & ...
    (contains(status, "candidate_for_manual_review") | ...
    contains(status, "site_outage_coc_ml_advisory") | contains(status, "conditional")), :);
if isempty(rows)
    return;
end

times = sort(unique(rows.timestamp));
idx = find(times == timestamp, 1);
if isempty(idx)
    return;
end
firstIdx = idx;
while firstIdx > 1 && minutes(times(firstIdx) - times(firstIdx - 1)) <= 30
    firstIdx = firstIdx - 1;
end
lastIdx = idx;
while lastIdx < numel(times) && minutes(times(lastIdx + 1) - times(lastIdx)) <= 30
    lastIdx = lastIdx + 1;
end
episodeRows = rows(rows.timestamp >= times(firstIdx) & rows.timestamp <= times(lastIdx), :);
if isempty(episodeRows)
    return;
end

[groups, targetSector, deltaPrs, deltaTilt] = findgroups(episodeRows.target_sim_sector_id, ...
    episodeRows.delta_prs_dB, episodeRows.delta_tilt_deg);
eventCount = splitapply(@numel, episodeRows.timestamp, groups);
meanReward = splitapply(@(x) mean(x, 'omitnan'), episodeRows.predicted_reward, groups);
episodeSummary = table(targetSector, deltaPrs, deltaTilt, eventCount, meanReward);
episodeSummary = sortrows(episodeSummary, {'eventCount','meanReward'}, {'descend','descend'});
best = episodeSummary(1, :);

bestRows = episodeRows(episodeRows.target_sim_sector_id == best.targetSector & ...
    episodeRows.delta_prs_dB == best.deltaPrs & episodeRows.delta_tilt_deg == best.deltaTilt, :);
sourceSectors = sort(unique(bestRows.source_sim_sector_id));

action.hasAction = true;
action.targetSector = best.targetSector;
action.deltaPrs = best.deltaPrs;
action.deltaTilt = best.deltaTilt;
action.eventCount = best.eventCount;
action.meanReward = best.meanReward;
action.firstTimestamp = min(bestRows.timestamp);
action.lastTimestamp = max(bestRows.timestamp);
action.affectedSectors = strjoin(compose('S%d', sourceSectors), ', ');
action.targetLoad = mean(read_optional_column(bestRows, 'target_sector_load'), 'omitnan');
action.estimatedTargetLoad = mean(read_optional_column(bestRows, 'estimated_target_load_after_coc'), 'omitnan');
action.hardLoadLimit = 0.90;
action.targetUsers = mean(read_optional_column(bestRows, 'target_active_users'), 'omitnan');
action.estimatedTargetUsers = mean(read_optional_column(bestRows, 'estimated_target_users_after_coc'), 'omitnan');
end

function values = read_optional_column(T, name)
if ismember(name, T.Properties.VariableNames)
    values = T.(name);
else
    values = nan(height(T), 1);
end
end

function draw_legend()
x0 = -1.40;
y0 = 1.23;
items = {
    [0.38 0.70 0.38], 'normal';
    [0.93 0.58 0.12], 'degraded';
    [0.78 0.12 0.12], 'outage-like';
    [0.05 0.35 0.85], 'COC suggestion arrow'};
for i = 1:size(items, 1)
    scatter(x0, y0 - 0.08*i, 50, items{i,1}, 'filled', 'MarkerEdgeColor', 'k');
    text(x0 + 0.06, y0 - 0.08*i, items{i,2}, 'FontSize', 8, ...
        'VerticalAlignment', 'middle', 'Interpreter', 'none');
end
end
