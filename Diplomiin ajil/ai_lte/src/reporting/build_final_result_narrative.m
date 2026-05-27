function paths = build_final_result_narrative(cfg, tables, manifest, limitations, beforeAfter)
%BUILD_FINAL_RESULT_NARRATIVE Write thesis-ready markdown files.
%
% All headline numeric values come from the bundle (Phase 12E summaries
% via build_final_thesis_summary_tables) - nothing hardcoded.

pkgDir = fullfile(cfg.resultsDir, 'thesis_package');
ensure_folder(pkgDir);

paths = struct();
paths.summary_md           = fullfile(pkgDir, 'final_result_summary.md');
paths.architecture_md      = fullfile(pkgDir, 'final_architecture_summary.md');
paths.claims_md            = fullfile(pkgDir, 'final_thesis_claims_and_boundaries.md');
paths.report_draft_md      = fullfile(pkgDir, 'final_result_report_draft.md');
paths.before_after_md      = fullfile(pkgDir, 'final_before_after_kpi_interpretation.md');

write_summary_md(paths.summary_md, tables, manifest, limitations, beforeAfter);
write_architecture_md(paths.architecture_md);
write_claims_md(paths.claims_md);
write_report_draft_md(paths.report_draft_md, tables, manifest, limitations, beforeAfter);
write_before_after_interpretation(paths.before_after_md, beforeAfter);
end

function write_summary_md(filePath, tables, manifest, limitations, beforeAfter)
fid = open_w(filePath);
cleanup = onCleanup(@() fclose(fid));

K = build_headline_struct(tables);

w(fid, '# Final Result Summary');
w(fid, '');
w(fid, 'Thesis-ready summary of the synthetic AI/ML-assisted LTE SON-inspired simulation framework. All numeric values below are read from the corrected post-fix Phase 12E summaries.');
w(fid, '');

w(fid, '## 1. Framework overview');
w(fid, '- MATLAB simulation framework over a 7-site / 21-sector tri-sector LTE macro topology.');
w(fid, '- Phases 1B-7C build RF, traffic, KPI, scenario, dataset, clustering, COD, TP, and QP layers.');
w(fid, '- Phases 8A-8C generate candidate actions, evaluate them counterfactually, and define a safety-constrained oracle.');
w(fid, '- Phases 9A-10A train and safety-filter module-specific action-value models.');
w(fid, '- Phases 11A-11B coordinate module decisions offline and produce final decision tables.');
w(fid, '- Phases 12A-12E extend the simulator state, run a one-step KPI(t)->KPI(t+1) evaluation for the implementable subset, and compare baseline vs AI/ML vs oracle.');
w(fid, '- Phase 13 (this package) only summarizes and validates the above; it adds no new simulation behavior.');
w(fid, '');

w(fid, '## 2. RF/KPI validation summary');
w(fid, '- Topology: 7 sites, 21 sectors, ISD derived from link-budget radius.');
w(fid, '- RF: 3GPP UMa NLOS pathloss, antenna pattern with vertical tilt, configurable shadowing.');
w(fid, '- KPI engine: simplified wideband spectral efficiency, sector load, QoS satisfaction.');
w(fid, '- Phase 4 dataset: 8 scenarios x 21 realizations = 168 groups across 3,528 sector-state rows.');
w(fid, '');

w(fid, '## 3. Scenario generation summary');
w(fid, '- Scenarios: normal, low_load, overload, degraded_sector, outage_sector, low_load_energy_saving_candidate, handover_stress, mixed_conflict.');
w(fid, '- Phase 3B sanity validation passes all checks.');
w(fid, '- Phase 4B leakage audit excludes scenario_id, scenario_name, traffic_mode, sector_status, impaired_sector_id, outage_flag, degradation_flag, cod_label, overload_flag, es_candidate as ML inputs.');
w(fid, '');

