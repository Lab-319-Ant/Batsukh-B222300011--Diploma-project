%% Vendor KPI suggestion-only runner: COD + COC/OH
% This script maps real vendor KPI files onto the simulated 7-site /
% 21-sector structure and generates KPI-based COD/COC recommendations.
% It does not apply actions or claim real before/after healing.

clear; clc; close all;

rootDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(rootDir, 'config')));
addpath(genpath(fullfile(rootDir, 'src')));

vcfg = vendor_kpi_config();
ensure_folder(vcfg.processedDir);
ensure_folder(vcfg.tablesDir);
ensure_folder(vcfg.figuresDir);

fprintf('\nVendor KPI suggestion-only mode\n');
fprintf('Raw KPI folder: %s\n', vcfg.rawKpiDir);

rawKpi = load_vendor_kpi(vcfg);
cleanKpi = standardize_vendor_kpi(rawKpi, vcfg);
validation = validate_vendor_kpi(cleanKpi, vcfg);
codTable = run_cod_from_vendor_kpi(cleanKpi, vcfg);
cocSuggestions = suggest_coc_actions_from_kpi(codTable, vcfg);
[cocMlRanking, cocMlSelected] = rank_coc_actions_from_vendor_kpi(codTable, vcfg);
[cocMlSimpleActions, cocMlSimpleSummary] = build_vendor_coc_ml_readable_report(cocMlSelected);
[cocEpisodeSummary, cocEpisodeDecisions] = build_vendor_coc_episode_decisions(codTable, cocMlRanking, cocMlSelected, vcfg);
tpTable = run_tp_from_vendor_kpi(cleanKpi, vcfg);
tpUserForecast = run_tp_site_user_forecast(cleanKpi, vcfg);
esTable = suggest_es_from_vendor_kpi(tpTable, codTable, vcfg);
tpPerformanceReport = build_vendor_tp_prediction_performance(tpTable);
tpOverloadReport = build_vendor_tp_overload_report(tpTable, codTable, vcfg);
tpOverloadEpisodes = build_vendor_tp_overload_episodes(tpTable, codTable, tpPerformanceReport, vcfg);
qpTable = run_qp_from_vendor_kpi(tpTable, codTable, vcfg);
qpDegradationEpisodes = build_vendor_qp_degradation_report(qpTable, vcfg);
esSleepReport = build_vendor_es_sleep_report(esTable, vcfg);
esGateReport = build_vendor_es_gate_report(esTable, vcfg);
summaryTable = build_vendor_engineering_summary(cleanKpi, validation, codTable, ...
    cocSuggestions, cocMlSelected, tpOverloadEpisodes, qpDegradationEpisodes, esSleepReport);
sectorMapping = build_vendor_sector_mapping_export(vcfg);
sectorConfig = build_vendor_sector_config_export(sectorMapping, vcfg);

