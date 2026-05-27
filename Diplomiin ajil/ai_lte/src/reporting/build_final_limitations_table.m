function T = build_final_limitations_table()
%BUILD_FINAL_LIMITATIONS_TABLE Honest limitation statements for the thesis package.

rows = {
    'synthetic_simulation_only',           'All inputs, scenarios, and KPIs come from the synthetic LTE simulator; no live measurement data.';
    'simplified_rf_kpi_model',             '3GPP UMa NLOS pathloss + simplified wideband spectral-efficiency model; not a full LTE scheduler.';
    'cio_affects_association_only',        'CIO bias changes serving-cell selection but never modifies physical RSRP or SINR.';
    'one_step_kpi_only',                   'Phase 12D performs a single KPI(t)->KPI(t+1) recomputation; no multi-step iteration.';
    'no_multi_step_closed_loop',           'No iterative KPI feedback control. Each action is evaluated on a fresh cloned topology.';
    'only_coc_lb_physically_applied',      'Only COC/OH and LB/MLB actions are physically applied; ES and HO/MRO are queued only.';
    'es_sleep_not_physically_applied',     'sectors.is_sleeping flag exists but the RF and KPI engines do not yet consume it; ES sleep is NOT applied to KPI(t+1).';
    'homro_homttt_not_physically_applied', 'hom_offset_dB and ttt_offset_ms columns exist as state placeholders; HO/MRO HOM/TTT is NOT applied to KPI(t+1).';
    'qp_bimodal_bounded_support_model',    'Phase 7C confirmed QoS satisfaction is bimodal; QP is interpreted as a bounded-support model rather than a robust continuous predictor.';
    'no_active_sector_qos_imputation',     'When a sector has no active UEs, QoS is imputed; this contributes to the bimodal QP target distribution and must be considered when reading QP figures.';
    'phase9b_actual_vs_predicted_diagnostic_only', 'The Phase 9B actual-vs-predicted reward scatter is a diagnostic only. It must NOT be used as a main thesis figure or as evidence of perfect reward prediction.';
    'qp_raw_scatter_diagnostic_only',      'The raw Phase 7C QP actual-vs-predicted plot is diagnostic only. Use QP target-distribution + bounded-prediction metrics as the main QP evidence.';
    'no_live_ran_data',                    'No real radio access network measurements, no operator data, no field validation.';
    'no_commercial_son_deployment',        'No commercial SON or AI-RAN claim. Framework is a thesis-grade simulation study.';
    };

T = cell2table(rows, 'VariableNames', {'limitation_id','description'});
end
