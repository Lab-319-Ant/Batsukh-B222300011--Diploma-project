function [moduleSummary, scenarioSummary] = summarize_phase11a_coordination(inputTable, candidateActions, conflictLog, rejectedLog)
%SUMMARIZE_PHASE11A_COORDINATION Per-module and per-scenario summaries.

moduleSummary = table();
scenarioSummary = table();
if isempty(inputTable)
    return;
end

modules = {'COC/OH','LB/MLB','ES','HO/MRO'};
nModules = numel(modules);
rows = cell(nModules, 10);
for k = 1:nModules
    m = modules{k};
    inputMask = strcmp(inputTable.module_name, m);
    candMask = strcmp(candidateActions.module_name, m);

    selectedBefore = sum(inputMask);
    acceptedAfter = sum(candMask & candidateActions.accepted_flag);
    rejectedAfter = sum(candMask & candidateActions.rejected_flag);
    rejectionRate = 0;
    if selectedBefore > 0
        rejectionRate = rejectedAfter / selectedBefore;
    end

    if ~isempty(conflictLog) && height(conflictLog) > 0
        conflictMask = strcmp(conflictLog.module_a, m) | strcmp(conflictLog.module_b, m);
        conflictCount = sum(conflictMask);
    else
        conflictCount = 0;
    end

    if ~isempty(rejectedLog) && height(rejectedLog) > 0
        rejByModule = strcmp(rejectedLog.module_name, m);
        safetyRej = sum(rejByModule & rejectedLog.safety_related_flag);
        prioRej = sum(rejByModule & ~rejectedLog.safety_related_flag);
    else
        safetyRej = 0;
        prioRej = 0;
    end

    noopCount = sum(inputMask & inputTable.noop_selected);
    fallbackCount = sum(inputMask & inputTable.fallback_used);

    rows(k, :) = {m, selectedBefore, acceptedAfter, rejectedAfter, rejectionRate, ...
        conflictCount, safetyRej, prioRej, noopCount, fallbackCount};
end
moduleSummary = cell2table(rows, 'VariableNames', {'module_name','selected_before_coordination', ...
    'accepted_after_coordination','rejected_after_coordination','rejection_rate', ...
    'conflict_count','safety_rejection_count','priority_rejection_count', ...
    'noop_count','fallback_count'});

scenarios = unique(string(inputTable.scenario_name), 'stable');
nScn = numel(scenarios);
sRows = cell(nScn, 8);
for k = 1:nScn
    s = scenarios(k);
    inputMask = strcmp(string(inputTable.scenario_name), s);
    candMask = strcmp(string(candidateActions.scenario_name), s);

    selectedBefore = sum(inputMask);
    acceptedAfter = sum(candMask & candidateActions.accepted_flag);
    rejectedAfter = sum(candMask & candidateActions.rejected_flag);

    if ~isempty(conflictLog) && height(conflictLog) > 0
        conflictMask = strcmp(string(conflictLog.scenario_name), s);
        conflictCount = sum(conflictMask);
    else
        conflictCount = 0;
    end

    if ~isempty(rejectedLog) && height(rejectedLog) > 0
        rejMask = strcmp(string(rejectedLog.scenario_name), s);
        safetyRej = sum(rejMask & rejectedLog.safety_related_flag);
    else
        safetyRej = 0;
    end

    noopCount = sum(inputMask & inputTable.noop_selected);
    fallbackCount = sum(inputMask & inputTable.fallback_used);

    sRows(k, :) = {char(s), selectedBefore, acceptedAfter, rejectedAfter, ...
        conflictCount, safetyRej, noopCount, fallbackCount};
end
scenarioSummary = cell2table(sRows, 'VariableNames', {'scenario_name', ...
    'selected_before_coordination','accepted_after_coordination', ...
    'rejected_after_coordination','conflict_count','safety_rejection_count', ...
    'noop_count','fallback_count'});
end
