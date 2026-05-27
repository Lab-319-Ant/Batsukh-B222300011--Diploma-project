function actions = generate_coc_candidates(cfg, stateTable, neighbors)
%GENERATE_COC_CANDIDATES Candidate COC/OH compensation actions only.
%
% Trigger rule:
%   COC fires when at least one of the following holds:
%     (a) the sector is the ground-truth impaired sector for the
%         realization (is_target_impaired_sector) or has outage_label /
%         degraded_label set, OR
%     (b) the COD classifier predicts 'outage' or 'degraded' AND RF or
%         attach evidence corroborates impairment, OR
%     (c) cluster monitor flags the sector as a COC trigger candidate AND
%         RF or attach evidence corroborates impairment (low RSRP or
%         attach rate below cocLowAttachThreshold).
%
% The previous OR-only rule fired on any sector with attach_rate < 0.80,
% and the COD-only rule could over-generate COC candidates for low-load or
% handover-stress sectors. The corroboration requirement prevents COC from
% being treated as a generic KPI repair action when there is no coverage or
% attachment evidence.

predictedLabel = string(stateTable.cod_predicted_label);
clusterTrigger = string(stateTable.cluster_trigger_candidate);

groundTruthImpaired = stateTable.is_target_impaired_sector | ...
    stateTable.outage_label | stateTable.degraded_label;
rfWeak = stateTable.mean_RSRP_dBm <= cfg.cocLowRsrpThreshold_dBm;
attachLow = stateTable.attach_rate_sector < cfg.cocLowAttachThreshold;
codImpaired = (predictedLabel == "outage" | predictedLabel == "degraded") & (rfWeak | attachLow);
clusterCoc = contains(clusterTrigger, 'COC');

trigger = groundTruthImpaired | codImpaired | (clusterCoc & (rfWeak | attachLow));
sourceRows = stateTable(trigger, :);
cioValues = 0;
if cfg.enableCocCioCandidates
    cioValues = cfg.cocDeltaCIO_dB;
end
perSource = 1 + cfg.phase8TopNNeighbors * (numel(cfg.cocDeltaPRS_dB) * numel(cfg.cocDeltaTilt_deg) * numel(cioValues) - 1);
rows = cell(height(sourceRows) * perSource, width(empty_action_table()));
rowIdx = 0;

for i = 1:height(sourceRows)
    src = sourceRows(i, :);
    targetNeighbors = top_neighbors_for_sector(neighbors, src.sector_id, cfg.phase8TopNNeighbors);
    rowIdx = rowIdx + 1;
    rows(rowIdx, :) = make_action_cell(src, 'COC/OH', 'no_op', 0, 0, 0, 0, 0, 0, 0, 'COC no-op candidate');
    for n = targetNeighbors(:)'
        for p = cfg.cocDeltaPRS_dB
            for tilt = cfg.cocDeltaTilt_deg
                for cio = cioValues
                    if p == 0 && tilt == 0 && cio == 0
                        continue;
                    end
                    rowIdx = rowIdx + 1;
                    rows(rowIdx, :) = make_action_cell(src, 'COC/OH', 'compensate_neighbor', n, p, tilt, cio, 0, 0, 0, ...
                        'Increase neighbor coverage/steering candidate for impaired sector');
                end
            end
        end
    end
end
actions = action_cells_to_table(rows(1:rowIdx, :));
end
