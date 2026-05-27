# AI/ML-Assisted LTE SON-Inspired Simulation

This MATLAB project is a simulation-based LTE RAN framework under staged development. The active thesis workflow uses supervised ML models only: COD classification, TP/QP regression, and supervised action-value reward regression. It includes an offline safety/coordinator chain. It does not claim real deployment, live AI-RAN operation, full 3GPP SON compliance, or full closed-loop SON control.

The current thesis-safe implementation is Phase 12E: limited one-step KPI(t) -> KPI(t+1) validation and baseline vs AI/ML vs oracle comparison. The KPI(t+1) step is intentionally narrow:

- Only final, safety-valid, executable COC/OH and LB/MLB actions are physically applied.
- COC/OH can modify target-sector reference-power offset, tilt, and CIO when those parameters are selected.
- LB/MLB CIO bias modifies the target sector `sectors.cio_dB` and affects association bias only.
- ES and HO/MRO remain not physically applied to RF/KPI in the KPI(t)->KPI(t+1) stage.
- ES sleep is not implemented as physical cell sleep.
- HO/MRO HOM/TTT are not implemented as physical handover-parameter changes.
- The evaluation is one-step cloned-state evaluation, not a multi-step closed-loop controller.

Phase 13 packaging is disabled by default until the supervised-only result package is regenerated. Existing `results/thesis_package` outputs should be treated as stale until Phase 13 is explicitly enabled again.

Supported run modes are configured in `config/sim_config.m` using `cfg.runMode`, or by setting the `LTE_SON_RUN_MODE` environment variable:

- `full`: run the full staged pipeline.
- `phase4_only`: regenerate only the Phase 4 multi-scenario dataset.
- `phase8a_only`: reuse existing upstream tables and regenerate Phase 8A plus Phase 8B if enabled.
- `reuse_phase4_to_phase8a`: reuse Phase 4 tables, rebuild Phase 4B/6A/6B, then run Phase 8A and Phase 8B. Phase 5 K-means is skipped when `cfg.enableUnsupervisedClustering = false`.
- `fast_debug`: reduced-size debug run for code checks only.

Run in MATLAB:

```matlab
main
```

## Phase 1B RF Baseline

- Estimate planned LTE coverage radius from a link-budget MAPL calculation.
- Convert planned cell radius to hexagonal ISD using `ISD = sqrt(3) * R_cell`.
- Build one shared 7-site / 21-sector LTE macro topology.
- Drop UEs over the planned coverage union.
- Compute multi-sector RSRP using LTE reference signal power.
- Compute SINR using total received serving-sector power, inter-sector interference, and thermal noise.
- Select best serving sector by maximum RSRP.
- Determine RF-attached and unattached UEs from RSRP and SINR thresholds.

## Phase 2 Traffic And KPI Scope

Phase 1B validated RF-level coverage, RSRP, SINR, and attachment behavior. It did not model traffic demand, sector capacity, congestion, PRB usage, or QoS satisfaction.

Phase 2 adds:

- UE traffic demand assignment.
- Simplified SINR-to-spectral-efficiency mapping.
- Simplified wideband sector throughput allocation.
- Sector offered traffic, served traffic, unserved traffic, load, overload, and QoS KPIs.
- Network-level traffic, load, fairness, and QoS KPIs.

This is not a real LTE scheduler. The capacity model is a simplified wideband approximation used to create traffic-aware KPI data before scenario generation and ML.

## Phase 2C Traffic Calibration Scope

Phase 2C calibrates offered traffic before scenario generation. It keeps the same RF topology, UE locations, RSRP, SINR, and RF attachment state, then tests multiple traffic modes:

- `low_load`: 5% active UEs, 0.5-3 Mbps demand.
- `normal`: 15% active UEs, 1-8 Mbps demand.
- `overload`: 30% active UEs, 3-12 Mbps demand.
- `heavy_overload`: 100% active UEs, 20-80 Mbps demand.

RF attachment remains separate from QoS satisfaction. Inactive UEs are not counted as QoS failures. QoS satisfaction is evaluated over active traffic-demand UEs.

## Phase 3 Scenario Generation Scope

Phase 3 generates synthetic LTE network scenarios over the same 7-site / 21-sector topology. The scenarios modify traffic load, sector status, or sector impairment to produce different KPI states.

Implemented scenarios:

- `normal`
- `low_load`
- `overload`
- `degraded_sector`
- `outage_sector`
- `low_load_energy_saving_candidate`
- `handover_stress`
- `mixed_conflict`

This phase prepares labeled simulation data for later COD, load balancing, energy saving, handover optimization, oracle benchmarking, and ML-based modules. No ML model, SON action selection, oracle benchmark, or closed-loop control is implemented in Phase 3.

## Phase 3B Sanity Validation Scope

Phase 3B validates whether the generated scenarios produce distinct KPI states. In particular, the handover-stress scenario is refined by increasing the proportion of UEs near sector-boundary regions, measured using the best-versus-second-best RSRP gap. A scenario-specific handover-stress risk threshold is used for risk labeling only; it does not change RF attachment or SINR equations.

This is still a synthetic handover-risk indicator, not a full mobility model and not HO/MRO control.

## Phase 4 Dataset Scope

Phase 4 generates a reusable multi-scenario KPI dataset from repeated synthetic realizations. It varies scenario type, random seeds, UE sampling, traffic demand, shadowing, and impaired-sector selection while keeping one common 7-site / 21-sector topology.

