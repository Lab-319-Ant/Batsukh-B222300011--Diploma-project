function [moduleSummary, actionSummary] = summarize_phase12a_feasibility(feasibility)
%SUMMARIZE_PHASE12A_FEASIBILITY Implementability tallies by module and action type.

if isempty(feasibility)
    moduleSummary = table();
    actionSummary = table();
    return;
end

statuses = {'implementable_now','partially_implementable', ...
    'not_implemented_in_simulator','no_parameter_change_required'};

modules = unique(string(feasibility.module_name), 'stable');
nM = numel(modules);
mRows = cell(nM, 7);
for k = 1:nM
    m = modules(k);
    mask = string(feasibility.module_name) == m;
    sub = feasibility(mask, :);
    counts = status_counts(sub.implementability_status, statuses);
    canApply = sum(logical(sub.can_apply_in_phase12b));
    mRows(k, :) = {char(m), height(sub), counts(1), counts(2), counts(3), counts(4), canApply};
end
moduleSummary = cell2table(mRows, 'VariableNames', {'module_name','total_actions', ...
    'implementable_now','partially_implementable','not_implemented_in_simulator', ...
    'no_parameter_change_required','can_apply_in_phase12b_count'});

actionTypes = unique(string(feasibility.accepted_action_type), 'stable');
nA = numel(actionTypes);
aRows = cell(nA, 7);
for k = 1:nA
    a = actionTypes(k);
    mask = string(feasibility.accepted_action_type) == a;
    sub = feasibility(mask, :);
    counts = status_counts(sub.implementability_status, statuses);
    canApply = sum(logical(sub.can_apply_in_phase12b));
    aRows(k, :) = {char(a), height(sub), counts(1), counts(2), counts(3), counts(4), canApply};
end
actionSummary = cell2table(aRows, 'VariableNames', {'action_type','total_actions', ...
    'implementable_now','partially_implementable','not_implemented_in_simulator', ...
    'no_parameter_change_required','can_apply_in_phase12b_count'});
end

function counts = status_counts(statusCol, statuses)
counts = zeros(numel(statuses), 1);
for i = 1:numel(statuses)
    counts(i) = sum(strcmp(statusCol, statuses{i}));
end
end
