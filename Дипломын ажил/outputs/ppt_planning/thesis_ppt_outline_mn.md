# Дипломын PPT бүтэц: AI/ML-assisted LTE SON-inspired simulation

## Үндсэн claim boundary

Төслийг PPT дээр ингэж нэрлэ:

**AI/ML-assisted LTE SON-inspired synthetic simulation framework with offline coordination and limited one-step KPI(t)->KPI(t+1) evaluation.**

Ингэж хэлж болохгүй:

- Бүрэн AI-RAN deployment
- 3GPP-compliant full SON implementation
- Live closed-loop control
- ES physical sleep ажилласан
- HO/MRO HOM/TTT физик параметрээр KPI-д нөлөөлсөн
- Бодит KPI дээр parameter өөрчилж before/after healing баталсан

Одоогийн workspace дээр `results/thesis_package` фолдер байхгүй. Тиймээс PPT-ийн үндсэн result source нь `results/figures`, `results/tables`, `results/vendor/figures`, `results/vendor/tables`.

## Санал болгож буй 19 slide бүтэц

### Slide 1 - Гарчиг

Claim title: **AI/ML-assisted LTE SON-inspired RAN simulation and KPI advisory**

Оруулах зүйл:

- Гарчиг, нэр, сургууль, удирдагч
- Арын зураг хэрэггүй. Цэвэр technical title байхад болно.

Ярих санаа:

- Энэ бол бодит сүлжээг шууд удирдсан систем биш.
- Synthetic LTE RAN дээр ML decision chain хийж, дараа нь real KPI дээр advisory хэлбэрээр шалгасан.

### Slide 2 - Асуудал ба зорилго

Claim title: **RAN KPI degradation needs detection, decision support, and safety filtering**

Оруулах зүйл:

- Зорилго: RF/traffic/KPI simulation үүсгэх, COD/TP/QP/action-value ML сургах, safety/coordinator-оор action сонгох, KPI(t+1)-ийг нэг алхмаар шалгах, real KPI дээр advisory турших.

Ярих санаа:

- KPI муудах үед шууд action хийхээс өмнө detection, prediction, candidate, reward, safety гэсэн давхаргууд хэрэгтэй.
- Миний ажил энэ chain-ийг simulation орчинд бүрэн явуулж, бодит KPI дээр recommendation байдлаар хэрэглэсэн.

### Slide 3 - Судалгааны хамрах хүрээ ба үнэн зөв хязгаар

Claim title: **The implemented system is offline and one-step, not closed-loop**

Оруулах файл:

- `A Study on Artificial Intelligence-Based Radio Networks/README.md`
- `A Study on Artificial Intelligence-Based Radio Networks/results/tables/phase12e_limitations_table.csv`

Онцлох тоо:

- Applied KPI update: 64 rows
- Applied modules: COC/OH = 9, LB/MLB = 55
- ES = 0, HO/MRO = 0 physically applied

Ярих санаа:

- Phase 12E хүртэл implemented.
- KPI(t)->KPI(t+1) нь cloned-state one-step evaluation.
- ES болон HO/MRO нь decision-support түвшинд үлдсэн.

### Slide 4 - Фолдер ба эх сурвалжийн зураглал

Claim title: **Project evidence comes from code, tables, figures, models, and real KPI workbooks**

Оруулах зүйл:

- `src/`: MATLAB implementation
- `config/sim_config.m`: topology, phases, thresholds
- `results/figures/`: synthetic simulation figures
- `results/tables/`: validation/result CSVs
- `models/`: trained `.mat` models
- `KPI/*.xlsx`: 7 real vendor KPI files
- `results/vendor/*`: real KPI advisory outputs

Ярих санаа:

- Нийт файлын бүтэц: 238 `.m`, 224 `.csv`, 81 `.png`, 8 `.mat`, 7 `.xlsx`.
- PPT дээр эхлээд simulation source, дараа нь real KPI source гэж салгана.

### Slide 5 - Synthetic RAN environment

Claim title: **A repeatable 7-site / 21-sector LTE macro topology is the base environment**