Generated datasets:

- network-state dataset: one row per scenario realization.
- sector-state dataset: one row per sector per scenario realization.
- scenario plan: scenario labels, seeds, traffic mode, and impairment setup.
- validation table: dataset integrity and scenario-distinctness checks.

This phase is still not ML. It does not train COD, TP, QP, load balancing, energy saving, HO/MRO, oracle benchmarking, or closed-loop control.

## Phase 4B Feature Preparation Scope

Phase 4B prepares leakage-controlled feature tables for supervised outage detection, traffic/QoS prediction, and action-evaluation modules. Direct scenario labels, impairment flags, sector status, and power-offset metadata are excluded from ML input feature sets. Traceability metadata may remain in the saved tables, but the explicit input-feature lists exclude those columns.

This phase does not train ML models. It does not implement COD, TP, QP, action selection, oracle benchmarking, or closed-loop control.

## Phase 5 Clustering State Monitor Scope

Phase 5 K-means clustering is archived/disabled in the active supervised-only thesis workflow (`cfg.enableUnsupervisedClustering = false`). Earlier Phase 5 outputs are historical diagnostics only and should not be used as main thesis evidence.

Candidate-action triggering now uses supervised COD output and direct pre-action KPI conditions instead of K-means cluster assignments. Clustering is not an active model, not a final decision maker, and not part of the supervised model comparison.

## Phase 6A COD Dataset Preparation Scope

Phase 6A prepares a balanced leakage-controlled dataset for later Cell Outage Detection training. It increases degraded and outage examples using the existing scenario engine and validates that direct scenario labels, impairment flags, sector status, and power-offset metadata are excluded from COD input features.

This phase does not train a COD classifier. It does not implement outage compensation, load balancing, energy saving, handover optimization, oracle benchmarking, action selection, a decision coordinator, or closed-loop SON control.

## Phase 6B COD Classifier Scope

Phase 6B trains a Random Forest classifier for Cell Outage Detection using a balanced synthetic COD dataset. The model is evaluated on both a balanced validation/test split and the original imbalanced sector-state dataset. The classifier is used only for detection/classification of normal, degraded, and outage sector states.

This phase does not implement outage compensation, load balancing, energy saving, handover optimization, oracle benchmarking, action selection, a decision coordinator, or closed-loop SON control.

## Phase 7A Temporal TP/QP Dataset Scope

Phase 7A generates time-indexed LTE traffic and QoS datasets for later Traffic Prediction and QoS Prediction modules. The RF state is kept static per scenario while traffic demand varies over 15-minute time steps using a synthetic diurnal traffic profile with stochastic variation.

Phase 7A now prepares both network-level and sector-level time-indexed lag feature tables for later TP/QP regression. Network-level features support aggregate traffic/QoS prediction, while sector-level features support later load balancing, energy saving, and sector KPI prediction.

This phase does not train TP or QP models. It does not implement action selection, oracle benchmarking, a decision coordinator, or closed-loop SON control.

## Phase 7B TP/QP Regression Scope

Phase 7B trains regression-based Traffic Prediction and QoS Prediction models using time-indexed lag features from the synthetic LTE simulation. A walk-forward split is used to avoid future-data leakage: each scenario-sector sequence is split into early training samples, middle validation samples, and final test samples.

The TP/QP models provide prediction capability only. They do not perform action selection, oracle benchmarking, SON control, or closed-loop optimization.

## Phase 7C TP/QP Diagnostic Scope

Phase 7C compares TP/QP regression models against simple persistence and mean baselines, checks bounded QoS prediction behavior, and diagnoses scenario-wise QP performance. This phase is used to avoid overstating prediction quality.

No action selection, oracle benchmark, coordinator, or closed-loop control is implemented in Phase 7C.

## Phase 8A Candidate Action Scope

Phase 8A generates valid candidate action tables for later counterfactual action evaluation. Candidate spaces are prepared for COC/OH, LB/MLB, ES, and HO/MRO only. TP and QP remain support/prediction modules and do not receive direct actions.

This phase only defines possible actions. It uses an RF-aware neighbor ranking based on baseline UE second-best RSRP evidence, sector azimuth alignment, and site geometry. Same-site sectors remain possible neighbors, but distance-only co-site ranking is avoided.

This phase does not evaluate rewards, select actions, train action-value models, run oracle benchmarking, apply actions to KPI(t+1), or claim closed-loop control.

## Phase 8B Counterfactual Evaluation Scope

Phase 8B evaluates Phase 8A candidate actions using a deterministic local counterfactual KPI proxy. It estimates pre/post KPI deltas and reward terms for candidate actions. The reward formula is documented in `docs/phase8b_reward_formula.md`. This prepares data for later oracle benchmarking and action-value model training.

The Phase 8B evaluator is **not closed-loop control**. It does not select the best action, train an action-value model, run oracle benchmarking, enforce a final safety checker (only diagnostic flagging via `safety_check_action.m`), coordinate module conflicts, or apply an action to generate KPI(t+1).

Phase 8B writes a validation table `phase8b_counterfactual_validation.csv` summarising reward distribution, NaN/Inf reward counts, duplicate row counts, ES-sleep-on-impaired counts, and safety-flag counts by module.

## Phase 8C Safety-Constrained Oracle Benchmark Scope

