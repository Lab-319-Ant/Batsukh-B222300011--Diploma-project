function actions = generate_mro_candidates(cfg, stateTable, neighbors)
%GENERATE_MRO_CANDIDATES Candidate HO/MRO parameter actions only.

trigger = stateTable.handover_risk_score > cfg.mroHandoverRiskThreshold;
sourceRows = stateTable(trigger, :);
perSource = 1 + cfg.phase8TopNNeighbors * (numel(cfg.mroDeltaHOM_dB) * numel(cfg.mroDeltaTTT_ms) * numel(cfg.mroDeltaCIO_dB) - 1);
rows = cell(height(sourceRows) * perSource, width(empty_action_table()));
rowIdx = 0;

for i = 1:height(sourceRows)
    src = sourceRows(i, :);
    neighborIds = top_neighbors_for_sector(neighbors, src.sector_id, cfg.phase8TopNNeighbors);
    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = make_action_cell(src, 'HO/MRO', 'no_op', 0, 0, 0, 0, 0, 0, 0, 'MRO no-op candidate');
    for n = neighborIds(:)'
        for hom = cfg.mroDeltaHOM_dB
            for ttt = cfg.mroDeltaTTT_ms
                for cio = cfg.mroDeltaCIO_dB
                    if hom == 0 && ttt == 0 && cio == 0
                        continue;
                    end
                    rowIdx = rowIdx + 1;
                    rows(rowIdx, :) = make_action_cell(src, 'HO/MRO', 'handover_parameter_adjustment', n, 0, 0, cio, hom, ttt, 0, ...
                        'HOM/TTT/CIO candidate for handover-risk sector');
                end
            end
        end
    end
end
actions = action_cells_to_table(rows(1:rowIdx, :));
end
