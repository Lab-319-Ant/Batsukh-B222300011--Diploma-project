function neighbors = find_neighbor_sectors(cfg, topology)
%FIND_NEIGHBOR_SECTORS Rank sectors using RF evidence and geometry.
%
% Distance-only ranking is too weak for LTE SON candidate generation because
% co-sited sectors have identical x/y coordinates. This routine uses the
% baseline UE locations to count second-best RSRP relations, then combines
% those counts with azimuth alignment and site geometry. Same-site sectors
% remain possible neighbors, but they are not ranked first only because
% their coordinate distance is zero.

sectors = topology.sectors;
numSectors = height(sectors);
ueEvidence = compute_second_best_ue_evidence(cfg, topology);

rows = cell(numSectors * (numSectors - 1), 17);
rowIdx = 0;
for i = 1:numSectors
    sourceSectorId = sectors.sectorId(i);
    sourceSiteId = sectors.siteId(i);
    sourceAz = sectors.azimuth_deg(i);

    maxSecondBest = max(ueEvidence.secondBestCount(i, :));
    maxBoundary = max(ueEvidence.boundarySecondBestCount(i, :));
    if maxSecondBest <= 0
        maxSecondBest = 1;
    end
    if maxBoundary <= 0
        maxBoundary = 1;
    end

    for j = 1:numSectors
        if i == j
            continue;
        end

        targetSectorId = sectors.sectorId(j);
        targetSiteId = sectors.siteId(j);
        targetAz = sectors.azimuth_deg(j);
        sameSite = sourceSiteId == targetSiteId;

        dx = sectors.x_m(j) - sectors.x_m(i);
        dy = sectors.y_m(j) - sectors.y_m(i);
        distance_m = sqrt(dx ^ 2 + dy ^ 2);

        if sameSite
            sourceAzOffset = abs(wrap_to_180(targetAz - sourceAz));
            targetAzOffset = sourceAzOffset;
            sourceAlign = 0;
            targetAlign = 0;
            distanceScore = 0.20;
            coSiteScore = max(0, 1 - abs(sourceAzOffset - 120) / 120);
            sameSitePenalty = 0.35;
        else
            sourceBearing = atan2d(dx, dy);
            targetBearing = atan2d(-dx, -dy);
            sourceAzOffset = abs(wrap_to_180(sourceBearing - sourceAz));
            targetAzOffset = abs(wrap_to_180(targetBearing - targetAz));
            sourceAlign = max(0, 1 - sourceAzOffset / 120);
            targetAlign = max(0, 1 - targetAzOffset / 120);
            distanceScore = 1 / (1 + distance_m / max(topology.ISD_m, eps));
            coSiteScore = 0;
            sameSitePenalty = 0;
        end

        secondBestCount = ueEvidence.secondBestCount(i, j);
        boundarySecondBestCount = ueEvidence.boundarySecondBestCount(i, j);
        rfSecondBestScore = secondBestCount / maxSecondBest;
        boundaryScore = boundarySecondBestCount / maxBoundary;

        neighborScore = 4.0 * rfSecondBestScore + ...
            2.0 * boundaryScore + ...
            1.2 * sourceAlign + ...
            0.8 * targetAlign + ...
            0.5 * distanceScore + ...
            0.4 * coSiteScore - ...
            sameSitePenalty;

        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = {sourceSectorId, targetSectorId, sourceSiteId, targetSiteId, ...
            sameSite, distance_m, sourceAz, targetAz, sourceAzOffset, targetAzOffset, ...
            secondBestCount, boundarySecondBestCount, rfSecondBestScore, boundaryScore, ...
            sourceAlign, targetAlign, neighborScore};
    end
end

neighbors = cell2table(rows(1:rowIdx, :), 'VariableNames', ...
    {'source_sector_id','neighbor_sector_id','source_site_id','neighbor_site_id', ...
    'is_same_site','distance_m','source_azimuth_deg','neighbor_azimuth_deg', ...
    'source_target_azimuth_offset_deg','target_source_azimuth_offset_deg', ...
    'ue_second_best_count','boundary_ue_second_best_count','rf_second_best_score', ...
    'boundary_second_best_score','source_alignment_score','target_alignment_score', ...
    'neighbor_score'});