Phase 8C implements a safety-constrained oracle benchmark over the counterfactually evaluated candidate action table. The oracle selects the highest-reward safety-valid action within each decision group and serves as an upper-bound benchmark for later action-value ML models. This phase does not train ML models, coordinate multiple modules, apply actions to the simulator, or create KPI(t+1). Therefore, it is not closed-loop control.

Decision grouping: `(scenario_name, realization_id, source_sector_id, module_name)`. Selection order:

1. Among safety-valid candidates in the group, pick the maximum-reward row.
2. Else fall back to a safe no-op (literal `is_no_op` row, or ES `keep_active`).
3. Else fall back to the highest-reward no-op (`safety_valid = false`).
4. Else fall back to the overall highest-reward row (`safety_valid = false`).

Outputs:

- `results/tables/phase8c_oracle_selected_actions.csv`
- `results/tables/phase8c_oracle_summary_by_module.csv`
- `results/tables/phase8c_oracle_summary_by_scenario.csv`
- `results/tables/phase8c_oracle_safety_summary.csv`
- `results/tables/phase8c_oracle_validation.csv`

## Phase 9A Action-Value Dataset Preparation Scope

Phase 9A prepares leakage-controlled action-value datasets from the counterfactual evaluation and oracle benchmark. These datasets are intended for later module-specific reward regression models. Reward and oracle-selected indicators are targets/evaluation metadata, not model inputs. Post-action KPI columns are excluded from input features. This phase does not train action-value ML models, coordinate modules, apply actions, or generate KPI(t+1).

Outputs:

- `results/tables/phase9a_action_value_dataset_all.csv`
- `results/tables/phase9a_action_value_dataset_coc.csv`
- `results/tables/phase9a_action_value_dataset_lb.csv`
- `results/tables/phase9a_action_value_dataset_es.csv`
- `results/tables/phase9a_action_value_dataset_mro.csv`
- `results/tables/phase9a_action_value_feature_dictionary.csv`
- `results/tables/phase9a_action_value_leakage_audit.csv`
- `results/tables/phase9a_action_value_dataset_summary.csv`
- `results/tables/phase9a_action_value_validation.csv`

## Phase 9B Action-Value Regression Scope

Phase 9B trains module-specific action-value regression models to predict counterfactual reward from pre-action KPI features and action parameters. The models are evaluated offline using oracle-regret and top-1/top-2 oracle-action match metrics. This phase does not apply actions, coordinate modules, update network state, or implement closed-loop control.

Trained models (LSBoost regression-tree ensemble; TreeBagger fallback) are saved as:

- `models/phase9b_coc_action_value_model.mat`
- `models/phase9b_lb_action_value_model.mat`
- `models/phase9b_es_action_value_model.mat`
- `models/phase9b_mro_action_value_model.mat`

Outputs:

- `results/tables/phase9b_action_value_metrics.csv`
- `results/tables/phase9b_action_value_predictions.csv`
- `results/tables/phase9b_action_value_feature_importance.csv`
- `results/tables/phase9b_action_value_split_summary.csv`
- `results/tables/phase9b_action_selection_preview.csv`
- `results/tables/phase9b_oracle_regret_preview.csv`
- `results/tables/phase9b_action_value_validation.csv`
- `results/figures/phase9b_action_value_actual_vs_predicted.png`
- `results/figures/phase9b_action_value_error_by_module.png`
- `results/figures/phase9b_action_value_oracle_regret.png`

Group-aware split: each (scenario_name, realization_id) realization is assigned to exactly one of train / validation / test (stratified per scenario), preventing same-realization leakage between train and test. Primary training uses `safe_training_candidate == true` rows only; unsafe rows are excluded from training but kept for diagnostic evaluation.

## Supervised Action-Value Model Comparison

The active thesis comparison uses three supervised regressors on the same action-value reward target and the same group-aware train / validation / test split:

- Linear/Ridge regression.
- Random Forest / Bagged Trees regression.
- LSBoost / Gradient Boosting regression.

Inputs are pre-action KPI features and action-parameter features only. The target is the existing counterfactual reward. Forbidden inputs such as reward leakage, oracle-selected flags, safety-valid flags, scenario labels, outage/degradation labels, and post-action KPI columns are excluded.

Outputs:

- `results/tables/supervised_action_value_model_metrics.csv`
- `results/tables/supervised_action_value_model_predictions.csv`
- `results/tables/supervised_action_value_model_split_summary.csv`
- `results/tables/supervised_action_value_model_ranking.csv`
- `results/tables/supervised_action_value_model_feature_use.csv`
- `results/tables/supervised_action_value_model_validation.csv`
- `results/figures/supervised_action_value_actual_vs_predicted_test.png`
- `results/figures/supervised_action_value_actual_vs_predicted_test_safe.png`
- `results/figures/supervised_action_value_actual_vs_predicted_test_unsafe_diagnostic.png`
- `results/figures/supervised_action_value_actual_vs_predicted_test_mixed_diagnostic.png`
- `results/figures/supervised_action_value_test_r2_by_module.png`
- `results/figures/supervised_action_value_test_mae_by_module.png`

The main actual-vs-predicted calibration plot uses safe test candidates only, matching the safe-only training distribution. Unsafe and mixed safe+unsafe plots are diagnostic only and are expected to look poor because unsafe penalty-heavy candidates were excluded from training. Final action-selection evidence should also include ranking and regret metrics.

