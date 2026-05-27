function selectionTable = select_safety_enforced_ml_actions(joinedTable)
%SELECT_SAFETY_ENFORCED_ML_ACTIONS Pick raw top-1 and safety-enforced top-1.
%
% Input:
%   joinedTable - per-candidate-action rows for one or more decision
%                 groups, must contain at least:
%                   action_id, oracle_group_id, scenario_name,
%                   realization_id, source_sector_id, target_sector_id,
%                   module_name, action_type, predicted_reward,
%                   actual_reward, is_no_op, safety_is_unsafe,
%                   delta_prs_dB, delta_tilt_deg, delta_cio_dB,
%                   delta_hom_dB, delta_ttt_ms, es_action
%
% Output:
%   selectionTable - one row per (oracle_group_id) decision group with
%   the raw-top-1 and safety-enforced selected action recorded, along
%   with the fields required by the Phase 10A output schema.

selectionTable = empty_selection_schema();
if isempty(joinedTable)
    return;
end

T = joinedTable;
T.module_name = string(T.module_name);
T.action_type = string(T.action_type);
T.scenario_name = string(T.scenario_name);
T.es_action = string(T.es_action);

isFunctionalNoOp = logical(T.is_no_op) | ...
    (T.module_name == "ES" & T.action_type == "keep_active");
T.is_functional_noop = isFunctionalNoOp;

[uniqueGroups, ~, idx] = unique(T.oracle_group_id, 'stable');
nGroups = numel(uniqueGroups);
rows = cell(nGroups, 28);

for g = 1:nGroups
    members = find(idx == g);
    grpRows = T(members, :);

    [~, sortIdx] = sort(grpRows.predicted_reward, 'descend');
    grpRows = grpRows(sortIdx, :);

    rawTop1 = grpRows(1, :);
    rawUnsafe = logical(rawTop1.safety_is_unsafe);

    safeMask = ~logical(grpRows.safety_is_unsafe);
    if any(safeMask)
        safeCandidates = grpRows(safeMask, :);
        safeTop1 = safeCandidates(1, :);
        selectionReason = "safe_best_predicted";
        fallbackUsed = false;
        noopSelected = logical(safeTop1.is_functional_noop);
    else
        % No safe candidate. Prefer a (possibly unsafe) no-op fallback.
        noopMask = grpRows.is_functional_noop;
        if any(noopMask)
            noopCandidates = grpRows(noopMask, :);
            safeTop1 = noopCandidates(1, :);
            selectionReason = "no_safe_action_fallback_noop";
            fallbackUsed = true;
            noopSelected = true;
        else
            safeTop1 = rawTop1;
            selectionReason = "no_safe_action_available_unsafe_fallback";
            fallbackUsed = true;
            noopSelected = false;
        end
    end

    safetyFilterChanged = rawTop1.action_id ~= safeTop1.action_id;

    rows(g, :) = {uniqueGroups(g), ...
        char(rawTop1.scenario_name), rawTop1.realization_id, ...
        rawTop1.source_sector_id, safeTop1.target_sector_id, ...
        char(rawTop1.module_name), ...
        rawTop1.action_id, safeTop1.action_id, ...
        char(rawTop1.action_type), char(safeTop1.action_type), ...
        rawTop1.predicted_reward, safeTop1.predicted_reward, ...
        rawTop1.actual_reward, safeTop1.actual_reward, ...
        ~rawUnsafe, ~logical(safeTop1.safety_is_unsafe), ...
        safetyFilterChanged, fallbackUsed, noopSelected, ...
        char(selectionReason), ...
        safeTop1.delta_prs_dB, safeTop1.delta_tilt_deg, safeTop1.delta_cio_dB, ...
        safeTop1.delta_hom_dB, safeTop1.delta_ttt_ms, char(safeTop1.es_action), ...
        rawTop1.action_id, safeTop1.action_id};
end

selectionTable = cell2table(rows, 'VariableNames', ...
    {'oracle_group_id','scenario_name','realization_id','source_sector_id', ...
    'target_sector_id','module_name','selected_action_id_raw','selected_action_id_safe', ...
    'raw_action_type','safe_action_type','raw_predicted_reward','safe_predicted_reward', ...
    'raw_true_reward','safe_true_reward','raw_selected_safety_valid', ...
    'safe_selected_safety_valid','safety_filter_changed_action','fallback_used', ...
    'noop_selected','selection_reason','delta_prs_dB','delta_tilt_deg', ...
    'delta_cio_dB','delta_hom_dB','delta_ttt_ms','es_action', ...
    'raw_action_id_for_top2','safe_action_id_for_top2'});
end

function T = empty_selection_schema()
T = table('Size', [0 28], ...
    'VariableTypes', {'double','cell','double','double','double','cell','double','double', ...
    'cell','cell','double','double','double','double','logical','logical','logical','logical', ...
    'logical','cell','double','double','double','double','double','cell','double','double'}, ...
    'VariableNames', {'oracle_group_id','scenario_name','realization_id','source_sector_id', ...
    'target_sector_id','module_name','selected_action_id_raw','selected_action_id_safe', ...
    'raw_action_type','safe_action_type','raw_predicted_reward','safe_predicted_reward', ...
    'raw_true_reward','safe_true_reward','raw_selected_safety_valid', ...
    'safe_selected_safety_valid','safety_filter_changed_action','fallback_used', ...
    'noop_selected','selection_reason','delta_prs_dB','delta_tilt_deg', ...
    'delta_cio_dB','delta_hom_dB','delta_ttt_ms','es_action', ...
    'raw_action_id_for_top2','safe_action_id_for_top2'});
end
