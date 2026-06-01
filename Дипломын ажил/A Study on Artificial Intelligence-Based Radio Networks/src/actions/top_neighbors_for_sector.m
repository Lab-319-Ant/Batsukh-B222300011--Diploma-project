function neighborIds = top_neighbors_for_sector(neighbors, sectorId, topN)
%TOP_NEIGHBORS_FOR_SECTOR Return top-N neighbor sector IDs.

idx = neighbors.source_sector_id == sectorId;
rows = sortrows(neighbors(idx, :), 'neighbor_rank');
neighborIds = rows.neighbor_sector_id(1:min(topN, height(rows)));
end