## Phase 10A Safety-Enforced ML Action Selection Scope

Phase 10A applies a safety-enforcement layer to the offline action-value ML predictions. Candidate actions are first ranked by predicted reward, then unsafe candidates are filtered using Phase 8B safety flags before the final offline ML-selected action is recorded. This phase compares raw ML selection and safety-enforced ML selection against the Phase 8C oracle. It does not coordinate modules, apply actions to the simulator, create KPI(t+1), or implement closed-loop control.

Selection rule (per (scenario, realization, source, module) decision group on the Phase 9B test split):

1. Rank candidates by Phase 9B predicted reward (descending).
2. Record the raw top-1 ML pick (with its `raw_selected_safety_valid` flag).
3. Filter to `safety_is_unsafe == false` candidates and pick the highest predicted reward among them.
4. If no safe candidate exists, prefer a no-op fallback (literal `is_no_op` row or ES `keep_active`); set `selection_reason = no_safe_action_fallback_noop`.
5. If neither a safe candidate nor a no-op exists, keep the raw top-1 as an unsafe fallback; set `selection_reason = no_safe_action_available_unsafe_fallback` (`safe_selected_safety_valid = false`).

Both selections are compared against the Phase 8C oracle. `raw_regret` and `safety_enforced_regret` use the Phase 8B *true* counterfactual reward for evaluation only — predicted reward is never used for evaluation.

Outputs:

- `results/tables/phase10a_safety_enforced_selected_actions.csv`
- `results/tables/phase10a_raw_vs_safe_selection_comparison.csv`
- `results/tables/phase10a_safety_enforced_regret.csv`
- `results/tables/phase10a_summary_by_module.csv`
- `results/tables/phase10a_summary_by_scenario.csv`
- `results/tables/phase10a_safety_filter_summary.csv`
- `results/tables/phase10a_safety_enforced_validation.csv`
- `results/figures/phase10a_regret_by_module.png`
- `results/figures/phase10a_raw_vs_safe_selection.png`
- `results/figures/phase10a_selection_outcomes.png`

## Phase 11A Decision Coordinator Preparation Scope

Phase 11A prepares coordinator-ready action outputs from the safety-enforced ML selections and performs offline conflict detection and conflict-resolution diagnostics. The coordinator applies module priority and safety rules to produce an accepted/rejected candidate-action log. This phase does not apply actions to the simulator, does not create KPI(t+1), and does not implement closed-loop control.

Coordinator priority (lower wins):

| Priority | Module | Role |
|---|---|---|
| 2 | COC/OH | action |
| 3 | LB/MLB | action |
| 4 | HO/MRO | action |
| 6 | ES | action (last) |

COD trigger / TP / QP are not action-selection modules in Phase 11A; they only provide trigger/diagnostic metadata.

Conflict types detected: `unsafe_non_fallback`, `same_sector_same_parameter`, `same_sector_orthogonal_param` (info), `es_sleep_overlap`, `lb_into_risky_target`, `cross_cell_counteracting`, `cross_cell_reinforcing` (info).

Outputs:

- `results/tables/phase11a_coordinator_input_actions.csv`
- `results/tables/phase11a_conflict_detection_log.csv`
- `results/tables/phase11a_conflict_resolution_log.csv`
- `results/tables/phase11a_coordinator_candidate_actions.csv`
- `results/tables/phase11a_rejected_action_log.csv`
- `results/tables/phase11a_summary_by_module.csv`
- `results/tables/phase11a_summary_by_scenario.csv`
- `results/tables/phase11a_coordination_validation.csv`
- `results/figures/phase11a_conflict_counts.png`
- `results/figures/phase11a_accepted_rejected_actions.png`
- `results/figures/phase11a_module_priority_outcomes.png`

## Phase 11B Final Coordinator Selection Scope

Phase 11B converts the offline coordinator preparation outputs into a final coordinator decision table. It separates executable-safe offline actions, no-op decisions, rejected actions, and unresolved unsafe fallback diagnostics. This phase still does not apply actions to the simulator, does not update KPI(t+1), and does not implement closed-loop control.

`final_decision_status` values:

| Status | executable_flag | Description |
|---|---|---|
| `final_safe_action` | true | Coordinator-accepted, safety-valid, non-noop. |
| `final_noop` | false | Coordinator-accepted, but a no-op (or ES keep_active). |
| `rejected_priority_conflict` | false | Lost a priority arbitration in Phase 11A. |
| `rejected_safety_conflict` | false | Rejected due to safety-related conflict (ES-sleep overlap, LB-to-risky-target, unsafe non-fallback). |
| `unresolved_unsafe_fallback` | false | Fallback path with no safe candidate AND no no-op alternative; retained as diagnostic only. |
| `diagnostic_only` | false | Reserved for edge cases that do not fit the other five statuses. |

Outputs:

- `results/tables/phase11b_final_coordinator_decisions.csv`
- `results/tables/phase11b_final_executable_actions.csv`
- `results/tables/phase11b_unresolved_fallback_diagnostics.csv`
- `results/tables/phase11b_final_rejected_actions.csv`
- `results/tables/phase11b_summary_by_module.csv`
- `results/tables/phase11b_summary_by_scenario.csv`
- `results/tables/phase11b_final_coordination_validation.csv`
- `results/figures/phase11b_final_decision_status.png`
- `results/figures/phase11b_executable_actions_by_module.png`
- `results/figures/phase11b_unresolved_fallbacks_by_scenario.png`

