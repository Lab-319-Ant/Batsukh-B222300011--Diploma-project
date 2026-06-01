function out = run_current_architecture_manifest(cfg)
%RUN_CURRENT_ARCHITECTURE_MANIFEST Create current workflow/figure/validation manifests.
%
% This reporting helper does not run simulation, train models, apply actions,
% or change any existing Phase 8-13 result tables. It only summarizes current
% artifacts into user-readable files.

if nargin < 1 || isempty(cfg)
    cfg = sim_config();
end

reportsDir = fullfile(cfg.resultsDir, 'reports');
ensure_folder(cfg.tablesDir);
ensure_folder(cfg.figuresDir);
ensure_folder(reportsDir);

plot_current_architecture_workflow(cfg);

figureManifest = build_simulation_figure_manifest(cfg);
validationManifest = build_validation_split_manifest(cfg);

writetable(figureManifest, fullfile(cfg.tablesDir, 'current_simulation_figure_manifest.csv'));
writetable(validationManifest, fullfile(cfg.tablesDir, 'current_validation_train_split_manifest.csv'));

write_current_architecture_report(cfg, reportsDir, figureManifest, validationManifest);

out = struct();
out.figureManifest = figureManifest;
out.validationManifest = validationManifest;
out.reportPath = fullfile(reportsDir, 'current_architecture_workflow_and_validation.md');
out.workflowFigurePath = fullfile(cfg.figuresDir, 'current_system_architecture_workflow.png');
end

function T = build_simulation_figure_manifest(cfg)
rows = {
    'system_architecture_workflow', 'results/figures/current_system_architecture_workflow.png', 'Architecture', 'Overall simulator and ML workflow diagram';
    'topology_and_ue_attachment', 'results/figures/phase1b_topology_ue_attachment.png', 'Network/UE/RF', '7-site / 21-sector topology with UE attachment';
    'best_server_map', 'results/figures/phase1b_best_server_map.png', 'Network/UE/RF', 'Best serving sector map';
    'best_rsrp_map', 'results/figures/phase1b_best_rsrp_map.png', 'Network/UE/RF', 'Best RSRP map';
    'best_sinr_map', 'results/figures/phase1b_best_sinr_map.png', 'Network/UE/RF', 'Best SINR map';
    'sector_load_map', 'results/figures/phase2_sector_load_map.png', 'Traffic/KPI', 'Traffic-aware sector load map';
    'ue_throughput_map', 'results/figures/phase2_ue_throughput_map.png', 'Traffic/KPI', 'UE throughput map';
    'qos_satisfaction_map', 'results/figures/phase2_qos_satisfaction_map.png', 'Traffic/KPI', 'UE QoS satisfaction map';
    'scenario_summary', 'results/figures/phase3_scenario_summary.png', 'Scenarios', 'Scenario-level KPI summary';
    'dataset_summary', 'results/figures/phase4_dataset_summary.png', 'Dataset', 'Multi-scenario dataset summary';
    'cluster_pca', 'results/figures/phase5_cluster_pca.png', 'Clustering', 'Cluster state PCA diagnostic';
    'cluster_scenario_heatmap', 'results/figures/phase5_cluster_scenario_heatmap.png', 'Clustering', 'Cluster by scenario heatmap';
    'cod_confusion_matrix', 'results/figures/phase6b_cod_test_confusion_matrix.png', 'COD', 'COD test confusion matrix';
    'tp_actual_vs_predicted', 'results/figures/phase7b_tp_actual_vs_predicted.png', 'TP/QP', 'TP actual vs predicted load';
    'qp_bounded_density', 'results/figures/phase7d_qp_bounded_actual_vs_predicted_with_density.png', 'TP/QP', 'QP bounded diagnostic with density';
    'candidate_action_counts', 'results/figures/phase8a_candidate_action_counts.png', 'Actions', 'Candidate action counts';
    'action_value_regret', 'results/figures/phase9b_action_value_oracle_regret.png', 'Action-value ML', 'Action-value oracle regret preview';
    'safety_raw_vs_safe', 'results/figures/phase10a_raw_vs_safe_selection.png', 'Safety', 'Raw vs safety-enforced selection';
    'coordinator_conflict_counts', 'results/figures/phase11a_conflict_counts.png', 'Coordinator', 'Coordinator conflict counts';
    'final_decision_status', 'results/figures/phase11b_final_decision_status.png', 'Coordinator', 'Final decision status';
    'one_step_pre_post_kpi', 'results/figures/phase12d_pre_post_kpi_by_module.png', 'One-step KPI', 'Pre/post KPI by module for applied actions';
    'baseline_ai_oracle_kpis', 'results/figures/phase12e_baseline_ai_oracle_kpis.png', 'Final comparison', 'Baseline vs AI/ML vs oracle KPI comparison';
    'attach_qos_tradeoff', 'results/figures/phase12e_tradeoff_attach_vs_qos.png', 'Final comparison', 'Attach vs QoS tradeoff';
    'phase13_before_after_kpi', 'results/thesis_package/final_before_after_kpi_comparison.png', 'Thesis package', 'Final packaged before/after KPI comparison'
    };