Оруулах зураг:

- `A Study on Artificial Intelligence-Based Radio Networks/results/figures/phase1b_topology_ue_attachment.png`
- optionally `phase1b_topology_site_sector_labels.png`

Оруулах тоо:

- 7 sites / 21 sectors
- 500 UEs
- 2.6 GHz
- planned radius = 462.1 m
- ISD = 800.4 m
- attach rate = 98.2%

Source table:

- `results/tables/phase1b_summary.csv`

Ярих санаа:

- Энэ нь real field геометр биш, controlled synthetic topology.
- RSRP/SINR/attachment нь дараагийн traffic/KPI simulation-ийн үндэс.

### Slide 6 - RF and traffic KPI layer

Claim title: **RF attachment is separated from traffic QoS and load**

Оруулах зураг:

- `results/figures/phase1b_best_rsrp_map.png`
- `results/figures/phase1b_best_sinr_map.png`
- `results/figures/phase2_sector_load_map.png`
- `results/figures/phase2_qos_satisfaction_map.png`

Оруулах тоо:

- Phase 2 active UEs = 75
- active attach rate = 98.67%
- offered traffic = 360.53 Mbps
- served traffic = 353.29 Mbps
- QoS satisfaction = 98.67%
- overloaded sectors = 0

Source table:

- `results/tables/phase2_network_kpis.csv`

Ярих санаа:

- RF coverage сайн байсан ч traffic нэмэгдэхэд QoS/load асуудал тусдаа гарна.
- Энэ нь ML-д хэрэгтэй KPI feature-үүдийг үүсгэнэ.

### Slide 7 - Scenario and dataset generation

Claim title: **Eight scenario types create controlled KPI degradation patterns**

Оруулах зураг:

- `results/figures/phase3_scenario_summary.png`
- `results/figures/phase4_dataset_summary.png`

Оруулах тоо:

- Phase 4 network rows = 168
- sector rows = 3528
- scenario count balanced: 21 realization per scenario
- scenario types: normal, low_load, overload, degraded_sector, outage_sector, low_load_energy_saving_candidate, handover_stress, mixed_conflict

Source table:

- `results/tables/phase4_dataset_validation.csv`

Ярих санаа:

- Энэ хэсэг дээр “training data хиймлээр үүсгэсэн” гэж тодорхой хэл.
- Leakage control хийсэн гэж хэлэхдээ `phase4b_feature_leakage_audit.csv`-г appendix/source гэж дурдана.

### Slide 8 - AI/ML architecture and module layers

Claim title: **The pipeline separates detection, prediction, action generation, reward learning, and safety**

Оруулах зураг:

- `results/figures/current_system_architecture_workflow.png`

Тайлбарлах layers:

- Data layer: topology, UE, RF, traffic, KPI
- Scenario/dataset layer: Phase 3-4
- Support ML: COD, TP, QP
- Action modules: COC/OH, LB/MLB, ES, HO/MRO
- Reward/oracle: counterfactual reward + oracle
- Action-value ML: supervised reward regression
- Safety/coordinator: unsafe filter + priority conflict resolution
- KPI update: one-step cloned-state evaluation

Ярих санаа:

- “AI” нь нэг black-box agent биш. Олон deterministic + supervised ML module нийлсэн chain.

### Slide 9 - Trigger and module logic

Claim title: **Triggers decide which module should propose actions**

Оруулах файл:

- `src/actions/generate_candidate_actions.m`
- `src/actions/generate_coc_candidates.m`
- `src/actions/generate_lb_candidates.m`
- `src/actions/generate_es_candidates.m`
- `src/actions/generate_mro_candidates.m`
- `src/actions/safety_check_action.m`

Оруулах table/diagram:

- COD/outage -> COC/OH
- high load / overload -> LB/MLB
- low-load candidate -> ES
- boundary/handover risk -> HO/MRO
- TP/QP -> support prediction, not direct action

Ярих санаа:

- Candidate action total = 130,894
- COC/OH = 8,946, LB/MLB = 10,348, ES = 2,664, HO/MRO = 108,936