neighbors = sortrows(neighbors, ...
    {'source_sector_id','neighbor_score','ue_second_best_count','boundary_ue_second_best_count','distance_m'}, ...
    {'ascend','descend','descend','descend','ascend'});

neighborRank = zeros(height(neighbors), 1);
for i = 1:numSectors
    idx = find(neighbors.source_sector_id == sectors.sectorId(i));
    neighborRank(idx) = (1:numel(idx))';
end
neighbors.neighbor_rank = neighborRank;
neighbors = movevars(neighbors, 'neighbor_rank', 'After', 'neighbor_sector_id');

if isfield(cfg, 'tablesDir')
    writetable(neighbors, fullfile(cfg.tablesDir, 'phase8a_neighbor_ranking.csv'));
end
end

function ueEvidence = compute_second_best_ue_evidence(cfg, topology)
numSectors = height(topology.sectors);
ueEvidence.secondBestCount = zeros(numSectors, numSectors);
ueEvidence.boundarySecondBestCount = zeros(numSectors, numSectors);

ueFile = fullfile(cfg.tablesDir, 'phase1b_ue_rf_results.csv');
if ~isfile(ueFile)
    return;
end

ueTable = readtable(ueFile);
if ~all(ismember({'x_m','y_m'}, ueTable.Properties.VariableNames))
    return;
end

rsrpMatrix = compute_rsrp_matrix_without_shadowing(cfg, topology, ueTable);
[sortedRsrp, sortedIdx] = sort(rsrpMatrix, 2, 'descend');
bestIdx = sortedIdx(:, 1);
secondIdx = sortedIdx(:, 2);
rsrpGap = sortedRsrp(:, 1) - sortedRsrp(:, 2);
boundaryThreshold = cfg.handoverMarginRisk_dB;
if isfield(cfg, 'handoverStressMarginRisk_dB')
    boundaryThreshold = max(boundaryThreshold, cfg.handoverStressMarginRisk_dB);
end

for u = 1:height(ueTable)
    src = bestIdx(u);
    tgt = secondIdx(u);
    ueEvidence.secondBestCount(src, tgt) = ueEvidence.secondBestCount(src, tgt) + 1;
    if rsrpGap(u) < boundaryThreshold
        ueEvidence.boundarySecondBestCount(src, tgt) = ueEvidence.boundarySecondBestCount(src, tgt) + 1;
    end
end
end

function rsrpMatrix = compute_rsrp_matrix_without_shadowing(cfg, topology, ueTable)
localCfg = cfg;
localCfg.shadowingEnabled = false;
numUE = height(ueTable);
numSectors = height(topology.sectors);
rsrpMatrix = zeros(numUE, numSectors);

for s = 1:numSectors
    dx = ueTable.x_m - topology.sectors.x_m(s);
    dy = ueTable.y_m - topology.sectors.y_m(s);
    d2D = sqrt(dx .^ 2 + dy .^ 2);
    pathLoss = calc_3gpp_uma_pathloss(localCfg, d2D, false);
    antennaGain = calc_antenna_gain(localCfg, topology.sectors.azimuth_deg(s), ...
        topology.sectors.electricalTilt_deg(s), dx, dy);

    refSignalPower_dBm = topology.sectors.refSignalPower_dBm(s) + ...
        get_sector_offset(topology.sectors, s, 'referencePowerOffset_dB');
    rsrpMatrix(:, s) = refSignalPower_dBm + antennaGain + cfg.ueAntennaGain_dBi ...
        - pathLoss - cfg.cableLoss_dB - cfg.bodyLoss_dB;
end
end

function offset_dB = get_sector_offset(sectors, rowIdx, varName)
if ismember(varName, sectors.Properties.VariableNames)
    offset_dB = sectors.(varName)(rowIdx);
else
    offset_dB = 0;
end
end

function wrapped = wrap_to_180(angle_deg)
wrapped = mod(angle_deg + 180, 360) - 180;
end
