function candidateActions = validate_candidate_action_table(candidateActions)
%VALIDATE_CANDIDATE_ACTION_TABLE Normalize candidate action table types.

if isempty(candidateActions)
    return;
end
candidateActions.module_name = cellstr(string(candidateActions.module_name));
candidateActions.action_type = cellstr(string(candidateActions.action_type));
candidateActions.scenario_name = cellstr(string(candidateActions.scenario_name));
candidateActions.notes = cellstr(string(candidateActions.notes));
end