Source table:

- `results/tables/phase8a_candidate_action_summary.csv`

### Slide 10 - Reward, oracle, and safety

Claim title: **Counterfactual reward is a training target, while safety removes risky selections**

Оруулах файл:

- `docs/phase8b_reward_formula.md`
- `results/figures/phase10a_raw_vs_safe_selection.png`

Reward formula:

`reward = coverage + QoS + load + handover + energy - safety/cost penalty`

Оруулах тоо:

- Phase 8C oracle groups: COC/OH 63, LB/MLB 796, ES 924, HO/MRO 612
- Phase 10A safety filter changed: COC/OH 1, LB/MLB 65, ES 134, HO/MRO 23

Source tables:

- `results/tables/phase8c_oracle_summary_by_module.csv`
- `results/tables/phase10a_safety_filter_summary.csv`

Ярих санаа:

- Reward нь action apply хийсэн бодит үр дүн биш, counterfactual proxy.
- Safety layer байхгүй бол raw ML top-1 сонголт unsafe байж болно.

### Slide 11 - AI/ML learning: action-value model

Claim title: **The model learns reward from leakage-controlled pre-action KPI and action features**

Оруулах зураг:

- `results/figures/supervised_coc_model_comparison.png`
- optionally `results/figures/supervised_action_value_test_r2_by_module.png`

Оруулах тоо:

- Compared models: Linear/Ridge, Random Forest, LSBoost
- Safe test R2:
  - COC/OH LSBoost = 0.997
  - LB/MLB LSBoost = 0.995
  - ES LSBoost = 1.000
  - HO/MRO LSBoost = 1.000
- Ranking:
  - COC/OH LSBoost top-1 oracle match = 86.7%
  - LB/MLB Random Forest top-1 oracle match = 93.1%

Source tables:

- `results/tables/supervised_action_value_model_metrics.csv`
- `results/tables/supervised_action_value_model_ranking.csv`

Ярих санаа:

- “Сурсан” гэдэг нь real network дээр туршсан гэсэн үг биш.
- It learned the counterfactual reward surface from simulation-generated examples.
- Unsafe/mixed diagnostic plots-ыг main result болгож болохгүй.

### Slide 12 - Offline coordinator

Claim title: **The coordinator converts model outputs into final executable decisions**

Оруулах зураг:

- `results/figures/phase11b_final_decision_status.png`
- `results/figures/phase11b_executable_actions_by_module.png`

Оруулах тоо:

- Final decisions = 561
- Executable actions = 238
- Final safe actions: COC/OH 9, LB/MLB 55, ES 66, HO/MRO 108
- KPI update eligible after simulator support: COC/OH 9, LB/MLB 55, ES 0, HO/MRO 0

Source tables:

- `results/tables/phase11b_summary_by_module.csv`
- `results/tables/phase11b_final_coordination_validation.csv`
- `results/tables/phase12c_eligible_summary_by_module.csv`

Ярих санаа:

- Coordinator priority/conflict resolution хийдэг.
- Гэхдээ final safe action бүр physical KPI update-д ороогүй. Simulator-д хэрэгжих боломжтой action л Phase 12D-д орсон.

### Slide 13 - One-step KPI(t)->KPI(t+1) method

Claim title: **Only implementable COC/OH and LB/MLB actions are applied to cloned topology**

Оруулах файл:

- `src/application/run_phase12d_one_step_kpi_update.m`
- `src/application/apply_eligible_actions_to_cloned_state.m`
- `src/application/apply_cio_bias_to_association.m`

Оруулах flow:

1. Phase 4 scenario replay
2. pre RF + traffic + KPI compute
3. clone topology
4. apply eligible actions
5. recompute RF + traffic + KPI
6. compare pre/post

Ярих санаа:

- Original topology mutate хийгдээгүй.
- CIO physical RSRP/SINR-г хиймлээр өсгөдөггүй, association bias дээр л хэрэглэгдэнэ.

### Slide 14 - Phase 12D KPI result

