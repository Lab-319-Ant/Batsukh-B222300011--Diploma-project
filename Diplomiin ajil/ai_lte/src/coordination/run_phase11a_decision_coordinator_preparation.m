function phase11a = run_phase11a_decision_coordinator_preparation(cfg)
%RUN_PHASE11A_DECISION_COORDINATOR_PREPARATION Offline coordinator prep + conflict diagnostics.
%
% Phase 11A is OFFLINE coordinator preparation only. It does NOT apply
% actions to the simulator, NOT generate KPI(t+1), NOT implement closed-
% loop control. It diagnoses module-action conflicts and produces an
% accepted/rejected log under fixed priority order:
%   COC/OH (2) > LB/MLB (3) > HO/MRO (4) > ES (6)
% with safety filtering applied first (any unsafe non-fallback action is
% rejected before any priority comparison).

phase10aFile = fullfile(cfg.tablesDir, 'phase10a_safety_enforced_selected_actions.csv');
if ~isfile(phase10aFile)
    error('Phase 11A: missing Phase 10A input %s', phase10aFile);
end
phase10aSelected = readtable(phase10aFile);

inputTable = prepare_phase11a_coordinator_inputs(phase10aSelected);
conflictLog = detect_action_conflicts(inputTable, cfg);
[resolutionLog, candidateActions, rejectedLog] = resolve_action_conflicts(inputTable, conflictLog);
[moduleSummary, scenarioSummary] = summarize_phase11a_coordination( ...
    inputTable, candidateActions, conflictLog, rejectedLog);

writetable(inputTable,        fullfile(cfg.tablesDir, 'phase11a_coordinator_input_actions.csv'));
writetable(conflictLog,       fullfile(cfg.tablesDir, 'phase11a_conflict_detection_log.csv'));
writetable(resolutionLog,     fullfile(cfg.tablesDir, 'phase11a_conflict_resolution_log.csv'));
writetable(candidateActions,  fullfile(cfg.tablesDir, 'phase11a_coordinator_candidate_actions.csv'));
writetable(rejectedLog,       fullfile(cfg.tablesDir, 'phase11a_rejected_action_log.csv'));
writetable(moduleSummary,     fullfile(cfg.tablesDir, 'phase11a_summary_by_module.csv'));
writetable(scenarioSummary,   fullfile(cfg.tablesDir, 'phase11a_summary_by_scenario.csv'));

try_plot('plot_phase11a_conflict_counts', cfg, conflictLog);
try_plot('plot_phase11a_accepted_rejected_actions', cfg, candidateActions);
try_plot('plot_phase11a_module_priority_outcomes', cfg, moduleSummary);

validationTable = validate_phase11a_coordination_preparation(cfg, inputTable, ...
    conflictLog, resolutionLog, candidateActions, rejectedLog, moduleSummary, scenarioSummary);

phase11a = struct();
phase11a.inputTable = inputTable;
phase11a.conflictLog = conflictLog;
phase11a.resolutionLog = resolutionLog;
phase11a.candidateActions = candidateActions;
phase11a.rejectedLog = rejectedLog;
phase11a.moduleSummary = moduleSummary;
phase11a.scenarioSummary = scenarioSummary;
phase11a.validationTable = validationTable;

phase11a.numInputs = height(inputTable);
phase11a.numConflicts = height(conflictLog);
phase11a.numAccepted = sum(candidateActions.accepted_flag);
phase11a.numRejected = sum(candidateActions.rejected_flag);
phase11a.numSafetyRejections = 0;
phase11a.numPriorityRejections = 0;
if ~isempty(rejectedLog) && height(rejectedLog) > 0
    phase11a.numSafetyRejections = sum(rejectedLog.safety_related_flag);
    phase11a.numPriorityRejections = sum(~rejectedLog.safety_related_flag);
end
phase11a.numFallbackUnsafeRetained = sum(inputTable.fallback_used & ~inputTable.safe_selected_safety_valid & candidateActions.accepted_flag);
end

function try_plot(fnName, cfg, T)
if exist(fnName, 'file') ~= 2 || isempty(T)
    return;
end
try
    feval(fnName, cfg, T);
catch ME
    warning('Phase 11A plot %s failed: %s', fnName, ME.message);
end
end
