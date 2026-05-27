function [resolutionLog, candidateActions, rejectedLog] = resolve_action_conflicts(inputTable, conflictLog)
%RESOLVE_ACTION_CONFLICTS Apply priority + safety rules to Phase 11A inputs.
%
% Outputs:
%   resolutionLog    - one row per resolved conflict
%   candidateActions - one row per input action with accepted/rejected flag
%   rejectedLog      - one row per rejected action with reason

resolutionLog = build_empty_resolution();
rejectedLog = build_empty_rejected();
candidateActions = init_candidates(inputTable);
if isempty(inputTable)
    return;
end

n = height(inputTable);
accepted = true(n, 1);
rejectionReason = strings(n, 1);
rejectionType = strings(n, 1);
rejectedByModule = strings(n, 1);
rejectedConflictId = nan(n, 1);
safetyRelated = false(n, 1);

errorConflicts = conflictLog(strcmp(conflictLog.severity, 'error'), :);
errorConflicts = sortrows(errorConflicts, 'conflict_id');

for i = 1:height(errorConflicts)
    c = errorConflicts(i, :);
    [winnerIdx, loserIdx] = pick_winner(inputTable, c);
    if isnan(loserIdx) || ~accepted(loserIdx)
        continue;
    end
    accepted(loserIdx) = false;
    rejectionReason(loserIdx) = string(c.conflict_reason{1});
    rejectionType(loserIdx) = string(c.conflict_type{1});
    rejectedConflictId(loserIdx) = c.conflict_id;
    if isnan(winnerIdx)
        rejectedByModule(loserIdx) = "";
    else
        rejectedByModule(loserIdx) = string(inputTable.module_name{winnerIdx});
    end
    safetyRelated(loserIdx) = is_safety_related(c.conflict_type{1});

    resolutionLog = append_resolution(resolutionLog, c, inputTable, winnerIdx, loserIdx);
end

candidateActions.accepted_flag = accepted;
candidateActions.rejected_flag = ~accepted;
candidateActions.rejection_reason = cellstr(rejectionReason);
candidateActions.rejection_type = cellstr(rejectionType);

[~, ~, gIdx] = unique(candidateActions.coordinator_group_id, 'stable');
candidateActions.final_candidate_rank = zeros(height(candidateActions), 1);
for g = unique(gIdx)'
    members = find(gIdx == g & accepted);
    if isempty(members), continue; end
    [~, ord] = sort(candidateActions.module_priority(members), 'ascend');
    candidateActions.final_candidate_rank(members(ord)) = 1:numel(members);
end

candidateActions.not_applied_flag = true(height(candidateActions), 1);

rejectedRows = find(~accepted);
for k = 1:numel(rejectedRows)
    r = rejectedRows(k);
    row = {inputTable.selected_action_id_safe(r), inputTable.module_name{r}, ...
        inputTable.scenario_name{r}, inputTable.realization_id(r), ...
        char(rejectionReason(r)), char(rejectionType(r)), ...
        rejectedConflictId(r), char(rejectedByModule(r)), safetyRelated(r)};
    rejectedLog = [rejectedLog; cell2table(row, 'VariableNames', rejectedLog.Properties.VariableNames)]; %#ok<AGROW>
end
end

function candidates = init_candidates(T)
if isempty(T)
    candidates = table();
    return;
end
candidates = table(T.coordinator_group_id, T.scenario_name, T.realization_id, ...
    T.module_name, T.selected_action_id_safe, T.safe_action_type, ...
    T.decision_source_sector_id, T.decision_target_sector_id, ...
    T.source_sector_id, T.target_sector_id, ...
    T.coordinator_affected_sector_id, T.application_affected_sector_id, ...
    T.application_state_variable, T.affected_parameter, ...
    true(height(T), 1), false(height(T), 1), ...
    repmat({''}, height(T), 1), ...
    T.module_priority, zeros(height(T), 1), ...
    true(height(T), 1), repmat({''}, height(T), 1), ...
    'VariableNames', {'coordinator_group_id','scenario_name','realization_id', ...
    'module_name','accepted_action_id','accepted_action_type', ...
    'decision_source_sector_id','decision_target_sector_id', ...
    'source_sector_id','target_sector_id', ...
    'coordinator_affected_sector_id','application_affected_sector_id', ...
    'application_state_variable','affected_parameter', ...
    'accepted_flag','rejected_flag','rejection_reason', ...
    'module_priority','final_candidate_rank','not_applied_flag','rejection_type'});
end

function [winnerIdx, loserIdx] = pick_winner(T, conflict)
moduleA = conflict.module_a{1};
moduleB = conflict.module_b{1};
aId = conflict.action_id_a;
bId = conflict.action_id_b;
ctype = conflict.conflict_type{1};

