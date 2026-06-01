function [selectionPreview, regretPreview] = select_best_predicted_actions(moduleTable, predictionTable, moduleName)
%SELECT_BEST_PREDICTED_ACTIONS Offline action ranking preview vs oracle.
%
% For every oracle group in the test split:
%   1) Predict reward for all candidate actions in the group.
%   2) Select the top-1 (and top-2) predicted-reward rows.
%   3) Compare with the oracle-selected action_id.
%   4) Compute regret = oracle_reward - true_reward_of_top1_predicted.
%
% This is OFFLINE ranking only. It does not apply actions, does not
% touch the simulator, does not produce KPI(t+1).
%
% Inputs:
%   moduleTable     - the Phase 9A per-module dataset (rows include
%                     oracle_group_id, oracle_selected, etc.)
%   predictionTable - rows from evaluate_action_value_regressor with
%                     split == 'test'
%   moduleName      - module identifier ('COC/OH', 'LB/MLB', 'ES', 'HO/MRO')

selectionPreview = empty_selection_table();
regretPreview = empty_regret_table();
if isempty(predictionTable)
    return;
end
testPredictions = predictionTable(strcmp(predictionTable.split, 'test'), :);
if isempty(testPredictions)
    return;
end

% Restrict to test rows that have an oracle group.
hasGroup = ~isnan(testPredictions.oracle_group_id);
testPredictions = testPredictions(hasGroup, :);
if isempty(testPredictions)
    return;
end

% Build a lookup from action_id to safety_valid and is_no_op in the
% module table.
[~, idx] = ismember(testPredictions.action_id, moduleTable.action_id);
matched = idx > 0;
moduleSafetyValid = false(height(testPredictions), 1);
moduleIsNoOp = false(height(testPredictions), 1);
if any(matched)
    moduleSafetyValid(matched) = logical(moduleTable.safety_valid(idx(matched)));
    moduleIsNoOp(matched) = logical(moduleTable.is_no_op(idx(matched))) | ...
        (string(moduleTable.module_name(idx(matched))) == "ES" & ...
         string(moduleTable.action_type(idx(matched))) == "keep_active");
end
testPredictions.safety_valid_lookup = moduleSafetyValid;
testPredictions.is_no_op_lookup = moduleIsNoOp;

groups = unique(testPredictions.oracle_group_id);
nGroups = numel(groups);

selRows = cell(nGroups, 11);
regretRows = cell(nGroups, 9);

for g = 1:nGroups
    gid = groups(g);
    rows = testPredictions(testPredictions.oracle_group_id == gid, :);
    if isempty(rows)
        continue;
    end

    [~, sortIdx] = sort(rows.predicted_reward, 'descend');
    rows = rows(sortIdx, :);
    top1 = rows(1, :);
    if height(rows) >= 2
        top2Ids = rows.action_id(1:2);
    else
        top2Ids = rows.action_id(1);
    end

    oracleMask = rows.oracle_selected;
    if any(oracleMask)
        oracleRow = rows(find(oracleMask, 1, 'first'), :);
    else
        oracleRow = rows(1, :);
    end

    matchTop1 = double(top1.action_id == oracleRow.action_id);
    matchTop2 = double(any(top2Ids == oracleRow.action_id));
    regret = oracleRow.actual_reward - top1.actual_reward;

    selRows(g, :) = {moduleName, gid, char(string(top1.scenario_name)), ...
        top1.realization_id, top1.source_sector_id, top1.action_id, ...
        char(string(top1.action_type)), oracleRow.action_id, ...
        matchTop1, matchTop2, logical(top1.safety_valid_lookup)};
    regretRows(g, :) = {moduleName, gid, char(string(top1.scenario_name)), ...
        top1.realization_id, top1.source_sector_id, top1.action_id, ...
        oracleRow.actual_reward, top1.actual_reward, regret};
end

selRows = selRows(~cellfun('isempty', selRows(:, 1)), :);
regretRows = regretRows(~cellfun('isempty', regretRows(:, 1)), :);

if ~isempty(selRows)
    selectionPreview = cell2table(selRows, 'VariableNames', ...
        {'module_name','oracle_group_id','scenario_name','realization_id', ...
        'source_sector_id','top1_predicted_action_id','top1_action_type', ...
        'oracle_selected_action_id','oracle_match_top1','oracle_match_top2', ...
        'selected_action_safety_valid'});
end
if ~isempty(regretRows)
    regretPreview = cell2table(regretRows, 'VariableNames', ...
        {'module_name','oracle_group_id','scenario_name','realization_id', ...
        'source_sector_id','top1_predicted_action_id','oracle_reward', ...
        'predicted_selected_true_reward','regret'});
end
end

function T = empty_selection_table()
T = table('Size', [0 11], ...
    'VariableTypes', {'cell','double','cell','double','double','double','cell','double','double','double','logical'}, ...
    'VariableNames', {'module_name','oracle_group_id','scenario_name', ...
    'realization_id','source_sector_id','top1_predicted_action_id', ...
    'top1_action_type','oracle_selected_action_id','oracle_match_top1', ...
    'oracle_match_top2','selected_action_safety_valid'});
end

function T = empty_regret_table()
T = table('Size', [0 9], ...
    'VariableTypes', {'cell','double','cell','double','double','double','double','double','double'}, ...
    'VariableNames', {'module_name','oracle_group_id','scenario_name', ...
    'realization_id','source_sector_id','top1_predicted_action_id', ...
    'oracle_reward','predicted_selected_true_reward','regret'});
end