names = rows(:, 1);
paths = rows(:, 2);
layers = rows(:, 3);
notes = rows(:, 4);
existsFlag = false(size(paths));
for i = 1:numel(paths)
    existsFlag(i) = isfile(fullfile(fileparts(cfg.resultsDir), paths{i}));
end

T = table(names, paths, existsFlag, layers, notes, ...
    'VariableNames', {'artifact_name','relative_path','exists_flag','layer','notes'});
end

function T = build_validation_split_manifest(cfg)
rows = {
    'RF baseline', 'phase1b_summary.csv', '', '', 'RF/topology summary; no ML split';
    'Scenario dataset', 'phase4_dataset_validation.csv', '', '', 'Dataset consistency, KPI ranges, scenario sanity';
    'ML feature tables', 'phase4b_ml_feature_validation.csv', '', 'phase4b_feature_dictionary.csv', 'Leakage-controlled clustering/COD/TPQP feature tables';
    'Clustering monitor', 'phase5_clustering_validation.csv', '', '', 'Clustering output and monitor sanity checks';
    'COD dataset', 'phase6a_cod_dataset_validation.csv', 'phase6a_cod_split_plan.csv', 'phase6a_cod_feature_list.csv', 'COD has explicit split plan';
    'COD classifier', 'phase6b_cod_model_validation.csv', 'phase6a_cod_split_plan.csv', 'phase6a_cod_feature_list.csv', 'Train/validation/test metrics and confusion matrices';
    'Temporal TP/QP dataset', 'phase7a_dataset_validation.csv', '', 'phase7a_sector_tp_qp_feature_dictionary.csv', 'Temporal target and feature-table validation';
    'TP/QP regression', 'phase7b_tp_qp_validation.csv', 'phase7b_tp_qp_split_summary.csv', 'phase7a_sector_tp_qp_feature_dictionary.csv', 'Walk-forward train/validation/test split';
    'QP audit', 'phase7d_qp_audit_validation.csv', 'phase7d_qp_split_audit.csv', 'phase7d_qp_target_formula_audit.csv', 'QP target and split limitation audit';
    'Candidate actions', 'phase8a_candidate_action_validation.csv', '', '', 'Candidate action table validation';
    'Counterfactual action evaluation', 'phase8b_counterfactual_validation.csv', '', '', 'Reward/safety/counterfactual table validation';
    'Safety-constrained oracle', 'phase8c_oracle_validation.csv', '', '', 'Oracle benchmark validation';
    'Action-value dataset', 'phase9a_action_value_validation.csv', '', 'phase9a_action_value_feature_dictionary.csv', 'Action-value dataset and leakage validation';
    'Action-value models', 'phase9b_action_value_validation.csv', 'phase9b_action_value_split_summary.csv', 'phase9a_action_value_feature_dictionary.csv', 'Group-aware action-value split and model validation';
    'Safety-enforced ML selection', 'phase10a_safety_enforced_validation.csv', '', '', 'Safety filter validation';
    'Coordinator preparation', 'phase11a_coordination_validation.csv', '', '', 'Conflict detection/resolution validation';
    'Final coordinator table', 'phase11b_final_coordination_validation.csv', '', '', 'Executable/fallback/rejected row validation';
    'Action feasibility', 'phase12a_feasibility_validation.csv', '', '', 'Implementability audit';
    'Simulator action-state support', 'phase12b_action_state_validation.csv', '', '', 'CIO/PRS/tilt/clone integrity validation';
    'KPI-update eligibility', 'phase12c_kpi_eligible_validation.csv', '', '', 'Eligible COC/OH and LB/MLB only';
    'One-step KPI update', 'phase12d_one_step_validation.csv', '', '', 'Applied-action and post-KPI validation';
    'Final comparison', 'phase12e_final_comparison_validation.csv', '', '', 'Baseline vs AI/ML vs oracle validation';
    'Thesis package', '../thesis_package/final_result_package_validation.csv', '', '', 'Package integrity validation'
    };

