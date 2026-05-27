function candidateActions = generate_candidate_actions(cfg, topology, stateTable)
%GENERATE_CANDIDATE_ACTIONS Combine module-specific candidate action rows.

neighbors = find_neighbor_sectors(cfg, topology);
coc = generate_coc_candidates(cfg, stateTable, neighbors);
lb = generate_lb_candidates(cfg, stateTable, neighbors);
es = generate_es_candidates(cfg, stateTable);
mro = generate_mro_candidates(cfg, stateTable, neighbors);

candidateActions = [coc; lb; es; mro];
if ~isempty(candidateActions)
    candidateActions.action_id = (1:height(candidateActions))';
    candidateActions = movevars(candidateActions, 'action_id', 'Before', 1);
end
end
