# Supervised Action-Value Model Comparison Report

Active workflow: supervised ML only. K-means/unsupervised clustering is disabled and archived.

## Split

Group-aware split keeps each scenario/realization group in exactly one split. Training uses `safe_training_candidate` rows. The main calibration plot and main calibration metrics now use safe test candidates only. Unsafe and mixed safe+unsafe test rows are reported separately as diagnostics.

## Validation
Validation errors: 0
Validation warnings: 1

Warning interpretation: weak mixed-test R2 for COC/OH and LB/MLB is expected because mixed test rows include unsafe penalty-heavy candidates that were excluded from training. This mixed scatter is diagnostic only, not the main supervised calibration figure.

## Thesis-safe statement

The action-value learner is a supervised reward-regression model trained on leakage-controlled pre-action KPI and action-parameter features. Linear/Ridge, Random Forest/Bagged Trees, and LSBoost are compared using the same group-aware train/validation/test split. Because training excludes unsafe candidates, safe and unsafe test rows are evaluated separately. The safe-test actual-vs-predicted plot is the calibration figure; unsafe and mixed safe+unsafe plots are diagnostic evidence of penalty-dominated out-of-distribution rows. Final action-selection quality is interpreted using oracle top-k match and regret because several reward targets are compressed or tied.

## Main files

- results/tables/supervised_action_value_model_metrics.csv
- results/tables/supervised_action_value_model_predictions.csv
- results/tables/supervised_action_value_model_split_summary.csv
- results/tables/supervised_action_value_model_validation.csv
- results/figures/supervised_action_value_actual_vs_predicted_test.png
- results/figures/supervised_action_value_actual_vs_predicted_test_safe.png
- results/figures/supervised_action_value_actual_vs_predicted_test_unsafe_diagnostic.png
- results/figures/supervised_action_value_actual_vs_predicted_test_mixed_diagnostic.png
- results/figures/supervised_action_value_test_r2_by_module.png
- results/figures/supervised_action_value_test_mae_by_module.png