layer = rows(:, 1);
validationFile = rows(:, 2);
splitFile = rows(:, 3);
featureFile = rows(:, 4);
notes = rows(:, 5);

validationExists = false(size(validationFile));
splitExists = false(size(splitFile));
featureExists = false(size(featureFile));
failedErrors = nan(size(validationFile));
failedWarnings = nan(size(validationFile));
for i = 1:numel(validationFile)
    vf = fullfile(cfg.tablesDir, validationFile{i});
    if startsWith(validationFile{i}, '../thesis_package')
        vf = fullfile(cfg.resultsDir, 'thesis_package', 'final_result_package_validation.csv');
    end
    validationExists(i) = isfile(vf);
    if validationExists(i)
        V = readtable(vf);
        if all(ismember({'severity','pass_flag'}, V.Properties.VariableNames))
            failedErrors(i) = sum(strcmp(V.severity, 'error') & ~logical(V.pass_flag));
            failedWarnings(i) = sum(strcmp(V.severity, 'warning') & ~logical(V.pass_flag));
        else
            failedErrors(i) = 0;
            failedWarnings(i) = 0;
        end
    end
    if ~isempty(splitFile{i})
        splitExists(i) = isfile(fullfile(cfg.tablesDir, splitFile{i}));
    end
    if ~isempty(featureFile{i})
        featureExists(i) = isfile(fullfile(cfg.tablesDir, featureFile{i}));
    end
end

T = table(layer, validationFile, validationExists, failedErrors, failedWarnings, ...
    splitFile, splitExists, featureFile, featureExists, notes, ...
    'VariableNames', {'layer','validation_file','validation_exists','failed_error_checks', ...
    'failed_warning_checks','split_file','split_exists','feature_or_dictionary_file', ...
    'feature_or_dictionary_exists','notes'});
end

function plot_current_architecture_workflow(cfg)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1500 900]);
axis off;

boxes = {
    0.05, 0.80, 0.22, 0.10, 'Synthetic LTE RAN', '7 sites / 21 sectors\newline UE + RF + traffic + KPI';
    0.38, 0.80, 0.22, 0.10, 'Scenario + Dataset', 'normal / overload / outage\newline validation + leakage control';
    0.71, 0.80, 0.22, 0.10, 'ML Support', 'clustering, COD, TP/QP\newline train/validation/test';
    0.05, 0.55, 0.22, 0.10, 'Action Modules', 'COC/OH, LB/MLB, ES, HO/MRO\newline discrete candidates';
    0.38, 0.55, 0.22, 0.10, 'Counterfactual + Oracle', 'reward table\newline safety-constrained oracle';
    0.71, 0.55, 0.22, 0.10, 'Action-Value ML', 'module regressors\newline predicted reward + regret';
    0.05, 0.30, 0.22, 0.10, 'Safety Filter', 'reject unsafe\newline fallback/no-op if needed';
    0.38, 0.30, 0.22, 0.10, 'Offline Coordinator', 'priority + conflict resolution\newline final action table';
    0.71, 0.30, 0.22, 0.10, 'One-Step KPI Update', 'cloned state only\newline COC/OH + LB/MLB applied';
    0.38, 0.08, 0.22, 0.10, 'Final Reporting', 'baseline vs AI/ML vs oracle\newline thesis package'
    };