Claim title: **AI/ML actions improve QoS and load on average but reduce attach rate slightly**

Оруулах зураг:

- `results/figures/phase12d_pre_post_kpi_by_module.png`
- `results/figures/phase12d_load_change_by_scenario.png`
- `results/figures/phase12d_kpi_update_outcomes.png`

Оруулах тоо:

- Applied actions = 64
- COC/OH mean delta QoS = +0.0104, delta attach = -0.0080
- LB/MLB mean delta QoS = +0.0165, delta attach = -0.0128
- Global mean delta QoS = +0.0156
- Global mean delta attach = -0.0121
- Global mean delta SINR = +0.0822 dB
- Global mean delta load = -0.0211

Source tables:

- `results/tables/phase12d_summary_by_module.csv`
- `results/tables/phase12e_baseline_ai_oracle_comparison.csv`

Ярих санаа:

- Энэ бол дипломын хамгийн чухал honest result.
- QoS/load/SINR дээр gain байна, attach-rate tradeoff байна. Tradeoff-ыг нууж болохгүй.

### Slide 15 - Baseline vs AI/ML vs oracle

Claim title: **AI/ML is close to the implementable oracle, but physical KPI and reward objectives are not identical**

Оруулах зураг:

- `results/figures/phase12e_baseline_ai_oracle_kpis.png`
- `results/figures/phase12e_oracle_gap_by_module.png`
- `results/figures/phase12e_tradeoff_attach_vs_qos.png`

Оруулах тоо:

- Baseline QoS = 0.5614
- AI/ML QoS = 0.5770
- Oracle QoS = 0.5643
- AI QoS delta = +0.0156
- Oracle QoS delta = +0.0029
- mean attach: baseline 0.9693 -> AI 0.9572

Source table:

- `results/tables/phase12e_baseline_ai_oracle_comparison.csv`

Ярих санаа:

- Oracle нь reward oracle болохоос QoS-only oracle биш.
- Зарим physical QoS дээр AI oracle-оос өндөр харагдаж болно. Энэ нь reward objective олон KPI/penalty-тэй байгааг илтгэнэ.

### Slide 16 - Real KPI data ingestion

Claim title: **Seven real LTE site KPI workbooks are mapped into the 7-site / 21-sector analysis frame**

Оруулах зураг:

- `results/vendor/figures/vendor_availability_heatmap.png`
- `results/vendor/figures/vendor_dl_prb_heatmap.png`

Оруулах тоо:

- Real KPI files = 7
- sectors = 21
- rows = 12,324
- time window = 2026-05-17 23:45 to 2026-05-24 02:30
- average availability = 98.85%
- average DL PRB = 43.42%
- max DL PRB = 99.63%

Source files:

- `KPI/denver.xlsx`
- `KPI/gemtel.xlsx`
- `KPI/hiid.xlsx`
- `KPI/mkm.xlsx`
- `KPI/rivercastle.xlsx`
- `KPI/shutis.xlsx`
- `KPI/uulzwar.xlsx`
- `results/vendor/tables/vendor_site_inventory.csv`
- `results/vendor/tables/vendor_engineering_summary.csv`

Ярих санаа:

- Real KPI хэсэг нь simulation model-ийг live сүлжээнд action хийсэн баталгаа биш.
- Энэ нь KPI parsing, forecast, degradation detection, advisory workflow.

### Slide 17 - Real KPI TP/QP advisory

Claim title: **Real KPI forecasting identifies overload and degradation risks, but evidence quality varies by site**

Оруулах зураг:

- `results/vendor/figures/vendor_tp_user_forecast_summary.png`
- `results/vendor/figures/vendor_tp_user_forecast_scatter.png`
- `results/vendor/figures/vendor_tp_overload_summary.png`
- `results/vendor/figures/vendor_qp_degradation_summary.png`

Оруулах тоо:

- TP test MAE average = 4.47 active users
- TP test R2 average = 0.51
- R2 >= 0.5 sites = 5/7
- overload episodes = 329
- QP degradation episodes = 11

Source tables:

