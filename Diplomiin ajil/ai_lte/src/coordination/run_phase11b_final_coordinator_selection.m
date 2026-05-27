function phase11b = run_phase11b_final_coordinator_selection(cfg)
%RUN_PHASE11B_FINAL_COORDINATOR_SELECTION Final coordinator decision table.
%
% Phase 11B is OFFLINE final-decision projection. It does NOT apply
% actions to the simulator, NOT update KPI(t+1), NOT implement closed-
% loop control. Every row carries not_applied_flag = true. Unsafe
% fallback rows are explicitly marked unresolved_unsafe_fallback and
% NEVER executable.

requiredFiles = {'phase11a_coordinator_input_actions.csv', ...
    'phase11a_coordinator_candidate_actions.csv', ...
    'phase11a_rejected_action_log.csv', ...
    'phase11a_conflict_resolution_log.csv'};
for i = 1:numel(requiredFiles)
    p = fullfile(cfg.tablesDir, requiredFiles{i});
    if ~isfile(p)
        error('Phase 11B: missing input %s', p);
    end
end

inputTable = readtable(fullfile(cfg.tablesDir, 'phase11a_coordinator_input_actions.csv'));
candidateActions = readtable(fullfile(cfg.tablesDir, 'phase11a_coordinator_candidate_actions.csv'));
rejectedLog = readtable(fullfile(cfg.tablesDir, 'phase11a_rejected_action_log.csv'));
resolutionLog = readtable(fullfile(cfg.tablesDir, 'phase11a_conflict_resolution_log.csv'));

finalDecisions = build_final_coordinator_decisions(inputTable, candidateActions, rejectedLog, resolutionLog);

executable = finalDecisions(strcmp(finalDecisions.final_decision_status, 'final_safe_action'), :);
unresolved = finalDecisions(strcmp(finalDecisions.final_decision_status, 'unresolved_unsafe_fallback'), :);
rejected = finalDecisions( ...
    strcmp(finalDecisions.final_decision_status, 'rejected_priority_conflict') | ...
    strcmp(finalDecisions.final_decision_status, 'rejected_safety_conflict'), :);

[moduleSummary, scenarioSummary] = summarize_phase11b_final_decisions(finalDecisions);

writetable(finalDecisions, fullfile(cfg.tablesDir, 'phase11b_final_coordinator_decisions.csv'));
writetable(executable,    fullfile(cfg.tablesDir, 'phase11b_final_executable_actions.csv'));
writetable(unresolved,    fullfile(cfg.tablesDir, 'phase11b_unresolved_fallback_diagnostics.csv'));
writetable(rejected,      fullfile(cfg.tablesDir, 'phase11b_final_rejected_actions.csv'));
writetable(moduleSummary, fullfile(cfg.tablesDir, 'phase11b_summary_by_module.csv'));
writetable(scenarioSummary, fullfile(cfg.tablesDir, 'phase11b_summary_by_scenario.csv'));

try_plot('plot_phase11b_final_decision_status', cfg, finalDecisions);
try_plot('plot_phase11b_executable_actions_by_module', cfg, moduleSummary);
try_plot('plot_phase11b_unresolved_fallbacks_by_scenario', cfg, scenarioSummary);

validationTable = validate_phase11b_final_coordinator_selection(cfg, ...
    finalDecisions, candidateActions, inputTable, moduleSummary, scenarioSummary);

phase11b = struct();
phase11b.finalDecisions = finalDecisions;
phase11b.executable = executable;
phase11b.unresolved = unresolved;
phase11b.rejected = rejected;
phase11b.moduleSummary = moduleSummary;
phase11b.scenarioSummary = scenarioSummary;
phase11b.validationTable = validationTable;
phase11b.numFinalDecisions = height(finalDecisions);
phase11b.numExecutable = height(executable);
phase11b.numNoop = sum(strcmp(finalDecisions.final_decision_status, 'final_noop'));
phase11b.numRejected = height(rejected);
phase11b.numUnresolved = height(unresolved);
end

function try_plot(fnName, cfg, T)
if exist(fnName, 'file') ~= 2 || isempty(T)
    return;
end
try
    feval(fnName, cfg, T);
catch ME
    warning('Phase 11B plot %s failed: %s', fnName, ME.message);
end
end
