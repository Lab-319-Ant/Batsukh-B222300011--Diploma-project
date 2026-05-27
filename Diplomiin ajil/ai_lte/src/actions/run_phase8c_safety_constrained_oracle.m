function phase8c = run_phase8c_safety_constrained_oracle(cfg)
%RUN_PHASE8C_SAFETY_CONSTRAINED_ORACLE Upper-bound oracle over Phase 8B.
%
% Phase 8C is an UPPER-BOUND BENCHMARK only. For each decision group it
% selects the highest-reward safety-valid candidate from the Phase 8B
% counterfactual action table. It does NOT:
%   - train any ML model
%   - coordinate multiple modules
%   - apply actions to the simulator
%   - produce KPI(t+1)
%   - constitute closed-loop SON control
%
% Inputs (read from cfg.tablesDir):
%   phase8b_counterfactual_action_table.csv
%   phase8b_safety_check.csv
%
% Outputs (written to cfg.tablesDir):
%   phase8c_oracle_selected_actions.csv
%   phase8c_oracle_summary_by_module.csv
%   phase8c_oracle_summary_by_scenario.csv
%   phase8c_oracle_safety_summary.csv
%   phase8c_oracle_validation.csv

cfFile = fullfile(cfg.tablesDir, 'phase8b_counterfactual_action_table.csv');
safetyFile = fullfile(cfg.tablesDir, 'phase8b_safety_check.csv');
if ~isfile(cfFile)
    error('Missing Phase 8B counterfactual action table: %s', cfFile);
end
if ~isfile(safetyFile)
    error('Missing Phase 8B safety check table: %s', safetyFile);
end

cfTable = readtable(cfFile);
safetyTable = readtable(safetyFile);

joined = join_counterfactual_and_safety(cfTable, safetyTable);

selectedTable = build_oracle_selection(joined);
moduleSummary = summarize_oracle_by_module(selectedTable);
scenarioSummary = summarize_oracle_by_scenario(selectedTable);
safetySummary = summarize_oracle_safety(joined, selectedTable);

writetable(selectedTable, fullfile(cfg.tablesDir, 'phase8c_oracle_selected_actions.csv'));
writetable(moduleSummary, fullfile(cfg.tablesDir, 'phase8c_oracle_summary_by_module.csv'));
writetable(scenarioSummary, fullfile(cfg.tablesDir, 'phase8c_oracle_summary_by_scenario.csv'));
writetable(safetySummary, fullfile(cfg.tablesDir, 'phase8c_oracle_safety_summary.csv'));

validationTable = validate_phase8c_oracle(cfg, selectedTable, joined, moduleSummary, scenarioSummary);

phase8c = struct();
phase8c.selectedTable = selectedTable;
phase8c.moduleSummary = moduleSummary;
phase8c.scenarioSummary = scenarioSummary;
phase8c.safetySummary = safetySummary;
phase8c.validationTable = validationTable;
phase8c.numGroups = height(selectedTable);
phase8c.numSafeSelected = sum(selectedTable.safety_valid);
phase8c.numUnsafeFallback = sum(~selectedTable.safety_valid);
phase8c.numNoopSelected = sum(selectedTable.is_noop);
phase8c.meanOracleReward = mean(selectedTable.reward, 'omitnan');
end

function joined = join_counterfactual_and_safety(cfTable, safetyTable)
%JOIN_COUNTERFACTUAL_AND_SAFETY Left-join Phase 8B tables on action_id.
safetyCols = {'action_id', ...
    'safety_attach_loss','safety_qos_loss','safety_sinr_loss','safety_rsrp_loss', ...
    'safety_neighbor_overload','safety_handover_risk','safety_es_sleep_impaired', ...
    'safety_is_unsafe','invalid_reason'};
keep = intersect(safetyCols, safetyTable.Properties.VariableNames, 'stable');
joined = outerjoin(cfTable, safetyTable(:, keep), 'Keys', 'action_id', ...
    'MergeKeys', true, 'Type', 'left');

% Defensive coercions: outerjoin can produce NaN/missing for unmatched rows
flagCols = {'safety_attach_loss','safety_qos_loss','safety_sinr_loss', ...
    'safety_rsrp_loss','safety_neighbor_overload','safety_handover_risk', ...
    'safety_es_sleep_impaired','safety_is_unsafe'};