## Phase 12A Action Application Feasibility Audit Scope

Phase 12A audits whether the final coordinator-selected executable actions can be represented by the current simulator state variables. It produces an action-to-simulator mapping and implementability summary, but does not apply actions, mutate simulator state, generate KPI(t+1), or implement closed-loop control.

Action-to-simulator mapping (current simulator capabilities):

| Module | Parameter | Status | State variable |
|---|---|---|---|
| COC/OH | `delta_prs_dB` | implementable_now | `sectors.referencePowerOffset_dB` (already mutated by Phase 3) |
| COC/OH | `delta_tilt_deg` | partially_implementable | `sectors.electricalTilt_deg` (column exists, no mutation helper yet) |
| COC/OH | `delta_cio_dB` | not_implemented_in_simulator | No CIO/bias state; association is pure max-RSRP |
| LB/MLB | `delta_cio_dB` | not_implemented_in_simulator | Same CIO gap; biased association unimplemented |
| ES | `sleep` | partially_implementable | Approximable via Phase 3 outage-style offsets; no native sleep/active state |
| ES | `keep_active` | no_parameter_change_required | Classified as `final_noop` in Phase 11B |
| ES | `wake_up` | not_implemented_in_simulator | No sleep state to reverse |
| HO/MRO | `delta_hom_dB` | not_implemented_in_simulator | No HOM state; handover_risk_score is derived |
| HO/MRO | `delta_ttt_ms` | not_implemented_in_simulator | No TTT state; no temporal handover trigger model |
| HO/MRO | `delta_cio_dB` | not_implemented_in_simulator | Same CIO gap |

Outputs:

- `results/tables/phase12a_action_application_feasibility.csv`
- `results/tables/phase12a_action_parameter_mapping.csv`
- `results/tables/phase12a_implementability_summary_by_module.csv`
- `results/tables/phase12a_implementability_summary_by_action_type.csv`
- `results/tables/phase12a_skipped_non_executable_actions.csv`
- `results/tables/phase12a_feasibility_validation.csv`

## Phase 12B Simulator Action-State Extension Scope

Phase 12B adds simulator state support for selected action parameters, especially CIO/bias and cloned-state action application. CIO affects association bias only and does not artificially change physical RSRP or SINR. This phase prepares the simulator for later one-step KPI(t+1) evaluation but does not apply final actions, does not generate KPI(t+1), and does not implement closed-loop control.

State columns added to `topology.sectors`:

| Column | Default | Role |
|---|---|---|
| `cio_dB` | 0 | Per-sector association bias; affects best-server metric only |
| `referencePowerOffset_dB` | 0 | Additive RSRP offset (already used by Phase 3) |
| `txPowerOffset_dB` | 0 | Additive SINR/interference power offset |
| `hom_offset_dB` | 0 | Placeholder; **NOT RF-CONNECTED** |
| `ttt_offset_ms` | 0 | Placeholder; **NOT RF-CONNECTED** |
| `is_sleeping` | false | Placeholder; **NOT YET CONSUMED BY RF/KPI** |

Six tests verify these properties:

1. `cio_dB` default zero, baseline association unchanged when all CIO = 0.
2. +6 dB CIO on a neighbor changes biased best-server for at least one UE but does **not** mutate physical RSRP.
3. +3 dB `referencePowerOffset_dB` increases physical RSRP from that sector by ~3 dB for nearby UEs.
4. Tilt offset measurably changes RSRP from that sector (tilt is consumed by `calc_antenna_gain`).
5. `apply_single_action_to_cloned_state` mutates the clone but never the original.
6. No `kpi_t_plus_1` / `kpi_next` / `next_state_dataset` / closed-loop columns added anywhere.

Outputs:

- `results/tables/phase12b_action_state_support_audit.csv`
- `results/tables/phase12b_cio_bias_association_test.csv`
- `results/tables/phase12b_reference_power_offset_test.csv`
- `results/tables/phase12b_tilt_usage_test.csv`
- `results/tables/phase12b_state_clone_integrity_test.csv`
- `results/tables/phase12b_action_state_validation.csv`

## Phase 12C Post-Extension Feasibility Refresh Scope

Phase 12C refreshes the action implementability audit after the simulator action-state extension and prepares a KPI(t+1)-eligible action set. Only fully implementable, safety-valid, final coordinator actions are included. ES sleep and HO/MRO HOM/TTT actions remain excluded because their simulator effects are not fully connected. This phase does not apply actions, recompute KPIs, generate KPI(t+1), or implement closed-loop control.

Eligibility filter (all five must hold):

1. Source row is a Phase 11B `final_safe_action` with `executable_flag = true` and `safety_valid = true`.
2. Re-classified under the Phase 12B post-extension mapping as `implementable_now`.
3. Module in {COC/OH, LB/MLB}.
4. Δ`HOM` = 0 and Δ`TTT` = 0 (state placeholders, not RF-connected).
5. `sleep_flag = 0` and `es_action` in {`""`, `keep_active`} (sleep RF impact not implemented).

Outputs:

- `results/tables/phase12c_post_extension_feasibility.csv`
- `results/tables/phase12c_kpi_update_eligible_actions.csv`
- `results/tables/phase12c_kpi_update_excluded_actions.csv`
- `results/tables/phase12c_eligible_summary_by_module.csv`
- `results/tables/phase12c_eligible_summary_by_action_type.csv`
- `results/tables/phase12c_kpi_eligible_validation.csv`

