function [moduleSummary, scenarioSummary] = summarize_phase11b_final_decisions(finalDecisions)
%SUMMARIZE_PHASE11B_FINAL_DECISIONS Per-module and per-scenario tallies.

if isempty(finalDecisions)
    moduleSummary = table();
    scenarioSummary = table();
    return;
end

statuses = {'final_safe_action','final_noop','rejected_priority_conflict', ...
    'rejected_safety_conflict','unresolved_unsafe_fallback','diagnostic_only'};

modules = unique(string(finalDecisions.module_name), 'stable');
nM = numel(modules);
moduleRows = cell(nM, 10);
for k = 1:nM
    m = modules(k);
    mask = string(finalDecisions.module_name) == m;
    sub = finalDecisions(mask, :);
    counts = status_counts(sub, statuses);
    moduleRows(k, :) = {char(m), height(sub), counts(1), counts(2), counts(3), ...
        counts(4), counts(5), counts(6), sum(sub.executable_flag), sum(~sub.executable_flag)};
end
moduleSummary = cell2table(moduleRows, 'VariableNames', {'module_name', ...
    'total_decisions','final_safe_action','final_noop', ...
    'rejected_priority_conflict','rejected_safety_conflict', ...
    'unresolved_unsafe_fallback','diagnostic_only','executable_count','non_executable_count'});

scenarios = unique(string(finalDecisions.scenario_name), 'stable');
nS = numel(scenarios);
scenRows = cell(nS, 9);
for k = 1:nS
    s = scenarios(k);
    mask = string(finalDecisions.scenario_name) == s;
    sub = finalDecisions(mask, :);
    counts = status_counts(sub, statuses);
    scenRows(k, :) = {char(s), height(sub), counts(1), counts(2), counts(3), ...
        counts(4), counts(5), sum(sub.executable_flag), sum(~sub.executable_flag)};
end
scenarioSummary = cell2table(scenRows, 'VariableNames', {'scenario_name', ...
    'total_decisions','final_safe_action','final_noop', ...
    'rejected_priority_conflict','rejected_safety_conflict', ...
    'unresolved_unsafe_fallback','executable_count','non_executable_count'});
end

function counts = status_counts(sub, statuses)
counts = zeros(numel(statuses), 1);
for i = 1:numel(statuses)
    counts(i) = sum(strcmp(sub.final_decision_status, statuses{i}));
end
end