for i = 1:numel(flagCols)
    c = flagCols{i};
    if ismember(c, joined.Properties.VariableNames)
        v = joined.(c);
        if iscell(v)
            v = str2double(v);
        end
        v(~isfinite(v)) = 0;
        joined.(c) = logical(v);
    else
        joined.(c) = false(height(joined), 1);
    end
end
if ~ismember('invalid_reason', joined.Properties.VariableNames)
    joined.invalid_reason = repmat({'ok'}, height(joined), 1);
end
end

function selectedTable = build_oracle_selection(joined)
%BUILD_ORACLE_SELECTION Pick one row per (scenario, realization, source, module).
%
% Selection rule:
%   1) Among safety-valid candidates, choose the maximum-reward row.
%   2) Else fall back to a safe no-op (literal is_no_op or ES keep_active).
%   3) Else fall back to the highest-reward no-op (least-unsafe no-op).
%   4) Else fall back to the highest-reward candidate of any kind.
%
% Cases 3 and 4 leave safety_valid = false.

scenario = string(joined.scenario_name);
realization = joined.realization_id;
source = joined.source_sector_id;
module = string(joined.module_name);
groupKey = strcat(scenario, "|", string(realization), "|", string(source), "|", module);
[uniqueGroups, ~, idx] = unique(groupKey, 'stable');
nGroups = numel(uniqueGroups);

reward = joined.reward;
safe = ~joined.safety_is_unsafe;
isNoOp = logical(joined.is_no_op) | ...
    (string(joined.module_name) == "ES" & string(joined.action_type) == "keep_active");

selectedRowIdx = zeros(nGroups, 1);
selectedReason = strings(nGroups, 1);
selectedSafety = false(nGroups, 1);

for g = 1:nGroups
    members = find(idx == g);
    rSafe = safe(members);
    rNoOp = isNoOp(members);
    rRew  = reward(members);

    if any(rSafe)
        candIdx = find(rSafe);
        [~, k] = max(rRew(candIdx));
        selectedRowIdx(g) = members(candIdx(k));
        selectedReason(g) = "safe_best_reward";
        selectedSafety(g) = true;
        continue;
    end

    if any(rNoOp)
        safeNoOp = rNoOp & rSafe;
        if any(safeNoOp)
            candIdx = find(safeNoOp);
            [~, k] = max(rRew(candIdx));
            selectedRowIdx(g) = members(candIdx(k));
            selectedReason(g) = "fallback_no_safe_action_noop";
            selectedSafety(g) = true;
        else
            candIdx = find(rNoOp);
            [~, k] = max(rRew(candIdx));
            selectedRowIdx(g) = members(candIdx(k));
            selectedReason(g) = "no_safe_action_available";
            selectedSafety(g) = false;
        end
        continue;
    end

    [~, k] = max(rRew);
    selectedRowIdx(g) = members(k);
    selectedReason(g) = "no_safe_action_available";
    selectedSafety(g) = false;
end

picked = joined(selectedRowIdx, :);

esActionCol = strings(height(picked), 1);
esMask = string(picked.module_name) == "ES";
esActionCol(esMask) = string(picked.action_type(esMask));

isNoopOut = logical(picked.is_no_op) | ...
    (string(picked.module_name) == "ES" & string(picked.action_type) == "keep_active");

oracleGroupId = (1:nGroups).';

selectedTable = table(oracleGroupId, ...
    cellstr(string(picked.scenario_name)), picked.realization_id, ...
    picked.source_sector_id, cellstr(string(picked.module_name)), ...
    picked.action_id, cellstr(string(picked.action_type)), picked.target_sector_id, ...
    picked.reward, selectedSafety, cellstr(selectedReason), isNoopOut, ...
    picked.delta_prs_dB, picked.delta_tilt_deg, picked.delta_cio_dB, ...
    picked.delta_hom_dB, picked.delta_ttt_ms, cellstr(esActionCol), ...
    picked.pre_source_load_ratio, picked.post_source_load_ratio, ...
    picked.pre_source_RSRP_dBm, picked.post_source_RSRP_dBm, ...
    picked.pre_source_SINR_dB, picked.post_source_SINR_dB, ...
    picked.pre_source_qos_satisfaction_ratio, picked.post_source_qos_satisfaction_ratio, ...
    picked.pre_source_attach_rate, picked.post_source_attach_rate, ...
    picked.pre_source_handover_risk_score, picked.post_source_handover_risk_score, ...
    'VariableNames', {'oracle_group_id','scenario_name','realization_id', ...
    'source_sector_id','module_name','selected_action_id','selected_action_type', ...
    'target_sector_id','reward','safety_valid','oracle_selection_reason','is_noop', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms', ...
    'es_action','pre_source_load_ratio','post_source_load_ratio', ...
    'pre_source_RSRP_dBm','post_source_RSRP_dBm','pre_source_SINR_dB', ...
    'post_source_SINR_dB','pre_source_qos_satisfaction_ratio', ...
    'post_source_qos_satisfaction_ratio','pre_source_attach_rate', ...
    'post_source_attach_rate','pre_source_handover_risk_score', ...
    'post_source_handover_risk_score'});
