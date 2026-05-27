# Phase 8B Counterfactual Reward Formula

Phase 8B is a deterministic local KPI-proxy evaluator. It does not select
actions, train ML models, run an oracle, enforce a final safety checker,
coordinate modules, or update KPI(t+1). It is NOT closed-loop SON
control.

The reward described below is used only as a counterfactual target signal
for later modules (oracle benchmarking, ML action-value training).

## Final reward formula

```
reward = w_cov   * coverage_term
       + w_qos   * qos_term
       + w_load  * load_term
       + w_ho    * handover_term
       + w_es    * energy_term
       - w_pen   * penalty_term
```

Implemented in [src/actions/compute_counterfactual_reward.m](../src/actions/compute_counterfactual_reward.m).

Each KPI is counted exactly once. The previous implementation added a
module-specific bonus on top of the global weighted sum
(e.g. `+ 0.50 * load_term` for LB on top of `w_load * load_term`). That
caused the same KPI gain to be rewarded twice for the module that already
optimizes that KPI. The bonus block has been removed.

### KPI terms

```
delta_rsrp_norm   = (post_RSRP  - pre_RSRP)  / 10
delta_sinr_norm   = (post_SINR  - pre_SINR)  / 10
delta_attach      =  post_attach - pre_attach
delta_qos         =  post_qos    - pre_qos
risk_reduction    =  pre_risk    - post_risk

coverage_term = delta_attach + 0.25*delta_rsrp_norm + 0.25*delta_sinr_norm
qos_term      = delta_qos
load_term     = max(pre_src_load  - lb_overload, 0)
              - max(post_src_load - lb_overload, 0)
              - 0.50 * max(new_target_overload, 0)
handover_term = risk_reduction
energy_term   = energy_delta_proxy   (+1 sleep, -0.35 wake_up, 0 otherwise)
```

### Penalty term

```
negative_kpi_penalty = max(-delta_attach, 0)
                     + max(-delta_qos, 0)
                     + 0.25 * max(-delta_sinr_norm, 0)

new_target_overload = max(post_tgt_load - overload_penalty_threshold, 0)
                    - max(pre_tgt_load  - overload_penalty_threshold, 0)

new_source_overload = max(post_src_load - overload_penalty_threshold, 0)
                    - max(pre_src_load  - overload_penalty_threshold, 0)

penalty_term = max(new_target_overload, 0)
             + 0.50 * max(new_source_overload, 0)
             + interference_delta_proxy
             + action_cost_proxy
             + negative_kpi_penalty
```

The penalty term aggregates both safety risks (overload, negative KPI
deltas) and action cost (interference, parameter cost).

Important correction: overload penalty is action-relative. It penalizes
overload introduced or worsened by the candidate action, not the absolute
pre-existing bad state. Therefore a true no-op has zero reward unless a
future implementation explicitly models passive degradation.

### Weights

Configured in [config/sim_config.m](../config/sim_config.m):

| Weight | Value | Role |
|---|---|---|
| `phase8bRewardCoverageWeight` | 1.00 | Coverage gain |
| `phase8bRewardQosWeight`      | 1.20 | QoS gain (highest gain weight) |
| `phase8bRewardLoadWeight`     | 1.00 | Load-balancing gain |
| `phase8bRewardHandoverWeight` | 1.00 | Mobility-robustness gain |
| `phase8bRewardEnergyWeight`   | 0.50 | Energy-saving gain |
| `phase8bPenaltyWeight`        | 3.00 | Safety/cost penalty |

`phase8bPenaltyWeight` (3.00) is strictly greater than every single gain
weight, including `phase8bRewardQosWeight` (1.20). An action that produces
the maximum plausible gain in one dimension but causes the threshold
penalty in another can therefore not have a positive net reward unless
the safety penalty is small. This is a soft preference, not a hard
safety constraint — final safety enforcement lives in
[src/actions/safety_check_action.m](../src/actions/safety_check_action.m).

## What the reward is NOT

- It is not an oracle. The oracle (Phase 8C) selects the highest reward
  per (scenario, realization, source_sector) over valid candidates.
- It is not a learned action-value function.
- It does not apply the action or produce KPI(t+1).
- It does not enforce safety. Safety is flagged in a separate stub.