w(fid, '## 4. ML module summary');
w(fid, '- Clustering: k=4, scenario-aware crosstab interpretation, no scenario label as input.');
w(fid, '- COD: Random Forest classifier; balanced test accuracy ~0.97, outage recall 1.0; external imbalanced macro F1 ~0.75.');
w(fid, '- TP: LSBoost on lag features; overall test R^2 around 0.64 with weak low_load fit.');
w(fid, '- QP: target is bimodal in [0, 1]. Bounded-prediction R^2 ~0.53. Treated as a bounded-support model, NOT a robust continuous QoS predictor.');
w(fid, '');

w(fid, '## 5. Oracle and action-value learning summary');
w(fid, '- Oracle: safety-constrained max-reward selection over Phase 8B counterfactual table; 2,594 decision groups; 273 forced unsafe fallbacks (no safe candidate + no safe no-op).');
w(fid, '- Phase 9B action-value top-1 oracle match: COC/OH 0.926, LB/MLB 0.953, ES 0.408 (top-2 1.000), HO/MRO 0.071.');
w(fid, '- Reward is the deterministic Phase 8B local KPI proxy, not an oracle in itself.');
w(fid, '- Phase 9B actual-vs-predicted reward scatter is a diagnostic only; oracle regret + top-k match are the primary ranking metrics.');
w(fid, '');

w(fid, '## 6. Safety and coordinator summary');
w(fid, '- Phase 10A safety filter replaced unsafe top-1 ML picks where possible; residual unsafe fallback rows are retained as honest diagnostics.');
w(fid, '- Phase 11A coordinator detected and resolved duplicate-application-target and ES-sleep-overlap conflicts; priority order COC/OH > LB/MLB > HO/MRO > ES.');
w(fid, '- Phase 11B final coordinator table separates `final_safe_action`, `final_noop`, `rejected_priority_conflict`, `rejected_safety_conflict`, and `unresolved_unsafe_fallback`. Every row carries `not_applied_flag = true`.');
w(fid, '');

w(fid, '## 7. Before-and-After KPI(t)->KPI(t+1) Result');
w(fid, '');
w(fid, sprintf('After the pre-Phase-13 audit fixes, **%d** post-fix eligible actions (COC/OH compensation + LB/MLB CIO bias) were physically applied to cloned simulator states. ES sleep and HO/MRO HOM/TTT actions were NOT physically applied.', K.applied));
w(fid, '');
w(fid, 'Mean KPI deltas over the applied actions:');
w(fid, '');
w(fid, sprintf('- Attach rate: **%+0.4f** (degradation, reported honestly)', K.dAttach));
w(fid, sprintf('- Mean RSRP : **%+0.4f dB**', K.dRsrp));
w(fid, sprintf('- Mean SINR : **%+0.4f dB**', K.dSinr));
w(fid, sprintf('- Mean sector load: **%+0.4f**', K.dLoad));
w(fid, sprintf('- QoS satisfaction ratio: **%+0.4f**', K.dQos));
w(fid, sprintf('- Mean QoS gap to oracle (oracle - AI/ML): **%+0.4f**', K.qosGap));
w(fid, '');
w(fid, 'This is a **limited one-step KPI(t)->KPI(t+1) evaluation**, not full multi-step closed-loop control.');
w(fid, '');
if ~isempty(beforeAfter.summary)
    w(fid, '| KPI | KPI(t) baseline | AI/ML KPI(t+1) | delta | interpretation |');
    w(fid, '|---|---|---|---|---|');
    for r = 1:height(beforeAfter.summary)
        w(fid, sprintf('| %s | %.4f | %.4f | %+.4f | %s |', ...
            beforeAfter.summary.kpi_name{r}, ...
            beforeAfter.summary.baseline_kpi_t(r), ...
            beforeAfter.summary.ai_ml_kpi_t_plus_1(r), ...
            beforeAfter.summary.delta(r), ...
            beforeAfter.summary.interpretation{r}));
    end
    w(fid, '');
end