end

function summary = summarize_oracle_by_module(selected)
if isempty(selected)
    summary = table();
    return;
end
[groups, moduleName] = findgroups(string(selected.module_name));
oracle_group_count = splitapply(@numel, selected.oracle_group_id, groups);
safe_selected_count = splitapply(@(x) sum(logical(x)), selected.safety_valid, groups);
unsafe_fallback_count = oracle_group_count - safe_selected_count;
noop_selected_count = splitapply(@(x) sum(logical(x)), selected.is_noop, groups);
mean_oracle_reward = splitapply(@(x) mean(x, 'omitnan'), selected.reward, groups);
median_oracle_reward = splitapply(@(x) median(x, 'omitnan'), selected.reward, groups);
min_oracle_reward = splitapply(@(x) min(x, [], 'omitnan'), selected.reward, groups);
max_oracle_reward = splitapply(@(x) max(x, [], 'omitnan'), selected.reward, groups);
summary = table(cellstr(moduleName), oracle_group_count, safe_selected_count, ...
    unsafe_fallback_count, noop_selected_count, mean_oracle_reward, ...
    median_oracle_reward, min_oracle_reward, max_oracle_reward, ...
    'VariableNames', {'module_name','oracle_group_count','safe_selected_count', ...
    'unsafe_fallback_count','noop_selected_count','mean_oracle_reward', ...
    'median_oracle_reward','min_oracle_reward','max_oracle_reward'});
end

function summary = summarize_oracle_by_scenario(selected)
if isempty(selected)
    summary = table();
    return;
end
[groups, scenarioName] = findgroups(string(selected.scenario_name));
oracle_group_count = splitapply(@numel, selected.oracle_group_id, groups);
safe_selected_count = splitapply(@(x) sum(logical(x)), selected.safety_valid, groups);
unsafe_fallback_count = oracle_group_count - safe_selected_count;
noop_selected_count = splitapply(@(x) sum(logical(x)), selected.is_noop, groups);
mean_oracle_reward = splitapply(@(x) mean(x, 'omitnan'), selected.reward, groups);
summary = table(cellstr(scenarioName), oracle_group_count, safe_selected_count, ...
    unsafe_fallback_count, noop_selected_count, mean_oracle_reward, ...
    'VariableNames', {'scenario_name','oracle_group_count','safe_selected_count', ...
    'unsafe_fallback_count','noop_selected_count','mean_oracle_reward'});
end

function summary = summarize_oracle_safety(joined, selected)
[groups, moduleName] = findgroups(string(joined.module_name));
total_candidates = splitapply(@numel, joined.action_id, groups);
safety_valid_candidates = splitapply(@(x) sum(~logical(x)), joined.safety_is_unsafe, groups);
safety_invalid_candidates = total_candidates - safety_valid_candidates;
safety_valid_ratio = safety_valid_candidates ./ max(total_candidates, 1);

selectedUnsafe = zeros(numel(moduleName), 1);
for i = 1:numel(moduleName)
    mask = string(selected.module_name) == moduleName(i);
    selectedUnsafe(i) = sum(mask & ~selected.safety_valid);
end

summary = table(cellstr(moduleName), total_candidates, safety_valid_candidates, ...
    safety_invalid_candidates, safety_valid_ratio, selectedUnsafe, ...
    'VariableNames', {'module_name','total_candidates','safety_valid_candidates', ...
    'safety_invalid_candidates','safety_valid_ratio','oracle_selected_unsafe_count'});
end