- `results/vendor/tables/vendor_tp_user_forecast_metrics.csv`
- `results/vendor/tables/vendor_tp_overload_episodes.csv`
- `results/vendor/tables/vendor_qp_degradation_episodes.csv`

Ярих санаа:

- Энэ нь “usable advisory”, гэхдээ бүх site дээр ижил сайн биш.
- Shutis site test R2 negative тул overclaim хийхгүй.

### Slide 18 - Real KPI COD + COC ML advisory

Claim title: **COD detects abnormal KPI states and COC ML ranks compensation candidates for engineering review**

Оруулах зураг:

- `results/vendor/figures/vendor_cod_state_timeline.png`
- `results/vendor/figures/vendor_coc_ml_selected_actions.png`
- `results/vendor/figures/vendor_coc_episode_decision_detail.png`
- `results/vendor/figures/vendor_coc_target_safety_summary.png`

Оруулах тоо:

- COD normal rows = 12,162
- degraded rows = 22
- outage-like rows = 140
- COC ML advisory rows = 38
- COC no-op rows = 124
- COC episodes = 8
- longest episode = 375 minutes
- selected targets = S10 and S17
- non-noop parameter suggestions: +3 dB RS power, -1 degree electrical tilt

Source tables:

- `results/vendor/tables/vendor_engineering_summary.csv`
- `results/vendor/tables/vendor_coc_ml_selected_actions.csv`
- `results/vendor/tables/vendor_coc_episode_summary.csv`

Ярих санаа:

- Action нь engineering review-д зориулсан recommendation.
- Real parameter change хийсэн evidence байхгүй. Тиймээс “suggestion-only” гэж хэл.

### Slide 19 - Дүгнэлт ба limitation

Claim title: **The framework works as an offline decision-support chain, with clear limits before live deployment**

Оруулах зүйл:

- 3 contribution:
  1. Synthetic LTE RAN + scenario KPI dataset
  2. ML action-value + safety/coordinator chain
  3. Real KPI advisory workflow
- 3 limitations:
  1. one-step only, no closed-loop
  2. ES/HO-MRO physical action not implemented
  3. real KPI дээр no before/after action proof

Ярих санаа:

- Хамгийн сайн хамгаалалт: хийсэн зүйлээ үнэн зөв хязгаарлаж хэлэх.
- Дараагийн ажил: multi-step simulation, ES sleep RF hookup, HO/MRO temporal model, live-safe A/B validation.

## Main figures to use

Use as main:

- `results/figures/current_system_architecture_workflow.png`
- `results/figures/phase1b_topology_ue_attachment.png`
- `results/figures/phase1b_best_rsrp_map.png`
- `results/figures/phase1b_best_sinr_map.png`
- `results/figures/phase3_scenario_summary.png`
- `results/figures/phase4_dataset_summary.png`
- `results/figures/supervised_coc_model_comparison.png`
- `results/figures/phase10a_raw_vs_safe_selection.png`
- `results/figures/phase11b_final_decision_status.png`
- `results/figures/phase12d_pre_post_kpi_by_module.png`
- `results/figures/phase12e_baseline_ai_oracle_kpis.png`
- `results/vendor/figures/vendor_tp_user_forecast_summary.png`
- `results/vendor/figures/vendor_tp_overload_summary.png`
- `results/vendor/figures/vendor_coc_ml_selected_actions.png`
- `results/vendor/figures/vendor_coc_episode_decision_detail.png`

Avoid as main result:

- Phase 5 clustering figures: archived/disabled in current supervised-only workflow.
- Unsafe/mixed action-value scatter plots: diagnostic only.
- `results/thesis_package/*`: folder is absent in the current workspace.

## Suggested speaking order

1. Why RAN needs ML-assisted decision support.
2. What was implemented and what was not.
3. Synthetic RAN environment.
4. Scenario/dataset generation.
5. ML modules and trigger/action layers.
6. Reward/oracle/safety/coordinator chain.
7. One-step KPI(t+1) result and tradeoff.
8. Real KPI advisory extension.
9. Limitations and future engineering work.