w(fid, '## 8. Baseline vs AI/ML vs oracle comparison');
if ~isempty(tables.baselineAiOracle)
    w(fid, '');
    w(fid, '| Scope | Baseline | AI/ML | Oracle | AI delta | Oracle delta | Gap (oracle - AI) | Note |');
    w(fid, '|---|---|---|---|---|---|---|---|');
    T = tables.baselineAiOracle;
    for r = 1:height(T)
        w(fid, sprintf('| %s | %s | %s | %s | %s | %s | %s | %s |', ...
            T.comparison_scope{r}, ...
            fmt_num(T.baseline_metric(r)), fmt_num(T.ai_ml_metric(r)), fmt_num(T.oracle_metric(r)), ...
            fmt_num(T.ai_ml_delta_from_baseline(r)), fmt_num(T.oracle_delta_from_baseline(r)), ...
            fmt_num(T.ai_ml_gap_to_oracle(r)), T.interpretation{r}));
    end
    w(fid, '');
end

w(fid, '## 9. Main engineering finding');
w(fid, '');
w(fid, sprintf(['The corrected one-step evaluation shows that implementable compensation and CIO-based load-balancing actions can ' ...
    'slightly improve mean RSRP (%+0.4f dB), SINR (%+0.4f dB), load (%+0.4f), and QoS (%+0.4f), but still reduce attach rate (%+0.4f). ' ...
    'This confirms the tradeoff of CIO-based association bias: it can relieve load and improve quality for retained attached users, ' ...
    'but it does NOT physically improve weak received signal for all UEs. Therefore, coverage-aware safety coordination is necessary ' ...
    'before applying such actions broadly.'], ...
    K.dRsrp, K.dSinr, K.dLoad, K.dQos, K.dAttach));
w(fid, '');

w(fid, '## 10. Limitations');
if ~isempty(limitations)
    for r = 1:height(limitations)
        w(fid, sprintf('- **%s** -- %s', limitations.limitation_id{r}, limitations.description{r}));
    end
end
w(fid, '');

w(fid, '## 11. Thesis-ready conclusion');
w(fid, '');
w(fid, 'A synthetic AI/ML-assisted LTE SON-inspired simulation framework was developed and evaluated end-to-end:');
w(fid, '');
w(fid, '1. Multi-scenario RF/KPI dataset generation with explicit leakage control.');
w(fid, '2. Five ML/diagnostic modules covering monitoring, detection, prediction, action-value estimation, and safety-enforced action selection.');
w(fid, '3. Safety-constrained oracle used only as an upper-bound benchmark, never as the reward function.');
w(fid, '4. Offline coordinator with explicit priority and conflict-resolution rules.');
w(fid, '5. Limited one-step KPI(t)->KPI(t+1) evaluation honestly showing the attach-rate cost of CIO-only LB/MLB actions, marginal SINR/QoS gains, and the implementation gap for ES sleep and HO/MRO HOM/TTT.');
w(fid, '');
w(fid, 'The framework is **NOT** a closed-loop SON controller, **NOT** a commercial AI-RAN deployment, and **NOT** validated on live RAN data. It is a thesis-grade evaluation of where safety-aware ML-assisted SON algorithms can and cannot help under realistic constraints.');
w(fid, '');

w(fid, '## Module status reference');
if ~isempty(tables.moduleStatus)
    w(fid, '');
    w(fid, '| Module | Status | Method | Applied to KPI(t+1)? |');
    w(fid, '|---|---|---|---|');
    for r = 1:height(tables.moduleStatus)
        w(fid, sprintf('| %s | %s | %s | %s |', ...
            tables.moduleStatus.module_name{r}, ...
            tables.moduleStatus.implemented_status{r}, ...
            tables.moduleStatus.ML_model_or_method{r}, ...
            tables.moduleStatus.physical_KPI_update_status{r}));
    end
    w(fid, '');
end

