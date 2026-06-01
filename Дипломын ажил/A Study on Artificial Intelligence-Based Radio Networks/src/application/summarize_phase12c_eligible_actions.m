function [moduleSummary, actionSummary] = summarize_phase12c_eligible_actions(eligible, excluded)
%SUMMARIZE_PHASE12C_ELIGIBLE_ACTIONS Per-module and per-action-type tallies.

if isempty(eligible) && isempty(excluded)
    moduleSummary = table();
    actionSummary = table();
    return;
end

allRows = combine_for_summary(eligible, excluded);

modules = unique(string(allRows.module_name), 'stable');
nM = numel(modules);
mRows = cell(nM, 4);
for k = 1:nM
    m = modules(k);
    mask = string(allRows.module_name) == m;
    eligCount = sum(mask & allRows.is_eligible);
    excCount = sum(mask & ~allRows.is_eligible);
    total = eligCount + excCount;
    eligRate = 0;
    if total > 0, eligRate = eligCount / total; end
    mRows(k, :) = {char(m), eligCount, excCount, eligRate};
end
moduleSummary = cell2table(mRows, 'VariableNames', ...
    {'module_name','eligible_count','excluded_count','eligible_rate'});

actionTypes = unique(string(allRows.action_type), 'stable');
nA = numel(actionTypes);
aRows = cell(nA, 4);
for k = 1:nA
    a = actionTypes(k);
    mask = string(allRows.action_type) == a;
    eligCount = sum(mask & allRows.is_eligible);
    excCount = sum(mask & ~allRows.is_eligible);
    total = eligCount + excCount;
    eligRate = 0;
    if total > 0, eligRate = eligCount / total; end
    aRows(k, :) = {char(a), eligCount, excCount, eligRate};
end
actionSummary = cell2table(aRows, 'VariableNames', ...
    {'action_type','eligible_count','excluded_count','eligible_rate'});
end

function combined = combine_for_summary(eligible, excluded)
if isempty(eligible)
    eligibleRows = table('Size', [0 3], 'VariableTypes', {'cell','cell','logical'}, ...
        'VariableNames', {'module_name','action_type','is_eligible'});
else
    eligibleRows = table(eligible.module_name, eligible.action_type, ...
        true(height(eligible), 1), ...
        'VariableNames', {'module_name','action_type','is_eligible'});
end
if isempty(excluded)
    excludedRows = table('Size', [0 3], 'VariableTypes', {'cell','cell','logical'}, ...
        'VariableNames', {'module_name','action_type','is_eligible'});
else
    excludedRows = table(excluded.module_name, excluded.action_type, ...
        false(height(excluded), 1), ...
        'VariableNames', {'module_name','action_type','is_eligible'});
end
combined = [eligibleRows; excludedRows];
end
