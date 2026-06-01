function validationTable = validate_phase8b_counterfactuals(cfg, counterfactualTable, safetyTable)
%VALIDATE_PHASE8B_COUNTERFACTUALS Phase 8B reward and safety diagnostics.
%
% Writes results/tables/phase8b_counterfactual_validation.csv. Each row is
% one check or diagnostic metric. The table is intentionally long-form so
% per-module and per-scenario summaries live next to pass/fail checks.

rows = {};
n = height(counterfactualTable);

rows = add_row(rows, 'total_evaluated_actions', 'diagnostic', true, ...
    fmt_int(n), 'n/a', 'Total Phase 8B counterfactual rows.');

% NaN/Inf reward counts.
reward = counterfactualTable.reward;
nanCount = sum(~isfinite(reward) & ~isnan(reward) | isnan(reward));
finiteMask = isfinite(reward);
rows = add_row(rows, 'reward_nan_or_inf_count', 'error', nanCount == 0, ...
    fmt_int(nanCount), '== 0', 'Reward must be a finite real number for every row.');

% Duplicate action rows. action_id is unique by construction (assigned as
% (1:height(candidateActions))') so it cannot detect semantic duplicates.
% A semantic duplicate is the SAME action (same source/target, same
% module, same action type, same parameter deltas, same sleep/no-op
% flags) evaluated in the SAME realization. The key below makes that
% explicit.
semanticKeyVars = {'dataset_id','scenario_id','realization_id', ...
    'source_sector_id','target_sector_id','module_name','action_type', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms', ...
    'sleep_flag','is_no_op'};
missingKeyVars = setdiff(semanticKeyVars, counterfactualTable.Properties.VariableNames);
if ~isempty(missingKeyVars)
    rows = add_row(rows, 'duplicate_action_row_count', 'error', false, ...
        sprintf('missing columns: %s', strjoin(missingKeyVars, ', ')), '== 0', ...
        'Counterfactual table must carry the full semantic action key for duplicate detection.');
else
    keys = build_semantic_key(counterfactualTable, semanticKeyVars);
    dupCount = numel(keys) - numel(unique(keys));
    rows = add_row(rows, 'duplicate_action_row_count', 'error', dupCount == 0, ...
        fmt_int(dupCount), '== 0', ...
        'No duplicated (dataset, scenario, realization, source, target, module, action_type, deltas, sleep_flag, is_no_op) rows.');
end

% Also surface the row identifier independently. action_id should still be
% unique by construction; if it is not, candidate generation has a bug.
actionIds = counterfactualTable.action_id;
actionIdDup = numel(actionIds) - numel(unique(actionIds));
rows = add_row(rows, 'action_id_uniqueness_check', 'error', actionIdDup == 0, ...
    fmt_int(actionIdDup), '== 0', ...
    'action_id is a row identifier only; it must be unique by construction.');

% Invalid actions (safety stub).
invalidCount = 0;
if ~isempty(safetyTable)
    invalidCount = sum(safetyTable.safety_is_unsafe);
end
rows = add_row(rows, 'safety_invalid_action_count', 'diagnostic', true, ...
    fmt_int(invalidCount), 'n/a', 'Actions flagged by safety_check_action as unsafe.');

% Reward min/mean/max overall.
if any(finiteMask)
    rows = add_row(rows, 'reward_min_overall', 'diagnostic', true, ...
        fmt_num(min(reward(finiteMask))), 'n/a', 'Minimum reward across all candidates.');
    rows = add_row(rows, 'reward_mean_overall', 'diagnostic', true, ...
        fmt_num(mean(reward(finiteMask))), 'n/a', 'Mean reward across all candidates.');
    rows = add_row(rows, 'reward_max_overall', 'diagnostic', true, ...
        fmt_num(max(reward(finiteMask))), 'n/a', 'Maximum reward across all candidates.');
end

% Per-module reward stats.
moduleNames = unique(string(counterfactualTable.module_name));
for k = 1:numel(moduleNames)
    mName = moduleNames(k);
    idx = string(counterfactualTable.module_name) == mName & finiteMask;
    if ~any(idx)
        continue;
    end
    rows = add_row(rows, sprintf('reward_min_module_%s', mName), 'diagnostic', true, ...
        fmt_num(min(reward(idx))), 'n/a', sprintf('Min reward for %s.', mName));
    rows = add_row(rows, sprintf('reward_mean_module_%s', mName), 'diagnostic', true, ...
        fmt_num(mean(reward(idx))), 'n/a', sprintf('Mean reward for %s.', mName));
    rows = add_row(rows, sprintf('reward_max_module_%s', mName), 'diagnostic', true, ...
        fmt_num(max(reward(idx))), 'n/a', sprintf('Max reward for %s.', mName));
end

% No-op reward distribution.
isNoOp = logical(counterfactualTable.is_no_op) & finiteMask;
if any(isNoOp)
    rows = add_row(rows, 'reward_min_no_op', 'diagnostic', true, ...
        fmt_num(min(reward(isNoOp))), 'n/a', 'Min reward across no-op rows.');
    rows = add_row(rows, 'reward_mean_no_op', 'diagnostic', true, ...
        fmt_num(mean(reward(isNoOp))), 'n/a', 'Mean reward across no-op rows.');
    rows = add_row(rows, 'reward_max_no_op', 'diagnostic', true, ...
        fmt_num(max(reward(isNoOp))), 'n/a', 'Max reward across no-op rows.');
end

% Safety violation counts by module.
if ~isempty(safetyTable)
    sModules = unique(string(safetyTable.module_name));
    for k = 1:numel(sModules)
        m = sModules(k);
        idx = string(safetyTable.module_name) == m;
        c = sum(safetyTable.safety_is_unsafe(idx));
        rows = add_row(rows, sprintf('safety_violation_count_module_%s', m), 'diagnostic', true, ...
            fmt_int(c), 'n/a', sprintf('Unsafe candidate count for %s.', m));
    end

    % ES sleep on impaired/degraded sectors.
    esSleepImpaired = sum(safetyTable.safety_es_sleep_impaired);
    rows = add_row(rows, 'es_sleep_on_impaired_count', 'error', esSleepImpaired == 0, ...
        fmt_int(esSleepImpaired), '== 0', ...
        'ES sleep candidates must not target impaired/degraded sectors without coverage verification.');
end

% Top reward action per (scenario, module).
if any(finiteMask)
    [topRows, topActions] = compute_top_reward_rows(counterfactualTable, finiteMask);
    for r = 1:height(topRows)
        rows = add_row(rows, ...
            sprintf('top_reward_action_%s_%s', topRows.scenario_name{r}, topRows.module_name{r}), ...
            'diagnostic', true, fmt_num(topRows.reward(r)), 'n/a', ...
            sprintf('action_id=%d (%s)', topRows.action_id(r), topActions{r}));
    end
end

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase8b_counterfactual_validation.csv'));
end

function [topRows, descriptions] = compute_top_reward_rows(T, finiteMask)
T = T(finiteMask, :);
keyScn = string(T.scenario_name);
keyMod = string(T.module_name);
combo = strcat(keyScn, "||", keyMod);
[uniqCombos, ~, idx] = unique(combo);
topRows = table();
descriptions = {};
for k = 1:numel(uniqCombos)
    rowsK = T(idx == k, :);
    [~, bestIdx] = max(rowsK.reward);
    best = rowsK(bestIdx, :);
    parts = split(uniqCombos(k), "||");
    addRow = table({char(parts(1))}, {char(parts(2))}, best.action_id, best.reward, ...
        'VariableNames', {'scenario_name','module_name','action_id','reward'});
    topRows = [topRows; addRow]; %#ok<AGROW>
    descriptions{end+1, 1} = sprintf('source=%d target=%d action=%s', ...
        best.source_sector_id, best.target_sector_id, char(string(best.action_type))); %#ok<AGROW>
end
end

function s = fmt_int(v)
s = sprintf('%d', v);
end

function s = fmt_num(v)
s = sprintf('%.6f', v);
end

function rows = add_row(rows, checkName, severity, passFlag, actualValue, expected, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expected, notes}; %#ok<AGROW>
end

function keys = build_semantic_key(T, keyVars)
%BUILD_SEMANTIC_KEY Concatenate semantic action key columns to a string.
n = height(T);
parts = strings(n, numel(keyVars));
for i = 1:numel(keyVars)
    col = T.(keyVars{i});
    if iscell(col)
        parts(:, i) = string(col);
    elseif isnumeric(col) || islogical(col)
        parts(:, i) = string(double(col));
    else
        parts(:, i) = string(col);
    end
end
keys = strings(n, 1);
for r = 1:n
    keys(r) = strjoin(parts(r, :), "|");
end
end
