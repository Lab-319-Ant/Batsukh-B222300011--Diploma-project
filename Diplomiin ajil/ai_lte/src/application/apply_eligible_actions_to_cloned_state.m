function clonedTopology = apply_eligible_actions_to_cloned_state(baseTopology, groupActions)
%APPLY_ELIGIBLE_ACTIONS_TO_CLONED_STATE Apply a group's eligible actions to a clone.
%
% Inputs:
%   baseTopology - topology BEFORE actions (must already have Phase 12B
%                  state columns initialized).
%   groupActions - table subset; one row per eligible action in this
%                  (scenario, realization) group.
%
% Output:
%   clonedTopology - new topology struct with all actions applied. The
%   input baseTopology is NEVER mutated (MATLAB tables are copy-on-write
%   and apply_single_action_to_cloned_state preserves the original).

clonedTopology = baseTopology;
if isempty(groupActions)
    return;
end
for r = 1:height(groupActions)
    actionRow = groupActions(r, :);
    clonedTopology = apply_single_action_to_cloned_state(clonedTopology, actionRow);
end
end
