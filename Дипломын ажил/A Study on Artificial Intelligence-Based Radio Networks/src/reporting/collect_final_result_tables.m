function bundle = collect_final_result_tables(cfg)
%COLLECT_FINAL_RESULT_TABLES Gather upstream summaries needed for Phase 13.
%
% Reads result CSVs written by earlier phases. Returns a struct with the
% loaded tables; missing files become empty tables rather than errors so
% the reporting layer can still run when an optional output is absent.

bundle = struct();
files = {
    'phase4b_ml_feature_validation',  'phase4b_validation';
    'phase5_clustering_validation',   'phase5_validation';
    'phase6b_cod_test_metrics',       'phase6b_test_metrics';
    'phase6b_cod_external_metrics',   'phase6b_external_metrics';
    'phase7b_tp_metrics',             'phase7b_tp_metrics';
    'phase7b_qp_metrics',             'phase7b_qp_metrics';
    'phase7b_tp_qp_validation',       'phase7b_validation';
    'phase7c_qp_bounded_prediction_metrics', 'phase7c_qp_bounded';
    'phase7c_tp_qp_diagnostic_validation', 'phase7c_validation';
    'phase8a_candidate_action_summary','phase8a_summary';
    'phase8a_candidate_action_validation','phase8a_validation';
    'phase8b_counterfactual_summary_by_module','phase8b_summary';
    'phase8b_counterfactual_validation','phase8b_validation';
    'phase8c_oracle_summary_by_module','phase8c_summary';
    'phase8c_oracle_safety_summary',  'phase8c_safety';
    'phase8c_oracle_validation',      'phase8c_validation';
    'phase9a_action_value_dataset_summary','phase9a_summary';
    'phase9a_action_value_validation','phase9a_validation';
    'phase9b_action_value_metrics',   'phase9b_metrics';
    'phase9b_action_value_validation','phase9b_validation';
    'phase10a_summary_by_module',     'phase10a_summary';
    'phase10a_safety_filter_summary', 'phase10a_safety';
    'phase10a_safety_enforced_validation','phase10a_validation';
    'phase11a_summary_by_module',     'phase11a_summary';
    'phase11a_coordination_validation','phase11a_validation';
    'phase11b_summary_by_module',     'phase11b_summary';
    'phase11b_final_coordination_validation','phase11b_validation';
    'phase12a_implementability_summary_by_module','phase12a_summary';
    'phase12a_feasibility_validation','phase12a_validation';
    'phase12b_action_state_validation','phase12b_validation';
    'phase12c_eligible_summary_by_module','phase12c_summary';
    'phase12c_kpi_eligible_validation','phase12c_validation';
    'phase12d_summary_by_module',     'phase12d_module';
    'phase12d_summary_by_scenario',   'phase12d_scenario';
    'phase12d_one_step_validation',   'phase12d_validation';
    'phase12e_summary_by_module',     'phase12e_module';
    'phase12e_summary_by_scenario',   'phase12e_scenario';
    'phase12e_tradeoff_summary',      'phase12e_tradeoff';
    'phase12e_baseline_ai_kpi_comparison','phase12e_baseline_ai';
    'phase12e_baseline_ai_oracle_comparison','phase12e_oracle_compare';
    'phase12e_final_comparison_validation','phase12e_validation';
    };

for i = 1:size(files, 1)
    bundle.(files{i, 2}) = safe_read(fullfile(cfg.tablesDir, [files{i, 1} '.csv']));
end
end

function T = safe_read(filePath)
if isfile(filePath)
    try
        T = readtable(filePath);
    catch
        T = table();
    end
else
    T = table();
end
end