## Phase 12D One-Step KPI(t) → KPI(t+1) Evaluation Scope

Phase 12D performs a one-step cloned-state KPI(t)→KPI(t+1) evaluation for the subset of final coordinator actions that are fully implementable by the current simulator. Only COC/OH and LB/MLB actions are applied. ES sleep and HO/MRO actions remain excluded. This phase is a limited one-step evaluation, not a full multi-step closed-loop controller.

Method per (scenario, realization) group:

1. Replay the Phase 4 scenario plan row using its stored `ue_seed`, `shadowing_seed`, and `traffic_seed` to reconstruct a reproducible pre-action state.
2. Compute RF + traffic + KPIs → **pre** state.
3. Clone the topology and apply every Phase 12C-eligible action for the group via `apply_eligible_actions_to_cloned_state`.
4. Re-run RF on the clone, with CIO bias applied at association only (physical RSRP is never inflated by CIO), and recompute traffic + KPIs → **post** state.
5. Record per-action pre/post KPI deltas.

Outputs:

- `results/tables/phase12d_one_step_kpi_update_results.csv`
- `results/tables/phase12d_pre_post_sector_kpis.csv`
- `results/tables/phase12d_pre_post_network_kpis.csv`
- `results/tables/phase12d_action_application_log.csv`
- `results/tables/phase12d_skipped_actions_log.csv`
- `results/tables/phase12d_summary_by_module.csv`
- `results/tables/phase12d_summary_by_scenario.csv`
- `results/tables/phase12d_one_step_validation.csv`
- `results/figures/phase12d_pre_post_kpi_by_module.png`
- `results/figures/phase12d_load_change_by_scenario.png`
- `results/figures/phase12d_rsrp_sinr_change.png`
- `results/figures/phase12d_kpi_update_outcomes.png`

## Phase 12E One-Step KPI Validation and Final Comparison Scope

Phase 12E validates the limited one-step KPI(t)→KPI(t+1) evaluation and produces thesis-ready baseline vs AI/ML vs oracle comparison tables. Oracle KPI comparison is computed only when the oracle-selected action is fully implementable by the current simulator. Non-implementable oracle actions are marked as not comparable. This phase does not implement multi-step closed-loop control and does not apply ES or HO/MRO actions.

Comparison flow per AI-evaluated row:

1. Pre-action KPIs come directly from Phase 12D's `pre_*` columns (replay of the Phase 4 scenario plan).
2. AI/ML KPI(t+1) comes from Phase 12D's `post_*` columns.
3. For the same `(scenario_name, realization_id, source_sector_id, module_name)` group, the Phase 8C oracle row is looked up.
4. Implementability check: oracle must be COC/OH `compensate_neighbor` or LB/MLB `cio_bias_to_neighbor` with `ΔHOM = 0`, `ΔTTT = 0`, `safety_valid = true`, and `es_action ∈ {"", "keep_active"}`.
5. If implementable, the oracle's action is applied to a cloned topology and the same Phase 4 realization is replayed to compute oracle KPI(t+1). Oracle no_op is treated as oracle KPI(t+1) = baseline.
6. Gaps `oracle_qos − ai_qos` etc. are computed and any physical-KPI-vs-reward disagreement is noted.

Outputs:

- `results/tables/phase12e_baseline_ai_kpi_comparison.csv`
- `results/tables/phase12e_baseline_ai_oracle_comparison.csv`
- `results/tables/phase12e_oracle_comparable_action_log.csv`
- `results/tables/phase12e_kpi_outcome_classification.csv`
- `results/tables/phase12e_summary_by_module.csv`
- `results/tables/phase12e_summary_by_scenario.csv`
- `results/tables/phase12e_tradeoff_summary.csv`
- `results/tables/phase12e_limitations_table.csv`
- `results/tables/phase12e_final_comparison_validation.csv`
- `results/figures/phase12e_baseline_ai_oracle_kpis.png`
- `results/figures/phase12e_kpi_delta_by_scenario.png`
- `results/figures/phase12e_tradeoff_attach_vs_qos.png`
- `results/figures/phase12e_oracle_gap_by_module.png`
- `results/figures/phase12e_final_outcome_counts.png`

## Phase 13 Final Thesis Result Package Scope

Phase 13 packages the completed simulation outputs into thesis-ready summaries, figures, validation tables, before-vs-after KPI tables, and limitation statements. It does not introduce new simulation logic, train models, apply actions, or extend closed-loop behavior. The final claim remains a synthetic AI/ML-assisted LTE SON-inspired framework with limited one-step KPI(t)→KPI(t+1) evaluation for implementable COC/OH and LB/MLB actions.

On every run, any pre-existing files in `results/thesis_package/` are first archived into `thesis_package/stale_<timestamp>/`, and fresh outputs are regenerated from the corrected post-fix Phase 12E summaries.

Outputs (all under `results/thesis_package/`):