for i = 1:size(boxes, 1)
    x = boxes{i, 1}; y = boxes{i, 2}; w = boxes{i, 3}; h = boxes{i, 4};
    annotation(fig, 'rectangle', [x y w h], 'Color', [0.15 0.25 0.35], 'LineWidth', 1.4);
    annotation(fig, 'textbox', [x+0.005 y+h-0.04 w-0.01 0.035], 'String', boxes{i, 5}, ...
        'FontWeight', 'bold', 'FontSize', 12, 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
    annotation(fig, 'textbox', [x+0.005 y+0.005 w-0.01 h-0.045], 'String', boxes{i, 6}, ...
        'FontSize', 10, 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
end

arrows = {
    [0.27 0.49], [0.85 0.85];
    [0.60 0.72], [0.85 0.85];
    [0.82 0.16], [0.80 0.65];
    [0.16 0.16], [0.80 0.65];
    [0.27 0.38], [0.60 0.60];
    [0.60 0.71], [0.60 0.60];
    [0.82 0.16], [0.55 0.40];
    [0.27 0.38], [0.35 0.35];
    [0.60 0.71], [0.35 0.35];
    [0.82 0.49], [0.30 0.18]
    };
for i = 1:size(arrows, 1)
    annotation(fig, 'arrow', arrows{i, 1}, arrows{i, 2}, 'LineWidth', 1.2);
end

annotation(fig, 'textbox', [0.05 0.94 0.90 0.04], 'String', ...
    'Current LTE SON-Inspired Simulation Workflow', 'FontWeight', 'bold', ...
    'FontSize', 18, 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
annotation(fig, 'textbox', [0.05 0.01 0.90 0.04], 'String', ...
    'Note: current physical KPI(t)->KPI(t+1) update applies COC/OH and LB/MLB only; ES and HO/MRO remain offline candidate/decision-support modules.', ...
    'FontSize', 10, 'EdgeColor', 'none', 'HorizontalAlignment', 'center');

save_figure(fig, fullfile(cfg.figuresDir, 'current_system_architecture_workflow.png'));
close(fig);
end

function write_current_architecture_report(cfg, reportsDir, figureManifest, validationManifest)
fid = fopen(fullfile(reportsDir, 'current_architecture_workflow_and_validation.md'), 'w');
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, '# Current Architecture, Figures, Validation, and Split Summary\n\n');
fprintf(fid, '## System Name\n\n');
fprintf(fid, 'Use this exact safe name for the implemented code:\n\n');
fprintf(fid, '**AI/ML-assisted LTE SON-inspired synthetic simulation framework with offline coordination and limited one-step KPI(t)->KPI(t+1) evaluation.**\n\n');
fprintf(fid, 'Do not claim full commercial AI-RAN, full 3GPP SON, ES physical sleep, HO/MRO physical HOM/TTT execution, or multi-step closed-loop control unless those features are implemented later.\n\n');

fprintf(fid, '## Workflow\n\n');
fprintf(fid, '1. Synthetic LTE topology, UE placement, RF, traffic, and KPI generation.\n');
fprintf(fid, '2. Scenario generation and validated datasets.\n');
fprintf(fid, '3. Clustering/COD/TP/QP support models with train/validation/test where applicable.\n');
fprintf(fid, '4. Candidate action generation for COC/OH, LB/MLB, ES, and HO/MRO.\n');
fprintf(fid, '5. Counterfactual reward and safety-constrained oracle benchmark.\n');
fprintf(fid, '6. Action-value regression, safety filtering, and offline coordinator.\n');
fprintf(fid, '7. One-step cloned-state KPI update for simulator-supported COC/OH and LB/MLB actions.\n');
fprintf(fid, '8. Baseline vs AI/ML vs oracle validation and thesis packaging.\n\n');

fprintf(fid, '## Main Simulation Figures\n\n');
for i = 1:height(figureManifest)
    fprintf(fid, '- `%s`: `%s` (%s)\n', figureManifest.artifact_name{i}, ...
        figureManifest.relative_path{i}, true_false(figureManifest.exists_flag(i)));
end

fprintf(fid, '\n## Validation and Split Files\n\n');
for i = 1:height(validationManifest)
    fprintf(fid, '- %s: validation `%s` (%s), errors=%s, warnings=%s', ...
        validationManifest.layer{i}, validationManifest.validation_file{i}, ...
        true_false(validationManifest.validation_exists(i)), ...
        num_to_text(validationManifest.failed_error_checks(i)), ...
        num_to_text(validationManifest.failed_warning_checks(i)));
    if ~isempty(validationManifest.split_file{i})
        fprintf(fid, ', split `%s` (%s)', validationManifest.split_file{i}, ...
            true_false(validationManifest.split_exists(i)));
    end
    if ~isempty(validationManifest.feature_or_dictionary_file{i})
        fprintf(fid, ', features `%s` (%s)', validationManifest.feature_or_dictionary_file{i}, ...
            true_false(validationManifest.feature_or_dictionary_exists(i)));
    end
    fprintf(fid, '.\n');
end
end

function s = true_false(v)
if v
    s = 'exists';
else
    s = 'missing';
end
end

function s = num_to_text(v)
if isnan(v)
    s = 'n/a';
else
    s = sprintf('%d', round(v));
end
end
