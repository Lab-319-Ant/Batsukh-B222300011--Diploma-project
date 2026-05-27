function manifest = build_final_figure_manifest(cfg)
%BUILD_FINAL_FIGURE_MANIFEST Map thesis figures to file paths and roles.
%
% figure_role values:
%   main_thesis_figure   - safe to use as primary result figure
%   diagnostic_only      - appendix / text reference, NOT a main result
%   appendix_only        - context figure (topology, maps)
%   avoid_as_main_result - explicitly do NOT use as primary result

entries = {
    'topology_map',                     'phase1b_topology_ue_attachment.png',         'appendix_only',     '7-site / 21-sector topology with UE placement and attachment';
    'ue_distribution_map',              'phase1b_topology_ue_attachment.png',         'appendix_only',     'UE locations over the planned coverage union';
    'best_server_map',                  'phase1b_best_server_map.png',                'appendix_only',     'Best-server per pixel over the study window';
    'rsrp_map',                         'phase1b_best_rsrp_map.png',                  'main_thesis_figure','Best RSRP heatmap';
    'sinr_map',                         'phase1b_best_sinr_map.png',                  'main_thesis_figure','Best SINR heatmap';
    'sector_load_map',                  'phase2_sector_load_map.png',                 'main_thesis_figure','Sector-level offered/served load';
    'cluster_state_map',                'phase5_cluster_scenario_heatmap.png',        'main_thesis_figure','Scenario x cluster heatmap';
    'cluster_pca',                      'phase5_cluster_pca.png',                     'diagnostic_only',   'Sector state PCA projection';
    'cod_confusion_matrix',             'phase6b_cod_external_confusion_matrix.png',  'main_thesis_figure','COD external (imbalanced) confusion matrix';
    'cod_feature_importance',           'phase6b_cod_feature_importance.png',         'appendix_only',     'COD feature importance';
    'tp_actual_vs_predicted',           'phase7b_tp_actual_vs_predicted.png',         'main_thesis_figure','TP regression actual vs predicted';
    'qp_target_distribution_by_scenario','phase7c_qp_target_variance_by_scenario.png','main_thesis_figure','QP target distribution by scenario - bimodal target (main QP evidence)';
    'qp_bounded_actual_vs_predicted',   'phase7c_qp_bounded_actual_vs_predicted.png', 'diagnostic_only',   'QP bounded actual vs predicted - diagnostic, use with target-distribution context';
    'qp_raw_actual_vs_predicted',       'phase7b_qp_actual_vs_predicted.png',         'avoid_as_main_result','Raw QP actual-vs-predicted; misleading without bimodal-target context';
    'phase8a_candidate_action_counts',  'phase8a_candidate_action_counts.png',        'appendix_only',     'Phase 8A candidate action counts by module x action type';
    'phase9b_action_value_actual_vs_predicted', 'phase9b_action_value_actual_vs_predicted.png', 'diagnostic_only', 'Phase 9B per-module action-value scatter - diagnostic only';
    'phase9b_action_value_oracle_regret','phase9b_action_value_oracle_regret.png',    'main_thesis_figure','Phase 9B oracle regret boxplot (ranking-quality evidence)';
    'phase9b_action_value_top_k_match', 'phase9b_action_value_error_by_module.png',   'main_thesis_figure','Phase 9B per-module ranking error / top-k context';
    'phase10a_raw_vs_safe_selection',   'phase10a_raw_vs_safe_selection.png',         'main_thesis_figure','Phase 10A safety filter changes per module';
    'phase10a_regret_by_module',        'phase10a_regret_by_module.png',              'main_thesis_figure','Phase 10A raw vs safety-enforced mean regret';
    'phase11a_conflict_counts',         'phase11a_conflict_counts.png',               'appendix_only',     'Phase 11A conflict count by type';
    'phase11b_final_decision_status',   'phase11b_final_decision_status.png',         'main_thesis_figure','Phase 11B final decision status distribution';
    'phase12d_pre_post_kpi_by_module',  'phase12d_pre_post_kpi_by_module.png',        'main_thesis_figure','Phase 12D pre vs post KPI delta by module';
    'phase12d_rsrp_sinr_change',        'phase12d_rsrp_sinr_change.png',              'main_thesis_figure','Phase 12D RSRP vs SINR change per applied action';
    'phase12e_baseline_ai_oracle_kpis', 'phase12e_baseline_ai_oracle_kpis.png',       'main_thesis_figure','Phase 12E mean QoS baseline vs AI/ML vs oracle';
    'phase12e_tradeoff_attach_vs_qos',  'phase12e_tradeoff_attach_vs_qos.png',        'main_thesis_figure','Phase 12E attach-rate vs QoS tradeoff scatter';
    'phase12e_kpi_delta_by_scenario',   'phase12e_kpi_delta_by_scenario.png',         'main_thesis_figure','Phase 12E mean delta KPIs per scenario';
    'phase12e_oracle_gap_by_module',    'phase12e_oracle_gap_by_module.png',          'main_thesis_figure','Phase 12E mean QoS gap to oracle per module';
    'phase12e_final_outcome_counts',    'phase12e_final_outcome_counts.png',          'main_thesis_figure','Phase 12E final outcome class counts';
    'final_before_after_kpi_comparison','final_before_after_kpi_comparison.png',      'main_thesis_figure','Phase 13 final before-vs-after KPI grouped bar chart';
    };

n = size(entries, 1);
keys = entries(:, 1);
files = entries(:, 2);
roles = entries(:, 3);
descs = entries(:, 4);
fullPaths = cell(n, 1);
exists = false(n, 1);
for i = 1:n
    candidate = fullfile(cfg.figuresDir, files{i});
    if isfile(candidate)
        fullPaths{i} = candidate;
        exists(i) = true;
    else
        thesisCandidate = fullfile(cfg.resultsDir, 'thesis_package', files{i});
        if isfile(thesisCandidate)
            fullPaths{i} = thesisCandidate;
            exists(i) = true;
        else
            fullPaths{i} = candidate;
        end
    end
end

manifest = table(keys, files, fullPaths, exists, roles, descs, ...
    'VariableNames', {'figure_key','file_name','full_path','available_flag','figure_role','description'});
end