- `final_result_summary.md` — 11-section thesis narrative with the main engineering finding and a dedicated **Before-and-After KPI(t)→KPI(t+1) Result** section
- `final_architecture_summary.md` — staged pipeline diagram
- `final_thesis_claims_and_boundaries.md` — eight allowed claims + ten forbidden-claim warnings
- `final_result_report_draft.md` — Word-convertible draft for the thesis chapter
- `final_before_after_kpi_interpretation.md` — per-KPI interpretation lines
- `final_module_status_table.csv` — 15 modules with method, physical KPI status, validation metric, and limitation
- `final_baseline_ai_oracle_summary.csv` — long-form baseline vs AI/ML vs oracle with deltas, gap, and interpretation
- `final_kpi_improvement_summary.csv` — headline metrics (applied action count, attach degradation, RSRP/SINR/load/QoS, QoS gap to oracle)
- `final_before_after_kpi_summary.csv` — per-KPI baseline / AI-ML / delta / interpretation
- `final_before_after_kpi_by_module.csv` — Phase 12E per-module breakdown
- `final_before_after_kpi_by_scenario.csv` — Phase 12E per-scenario breakdown
- `final_scenario_summary.csv` — per-scenario delta RSRP/SINR/load/QoS from Phase 12D
- `final_module_validation_summary.csv` — per-phase error/warning counts
- `final_safety_coordination_summary.csv` — Phase 10A safety filter outcomes joined with Phase 11A coordinator stats
- `final_oracle_regret_summary.csv` — Phase 8C oracle module summary
- `final_limitations_table.csv` — 14 honest limitations
- `final_figure_manifest.csv` — referenced thesis figures with `figure_role` ∈ {`main_thesis_figure`, `diagnostic_only`, `appendix_only`, `avoid_as_main_result`}. Phase 9B actual-vs-predicted reward scatter and the raw Phase 7C QP actual-vs-predicted plot are explicitly NOT main thesis figures.
- `final_before_after_kpi_comparison.png` — grouped bar chart (baseline / AI-ML / oracle)
- `final_result_package_validation.csv` — Phase 13 self-validation (25 checks)

## Current Outputs

Phase 1B figures:

- `results/figures/phase1b_topology_ue_attachment.png`
- `results/figures/phase1b_best_server_map.png`
- `results/figures/phase1b_best_rsrp_map.png`
- `results/figures/phase1b_best_sinr_map.png`
- `results/figures/phase1b_sector_load.png`

Phase 2 figures:

- `results/figures/phase2_sector_load_map.png`
- `results/figures/phase2_ue_throughput_map.png`
- `results/figures/phase2_qos_satisfaction_map.png`

Phase 2C figures:

- `results/figures/phase2c_traffic_calibration_summary.png`

Phase 3 figures:

- `results/figures/phase3_scenario_summary.png`

Phase 4 figures:

- `results/figures/phase4_dataset_summary.png`

Phase 1B tables:

- `results/tables/phase1b_sites.csv`
- `results/tables/phase1b_sectors.csv`
- `results/tables/phase1b_summary.csv`
- `results/tables/phase1b_sector_load.csv`
- `results/tables/phase1b_ue_rf_results.csv`

Phase 2 tables:

- `results/tables/phase2_ue_traffic_results.csv`
- `results/tables/phase2_sector_kpis.csv`
- `results/tables/phase2_network_kpis.csv`

Phase 2C tables:

- `results/tables/phase2c_traffic_calibration_summary.csv`
- `results/tables/phase2c_sector_kpis_by_mode.csv`
- `results/tables/phase2c_ue_traffic_by_mode.csv`

Phase 3 tables:

- `results/tables/phase3_scenario_summary.csv`
- `results/tables/phase3_sector_kpis_by_scenario.csv`
- `results/tables/phase3_network_kpis_by_scenario.csv`
- `results/tables/phase3_ue_results_by_scenario.csv`
- `results/tables/phase3_scenario_sanity_check.csv`

Phase 4 tables:

- `results/tables/phase4_scenario_plan.csv`
- `results/tables/phase4_network_state_dataset.csv`
- `results/tables/phase4_sector_state_dataset.csv`
- `results/tables/phase4_dataset_validation.csv`

Phase 4B tables:

- `results/tables/phase4b_sector_features_clustering.csv`
- `results/tables/phase4b_sector_features_cod.csv`
- `results/tables/phase4b_network_features_tp_qp.csv`
- `results/tables/phase4b_feature_dictionary.csv`
- `results/tables/phase4b_feature_leakage_audit.csv`
- `results/tables/phase4b_ml_feature_validation.csv`

Archived Phase 5 K-means diagnostics (not active in supervised-only workflow):

- `results/tables/phase5_clustering_input_features.csv`
- `results/tables/phase5_clustering_k_evaluation.csv`
- `results/tables/phase5_sector_cluster_assignments.csv`
- `results/tables/phase5_cluster_summary.csv`
- `results/tables/phase5_cluster_scenario_crosstab.csv`
- `results/tables/phase5_cluster_trigger_support.csv`
- `results/tables/phase5_clustering_validation.csv`

Archived Phase 5 figures:

- `results/figures/phase5_cluster_pca.png`
- `results/figures/phase5_cluster_scenario_heatmap.png`
- `results/figures/phase5_cluster_profiles.png`

Phase 6A tables:

- `results/tables/phase6a_cod_balanced_dataset.csv`
- `results/tables/phase6a_cod_feature_list.csv`
- `results/tables/phase6a_cod_label_distribution.csv`
- `results/tables/phase6a_cod_dataset_validation.csv`
- `results/tables/phase6a_cod_split_plan.csv`

Phase 6A figures:

- `results/figures/phase6a_cod_label_distribution.png`

