function [moduleSummary, scenarioSummary, filterSummary] = summarize_phase10a_selection(selectedTable)
%SUMMARIZE_PHASE10A_SELECTION Module, scenario, and filter summaries.

if isempty(selectedTable)
    moduleSummary = table();
    scenarioSummary = table();
    filterSummary = table();
    return;
end

modules = unique(string(selectedTable.module_name), 'stable');
moduleSummary = build_module_summary(selectedTable, modules);
filterSummary = build_filter_summary(selectedTable, modules);

scenarios = unique(string(selectedTable.scenario_name), 'stable');
scenarioSummary = build_scenario_summary(selectedTable, scenarios);
end

function summary = build_module_summary(T, modules)
n = numel(modules);
rows = cell(n, 13);
for k = 1:n
    m = modules(k);
    mask = string(T.module_name) == m;
    sub = T(mask, :);

    rawUnsafeTop1 = sum(~sub.raw_selected_safety_valid);
    safeUnsafeSelected = sum(~sub.safe_selected_safety_valid);
    filterChanged = sum(sub.safety_filter_changed_action);
    fallback = sum(sub.fallback_used);
    noop = sum(sub.noop_selected);
    rawMeanRegret = mean(sub.raw_regret, 'omitnan');
    safetyMeanRegret = mean(sub.safety_enforced_regret, 'omitnan');
    rawMatchRate = mean(sub.raw_top1_oracle_match, 'omitnan');
    safeMatchRate = mean(sub.safe_top1_oracle_match, 'omitnan');
    safeTop2Rate = mean(sub.safe_top2_oracle_match, 'omitnan');
    meanOracleReward = mean(sub.oracle_reward, 'omitnan');
    meanSafeReward = mean(sub.safe_true_reward, 'omitnan');

    rows(k, :) = {char(m), height(sub), rawUnsafeTop1, safeUnsafeSelected, ...
        filterChanged, fallback, noop, rawMeanRegret, safetyMeanRegret, ...
        rawMatchRate, safeMatchRate, safeTop2Rate, meanOracleReward};
    rows{k, 13} = meanOracleReward; %#ok<AGROW>
end

summary = cell2table(rows, 'VariableNames', {'module_name','decision_group_count', ...
    'raw_unsafe_top1_count','safe_unsafe_selected_count','safety_filter_changed_count', ...
    'fallback_count','noop_selected_count','raw_mean_regret', ...
    'safety_enforced_mean_regret','raw_top1_oracle_match_rate', ...
    'safe_top1_oracle_match_rate','safe_top2_oracle_match_rate', ...
    'mean_oracle_reward'});

meanSafe = zeros(n, 1);
for k = 1:n
    mask = string(T.module_name) == modules(k);
    meanSafe(k) = mean(T.safe_true_reward(mask), 'omitnan');
end
summary.mean_safe_selected_reward = meanSafe;
end

function summary = build_scenario_summary(T, scenarios)
n = numel(scenarios);
rows = cell(n, 7);
for k = 1:n
    s = scenarios(k);
    mask = string(T.scenario_name) == s;
    sub = T(mask, :);

    rows(k, :) = {char(s), height(sub), ...
        sum(~sub.safe_selected_safety_valid), ...
        sum(sub.fallback_used), ...
        sum(sub.noop_selected), ...
        mean(sub.safety_enforced_regret, 'omitnan'), ...
        mean(sub.safe_top1_oracle_match, 'omitnan')};
end
summary = cell2table(rows, 'VariableNames', {'scenario_name','decision_group_count', ...
    'safe_unsafe_selected_count','fallback_count','noop_selected_count', ...
    'safety_enforced_mean_regret','safe_top1_oracle_match_rate'});
end

function summary = build_filter_summary(T, modules)
n = numel(modules);
rows = cell(n, 10);
for k = 1:n
    m = modules(k);
    mask = string(T.module_name) == m;
    sub = T(mask, :);
    total = height(sub);
    if total == 0
        rows(k, :) = {char(m), 0, 0, 0, 0, 0, 0, 0, 0, 0};
        continue;
    end
    rawUnsafe = sum(~sub.raw_selected_safety_valid);
    safeUnsafe = sum(~sub.safe_selected_safety_valid);
    filterChanged = sum(sub.safety_filter_changed_action);
    fallback = sum(sub.fallback_used);
    rows(k, :) = {char(m), total, ...
        rawUnsafe, rawUnsafe / total, ...
        safeUnsafe, safeUnsafe / total, ...
        filterChanged, filterChanged / total, ...
        fallback, fallback / total};
end
summary = cell2table(rows, 'VariableNames', {'module_name','total_groups', ...
    'raw_unsafe_top1_count','raw_unsafe_top1_rate', ...
    'safe_unsafe_selected_count','safe_unsafe_selected_rate', ...
    'safety_filter_changed_count','safety_filter_changed_rate', ...
    'fallback_count','fallback_rate'});
end
