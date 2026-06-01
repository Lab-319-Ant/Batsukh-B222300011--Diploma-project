function phase12c = run_phase12c_post_extension_feasibility_refresh(cfg)
%RUN_PHASE12C_POST_EXTENSION_FEASIBILITY_REFRESH Build KPI(t+1)-eligible action set.
%
% Phase 12C is OFFLINE. It does NOT mutate simulator state, NOT recompute
% KPI, NOT generate KPI(t+1), NOT implement closed-loop control. It only:
%   1) re-classifies Phase 11B final-safe executable rows with the
%      post-Phase-12B mapping
%   2) filters to rows that are implementable_now AND belong to an
%      eligible module (COC/OH or LB/MLB) AND carry no non-zero
%      HOM/TTT/ES-sleep parameter
%   3) writes the eligible set, the excluded set, and per-module /
%      per-action-type summaries

execFile = fullfile(cfg.tablesDir, 'phase11b_final_executable_actions.csv');
if ~isfile(execFile)
    error('Phase 12C: missing Phase 11B executable actions %s', execFile);
end
executable = readtable(execFile);
executable = executable(strcmp(executable.final_decision_status, 'final_safe_action') & ...
    logical(executable.executable_flag) & logical(executable.safety_valid), :);

supportTable = audit_phase12b_action_state_support();

[eligible, excluded, postExtensionFeasibility] = ...
    build_phase12c_kpi_update_eligible_actions(executable, supportTable);

[moduleSummary, actionSummary] = summarize_phase12c_eligible_actions(eligible, excluded);

writetable(postExtensionFeasibility, ...
    fullfile(cfg.tablesDir, 'phase12c_post_extension_feasibility.csv'));
writetable(eligible,        fullfile(cfg.tablesDir, 'phase12c_kpi_update_eligible_actions.csv'));
writetable(excluded,        fullfile(cfg.tablesDir, 'phase12c_kpi_update_excluded_actions.csv'));
writetable(moduleSummary,   fullfile(cfg.tablesDir, 'phase12c_eligible_summary_by_module.csv'));
writetable(actionSummary,   fullfile(cfg.tablesDir, 'phase12c_eligible_summary_by_action_type.csv'));

validationTable = validate_phase12c_kpi_eligible_actions(cfg, executable, ...
    postExtensionFeasibility, eligible, excluded, moduleSummary, actionSummary);

phase12c = struct();
phase12c.executableReviewed = executable;
phase12c.postExtensionFeasibility = postExtensionFeasibility;
phase12c.eligible = eligible;
phase12c.excluded = excluded;
phase12c.moduleSummary = moduleSummary;
phase12c.actionSummary = actionSummary;
phase12c.validationTable = validationTable;
phase12c.numReviewed = height(executable);
phase12c.numEligible = height(eligible);
phase12c.numExcluded = height(excluded);
phase12c.eligibleModules = unique(string(eligible.module_name));
phase12c.eligibleActionTypes = unique(string(eligible.action_type));
end
