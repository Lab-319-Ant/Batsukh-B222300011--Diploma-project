# Phase 7D QP Audit Report

## Executive Verdict

Primary recommendation: **KEEP_BOUNDED_REGRESSION_WITH_LIMITATION**. Add the binary classification view as a diagnostic only; do not replace QP before Phase 13 packaging.

## Is This a Coding Bug?

No confirmed coding bug was found in the QP target-generation path. The target is copied from the next-step sector `qos_satisfaction_ratio`, and that sector KPI is computed as `mean(qosSatisfied)` over active attached UEs. No rounding, logical overwrite, forbidden label input, or future-target input was found.

Important limitation: sector QoS values that are missing because no active attached UEs exist are imputed to 1 inside the Phase 7 sector feature builder. That is a target-definition artifact and should be documented.

## Is the Target Bimodal?

Yes. Across all QP target rows, 21.03% are exactly 0, 78.88% are exactly 1, and 0.09% are between 0 and 1. Unique target values: 10.

Scenario-level distribution is written to `phase7d_qp_target_distribution_by_scenario.csv`.

## Regression Appropriateness

Continuous regression is weak for this target because the response is effectively endpoint-dominated. Bounded regression is acceptable only as a support diagnostic. It should not be described as a robust continuous QoS predictor.

Test bounded metrics: MAE 0.1622, RMSE 0.3054, R2 0.5310. Raw predictions below 0: 7.78%; above 1: 23.33%.

## Baseline Comparison

- `QP_bounded_model`: MAE 0.1622, RMSE 0.3054, R2 0.5310. model prediction clipped to [0,1]
- `train_mean_baseline`: MAE 0.3648, RMSE 0.4519, R2 -0.0270. deployable simple baseline using train target mean
- `persistence_baseline`: MAE 0.1367, RMSE 0.3692, R2 0.3146. deployable if previous sector QoS is available
- `scenario_mean_baseline_diagnostic`: MAE 0.2521, RMSE 0.3655, R2 0.3281. diagnostic only; scenario label is metadata and not a deployable input

## Binary Diagnostic

Using `actual_qos >= 0.8` and `bounded_prediction >= 0.8`, the test-set diagnostic has accuracy 0.8360, precision 0.9527, recall 0.8144, and F1 0.8781. This is an interpretation aid only, not a replacement for the stored QP regression model.

## Thesis Figure Guidance

Use as main thesis diagnostic: `phase7d_qp_target_distribution_by_scenario.png` plus `phase7d_qp_bounded_actual_vs_predicted_with_density.png` if a prediction plot is needed.

Avoid as a main result: the raw Phase 7C actual-vs-predicted QP plot, because raw regression predictions can be outside [0,1] and the vertical bands need context.

## Exact Thesis-Safe Wording

"The QP module is retained as a bounded one-step QoS prediction support diagnostic. The sector-level QoS target is validly bounded in [0,1] but is strongly bimodal because most sector-time samples are either fully unsatisfied or fully satisfied, with missing/no-active sector QoS imputed as satisfied in the Phase 7 feature table. Therefore QP is not claimed as a robust continuous QoS predictor; it is reported with a bounded-regression limitation and an optional threshold-based diagnostic view."

## Recommendation Table

Primary rationale: test bounded R2=0.5310; raw out-of-range below=7.78% above=23.33%

## Validation

Validation errors: 0. Validation warnings: 1.

Phase 8-12 outputs modified: no, according to the Phase 7D snapshot check.
