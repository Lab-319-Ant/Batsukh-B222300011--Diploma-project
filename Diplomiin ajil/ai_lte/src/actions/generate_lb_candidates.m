function actions = generate_lb_candidates(cfg, stateTable, neighbors)
%GENERATE_LB_CANDIDATES Candidate LB/MLB CIO-bias actions only.

trigger = stateTable.sector_load_ratio > cfg.lbOverloadThreshold | ...
    stateTable.overload_flag | contains(string(stateTable.cluster_trigger_candidate), 'LB/MLB');
sourceRows = stateTable(trigger, :);
perSource = 1 + cfg.phase8TopNNeighbors * (numel(cfg.lbDeltaCIO_dB) - 1);
rows = cell(height(sourceRows) * perSource, width(empty_action_table()));
rowIdx = 0;

for i = 1:height(sourceRows)
    src = sourceRows(i, :);
    neighborIds = top_neighbors_for_sector(neighbors, src.sector_id, cfg.phase8TopNNeighbors);
    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = make_action_cell(src, 'LB/MLB', 'no_op', 0, 0, 0, 0, 0, 0, 0, 'LB no-op candidate');
    for n = neighborIds(:)'
        for cio = cfg.lbDeltaCIO_dB
            if cio == 0
                continue;
            end
            rowIdx = rowIdx + 1;
            rows(rowIdx, :) = make_action_cell(src, 'LB/MLB', 'cio_bias_to_neighbor', n, 0, 0, cio, 0, 0, 0, ...
                'CIO bias candidate from overloaded source toward neighbor');
        end
    end
end
actions = action_cells_to_table(rows(1:rowIdx, :));
end
