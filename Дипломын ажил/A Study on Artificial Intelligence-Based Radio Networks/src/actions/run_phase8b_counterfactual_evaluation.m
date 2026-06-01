function phase8b = run_phase8b_counterfactual_evaluation(cfg)
%RUN_PHASE8B_COUNTERFACTUAL_EVALUATION Evaluate Phase 8A candidates offline.
%
% Phase 8B is counterfactual only. It estimates post-action KPI proxies and
% rewards for candidate actions without selecting an action, training an
% action-value model, applying an action to KPI(t+1), or running an oracle.

candidateFile = fullfile(cfg.tablesDir, 'phase8a_candidate_actions.csv');
stateFile = fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv');
if ~isfile(candidateFile)
    error('Missing Phase 8A candidate action table: %s', candidateFile);
end
if ~isfile(stateFile)
    error('Missing Phase 4 sector state table: %s', stateFile);
end

candidateActions = readtable(candidateFile);
sectorState = readtable(stateFile);

if isfield(cfg, 'phase8bMaxActions') && isfinite(cfg.phase8bMaxActions)
    candidateActions = candidateActions(1:min(height(candidateActions), cfg.phase8bMaxActions), :);
end

counterfactualTable = evaluate_counterfactual_action(cfg, candidateActions, sectorState);
counterfactualTable = join_dataset_keys(counterfactualTable, candidateActions);
summaryByModule = summarize_counterfactuals(counterfactualTable, {'module_name'});
summaryByScenario = summarize_counterfactuals(counterfactualTable, {'scenario_name','module_name'});

safetyTable = safety_check_action(cfg, counterfactualTable);
validationTable = validate_phase8b_counterfactuals(cfg, counterfactualTable, safetyTable);

writetable(counterfactualTable, fullfile(cfg.tablesDir, 'phase8b_counterfactual_action_table.csv'));
writetable(summaryByModule, fullfile(cfg.tablesDir, 'phase8b_counterfactual_summary_by_module.csv'));
writetable(summaryByScenario, fullfile(cfg.tablesDir, 'phase8b_counterfactual_summary_by_scenario.csv'));
writetable(safetyTable, fullfile(cfg.tablesDir, 'phase8b_safety_check.csv'));

phase8b = struct();
phase8b.counterfactualTable = counterfactualTable;
phase8b.summaryByModule = summaryByModule;
phase8b.summaryByScenario = summaryByScenario;
phase8b.safetyTable = safetyTable;
phase8b.validationTable = validationTable;
end

function out = join_dataset_keys(counterfactualTable, candidateActions)
%JOIN_DATASET_KEYS Ensure counterfactual rows expose dataset_id used by safety checker.
out = counterfactualTable;
if ismember('dataset_id', out.Properties.VariableNames)
    return;
end
keyCols = {'action_id','dataset_id'};
if all(ismember(keyCols, candidateActions.Properties.VariableNames))
    out = outerjoin(out, candidateActions(:, keyCols), ...
        'Keys', 'action_id', 'MergeKeys', true, 'Type', 'left');
end
end

function summaryTable = summarize_counterfactuals(T, groupVars)
if isempty(T)
    summaryTable = table();
    return;
end

if numel(groupVars) == 1
    [groups, groupValues{1}] = findgroups(T.(groupVars{1}));
else
    [groups, groupValues{1}, groupValues{2}] = findgroups(T.(groupVars{1}), T.(groupVars{2}));
end
candidate_count = splitapply(@numel, T.action_id, groups);
mean_reward = splitapply(@(x) mean(x, 'omitnan'), T.reward, groups);
median_reward = splitapply(@(x) median(x, 'omitnan'), T.reward, groups);
mean_delta_qos = splitapply(@(x) mean(x, 'omitnan'), T.delta_source_qos_satisfaction_ratio, groups);
mean_delta_load = splitapply(@(x) mean(x, 'omitnan'), T.delta_source_load_ratio, groups);
mean_delta_handover_risk = splitapply(@(x) mean(x, 'omitnan'), T.delta_source_handover_risk_score, groups);

summaryTable = table(groupValues{:}, candidate_count, mean_reward, median_reward, ...
    mean_delta_qos, mean_delta_load, mean_delta_handover_risk);
summaryTable.Properties.VariableNames = [groupVars, {'candidate_count','mean_reward', ...
    'median_reward','mean_delta_source_qos','mean_delta_source_load', ...
    'mean_delta_source_handover_risk'}];
end