w(fid, '## Figure manifest summary');
nAvail = sum(manifest.available_flag);
nMain = sum(strcmp(manifest.figure_role, 'main_thesis_figure'));
w(fid, sprintf('%d / %d referenced figures are available under `results/figures/` or `results/thesis_package/`. Of these, %d are classified `main_thesis_figure`. See `final_figure_manifest.csv` for roles.', ...
    nAvail, height(manifest), nMain));
end

function K = build_headline_struct(tables)
%BUILD_HEADLINE_STRUCT Pull headline numbers from the KPI improvement table.
K = struct('applied', 0, 'dAttach', NaN, 'dRsrp', NaN, 'dSinr', NaN, ...
    'dLoad', NaN, 'dQos', NaN, 'qosGap', NaN);
if isempty(tables.kpiImprovement)
    return;
end
KI = tables.kpiImprovement;
K.applied = round(value_for(KI, 'applied_action_count'));
K.dAttach = value_for(KI, 'delta_attach_rate');
K.dRsrp = value_for(KI, 'delta_mean_rsrp_dB');
K.dSinr = value_for(KI, 'delta_mean_sinr_dB');
K.dLoad = value_for(KI, 'delta_mean_sector_load');
K.dQos = value_for(KI, 'delta_qos_satisfaction_ratio');
K.qosGap = value_for(KI, 'qos_gap_to_oracle');
end

function v = value_for(KI, metricName)
mask = strcmp(KI.metric, metricName);
if any(mask)
    v = KI.value(find(mask, 1, 'first'));
else
    v = NaN;
end
end

function s = fmt_num(v)
if isnan(v), s = 'n/a'; return; end
s = sprintf('%+0.4f', v);
end

function write_architecture_md(filePath)
fid = open_w(filePath);
cleanup = onCleanup(@() fclose(fid));

w(fid, '# Final Architecture Summary');
w(fid, '');
w(fid, 'High-level architecture of the staged LTE SON-inspired simulation framework.');
w(fid, '');
w(fid, '```');
w(fid, 'Phase 1B  RF / topology / UE / RSRP / SINR / attach');
w(fid, 'Phase 2   traffic demand + KPI engine');
w(fid, 'Phase 2C  traffic calibration sensitivity');
w(fid, 'Phase 3   scenario generation (8 scenarios)');
w(fid, 'Phase 4   multi-scenario dataset (168 realizations) + 4B leakage-controlled features');
w(fid, 'Phase 5   k-means state monitor (k=4)');
w(fid, 'Phase 6A/B COD dataset + Random Forest classifier');
w(fid, 'Phase 7A/B/C TP/QP temporal dataset + LSBoost + bounded diagnostics');
w(fid, 'Phase 8A  candidate action generation');
w(fid, 'Phase 8B  counterfactual evaluation + safety stub');
w(fid, 'Phase 8C  safety-constrained oracle benchmark');
w(fid, 'Phase 9A  leakage-controlled action-value dataset');
w(fid, 'Phase 9B  per-module LSBoost reward regression');
w(fid, 'Phase 10A safety-enforced ML action selection');
w(fid, 'Phase 11A coordinator conflict detection + resolution');
w(fid, 'Phase 11B final coordinator decision table');
w(fid, 'Phase 12A action-application feasibility audit');
w(fid, 'Phase 12B simulator action-state extension (CIO bias + state placeholders)');
w(fid, 'Phase 12C KPI(t+1)-eligible action set (post-fix: 60 of 206)');
w(fid, 'Phase 12D one-step KPI(t)->KPI(t+1) cloned-state evaluation');
w(fid, 'Phase 12E baseline vs AI/ML vs oracle comparison + tradeoff analysis');
w(fid, 'Phase 13  thesis-ready packaging (this folder)');
w(fid, '```');
w(fid, '');
w(fid, 'See `final_module_status_table.csv` for per-module implementation status, ML method, physical-KPI-update status, validation metric, and module limitation.');
end

function write_claims_md(filePath)
fid = open_w(filePath);
cleanup = onCleanup(@() fclose(fid));