writetable(cleanKpi, fullfile(vcfg.processedDir, 'vendor_kpi_cleaned_15min.csv'));
writetable(cleanKpi, fullfile(vcfg.tablesDir, 'vendor_kpi_cleaned_15min.csv'));
writetable(vcfg.siteMap, fullfile(vcfg.tablesDir, 'vendor_site_mapping.csv'));
writetable(sectorMapping, fullfile(vcfg.tablesDir, 'vendor_provisional_sector_mapping.csv'));
writetable(sectorConfig, fullfile(vcfg.tablesDir, 'vendor_assumed_sector_config.csv'));
writetable(validation.siteInventory, fullfile(vcfg.tablesDir, 'vendor_site_inventory.csv'));
writetable(validation.cellCompleteness, fullfile(vcfg.tablesDir, 'vendor_kpi_completeness_report.csv'));
writetable(validation.ignoredCells, fullfile(vcfg.tablesDir, 'vendor_ignored_extra_cells.csv'));
writetable(validation.duplicateCellNames, fullfile(vcfg.tablesDir, 'vendor_duplicate_cell_name_report.csv'));
writetable(validation.rangeChecks, fullfile(vcfg.tablesDir, 'vendor_kpi_range_check.csv'));
writetable(validation.impossibleStates, fullfile(vcfg.tablesDir, 'vendor_kpi_impossible_state_check.csv'));
writetable(codTable, fullfile(vcfg.tablesDir, 'vendor_cod_state_timeline.csv'));
writetable(cocSuggestions, fullfile(vcfg.tablesDir, 'vendor_coc_suggestions.csv'));
writetable(cocMlRanking, fullfile(vcfg.tablesDir, 'vendor_coc_ml_action_ranking.csv'));
writetable(cocMlSelected, fullfile(vcfg.tablesDir, 'vendor_coc_ml_selected_actions.csv'));
writetable(cocMlSimpleActions, fullfile(vcfg.tablesDir, 'vendor_coc_ml_simple_actions.csv'));
writetable(cocMlSimpleSummary, fullfile(vcfg.tablesDir, 'vendor_coc_ml_simple_summary.csv'));
writetable(cocEpisodeSummary, fullfile(vcfg.tablesDir, 'vendor_coc_episode_summary.csv'));
writetable(cocEpisodeDecisions, fullfile(vcfg.tablesDir, 'vendor_coc_episode_decisions.csv'));
writetable(tpTable, fullfile(vcfg.tablesDir, 'vendor_tp_predictions.csv'));
writetable(tpPerformanceReport, fullfile(vcfg.tablesDir, 'vendor_tp_prediction_performance.csv'));
if ~isempty(tpUserForecast.predictions)
    writetable(tpUserForecast.predictions, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_test_predictions.csv'));
    writetable(tpUserForecast.metrics, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_metrics.csv'));
    writetable(tpUserForecast.featureWeights, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_feature_weights.csv'));
    writetable(tpUserForecast.splitSummary, fullfile(vcfg.tablesDir, 'vendor_tp_user_forecast_split_summary.csv'));
end
writetable(tpOverloadReport, fullfile(vcfg.tablesDir, 'vendor_tp_overload_risk.csv'));
writetable(tpOverloadEpisodes, fullfile(vcfg.tablesDir, 'vendor_tp_overload_episodes.csv'));
writetable(qpTable, fullfile(vcfg.tablesDir, 'vendor_qp_degradation_risk.csv'));
writetable(qpDegradationEpisodes, fullfile(vcfg.tablesDir, 'vendor_qp_degradation_episodes.csv'));
writetable(esTable, fullfile(vcfg.tablesDir, 'vendor_es_suggestions.csv'));
writetable(esSleepReport, fullfile(vcfg.tablesDir, 'vendor_es_sleep_candidates.csv'));
writetable(esGateReport, fullfile(vcfg.tablesDir, 'vendor_es_gate_report.csv'));
writetable(summaryTable, fullfile(vcfg.tablesDir, 'vendor_engineering_summary.csv'));

plot_vendor_kpi_heatmap(vcfg, cleanKpi, 'dl_prb_utilization', 'vendor_dl_prb_heatmap.png');
plot_vendor_kpi_heatmap(vcfg, cleanKpi, 'cell_availability', 'vendor_availability_heatmap.png');
plot_cod_state_timeline(vcfg, codTable);
plot_coc_suggestion_map(vcfg, cocSuggestions);
plot_vendor_coc_ml_ranking(vcfg, cocMlSelected);
plot_vendor_baseline_coverage_time_monitor(vcfg, codTable, cocMlSelected);
plot_vendor_coc_episode_overview(vcfg, cocEpisodeSummary, cocEpisodeDecisions);
plot_vendor_coc_episode_decision_detail(vcfg, codTable, cocEpisodeSummary, cocEpisodeDecisions);
plot_vendor_coc_target_safety_summary(vcfg, cocMlRanking, cocMlSelected);
plot_vendor_tp_overload_summary(vcfg, tpOverloadReport, tpOverloadEpisodes, tpPerformanceReport, tpTable);
plot_vendor_tp_user_forecast(vcfg, tpUserForecast);
plot_vendor_qp_degradation_summary(vcfg, qpTable, qpDegradationEpisodes);
plot_vendor_es_sleep_summary(vcfg, esSleepReport, esTable, esGateReport);

fprintf('\nSaved vendor KPI outputs:\n');
fprintf('  Tables : %s\n', vcfg.tablesDir);
fprintf('  Figures: %s\n', vcfg.figuresDir);
fprintf('  Cleaned: %s\n', fullfile(vcfg.processedDir, 'vendor_kpi_cleaned_15min.csv'));

disp(summaryTable);

function mapping = build_vendor_sector_mapping_export(vcfg)
siteCols = vcfg.siteMap(:, {'sim_site_id','sim_position','vendor_site_key','vendor_file'});
mapping = innerjoin(vcfg.cellMap, siteCols, 'Keys', 'sim_site_id');
mapping = sortrows(mapping, {'sim_site_id','sim_sector_id'});
mapping = mapping(:, {'sim_site_id','sim_position','sim_sector_id', ...
    'vendor_site_key','vendor_file','vendor_cell_id','sim_azimuth_deg'});
end

function sectorConfig = build_vendor_sector_config_export(sectorMapping, vcfg)
sectorConfig = sectorMapping(:, {'sim_site_id','sim_position','sim_sector_id', ...
    'vendor_site_key','vendor_file','vendor_cell_id','sim_azimuth_deg'});
sectorConfig.current_rs_power_dbm = repmat(vcfg.defaultRsPowerDbm, height(sectorConfig), 1);
sectorConfig.current_electrical_tilt_deg = repmat(vcfg.defaultElectricalTiltDeg, height(sectorConfig), 1);
sectorConfig.min_rs_power_dbm = repmat(vcfg.minRsPowerDbm, height(sectorConfig), 1);
sectorConfig.max_rs_power_dbm = repmat(vcfg.maxRsPowerDbm, height(sectorConfig), 1);
sectorConfig.min_electrical_tilt_deg = repmat(vcfg.minElectricalTiltDeg, height(sectorConfig), 1);
sectorConfig.max_electrical_tilt_deg = repmat(vcfg.maxElectricalTiltDeg, height(sectorConfig), 1);
sectorConfig.config_source = repmat({vcfg.vendorConfigSource}, height(sectorConfig), 1);
end

function S = build_vendor_engineering_summary(cleanKpi, validation, codTable, cocSuggestions, ...
    cocMlSelected, tpOverloadEpisodes, qpDegradationEpisodes, esSleepReport)
selected = cleanKpi(cleanKpi.selected_for_21cell_topology, :);
numSites = numel(unique(selected.sim_site_id));
numSectors = numel(unique(selected.sim_sector_id));
numRows = height(selected);

outageRows = sum(strcmp(codTable.cod_state, 'outage_like'));
degradedRows = sum(strcmp(codTable.cod_state, 'degraded_kpi'));
normalRows = sum(strcmp(codTable.cod_state, 'normal'));

if isempty(cocSuggestions)
    cocCandidateRows = 0;
    cocRejectedRows = 0;
else
    cocCandidateRows = sum(strcmp(cocSuggestions.safety_status, 'candidate_for_manual_review'));
    cocRejectedRows = sum(contains(string(cocSuggestions.safety_status), 'rejected'));
end
if ~isempty(cocMlSelected)
    mlStatus = string(cocMlSelected.ml_safety_status);
    cocMlAdvisoryRows = sum(contains(mlStatus, "candidate_for_manual_review") | ...
        contains(mlStatus, "site_outage_coc_ml_advisory") | contains(mlStatus, "conditional"));
else
    cocMlAdvisoryRows = 0;
end

incompleteCells = sum(~validation.cellCompleteness.complete_7day_15min);
ignoredCells = height(validation.ignoredCells);
rangeViolations = sum(validation.rangeChecks.out_of_range_count);
impossibleRows = sum(validation.impossibleStates.row_count);
tpOverloadEpisodeCount = height(tpOverloadEpisodes);
qpDegradationEpisodeCount = height(qpDegradationEpisodes);
esSleepCandidateCount = height(esSleepReport);

S = table(numSites, numSectors, numRows, normalRows, degradedRows, outageRows, ...
    cocCandidateRows, cocMlAdvisoryRows, cocRejectedRows, incompleteCells, ignoredCells, ...
    rangeViolations, impossibleRows, tpOverloadEpisodeCount, qpDegradationEpisodeCount, ...
    esSleepCandidateCount, ...
    {'Suggestion-only. No real parameter changes applied; no before/after healing claim.'}, ...
    'VariableNames', {'selected_site_count','selected_sector_count','selected_row_count', ...
    'cod_normal_rows','cod_degraded_rows','cod_outage_like_rows', ...
    'coc_rule_candidate_rows','coc_ml_advisory_rows','coc_rejected_rows','incomplete_selected_cells', ...
    'ignored_extra_cells','range_violation_rows','impossible_state_rows', ...
    'tp_overload_episode_count','qp_degradation_episode_count','es_sleep_candidate_count', ...
    'claim_boundary'});
end
