function phase12a = run_phase12a_action_application_feasibility(cfg)
%RUN_PHASE12A_ACTION_APPLICATION_FEASIBILITY Dry-run feasibility audit.
%
% Phase 12A is OFFLINE feasibility audit only. It does NOT mutate
% topology, RF, traffic, or KPI state. It produces an action -> simulator
% state-variable mapping and per-action implementability classification
% so that Phase 12B (one-step KPI(t+1) application) can target only the
% subset that is honestly executable on the current simulator.

decisionFile = fullfile(cfg.tablesDir, 'phase11b_final_coordinator_decisions.csv');
if ~isfile(decisionFile)
    error('Phase 12A: missing Phase 11B input %s', decisionFile);
end
finalDecisions = readtable(decisionFile);

executableMask = logical(finalDecisions.executable_flag) & ...
    logical(finalDecisions.safety_valid) & ...
    strcmp(finalDecisions.final_decision_status, 'final_safe_action');
executable = finalDecisions(executableMask, :);
nonExecutable = finalDecisions(~executableMask, :);

mapping = map_action_to_simulator_state();
feasibility = audit_action_implementability(executable, mapping);

[moduleSummary, actionSummary] = summarize_phase12a_feasibility(feasibility);

skipped = build_skipped_table(nonExecutable);

writetable(feasibility,     fullfile(cfg.tablesDir, 'phase12a_action_application_feasibility.csv'));
writetable(mapping,         fullfile(cfg.tablesDir, 'phase12a_action_parameter_mapping.csv'));
writetable(moduleSummary,   fullfile(cfg.tablesDir, 'phase12a_implementability_summary_by_module.csv'));
writetable(actionSummary,   fullfile(cfg.tablesDir, 'phase12a_implementability_summary_by_action_type.csv'));
writetable(skipped,         fullfile(cfg.tablesDir, 'phase12a_skipped_non_executable_actions.csv'));

validationTable = validate_phase12a_action_application_feasibility(cfg, finalDecisions, ...
    feasibility, mapping, moduleSummary, actionSummary, skipped);

phase12a = struct();
phase12a.feasibility = feasibility;
phase12a.mapping = mapping;
phase12a.moduleSummary = moduleSummary;
phase12a.actionSummary = actionSummary;
phase12a.skipped = skipped;
phase12a.validationTable = validationTable;

phase12a.numExecutableReviewed = height(feasibility);
phase12a.numImplementableNow = sum(strcmp(feasibility.implementability_status, 'implementable_now'));
phase12a.numPartial = sum(strcmp(feasibility.implementability_status, 'partially_implementable'));
phase12a.numNotImplemented = sum(strcmp(feasibility.implementability_status, 'not_implemented_in_simulator'));
phase12a.numNoChange = sum(strcmp(feasibility.implementability_status, 'no_parameter_change_required'));
phase12a.numSkippedNonExecutable = height(skipped);
end

function skipped = build_skipped_table(nonExecutable)
if isempty(nonExecutable)
    skipped = table('Size', [0 7], ...
        'VariableTypes', {'double','cell','double','double','cell','cell','cell'}, ...
        'VariableNames', {'final_decision_id','scenario_name','realization_id', ...
        'selected_action_id_safe','module_name','final_decision_status','reason_not_applied'});
    return;
end
reasons = strings(height(nonExecutable), 1);
status = string(nonExecutable.final_decision_status);
reasons(status == "final_noop") = "no-op decision; no parameter change to apply";
reasons(status == "rejected_priority_conflict") = "rejected by Phase 11A priority arbitration";
reasons(status == "rejected_safety_conflict") = "rejected by Phase 11A safety conflict rule";
reasons(status == "unresolved_unsafe_fallback") = "unresolved unsafe fallback; never executable";
reasons(status == "diagnostic_only") = "diagnostic-only row";

skipped = table(nonExecutable.final_decision_id, ...
    nonExecutable.scenario_name, nonExecutable.realization_id, ...
    nonExecutable.selected_action_id_safe, nonExecutable.module_name, ...
    cellstr(status), cellstr(reasons), ...
    'VariableNames', {'final_decision_id','scenario_name','realization_id', ...
    'selected_action_id_safe','module_name','final_decision_status','reason_not_applied'});
end