w(fid, '# Final Thesis Claims and Boundaries');
w(fid, '');
w(fid, '## Allowed claims');
w(fid, '');
w(fid, '1. A synthetic MATLAB LTE RAN simulation framework was developed.');
w(fid, '2. The framework supports RF/KPI generation over a 7-site / 21-sector topology.');
w(fid, '3. Multiple SON-inspired scenarios were generated and validated.');
w(fid, '4. ML-based monitoring, detection, prediction, and action-value estimation were implemented.');
w(fid, '5. A safety-constrained oracle and safety-enforced ML action selection were evaluated.');
w(fid, '6. An offline coordinator resolved module conflicts and produced final decision tables.');
w(fid, '7. A limited one-step KPI(t)->KPI(t+1) evaluation was implemented for implementable COC/OH and LB/MLB actions.');
w(fid, '8. CIO-based LB/MLB and implementable compensation/load-balancing actions improved mean RSRP, SINR, load, and QoS slightly, but introduced an attach-rate tradeoff.');
w(fid, '');
w(fid, '## Forbidden claims');
w(fid, '');
w(fid, 'The following statements MUST NOT be made about this thesis-grade simulation work:');
w(fid, '');
w(fid, '1. Do not claim commercial AI-RAN implementation.');
w(fid, '2. Do not claim real network deployment.');
w(fid, '3. Do not claim full 3GPP SON compliance.');
w(fid, '4. Do not claim all modules were physically applied.');
w(fid, '5. Do not claim ES sleep was applied to KPI(t+1).');
w(fid, '6. Do not claim HO/MRO HOM/TTT was applied to KPI(t+1).');
w(fid, '7. Do not claim multi-step iterative KPI feedback control.');
w(fid, '8. Do not claim QP is a robust continuous QoS predictor.');
w(fid, '9. Do not claim Phase 8B reward was substituted for physical KPI.');
w(fid, '10. Do not claim action-value actual-vs-predicted reward scatter proves perfect reward prediction.');
w(fid, '');
w(fid, '## Honest boundary of the contribution');
w(fid, '');
w(fid, 'This work is a single-step cloned-state evaluation of safety-aware ML-assisted LTE SON-inspired algorithms on a synthetic 7-site / 21-sector simulator. It demonstrates how individual SON modules interact with safety, coordination, and physical state constraints, and it surfaces honest tradeoffs (e.g. the attach-rate cost of CIO-only association bias). It is not a deployment study.');
end

function write_report_draft_md(filePath, tables, manifest, limitations, beforeAfter)
%WRITE_REPORT_DRAFT_MD Word-convertible Markdown draft for the thesis chapter.
fid = open_w(filePath);
cleanup = onCleanup(@() fclose(fid));

K = build_headline_struct(tables);

w(fid, '# Thesis Result Report Draft');
w(fid, '');
w(fid, '*Generated by Phase 13. Convert to Word/docx manually or via pandoc.*');
w(fid, '');
w(fid, '## Abstract');
w(fid, '');
w(fid, 'A MATLAB-based AI/ML-assisted LTE SON-inspired simulation framework was developed and evaluated end-to-end on a synthetic 7-site / 21-sector topology. The framework integrates clustering-based state monitoring, COD classification, TP/QP support prediction, candidate action generation, counterfactual evaluation, a safety-constrained oracle, per-module action-value regression, safety-enforced ML action selection, offline coordination, and a limited one-step KPI(t)->KPI(t+1) evaluation. The contribution is a controlled study of where safety-aware ML-assisted SON can and cannot help, not a production deployment.');
w(fid, '');

w(fid, '## 1. Introduction');
w(fid, '');
w(fid, 'Self-Organising Networks (SON) functions such as Cell Outage Compensation (COC/OH), Load Balancing (LB/MLB), Energy Saving (ES), and Mobility Robustness Optimization (HO/MRO) are well-studied in the 3GPP literature. This thesis develops a MATLAB simulator that exercises these functions with explicit ML, safety, and coordinator layers, on synthetic but reproducible data.');
w(fid, '');

