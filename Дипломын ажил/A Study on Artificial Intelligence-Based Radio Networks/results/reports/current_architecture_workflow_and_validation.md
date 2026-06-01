# Current Architecture, Figures, Validation, and Split Summary

## System Name

Use this exact safe name for the implemented code:

**AI/ML-assisted LTE SON-inspired synthetic simulation framework with offline coordination and limited one-step KPI(t)->KPI(t+1) evaluation.**

Do not claim full commercial AI-RAN, full 3GPP SON, ES physical sleep, HO/MRO physical HOM/TTT execution, or multi-step closed-loop control unless those features are implemented later.

## Workflow

1. Synthetic LTE topology, UE placement, RF, traffic, and KPI generation.
2. Scenario generation and validated datasets.
3. Clustering/COD/TP/QP support models with train/validation/test where applicable.
4. Candidate action generation for COC/OH, LB/MLB, ES, and HO/MRO.
5. Counterfactual reward and safety-constrained oracle benchmark.
6. Action-value regression, safety filtering, and offline coordinator.
7. One-step cloned-state KPI update for simulator-supported COC/OH and LB/MLB actions.
8. Baseline vs AI/ML vs oracle validation and thesis packaging.

## Main Simulation Figures

- `system_architecture_workflow`: `results/figures/current_system_architecture_workflow.png` (exists)
- `topology_and_ue_attachment`: `results/figures/phase1b_topology_ue_attachment.png` (exists)
- `best_server_map`: `results/figures/phase1b_best_server_map.png` (exists)
- `best_rsrp_map`: `results/figures/phase1b_best_rsrp_map.png` (exists)
- `best_sinr_map`: `results/figures/phase1b_best_sinr_map.png` (exists)
- `sector_load_map`: `results/figures/phase2_sector_load_map.png` (exists)
- `ue_throughput_map`: `results/figures/phase2_ue_throughput_map.png` (exists)
- `qos_satisfaction_map`: `results/figures/phase2_qos_satisfaction_map.png` (exists)
- `scenario_summary`: `results/figures/phase3_scenario_summary.png` (exists)
- `dataset_summary`: `results/figures/phase4_dataset_summary.png` (exists)
- `cluster_pca`: `results/figures/phase5_cluster_pca.png` (exists)
- `cluster_scenario_heatmap`: `results/figures/phase5_cluster_scenario_heatmap.png` (exists)
- `cod_confusion_matrix`: `results/figures/phase6b_cod_test_confusion_matrix.png` (exists)
- `tp_actual_vs_predicted`: `results/figures/phase7b_tp_actual_vs_predicted.png` (exists)
- `qp_bounded_density`: `results/figures/phase7d_qp_bounded_actual_vs_predicted_with_density.png` (exists)
- `candidate_action_counts`: `results/figures/phase8a_candidate_action_counts.png` (exists)
- `action_value_regret`: `results/figures/phase9b_action_value_oracle_regret.png` (exists)
- `safety_raw_vs_safe`: `results/figures/phase10a_raw_vs_safe_selection.png` (exists)
- `coordinator_conflict_counts`: `results/figures/phase11a_conflict_counts.png` (exists)
- `final_decision_status`: `results/figures/phase11b_final_decision_status.png` (exists)
- `one_step_pre_post_kpi`: `results/figures/phase12d_pre_post_kpi_by_module.png` (exists)
- `baseline_ai_oracle_kpis`: `results/figures/phase12e_baseline_ai_oracle_kpis.png` (exists)
- `attach_qos_tradeoff`: `results/figures/phase12e_tradeoff_attach_vs_qos.png` (exists)
- `phase13_before_after_kpi`: `results/thesis_package/final_before_after_kpi_comparison.png` (exists)

## Validation and Split Files

- RF baseline: validation `phase1b_summary.csv` (exists), errors=0, warnings=0.
- Scenario dataset: validation `phase4_dataset_validation.csv` (exists), errors=0, warnings=0.
- ML feature tables: validation `phase4b_ml_feature_validation.csv` (exists), errors=0, warnings=0, features `phase4b_feature_dictionary.csv` (exists).
- Clustering monitor: validation `phase5_clustering_validation.csv` (exists), errors=0, warnings=1.
- COD dataset: validation `phase6a_cod_dataset_validation.csv` (exists), errors=0, warnings=0, split `phase6a_cod_split_plan.csv` (exists), features `phase6a_cod_feature_list.csv` (exists).
- COD classifier: validation `phase6b_cod_model_validation.csv` (exists), errors=0, warnings=0, split `phase6a_cod_split_plan.csv` (exists), features `phase6a_cod_feature_list.csv` (exists).
- Temporal TP/QP dataset: validation `phase7a_dataset_validation.csv` (exists), errors=0, warnings=0, features `phase7a_sector_tp_qp_feature_dictionary.csv` (exists).
- TP/QP regression: validation `phase7b_tp_qp_validation.csv` (exists), errors=0, warnings=0, split `phase7b_tp_qp_split_summary.csv` (exists), features `phase7a_sector_tp_qp_feature_dictionary.csv` (exists).
- QP audit: validation `phase7d_qp_audit_validation.csv` (exists), errors=0, warnings=1, split `phase7d_qp_split_audit.csv` (exists), features `phase7d_qp_target_formula_audit.csv` (exists).
- Candidate actions: validation `phase8a_candidate_action_validation.csv` (exists), errors=0, warnings=0.
- Counterfactual action evaluation: validation `phase8b_counterfactual_validation.csv` (exists), errors=0, warnings=0.
- Safety-constrained oracle: validation `phase8c_oracle_validation.csv` (exists), errors=0, warnings=0.
- Action-value dataset: validation `phase9a_action_value_validation.csv` (exists), errors=0, warnings=0, features `phase9a_action_value_feature_dictionary.csv` (exists).
- Action-value models: validation `phase9b_action_value_validation.csv` (exists), errors=0, warnings=2, split `phase9b_action_value_split_summary.csv` (exists), features `phase9a_action_value_feature_dictionary.csv` (exists).
- Safety-enforced ML selection: validation `phase10a_safety_enforced_validation.csv` (exists), errors=0, warnings=1.
- Coordinator preparation: validation `phase11a_coordination_validation.csv` (exists), errors=0, warnings=0.
- Final coordinator table: validation `phase11b_final_coordination_validation.csv` (exists), errors=0, warnings=0.
- Action feasibility: validation `phase12a_feasibility_validation.csv` (exists), errors=0, warnings=0.
- Simulator action-state support: validation `phase12b_action_state_validation.csv` (exists), errors=0, warnings=0.
- KPI-update eligibility: validation `phase12c_kpi_eligible_validation.csv` (exists), errors=0, warnings=0.
- One-step KPI update: validation `phase12d_one_step_validation.csv` (exists), errors=0, warnings=1.
- Final comparison: validation `phase12e_final_comparison_validation.csv` (exists), errors=0, warnings=1.
- Thesis package: validation `../thesis_package/final_result_package_validation.csv` (exists), errors=0, warnings=0.