Phase 6B tables:

- `results/tables/phase6b_cod_validation_metrics.csv`
- `results/tables/phase6b_cod_test_metrics.csv`
- `results/tables/phase6b_cod_external_metrics.csv`
- `results/tables/phase6b_cod_validation_confusion_matrix.csv`
- `results/tables/phase6b_cod_test_confusion_matrix.csv`
- `results/tables/phase6b_cod_external_confusion_matrix.csv`
- `results/tables/phase6b_cod_feature_importance.csv`
- `results/tables/phase6b_cod_predictions_balanced.csv`
- `results/tables/phase6b_cod_predictions_external.csv`
- `results/tables/phase6b_cod_model_validation.csv`

Phase 6B figures:

- `results/figures/phase6b_cod_test_confusion_matrix.png`
- `results/figures/phase6b_cod_external_confusion_matrix.png`
- `results/figures/phase6b_cod_feature_importance.png`

Phase 6B model:

- `models/phase6b_cod_random_forest_model.mat`

Phase 7A tables:

- `results/tables/phase7a_temporal_sector_dataset.csv`
- `results/tables/phase7a_temporal_network_dataset.csv`
- `results/tables/phase7a_tp_qp_feature_table.csv`
- `results/tables/phase7a_sector_tp_qp_feature_table.csv`
- `results/tables/phase7a_sector_tp_qp_feature_dictionary.csv`
- `results/tables/phase7a_temporal_summary.csv`
- `results/tables/phase7a_dataset_validation.csv`

Phase 7A figures:

- `results/figures/phase7a_traffic_qos_timeline.png`

Phase 7B tables:

- `results/tables/phase7b_tp_metrics.csv`
- `results/tables/phase7b_qp_metrics.csv`
- `results/tables/phase7b_tp_predictions.csv`
- `results/tables/phase7b_qp_predictions.csv`
- `results/tables/phase7b_tp_feature_importance.csv`
- `results/tables/phase7b_qp_feature_importance.csv`
- `results/tables/phase7b_tp_qp_split_summary.csv`
- `results/tables/phase7b_tp_qp_validation.csv`

Phase 7B figures:

- `results/figures/phase7b_tp_actual_vs_predicted.png`
- `results/figures/phase7b_qp_actual_vs_predicted.png`
- `results/figures/phase7b_tp_error_by_scenario.png`
- `results/figures/phase7b_qp_error_by_scenario.png`

Phase 7B models:

- `models/phase7b_tp_regression_model.mat`
- `models/phase7b_qp_regression_model.mat`

Phase 7C tables:

- `results/tables/phase7c_tp_baseline_comparison.csv`
- `results/tables/phase7c_qp_baseline_comparison.csv`
- `results/tables/phase7c_qp_bounded_prediction_metrics.csv`
- `results/tables/phase7c_qp_predictions_bounded.csv`
- `results/tables/phase7c_qp_target_variance_diagnostic.csv`
- `results/tables/phase7c_qp_throughput_metrics.csv`
- `results/tables/phase7c_qp_throughput_predictions.csv`
- `results/tables/phase7c_tp_qp_diagnostic_validation.csv`

Phase 7C figures:

- `results/figures/phase7c_tp_model_vs_baseline.png`
- `results/figures/phase7c_qp_model_vs_baseline.png`
- `results/figures/phase7c_qp_bounded_actual_vs_predicted.png`
- `results/figures/phase7c_qp_target_variance_by_scenario.png`
- `results/figures/phase7c_qp_throughput_actual_vs_predicted.png`

Phase 7C model:

- `models/phase7c_qp_throughput_regression_model.mat`

Phase 8A tables:

- `results/tables/phase8a_candidate_actions.csv`
- `results/tables/phase8a_candidate_action_summary.csv`
- `results/tables/phase8a_candidate_action_validation.csv`
- `results/tables/phase8a_candidate_diagnostics_by_module.csv`
- `results/tables/phase8a_candidate_actions_by_scenario.csv`
- `results/tables/phase8a_neighbor_ranking.csv`
- `results/tables/phase8a_candidate_target_diagnostics.csv`

Phase 8A figures:

- `results/figures/phase8a_candidate_action_counts.png`

Phase 8B tables:

- `results/tables/phase8b_counterfactual_action_table.csv`
- `results/tables/phase8b_counterfactual_summary_by_module.csv`
- `results/tables/phase8b_counterfactual_summary_by_scenario.csv`
- `results/tables/phase8b_counterfactual_validation.csv`

Phase 8B documentation:

- `docs/phase8b_reward_formula.md`

Run audit tables:

- `results/tables/run_phase_timing_log.csv`
- `results/tables/run_dependency_summary.csv`

Logs:

- `results/logs/phase1b_run_summary.txt`
- `results/logs/phase2_run_summary.txt`
- `results/logs/phase2c_traffic_calibration_summary.txt`
- `results/logs/phase3_scenario_summary.txt`
- `results/logs/phase4_dataset_summary.txt`

## Next Phase

The project is implemented through Phase 12E. Before enabling Phase 13 packaging, the pre-Phase-13 audit must remain clean: Phase 13 disabled by default, no duplicate application-target/state-variable actions, no data leakage, and README claims aligned with the limited one-step KPI(t)→KPI(t+1) scope. After that, Phase 13 may be enabled only as a thesis-result packaging step, not as new simulation/control functionality.