idxA = find_action_idx(T, aId);
idxB = find_action_idx(T, bId);

switch ctype
    case 'unsafe_non_fallback'
        winnerIdx = NaN;
        loserIdx = idxA;
        return;
    case 'es_sleep_overlap'
        if strcmp(moduleA, 'ES')
            loserIdx = idxA; winnerIdx = idxB;
        else
            loserIdx = idxB; winnerIdx = idxA;
        end
        return;
    case 'lb_into_risky_target'
        if strcmp(moduleA, 'LB/MLB')
            loserIdx = idxA; winnerIdx = idxB;
        else
            loserIdx = idxB; winnerIdx = idxA;
        end
        return;
    case 'duplicate_application_target_parameter'
        % Fall through to deployment-style priority / predicted-reward rule.
end

% Default: priority-based (smaller number = higher priority).
if isnan(idxA) || isnan(idxB)
    winnerIdx = NaN; loserIdx = NaN;
    return;
end
pA = T.module_priority(idxA);
pB = T.module_priority(idxB);
if pA < pB
    winnerIdx = idxA; loserIdx = idxB;
elseif pB < pA
    winnerIdx = idxB; loserIdx = idxA;
else
    % Same priority (often two rows from the same module on the same
    % application target). Prefer higher predicted reward; deterministic
    % final tie-break is the lower selected_action_id_safe. Do not use
    % true_reward here because the deployment-style coordinator would not
    % know the realized post-action reward.
    if T.predicted_reward(idxA) > T.predicted_reward(idxB)
        winnerIdx = idxA; loserIdx = idxB;
    elseif T.predicted_reward(idxB) > T.predicted_reward(idxA)
        winnerIdx = idxB; loserIdx = idxA;
    elseif T.selected_action_id_safe(idxA) <= T.selected_action_id_safe(idxB)
        winnerIdx = idxA; loserIdx = idxB;
    else
        winnerIdx = idxB; loserIdx = idxA;
    end
end
end

function idx = find_action_idx(T, actionId)
hit = find(T.selected_action_id_safe == actionId, 1, 'first');
if isempty(hit)
    idx = NaN;
else
    idx = hit;
end
end

function tf = is_safety_related(conflictType)
tf = any(strcmp(conflictType, {'unsafe_non_fallback','es_sleep_overlap','lb_into_risky_target'}));
end

function log = append_resolution(log, conflict, T, winnerIdx, loserIdx)
winningModule = '';
rejectedModule = '';
winningActionId = NaN;
rejectedActionId = NaN;
safetyValidAfter = true;
if ~isnan(winnerIdx)
    winningModule = T.module_name{winnerIdx};
    winningActionId = T.selected_action_id_safe(winnerIdx);
    safetyValidAfter = safetyValidAfter & logical(T.safe_selected_safety_valid(winnerIdx));
end
if ~isnan(loserIdx)
    rejectedModule = T.module_name{loserIdx};
    rejectedActionId = T.selected_action_id_safe(loserIdx);
end
row = {conflict.coordinator_group_id, conflict.conflict_id, ...
    winningModule, rejectedModule, winningActionId, rejectedActionId, ...
    map_resolution_rule(conflict.conflict_type{1}), ...
    conflict.conflict_reason{1}, safetyValidAfter};
log = [log; cell2table(row, 'VariableNames', log.Properties.VariableNames)];
end

function rule = map_resolution_rule(ctype)
switch ctype
    case 'unsafe_non_fallback',         rule = 'reject_unsafe_non_fallback';
    case 'same_sector_same_parameter',  rule = 'priority_wins_same_param';
    case 'duplicate_application_target_parameter', rule = 'priority_or_predicted_reward_wins_duplicate_application_target';
    case 'es_sleep_overlap',            rule = 'reject_es_sleep_overlap';
    case 'lb_into_risky_target',        rule = 'reject_lb_to_risky_target';
    case 'cross_cell_counteracting',    rule = 'priority_wins_counteracting_cross_cell';
    otherwise,                          rule = 'no_rejection';
end
end

function T = build_empty_resolution()
T = table('Size', [0 9], ...
    'VariableTypes', {'double','double','cell','cell','double','double','cell','cell','logical'}, ...
    'VariableNames', {'coordinator_group_id','conflict_id','winning_module', ...
    'rejected_module','winning_action_id','rejected_action_id', ...
    'resolution_rule','resolution_reason','safety_valid_after_resolution'});
end

function T = build_empty_rejected()
T = table('Size', [0 9], ...
    'VariableTypes', {'double','cell','cell','double','cell','cell','double','cell','logical'}, ...
    'VariableNames', {'rejected_action_id','module_name','scenario_name','realization_id', ...
    'rejection_reason','rejection_type','conflict_id','rejected_by_module','safety_related_flag'});
end