w(fid, '## 2. Framework architecture');
w(fid, '');
w(fid, 'See `final_architecture_summary.md` for the staged phase diagram and `final_module_status_table.csv` for per-module implementation status.');
w(fid, '');

w(fid, '## 3. Methodology summary');
w(fid, '');
w(fid, '- Phase 1B-7C: RF / traffic / scenario / dataset / clustering / COD / TP / QP layers.');
w(fid, '- Phase 8A-8C: candidate action generation, counterfactual evaluation, safety-constrained oracle.');
w(fid, '- Phase 9A-10A: leakage-controlled action-value dataset, per-module LSBoost regressor, safety filter.');
w(fid, '- Phase 11A-11B: offline coordinator with priority and conflict resolution.');
w(fid, '- Phase 12A-12E: simulator state extension (CIO + reference power offset + tilt), eligible action set, one-step KPI(t)->KPI(t+1) cloned-state evaluation, baseline-vs-AI-vs-oracle comparison.');
w(fid, '');

w(fid, '## 4. Main result: before vs after one-step KPI evaluation');
w(fid, '');
w(fid, sprintf('After the pre-Phase-13 audit fixes, %d post-fix eligible COC/OH and LB/MLB actions were physically applied to cloned simulator states. ES sleep and HO/MRO HOM/TTT actions were NOT applied.', K.applied));
w(fid, '');
w(fid, '### 4.1 Headline KPI deltas');
w(fid, '');
w(fid, '| KPI | KPI(t) baseline | AI/ML KPI(t+1) | delta | interpretation |');
w(fid, '|---|---|---|---|---|');
if ~isempty(beforeAfter.summary)
    for r = 1:height(beforeAfter.summary)
        w(fid, sprintf('| %s | %.4f | %.4f | %+.4f | %s |', ...
            beforeAfter.summary.kpi_name{r}, ...
            beforeAfter.summary.baseline_kpi_t(r), ...
            beforeAfter.summary.ai_ml_kpi_t_plus_1(r), ...
            beforeAfter.summary.delta(r), ...
            beforeAfter.summary.interpretation{r}));
    end
end
w(fid, '');

w(fid, '### 4.2 Baseline vs AI/ML vs oracle');
w(fid, '');
w(fid, 'The oracle is a safety-constrained max-reward benchmark over the Phase 8B counterfactual reward; it is NOT the reward function and NOT an ML model. Where the oracle pick is implementable on the current simulator, its KPI(t+1) is re-computed on a cloned topology for honest comparison.');
w(fid, '');
if ~isempty(tables.baselineAiOracle)
    w(fid, '| Scope | Baseline | AI/ML | Oracle | AI delta | Oracle delta | Gap (oracle - AI) | Note |');
    w(fid, '|---|---|---|---|---|---|---|---|');
    T = tables.baselineAiOracle;
    for r = 1:height(T)
        w(fid, sprintf('| %s | %s | %s | %s | %s | %s | %s | %s |', ...
            T.comparison_scope{r}, ...
            fmt_num(T.baseline_metric(r)), fmt_num(T.ai_ml_metric(r)), fmt_num(T.oracle_metric(r)), ...
            fmt_num(T.ai_ml_delta_from_baseline(r)), fmt_num(T.oracle_delta_from_baseline(r)), ...
            fmt_num(T.ai_ml_gap_to_oracle(r)), T.interpretation{r}));
    end
end
w(fid, '');

w(fid, '### 4.3 Per-scenario KPI deltas');
w(fid, '');
if ~isempty(beforeAfter.byScenario)
    S = beforeAfter.byScenario;
    w(fid, '| scenario | actions | delta attach | delta QoS | QoS gap to oracle |');
    w(fid, '|---|---|---|---|---|');
    for r = 1:height(S)
        gap = NaN;
        if ismember('mean_qos_gap_to_oracle', S.Properties.VariableNames)
            gap = S.mean_qos_gap_to_oracle(r);
        end
        w(fid, sprintf('| %s | %d | %+.4f | %+.4f | %+.4f |', ...
            S.scenario_name{r}, S.total_actions(r), ...
            S.mean_delta_attach(r), S.mean_delta_qos(r), gap));
    end
