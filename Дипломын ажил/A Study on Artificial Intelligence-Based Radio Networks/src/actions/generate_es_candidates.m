function actions = generate_es_candidates(cfg, stateTable)
%GENERATE_ES_CANDIDATES Candidate ES keep/sleep/wake actions only.
%
% Trigger: sector_load_ratio < cfg.esLowLoadThreshold OR es_candidate.
%
% Safety gate (applied at generation, not just at safety check):
%   ES 'sleep' candidates are not generated for sectors that show any
%   impairment evidence:
%     - outage_label, degraded_label, or is_target_impaired_sector set
%     - COD classifier predicts 'outage' or 'degraded'
%     - mean_RSRP <= cocLowRsrpThreshold_dBm (weak coverage)
%     - attach_rate_sector < cocLowAttachThreshold (weak attachment)
%   This matches the impairment predicate used by safety_check_action so
%   the Phase 8B safety validation cannot flag any ES-sleep-on-impaired
%   row (the rows simply do not exist).
%
% 'keep_active' and 'wake_up' candidates are still generated for all
% triggered sources, including impaired ones.

trigger = stateTable.sector_load_ratio < cfg.esLowLoadThreshold | stateTable.es_candidate;
sourceRows = stateTable(trigger, :);
if isempty(sourceRows)
    actions = action_cells_to_table({});
    return;
end

impairedMask = compute_impaired_mask(cfg, sourceRows);

esActions = cfg.esActions;
maxRows = height(sourceRows) * numel(esActions);
rows = cell(maxRows, width(empty_action_table()));
rowIdx = 0;

for i = 1:height(sourceRows)
    src = sourceRows(i, :);
    for a = 1:numel(esActions)
        actionType = esActions{a};
        if strcmp(actionType, 'sleep') && impairedMask(i)
            continue;
        end
        rowIdx = rowIdx + 1;
        rows(rowIdx, :) = make_action_cell(src, 'ES', actionType, src.sector_id, 0, 0, 0, 0, 0, ...
            strcmp(actionType, 'sleep'), ...
            'Energy-saving candidate; safety will be evaluated later');
    end
end
actions = action_cells_to_table(rows(1:rowIdx, :));
end

function mask = compute_impaired_mask(cfg, sourceRows)
n = height(sourceRows);
mask = false(n, 1);
vars = sourceRows.Properties.VariableNames;

if ismember('outage_label', vars)
    mask = mask | logical(sourceRows.outage_label);
end
if ismember('degraded_label', vars)
    mask = mask | logical(sourceRows.degraded_label);
end
if ismember('is_target_impaired_sector', vars)
    mask = mask | logical(sourceRows.is_target_impaired_sector);
end
if ismember('cod_predicted_label', vars)
    predicted = string(sourceRows.cod_predicted_label);
    mask = mask | predicted == "outage" | predicted == "degraded";
end
if ismember('mean_RSRP_dBm', vars)
    mask = mask | sourceRows.mean_RSRP_dBm <= cfg.cocLowRsrpThreshold_dBm;
end
if ismember('attach_rate_sector', vars)
    mask = mask | sourceRows.attach_rate_sector < cfg.cocLowAttachThreshold;
end
end