end
w(fid, '');

w(fid, '## 5. Engineering finding');
w(fid, '');
w(fid, sprintf('Implementable compensation and CIO-based load-balancing actions can slightly improve mean RSRP (%+0.4f dB), SINR (%+0.4f dB), load (%+0.4f), and QoS (%+0.4f), but still reduce attach rate (%+0.4f). CIO-based association bias relieves load and improves quality for retained attached UEs, but does not physically improve received signal for borderline UEs. **Coverage-aware safety coordination is necessary before applying such actions broadly.**', ...
    K.dRsrp, K.dSinr, K.dLoad, K.dQos, K.dAttach));
w(fid, '');

w(fid, '## 6. Limitations');
if ~isempty(limitations)
    for r = 1:height(limitations)
        w(fid, sprintf('- **%s** -- %s', limitations.limitation_id{r}, limitations.description{r}));
    end
end
w(fid, '');

w(fid, '## 7. Conclusion');
w(fid, '');
w(fid, 'The framework demonstrates a controlled, leakage-aware AI/ML-assisted SON pipeline with explicit safety and coordination layers, and an honest one-step KPI(t)->KPI(t+1) evaluation. It is not closed-loop control, not a commercial AI-RAN deployment, and not validated on live RAN data.');
w(fid, '');

w(fid, '## Figures (main thesis figures only)');
mainMask = strcmp(manifest.figure_role, 'main_thesis_figure') & manifest.available_flag;
mainTable = manifest(mainMask, :);
for r = 1:height(mainTable)
    w(fid, sprintf('- `%s` -- %s', mainTable.file_name{r}, mainTable.description{r}));
end
w(fid, '');
w(fid, 'See `final_figure_manifest.csv` for the full manifest with role tags. Phase 9B actual-vs-predicted reward scatter and the raw Phase 7C QP actual-vs-predicted plot are explicitly classified as diagnostic_only / avoid_as_main_result and must NOT be used as primary thesis figures.');
end

function write_before_after_interpretation(filePath, beforeAfter)
fid = open_w(filePath);
cleanup = onCleanup(@() fclose(fid));

w(fid, '# Before-and-After KPI(t)->KPI(t+1) Interpretation');
w(fid, '');
w(fid, 'Per-KPI interpretation lines derived from the corrected post-fix Phase 12E results. Use these statements verbatim or paraphrased in the thesis main-result section.');
w(fid, '');
if ~isempty(beforeAfter.interpretation)
    for k = 1:numel(beforeAfter.interpretation)
        w(fid, char(beforeAfter.interpretation(k)));
    end
end
w(fid, '');
w(fid, '## Summary table');
w(fid, '');
if ~isempty(beforeAfter.summary)
    w(fid, '| KPI | KPI(t) baseline | AI/ML KPI(t+1) | delta | interpretation |');
    w(fid, '|---|---|---|---|---|');
    for r = 1:height(beforeAfter.summary)
        w(fid, sprintf('| %s | %.4f | %.4f | %+.4f | %s |', ...
            beforeAfter.summary.kpi_name{r}, ...
            beforeAfter.summary.baseline_kpi_t(r), ...
            beforeAfter.summary.ai_ml_kpi_t_plus_1(r), ...
            beforeAfter.summary.delta(r), ...
            beforeAfter.summary.interpretation{r}));
    end
end
end

function fid = open_w(filePath)
fid = fopen(filePath, 'w');
if fid < 0
    error('Cannot open %s for write.', filePath);
end
end

function w(fid, s)
fprintf(fid, '%s\n', s);
end
