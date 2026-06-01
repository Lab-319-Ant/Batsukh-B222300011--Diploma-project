%% AI/ML-assisted LTE RAN simulation - Phase 8B (counterfactual evaluation)
% Staged LTE RF/KPI, dataset, prediction, candidate-action, and
% counterfactual-evaluation framework.
%
% Purpose:
%   1) Estimate planned LTE coverage radius from link budget.
%   2) Convert planned radius to first-tier hexagonal ISD.
%   3) Build one common 7-site / 21-sector LTE macro topology.
%   4) Drop UEs over the planned coverage union.
%   5) Compute multi-sector RSRP, SINR, best-sector association, attach state, and load.
%   6) Save Phase 1B RF validation figures and CSV result tables.
%   7) Assign UE traffic demand and allocate simplified wideband throughput.
%   8) Compute sector and network KPIs for traffic, load, and QoS.
%   9) Run Phase 2C sensitivity over refined calibrated traffic modes.
%  10) Generate multi-scenario KPI datasets and leakage-controlled features.
%  11) Train/evaluate COD and TP/QP prediction models.
%  12) Generate candidate action tables for later counterfactual evaluation.
%  13) Evaluate candidate actions counterfactually using a deterministic
%      local KPI proxy (Phase 8B).
%
% IMPORTANT: This framework is NOT closed-loop SON control.
% Phase 8B is counterfactual evaluation only. It does not select actions,
% does not enforce a final safety checker, does not run an oracle, does not
% train an ML action-value model, does not coordinate module conflicts, and
% does not apply any action to produce KPI(t+1).

clear; clc; close all;

%% Add paths
thisFile = mfilename('fullpath');
[rootDir, ~, ~] = fileparts(thisFile);
addpath(genpath(fullfile(rootDir, 'config')));
addpath(genpath(fullfile(rootDir, 'src')));

%% Load configuration
cfg = sim_config();
cfg = configure_run_mode(cfg);
rng(cfg.seed);

ensure_folder(cfg.resultsDir);
ensure_folder(cfg.figuresDir);
ensure_folder(cfg.tablesDir);
ensure_folder(cfg.logsDir);
ensure_folder(cfg.modelsDir);

fprintf('\nRun mode                   : %s\n', cfg.runMode);

%% Phase 1: Link-budget based planned coverage radius
[cfg.plannedRadius_m, linkBudget] = estimate_coverage_radius(cfg);
cfg.ISD_m = sqrt(3) * cfg.plannedRadius_m;

% Use a study window large enough to show all first-tier sites and their
% planned coverage circles. This is separate from the UE drop area.
cfg.area_m = 2.25 * 2 * (cfg.ISD_m + cfg.plannedRadius_m);

fprintf('\n================ PHASE 1B LTE RF VALIDATION ===================\n');
fprintf('Active project phase       : %s\n', cfg.phaseName);
fprintf('RF validation baseline     : %s\n', cfg.rfPhaseName);
fprintf('Topology                   : 7 sites / 21 sectors\n');
fprintf('Carrier frequency          : %.2f GHz\n', cfg.fc_GHz);
fprintf('Path-loss model            : %s\n', cfg.pathlossModel);
fprintf('RS reference power P_RS    : %.1f dBm\n', cfg.refSignalPower_dBm);
fprintf('Total sector Tx power      : %.1f dBm\n', cfg.txPower_dBm);
fprintf('Antenna peak gain          : %.1f dBi\n', cfg.antennaGain_dBi);
fprintf('Minimum RSRP threshold     : %.1f dBm\n', cfg.minRSRP_dBm);
fprintf('Minimum SINR threshold     : %.1f dB\n', cfg.minSINR_dB);
fprintf('MAPL                       : %.2f dB\n', linkBudget.MAPL_dB);
fprintf('Estimated planned radius   : %.1f m\n', cfg.plannedRadius_m);
fprintf('Hexagonal ISD              : %.1f m\n', cfg.ISD_m);
fprintf('UE drop mode               : %s\n', cfg.ueDropMode);
fprintf('Study window width         : %.1f m\n', cfg.area_m);
fprintf('================================================================\n\n');

%% Phase 2: Create 7-site / 21-sector topology
topology = create_7site21sector_topology(cfg);

if strcmp(cfg.runMode, 'phase4_only')
    timingTable = run_phase4_only_workflow(cfg, topology);
    write_run_dependency_summary(cfg);
    fprintf('\nRun mode phase4_only completed. Timing rows: %d\n', height(timingTable));
    return;
end

if strcmp(cfg.runMode, 'phase8a_only')
    timingTable = run_phase8a_only_workflow(cfg, topology);
    write_run_dependency_summary(cfg);
    fprintf('\nRun mode phase8a_only completed. Timing rows: %d\n', height(timingTable));
    return;
end

if strcmp(cfg.runMode, 'reuse_phase4_to_phase8a')
    timingTable = run_reuse_phase4_to_phase8a_workflow(cfg, topology);
    write_run_dependency_summary(cfg);
    fprintf('\nRun mode reuse_phase4_to_phase8a completed. Timing rows: %d\n', height(timingTable));
    return;
end

phaseTimingTable = table();
phaseStart = tic;

%% Phase 3: Generate UEs over the planned coverage union
ues = generate_ues(cfg, topology);

%% Phase 4: RF propagation, RSRP, SINR, association
rf = calc_rsrp_sinr(cfg, topology, ues);
rfMap = compute_best_server_map(cfg, topology);

%% Phase 5: Results summary
attachedCount = sum(rf.isAttached);
attachRate = attachedCount / cfg.numUE;
sinrThresholdUECount = sum(rf.bestSINR_dB >= cfg.minSINR_dB);
sinrThresholdUERatio = sinrThresholdUECount / cfg.numUE;

sectorLoad = accumarray(rf.servingSector(rf.isAttached), 1, [height(topology.sectors), 1], @sum, 0);
sectorLoadRatio = sectorLoad / max(sum(sectorLoad), 1);

summaryTable = table( ...
    {cfg.rfPhaseName}, cfg.fc_GHz, height(topology.sites), height(topology.sectors), ...
    cfg.numUE, cfg.plannedRadius_m, cfg.ISD_m, cfg.area_m, linkBudget.MAPL_dB, ...
    attachedCount, cfg.numUE - attachedCount, attachRate, ...
    sinrThresholdUECount, sinrThresholdUERatio, ...
    mean(rf.bestRSRP_dBm, 'omitnan'), median(rf.bestRSRP_dBm, 'omitnan'), ...
    mean(rf.bestSINR_dB(rf.isAttached), 'omitnan'), median(rf.bestSINR_dB(rf.isAttached), 'omitnan'), ...
    rfMap.plannedCoverageRatio, rfMap.plannedRSRPCoverageRatio, rfMap.plannedSINRThresholdRatio, ...
    rfMap.studyCoverageRatio, ...
    'VariableNames', {'phaseName','fc_GHz','numSites','numSectors','numUE', ...
    'plannedRadius_m','ISD_m','studyWindow_m','MAPL_dB','attachedUE','unattachedUE', ...
    'attachRate','sinrThresholdUE','sinrThresholdUERatio','meanBestRSRP_dBm', ...
    'medianBestRSRP_dBm','meanAttachedSINR_dB','medianAttachedSINR_dB', ...
    'plannedCoverageRatio','plannedRSRPCoverageRatio','plannedSINRThresholdRatio', ...
    'studyCoverageRatio'});

sectorLoadTable = table( ...
    topology.sectors.sectorId, topology.sectors.siteId, topology.sectors.azimuth_deg, ...
    sectorLoad, sectorLoadRatio, ...
    'VariableNames', {'sectorId','siteId','azimuth_deg','attachedUE','loadRatio'});

servingSite = zeros(cfg.numUE, 1);
attachedServingSector = rf.servingSector(rf.isAttached);
servingSite(rf.isAttached) = topology.sectors.siteId(attachedServingSector);

ueTable = table( ...
    ues.ueId, ues.x_m, ues.y_m, rf.servingSector, servingSite, ...
    rf.bestRSRP_dBm, rf.bestSINR_dB, rf.isAttached, ...
    'VariableNames', {'ueId','x_m','y_m','servingSector','servingSite', ...
    'bestRSRP_dBm','bestSINR_dB','isAttached'});

writetable(topology.sites, fullfile(cfg.tablesDir, 'phase1b_sites.csv'));
writetable(topology.sectors, fullfile(cfg.tablesDir, 'phase1b_sectors.csv'));
writetable(summaryTable, fullfile(cfg.tablesDir, 'phase1b_summary.csv'));
writetable(sectorLoadTable, fullfile(cfg.tablesDir, 'phase1b_sector_load.csv'));
writetable(ueTable, fullfile(cfg.tablesDir, 'phase1b_ue_rf_results.csv'));

logFile = fullfile(cfg.logsDir, 'phase1b_run_summary.txt');
write_run_log(logFile, cfg, linkBudget, summaryTable);

fprintf('Attached UEs               : %d / %d\n', attachedCount, cfg.numUE);
fprintf('Attach rate                : %.2f %%\n', 100 * attachRate);
fprintf('UE SINR threshold ratio    : %.2f %%\n', 100 * sinrThresholdUERatio);
fprintf('Planned-area coverage      : %.2f %%\n', 100 * rfMap.plannedCoverageRatio);
fprintf('Mean best RSRP             : %.2f dBm\n', summaryTable.meanBestRSRP_dBm);
fprintf('Median best RSRP           : %.2f dBm\n', summaryTable.medianBestRSRP_dBm);
fprintf('Mean attached SINR         : %.2f dB\n', summaryTable.meanAttachedSINR_dB);
fprintf('Median attached SINR       : %.2f dB\n\n', summaryTable.medianAttachedSINR_dB);

disp('Sector load table:');
disp(sectorLoadTable);

%% Phase 6: Plots
plot_topology(cfg, topology, ues, rf);
plot_best_server_map(cfg, topology, rfMap);
plot_best_rsrp_map(cfg, topology, rfMap);
plot_best_sinr_map(cfg, topology, rfMap);
plot_sector_load(cfg, topology, sectorLoadTable);

fprintf('\nSaved Phase 1B outputs:\n');
fprintf('  Figures: %s\n', cfg.figuresDir);
fprintf('  Tables : %s\n', cfg.tablesDir);
fprintf('  Logs   : %s\n', cfg.logsDir);
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase1B_RF_validation', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 2: Traffic demand, throughput allocation, and KPI engine
rng(cfg.seed + 2000);
ueTraffic = assign_ue_traffic_demand(cfg, ues, rf);
[ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfg, ueTraffic, rf, topology);
sectorKpiTable = compute_sector_kpis(cfg, topology, ueTrafficResult, sectorCapacity_Mbps);
networkKpiTable = compute_network_kpis(cfg, topology, ueTrafficResult, sectorKpiTable, rfMap);

writetable(ueTrafficResult, fullfile(cfg.tablesDir, 'phase2_ue_traffic_results.csv'));
writetable(sectorKpiTable, fullfile(cfg.tablesDir, 'phase2_sector_kpis.csv'));
writetable(networkKpiTable, fullfile(cfg.tablesDir, 'phase2_network_kpis.csv'));

plot_sector_load_map(cfg, topology, sectorKpiTable, ueTrafficResult);
plot_ue_throughput_map(cfg, topology, ueTrafficResult);
plot_qos_satisfaction_map(cfg, topology, ueTrafficResult);

phase2LogFile = fullfile(cfg.logsDir, 'phase2_run_summary.txt');
write_phase2_log(phase2LogFile, cfg, networkKpiTable);

fprintf('\nPhase 2 Traffic + KPI Results\n');
fprintf('-----------------------------\n');
fprintf('Traffic mode                : %s\n', cfg.trafficMode);
fprintf('Active traffic UEs          : %d / %d\n', networkKpiTable.active_ues, networkKpiTable.num_ues);
fprintf('Total offered traffic       : %.2f Mbps\n', networkKpiTable.total_offered_traffic_Mbps);
fprintf('Total served traffic        : %.2f Mbps\n', networkKpiTable.total_served_traffic_Mbps);
fprintf('Total unserved traffic      : %.2f Mbps\n', networkKpiTable.total_unserved_traffic_Mbps);
fprintf('Attach rate                 : %.2f %%\n', 100 * networkKpiTable.attach_rate);
fprintf('Active-user QoS satisfaction: %.2f %%\n', 100 * networkKpiTable.qos_satisfaction_ratio);
fprintf('Overloaded sectors          : %d / %d\n', networkKpiTable.overloaded_sector_count, height(topology.sectors));
fprintf('Mean sector load            : %.2f\n', networkKpiTable.mean_sector_load);
fprintf('Max sector load             : %.2f\n', networkKpiTable.max_sector_load);
fprintf('Mean UE throughput          : %.2f Mbps\n', networkKpiTable.mean_ue_throughput_Mbps);
fprintf('Jain fairness index         : %.4f\n', networkKpiTable.jain_fairness_index);

fprintf('\nSaved Phase 2 outputs:\n');
fprintf('  Figures: %s\n', cfg.figuresDir);
fprintf('  Tables : %s\n', cfg.tablesDir);
fprintf('  Logs   : %s\n', cfg.logsDir);
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase2_traffic_kpi_engine', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 2C: Traffic calibration refinement and sensitivity validation
[calibrationSummary, calibrationSectorKpis, calibrationUeResults] = ...
    run_traffic_calibration(cfg, topology, ues, rf, rfMap);

writetable(calibrationSummary, fullfile(cfg.tablesDir, 'phase2c_traffic_calibration_summary.csv'));
writetable(calibrationSectorKpis, fullfile(cfg.tablesDir, 'phase2c_sector_kpis_by_mode.csv'));
writetable(calibrationUeResults, fullfile(cfg.tablesDir, 'phase2c_ue_traffic_by_mode.csv'));

plot_traffic_calibration_summary(cfg, calibrationSummary);

phase2cLogFile = fullfile(cfg.logsDir, 'phase2c_traffic_calibration_summary.txt');
write_phase2c_log(phase2cLogFile, calibrationSummary);

fprintf('\nPhase 2C Traffic Calibration Results\n');
fprintf('------------------------------------\n');
disp(calibrationSummary(:, {'traffic_mode','active_user_ratio','total_offered_traffic_Mbps', ...
    'total_served_traffic_Mbps','qos_satisfaction_ratio','overloaded_sector_count', ...
    'mean_sector_load','max_sector_load'}));

fprintf('\nSaved Phase 2C outputs:\n');
fprintf('  Figure : %s\n', fullfile(cfg.figuresDir, 'phase2c_traffic_calibration_summary.png'));
fprintf('  Tables : %s\n', cfg.tablesDir);
fprintf('  Logs   : %s\n', cfg.logsDir);
fprintf('\nProceeding to Phase 3 scenario generation using the calibrated traffic modes.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase2C_traffic_calibration', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 3: Scenario generation over the common topology
[scenarioSummary, sectorKpisByScenario, networkKpisByScenario, ueResultsByScenario] = ...
    run_phase3_scenarios(cfg, topology, ues);

writetable(scenarioSummary, fullfile(cfg.tablesDir, 'phase3_scenario_summary.csv'));
writetable(sectorKpisByScenario, fullfile(cfg.tablesDir, 'phase3_sector_kpis_by_scenario.csv'));
writetable(networkKpisByScenario, fullfile(cfg.tablesDir, 'phase3_network_kpis_by_scenario.csv'));
writetable(ueResultsByScenario, fullfile(cfg.tablesDir, 'phase3_ue_results_by_scenario.csv'));

plot_phase3_scenario_summary(cfg, scenarioSummary);
sanityTable = validate_phase3_scenarios(cfg, scenarioSummary);

phase3LogFile = fullfile(cfg.logsDir, 'phase3_scenario_summary.txt');
write_phase3_log(phase3LogFile, scenarioSummary);

fprintf('\nPhase 3 Scenario Generation Results\n');
fprintf('-----------------------------------\n');
for i = 1:height(scenarioSummary)
    name = scenarioSummary.scenario_name{i};
    fprintf('%s:\n', name);
    switch name
        case {'normal','low_load','overload'}
            fprintf('  attach rate        : %.2f %%\n', 100 * scenarioSummary.attach_rate(i));
            fprintf('  QoS ratio          : %.2f %%\n', 100 * scenarioSummary.qos_satisfaction_ratio_active(i));
            fprintf('  overloaded sectors : %d\n', scenarioSummary.overloaded_sector_count(i));
            fprintf('  mean load          : %.2f\n', scenarioSummary.mean_sector_load(i));
        case {'degraded_sector','outage_sector'}
            fprintf('  attach rate        : %.2f %%\n', 100 * scenarioSummary.attach_rate(i));
            fprintf('  QoS ratio          : %.2f %%\n', 100 * scenarioSummary.qos_satisfaction_ratio_active(i));
            fprintf('  impaired sector    : %d\n', scenarioSummary.impaired_sector_id(i));
        case 'low_load_energy_saving_candidate'
            fprintf('  ES candidate sectors: %d\n', scenarioSummary.es_candidate_sector_count(i));
            fprintf('  mean load           : %.2f\n', scenarioSummary.mean_sector_load(i));
        case 'handover_stress'
            fprintf('  boundary UE ratio  : %.2f %%\n', 100 * scenarioSummary.boundary_ue_ratio(i));
            fprintf('  handover risk score: %.4f\n', scenarioSummary.handover_risk_score(i));
        case 'mixed_conflict'
            fprintf('  attach rate        : %.2f %%\n', 100 * scenarioSummary.attach_rate(i));
            fprintf('  QoS ratio          : %.2f %%\n', 100 * scenarioSummary.qos_satisfaction_ratio_active(i));
            fprintf('  overloaded sectors : %d\n', scenarioSummary.overloaded_sector_count(i));
            fprintf('  impaired sector    : %d\n', scenarioSummary.impaired_sector_id(i));
    end
end

fprintf('\nSaved Phase 3 outputs:\n');
fprintf('  Figure : %s\n', fullfile(cfg.figuresDir, 'phase3_scenario_summary.png'));
fprintf('  Tables : %s\n', cfg.tablesDir);
fprintf('  Logs   : %s\n', cfg.logsDir);

fprintf('\nPhase 3B Scenario Sanity Check\n');
fprintf('------------------------------\n');
passedCount = sum(sanityTable.pass_flag);
failedCount = height(sanityTable) - passedCount;
fprintf('Passed checks: %d\n', passedCount);
fprintf('Failed checks: %d\n', failedCount);
if failedCount > 0
    failedChecks = sanityTable(~sanityTable.pass_flag, :);
    disp(failedChecks(:, {'check_name','expected_condition','actual_value','reference_value','notes'}));
end
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase3_scenario_generation_and_sanity', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 4: Multi-scenario dataset generation and validation
fprintf('\nPhase 4 Multi-Scenario Dataset Generation\n');
fprintf('-----------------------------------------\n');
[sectorStateDataset, networkStateDataset, phase4ScenarioPlan] = generate_phase4_dataset(cfg, topology);
phase4ValidationTable = validate_phase4_dataset(cfg, sectorStateDataset, networkStateDataset, phase4ScenarioPlan);

writetable(phase4ScenarioPlan, fullfile(cfg.tablesDir, 'phase4_scenario_plan.csv'));
writetable(sectorStateDataset, fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv'));
writetable(networkStateDataset, fullfile(cfg.tablesDir, 'phase4_network_state_dataset.csv'));
plot_phase4_dataset_summary(cfg, networkStateDataset);

phase4LogFile = fullfile(cfg.logsDir, 'phase4_dataset_summary.txt');
write_phase4_log(phase4LogFile, cfg, sectorStateDataset, networkStateDataset, phase4ValidationTable);

phase4Passed = sum(phase4ValidationTable.pass_flag);
phase4Failed = height(phase4ValidationTable) - phase4Passed;
fprintf('Network-state rows         : %d\n', height(networkStateDataset));
fprintf('Sector-state rows          : %d\n', height(sectorStateDataset));
fprintf('Scenario types             : %d\n', numel(cfg.phase4ScenarioTypes));
fprintf('Realizations per scenario  : %d\n', cfg.phase4NumRealizationsPerScenario);
fprintf('Validation passed checks   : %d\n', phase4Passed);
fprintf('Validation failed checks   : %d\n', phase4Failed);
if phase4Failed > 0
    failedChecks = phase4ValidationTable(~phase4ValidationTable.pass_flag, :);
    disp(failedChecks(:, {'check_name','expected_condition','actual_value','reference_value','notes'}));
end

fprintf('\nSaved Phase 4 outputs:\n');
fprintf('  Figure : %s\n', fullfile(cfg.figuresDir, 'phase4_dataset_summary.png'));
fprintf('  Tables : %s\n', cfg.tablesDir);
fprintf('  Logs   : %s\n', cfg.logsDir);
fprintf('\nNext engineering step: use Phase 4 validation results to prepare supervised ML datasets. Do not train ML before reviewing feature leakage.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase4_multi_scenario_dataset', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 4B: Feature leakage review and ML dataset preparation
fprintf('\nPhase 4B Feature Leakage Review\n');
fprintf('-------------------------------\n');
[clusteringFeatures, codFeatures, tpqpFeatures, featureDictionary, featureSets] = ...
    prepare_phase4_ml_feature_tables(cfg, sectorStateDataset, networkStateDataset);
leakageAudit = audit_feature_leakage(cfg, clusteringFeatures, codFeatures, tpqpFeatures, featureSets);
phase4bValidationTable = validate_phase4_ml_features(cfg, clusteringFeatures, ...
    codFeatures, tpqpFeatures, featureDictionary, leakageAudit, featureSets);

leakageRiskCount = sum(leakageAudit.leakage_risk);
validationErrors = phase4bValidationTable(strcmp(phase4bValidationTable.severity, 'error') & ...
    ~phase4bValidationTable.pass_flag, :);
validationWarnings = phase4bValidationTable(strcmp(phase4bValidationTable.severity, 'warning') & ...
    ~phase4bValidationTable.pass_flag, :);

if isfield(cfg, 'enableUnsupervisedClustering') && ~cfg.enableUnsupervisedClustering
    fprintf('Sector monitor feature rows: %d (K-means disabled; table kept for compatibility)\n', height(clusteringFeatures));
else
    fprintf('Clustering feature rows    : %d\n', height(clusteringFeatures));
end
fprintf('COD feature rows           : %d\n', height(codFeatures));
fprintf('TP/QP network feature rows : %d\n', height(tpqpFeatures));
fprintf('Leakage checks             : %d risk columns\n', leakageRiskCount);
fprintf('Validation errors          : %d\n', height(validationErrors));
fprintf('Validation warnings        : %d\n', height(validationWarnings));
if ~isempty(validationErrors)
    disp(validationErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(validationWarnings)
    disp(validationWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end

fprintf('Saved feature tables:\n');
fprintf('  phase4b_sector_features_clustering.csv\n');
fprintf('  phase4b_sector_features_cod.csv\n');
fprintf('  phase4b_network_features_tp_qp.csv\n');
fprintf('  phase4b_feature_dictionary.csv\n');
fprintf('  phase4b_feature_leakage_audit.csv\n');
fprintf('  phase4b_ml_feature_validation.csv\n');
fprintf('\nPhase 4B prepares leakage-controlled tables only. No ML model has been trained.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase4B_feature_leakage_review', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 5: Optional clustering-based state monitor
if ~isfield(cfg, 'enableUnsupervisedClustering') || cfg.enableUnsupervisedClustering
    fprintf('\nPhase 5 Clustering-Based State Monitor\n');
    fprintf('--------------------------------------\n');
    phase5 = run_phase5_clustering_state_monitor(cfg);
    phase5Errors = phase5.validationTable(strcmp(phase5.validationTable.severity, 'error') & ...
        ~phase5.validationTable.pass_flag, :);
    phase5Warnings = phase5.validationTable(strcmp(phase5.validationTable.severity, 'warning') & ...
        ~phase5.validationTable.pass_flag, :);

    fprintf('Input rows                  : %d\n', phase5.inputRows);
    fprintf('Selected input features     : %d\n', numel(phase5.selectedFeatures));
    fprintf('Evaluated k values          : %s\n', mat2str(phase5.kEvaluationTable.k'));
    fprintf('Selected k                  : %d\n', phase5.selectedK);
    if isnan(phase5.meanSilhouette)
        fprintf('Mean silhouette             : NaN (silhouette unavailable or failed)\n');
    else
        fprintf('Mean silhouette             : %.4f\n', phase5.meanSilhouette);
    end
    fprintf('Cluster sizes               : %s\n', mat2str(phase5.clusterSizes'));
    fprintf('Validation errors           : %d\n', height(phase5Errors));
    fprintf('Validation warnings         : %d\n', height(phase5Warnings));
    if ~isempty(phase5Errors)
        disp(phase5Errors(:, {'check_name','actual_value','expected_condition','notes'}));
    end
    if ~isempty(phase5Warnings)
        disp(phase5Warnings(:, {'check_name','actual_value','expected_condition','notes'}));
    end
    fprintf('Saved:\n');
    fprintf('  phase5_clustering_input_features.csv\n');
    fprintf('  phase5_clustering_k_evaluation.csv\n');
    fprintf('  phase5_sector_cluster_assignments.csv\n');
    fprintf('  phase5_cluster_summary.csv\n');
    fprintf('  phase5_cluster_scenario_crosstab.csv\n');
    fprintf('  phase5_cluster_trigger_support.csv\n');
    fprintf('  phase5_clustering_validation.csv\n');
    fprintf('  phase5_cluster_pca.png\n');
    fprintf('  phase5_cluster_scenario_heatmap.png\n');
    fprintf('  phase5_cluster_profiles.png\n');
    fprintf('\nPhase 5 is an unsupervised monitoring aid only. It is not COD training, action selection, oracle benchmarking, or closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase5_clustering_state_monitor', toc(phaseStart), 'completed', '');
else
    fprintf('\nPhase 5 Clustering-Based State Monitor\n');
    fprintf('--------------------------------------\n');
    fprintf('Skipped because cfg.enableUnsupervisedClustering = false.\n');
    fprintf('Supervised/KPI trigger metadata will be generated inside Phase 8A instead of using K-means clusters.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase5_clustering_state_monitor', toc(phaseStart), 'skipped', 'cfg.enableUnsupervisedClustering=false');
end
phaseStart = tic;

%% Phase 6A: COD dataset balancing and feature validation
fprintf('\nPhase 6A COD Dataset Preparation\n');
fprintf('--------------------------------\n');
phase6a = prepare_cod_balanced_dataset(cfg, topology);
phase6aErrors = phase6a.validationTable(strcmp(phase6a.validationTable.severity, 'error') & ...
    ~phase6a.validationTable.pass_flag, :);
phase6aWarnings = phase6a.validationTable(strcmp(phase6a.validationTable.severity, 'warning') & ...
    ~phase6a.validationTable.pass_flag, :);

fprintf('Original COD label distribution:\n');
disp(phase6a.originalDistribution);
fprintf('Balanced COD label distribution:\n');
disp(phase6a.labelDistribution);
fprintf('Input feature count        : %d\n', numel(phase6a.inputFeatures));
fprintf('Validation errors          : %d\n', height(phase6aErrors));
fprintf('Validation warnings        : %d\n', height(phase6aWarnings));
if ~isempty(phase6aErrors)
    disp(phase6aErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase6aWarnings)
    disp(phase6aWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('Saved:\n');
fprintf('  phase6a_cod_balanced_dataset.csv\n');
fprintf('  phase6a_cod_feature_list.csv\n');
fprintf('  phase6a_cod_label_distribution.csv\n');
fprintf('  phase6a_cod_dataset_validation.csv\n');
fprintf('  phase6a_cod_split_plan.csv\n');
fprintf('  phase6a_cod_label_distribution.png\n');
fprintf('\nPhase 6A prepares the COD dataset only. No COD classifier has been trained.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase6A_cod_dataset_preparation', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 6B: COD Random Forest classifier training and validation
fprintf('\nPhase 6B COD Random Forest Classifier\n');
fprintf('-------------------------------------\n');
phase6b = run_phase6b_cod_training(cfg);
phase6bErrors = phase6b.validationTable(strcmp(phase6b.validationTable.severity, 'error') & ...
    ~phase6b.validationTable.pass_flag, :);
phase6bWarnings = phase6b.validationTable(strcmp(phase6b.validationTable.severity, 'warning') & ...
    ~phase6b.validationTable.pass_flag, :);

fprintf('Training rows              : %d\n', phase6b.trainingRows);
fprintf('Validation rows            : %d\n', phase6b.validationRows);
fprintf('Test rows                  : %d\n', phase6b.testRows);
fprintf('External evaluation rows   : %d\n', phase6b.externalRows);
fprintf('Input feature count        : %d\n', numel(phase6b.inputFeatures));
fprintf('Test accuracy              : %.4f\n', phase6b.testSummary.accuracy);
fprintf('Test macro F1              : %.4f\n', phase6b.testSummary.macro_f1);
fprintf('Test outage recall         : %.4f\n', phase6b.testSummary.outage_recall);
fprintf('Test missed detection rate : %.4f\n', phase6b.testSummary.missed_detection_rate);
fprintf('External accuracy          : %.4f\n', phase6b.externalSummary.accuracy);
fprintf('External macro F1          : %.4f\n', phase6b.externalSummary.macro_f1);
fprintf('External outage recall     : %.4f\n', phase6b.externalSummary.outage_recall);
fprintf('External missed detection  : %.4f\n', phase6b.externalSummary.missed_detection_rate);
fprintf('Validation errors          : %d\n', height(phase6bErrors));
fprintf('Validation warnings        : %d\n', height(phase6bWarnings));
if ~isempty(phase6bErrors)
    disp(phase6bErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase6bWarnings)
    disp(phase6bWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('\nPhase 6B trains COD classification only. No compensation, action selection, oracle benchmarking, or closed-loop control has been implemented.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase6B_cod_random_forest', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 7A: Time-indexed TP/QP dataset generation and validation
fprintf('\nPhase 7A Temporal TP/QP Dataset\n');
fprintf('-------------------------------\n');
phase7 = generate_phase7_temporal_dataset(cfg, topology);
phase7Errors = phase7.validationTable(strcmp(phase7.validationTable.severity, 'error') & ...
    ~phase7.validationTable.pass_flag, :);
phase7Warnings = phase7.validationTable(strcmp(phase7.validationTable.severity, 'warning') & ...
    ~phase7.validationTable.pass_flag, :);

fprintf('Scenario types             : %d\n', numel(cfg.phase7ScenarioTypes));
fprintf('Time steps per scenario    : %d\n', cfg.phase7TimeStepsPerDay * cfg.phase7NumDays);
fprintf('Network temporal rows      : %d\n', height(phase7.networkTemporal));
fprintf('Sector temporal rows       : %d\n', height(phase7.sectorTemporal));
fprintf('Network lag feature rows   : %d\n', height(phase7.featureTable));
fprintf('Sector lag feature rows    : %d\n', height(phase7.sectorFeatureTable));
fprintf('Lag steps                  : %s\n', mat2str(cfg.phase7LagSteps));
fprintf('Prediction horizon steps   : %d\n', cfg.phase7PredictionHorizonSteps);
fprintf('Validation errors          : %d\n', height(phase7Errors));
fprintf('Validation warnings        : %d\n', height(phase7Warnings));
if ~isempty(phase7Errors)
    disp(phase7Errors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase7Warnings)
    disp(phase7Warnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('Saved:\n');
fprintf('  phase7a_temporal_sector_dataset.csv\n');
fprintf('  phase7a_temporal_network_dataset.csv\n');
fprintf('  phase7a_tp_qp_feature_table.csv\n');
fprintf('  phase7a_sector_tp_qp_feature_table.csv\n');
fprintf('  phase7a_sector_tp_qp_feature_dictionary.csv\n');
fprintf('  phase7a_temporal_summary.csv\n');
fprintf('  phase7a_dataset_validation.csv\n');
fprintf('  phase7a_traffic_qos_timeline.png\n');
fprintf('\nPhase 7A generates temporal TP/QP datasets only. No TP/QP prediction model has been trained.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase7A_temporal_tp_qp_dataset', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 7B: TP/QP regression training and walk-forward validation
fprintf('\nPhase 7B TP/QP Regression Training\n');
fprintf('----------------------------------\n');
phase7b = run_phase7b_tp_qp_training(cfg);
phase7bErrors = phase7b.validationTable(strcmp(phase7b.validationTable.severity, 'error') & ...
    ~phase7b.validationTable.pass_flag, :);
phase7bWarnings = phase7b.validationTable(strcmp(phase7b.validationTable.severity, 'warning') & ...
    ~phase7b.validationTable.pass_flag, :);

fprintf('Input rows                 : %d\n', phase7b.inputRows);
fprintf('Input feature count        : %d\n', numel(phase7b.inputFeatures));
fprintf('Train rows                 : %d\n', phase7b.trainRows);
fprintf('Validation rows            : %d\n', phase7b.validationRows);
fprintf('Test rows                  : %d\n', phase7b.testRows);
fprintf('\nTP target                  : %s\n', phase7b.tpTarget);
fprintf('TP test MAE                : %.4f\n', phase7b.tpTestSummary.mae);
fprintf('TP test RMSE               : %.4f\n', phase7b.tpTestSummary.rmse);
fprintf('TP test R2                 : %.4f\n', phase7b.tpTestSummary.r2);
fprintf('\nQP target                  : %s\n', phase7b.qpTarget);
fprintf('QP test MAE                : %.4f\n', phase7b.qpTestSummary.mae);
fprintf('QP test RMSE               : %.4f\n', phase7b.qpTestSummary.rmse);
fprintf('QP test R2                 : %.4f\n', phase7b.qpTestSummary.r2);
fprintf('\nValidation errors          : %d\n', height(phase7bErrors));
fprintf('Validation warnings        : %d\n', height(phase7bWarnings));
if ~isempty(phase7bErrors)
    disp(phase7bErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase7bWarnings)
    disp(phase7bWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('\nPhase 7B provides prediction models only. It does not perform action selection, oracle benchmarking, or closed-loop control.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase7B_tp_qp_regression', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 7C: TP/QP baseline comparison and diagnostics
fprintf('\nPhase 7C TP/QP Diagnostics\n');
fprintf('--------------------------\n');
phase7c = run_phase7c_tp_qp_diagnostics(cfg);
phase7cErrors = phase7c.validationTable(strcmp(phase7c.validationTable.severity, 'error') & ...
    ~phase7c.validationTable.pass_flag, :);
phase7cWarnings = phase7c.validationTable(strcmp(phase7c.validationTable.severity, 'warning') & ...
    ~phase7c.validationTable.pass_flag, :);

tpModelTest = phase7c.tpComparison(strcmp(phase7c.tpComparison.split, 'test') & ...
    strcmp(phase7c.tpComparison.scenario_name, 'ALL') & strcmp(phase7c.tpComparison.model_name, 'TP_model'), :);
tpPersistTest = phase7c.tpComparison(strcmp(phase7c.tpComparison.split, 'test') & ...
    strcmp(phase7c.tpComparison.scenario_name, 'ALL') & strcmp(phase7c.tpComparison.model_name, 'TP_persistence'), :);
qpModelTest = phase7c.qpComparison(strcmp(phase7c.qpComparison.split, 'test') & ...
    strcmp(phase7c.qpComparison.scenario_name, 'ALL') & strcmp(phase7c.qpComparison.model_name, 'QP_model'), :);
qpPersistTest = phase7c.qpComparison(strcmp(phase7c.qpComparison.split, 'test') & ...
    strcmp(phase7c.qpComparison.scenario_name, 'ALL') & strcmp(phase7c.qpComparison.model_name, 'QP_persistence'), :);
boundedTest = phase7c.qpBoundedMetrics(strcmp(phase7c.qpBoundedMetrics.split, 'test') & ...
    strcmp(phase7c.qpBoundedMetrics.scenario_name, 'ALL') & strcmp(phase7c.qpBoundedMetrics.model_name, 'QP_bounded'), :);
lowVarianceScenarios = phase7c.qpVarianceDiagnostic(phase7c.qpVarianceDiagnostic.target_std < 0.05, :);

fprintf('TP model vs persistence baseline:\n');
fprintf('  model RMSE       : %.4f, R2: %.4f\n', tpModelTest.RMSE, tpModelTest.R2);
fprintf('  persistence RMSE : %.4f, R2: %.4f\n', tpPersistTest.RMSE, tpPersistTest.R2);
fprintf('QP model vs persistence baseline:\n');
fprintf('  model RMSE       : %.4f, R2: %.4f\n', qpModelTest.RMSE, qpModelTest.R2);
fprintf('  persistence RMSE : %.4f, R2: %.4f\n', qpPersistTest.RMSE, qpPersistTest.R2);
fprintf('QP raw prediction range    : [%.4f, %.4f]\n', phase7c.rawQpPredictionRange(1), phase7c.rawQpPredictionRange(2));
fprintf('QP bounded metrics         : RMSE %.4f, R2 %.4f\n', boundedTest.RMSE, boundedTest.R2);
fprintf('QP low-variance scenarios  : %d\n', height(lowVarianceScenarios));
fprintf('Validation errors          : %d\n', height(phase7cErrors));
fprintf('Validation warnings        : %d\n', height(phase7cWarnings));
if ~isempty(phase7cErrors)
    disp(phase7cErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase7cWarnings)
    disp(phase7cWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('\nPhase 7C is diagnostic only. It does not implement action selection, oracle benchmarking, or closed-loop control.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase7C_tp_qp_diagnostics', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 8A: Candidate action table generation
fprintf('\nPhase 8A Candidate Action Generation\n');
fprintf('------------------------------------\n');
fprintf('Phase 8A defines candidate action spaces only. It does not select, apply, or evaluate actions.\n');
phase8a = run_phase8a_candidate_action_generation(cfg, topology);
phase8aErrors = phase8a.validationTable(strcmp(phase8a.validationTable.severity, 'error') & ...
    ~phase8a.validationTable.pass_flag, :);
phase8aWarnings = phase8a.validationTable(strcmp(phase8a.validationTable.severity, 'warning') & ...
    ~phase8a.validationTable.pass_flag, :);

fprintf('Candidate action rows      : %d\n', height(phase8a.candidateActions));
disp(phase8a.summaryTable);
fprintf('Validation errors          : %d\n', height(phase8aErrors));
fprintf('Validation warnings        : %d\n', height(phase8aWarnings));
if ~isempty(phase8aErrors)
    disp(phase8aErrors(:, {'check_name','actual_value','expected_condition','notes'}));
end
if ~isempty(phase8aWarnings)
    disp(phase8aWarnings(:, {'check_name','actual_value','expected_condition','notes'}));
end
fprintf('Saved:\n');
fprintf('  phase8a_candidate_actions.csv\n');
fprintf('  phase8a_candidate_action_summary.csv\n');
fprintf('  phase8a_candidate_action_validation.csv\n');
fprintf('  phase8a_neighbor_ranking.csv\n');
fprintf('  phase8a_candidate_target_diagnostics.csv\n');
fprintf('  phase8a_candidate_action_counts.png\n');
fprintf('\nPhase 8A defines candidate actions only. It does not evaluate rewards, select actions, train action-value models, or apply actions.\n');
phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase8A_candidate_action_generation', toc(phaseStart), 'completed', '');
phaseStart = tic;

%% Phase 8B: Counterfactual action evaluation
if isfield(cfg, 'enablePhase8B') && cfg.enablePhase8B
    fprintf('\nPhase 8B Counterfactual Action Evaluation\n');
    fprintf('-----------------------------------------\n');
    fprintf('Phase 8B is counterfactual evaluation only. It is NOT closed-loop SON control.\n');
    phase8b = run_phase8b_counterfactual_evaluation(cfg);
    fprintf('Counterfactual action rows : %d\n', height(phase8b.counterfactualTable));
    fprintf('Mean reward                : %.4f\n', mean(phase8b.counterfactualTable.reward, 'omitnan'));
    if isfield(phase8b, 'validationTable') && ~isempty(phase8b.validationTable)
        failed = phase8b.validationTable(~phase8b.validationTable.pass_flag, :);
        fprintf('Phase 8B validation failures: %d\n', height(failed));
        if ~isempty(failed)
            disp(failed(:, {'check_name','severity','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase8b_counterfactual_action_table.csv\n');
    fprintf('  phase8b_counterfactual_summary_by_module.csv\n');
    fprintf('  phase8b_counterfactual_summary_by_scenario.csv\n');
    fprintf('  phase8b_counterfactual_validation.csv\n');
    fprintf('\nPhase 8B evaluates candidate actions counterfactually only. It does not select actions, train action-value models, run oracle benchmarking, or update KPI(t+1). It is NOT closed-loop.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase8B_counterfactual_action_evaluation', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 8C: Safety-constrained oracle benchmark
if isfield(cfg, 'enablePhase8C') && cfg.enablePhase8C
    fprintf('\nPhase 8C Safety-Constrained Oracle Benchmark\n');
    fprintf('--------------------------------------------\n');
    phase8c = run_phase8c_safety_constrained_oracle(cfg);
    fprintf('Oracle groups               : %d\n', phase8c.numGroups);
    fprintf('Safe selected actions       : %d\n', phase8c.numSafeSelected);
    fprintf('Unsafe fallback selections  : %d\n', phase8c.numUnsafeFallback);
    fprintf('No-op selected actions      : %d\n', phase8c.numNoopSelected);
    fprintf('Mean oracle reward          : %.4f\n', phase8c.meanOracleReward);
    if isfield(phase8c, 'validationTable') && ~isempty(phase8c.validationTable)
        errs = phase8c.validationTable(strcmp(phase8c.validationTable.severity, 'error') & ...
            ~phase8c.validationTable.pass_flag, :);
        warns = phase8c.validationTable(strcmp(phase8c.validationTable.severity, 'warning') & ...
            ~phase8c.validationTable.pass_flag, :);
        fprintf('Validation errors           : %d\n', height(errs));
        fprintf('Validation warnings         : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase8c_oracle_selected_actions.csv\n');
    fprintf('  phase8c_oracle_summary_by_module.csv\n');
    fprintf('  phase8c_oracle_summary_by_scenario.csv\n');
    fprintf('  phase8c_oracle_safety_summary.csv\n');
    fprintf('  phase8c_oracle_validation.csv\n');
    fprintf('\nPhase 8C is an upper-bound oracle benchmark only. It does not train ML models, coordinate modules, apply actions, or produce KPI(t+1). It is NOT closed-loop.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase8C_safety_constrained_oracle', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 9A: Action-Value ML Dataset Preparation
if isfield(cfg, 'enablePhase9A') && cfg.enablePhase9A
    fprintf('\nPhase 9A Action-Value Dataset Preparation\n');
    fprintf('-----------------------------------------\n');
    phase9a = prepare_phase9a_action_value_datasets(cfg);
    fprintf('Total action rows           : %d\n', phase9a.totalRows);
    fprintf('Safe candidate rows         : %d\n', phase9a.safeRows);
    fprintf('Unsafe candidate rows       : %d\n', phase9a.unsafeRows);
    fprintf('Oracle-selected rows        : %d\n', phase9a.oracleSelectedRows);
    fprintf('Rows by module:\n');
    disp(phase9a.summary(:, {'module_name','total_rows','safe_rows','oracle_selected_rows', ...
        'no_op_rows','mean_reward'}));
    if isfield(phase9a, 'validationTable') && ~isempty(phase9a.validationTable)
        errs = phase9a.validationTable(strcmp(phase9a.validationTable.severity, 'error') & ...
            ~phase9a.validationTable.pass_flag, :);
        warns = phase9a.validationTable(strcmp(phase9a.validationTable.severity, 'warning') & ...
            ~phase9a.validationTable.pass_flag, :);
        fprintf('Validation errors           : %d\n', height(errs));
        fprintf('Validation warnings         : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase9a_action_value_dataset_all.csv\n');
    fprintf('  phase9a_action_value_dataset_coc.csv\n');
    fprintf('  phase9a_action_value_dataset_lb.csv\n');
    fprintf('  phase9a_action_value_dataset_es.csv\n');
    fprintf('  phase9a_action_value_dataset_mro.csv\n');
    fprintf('  phase9a_action_value_feature_dictionary.csv\n');
    fprintf('  phase9a_action_value_leakage_audit.csv\n');
    fprintf('  phase9a_action_value_dataset_summary.csv\n');
    fprintf('  phase9a_action_value_validation.csv\n');
    fprintf('\nPhase 9A prepares leakage-controlled action-value datasets only. It does not train ML, coordinate modules, apply actions, or generate KPI(t+1). It is NOT closed-loop.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase9A_action_value_dataset_preparation', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 9B: Module-Specific Action-Value Regression
if isfield(cfg, 'enablePhase9B') && cfg.enablePhase9B
    fprintf('\nPhase 9B Action-Value Regression\n');
    fprintf('--------------------------------\n');
    phase9b = run_phase9b_action_value_training(cfg);
    moduleKeys = fieldnames(phase9b.moduleResults);
    for k = 1:numel(moduleKeys)
        m = phase9b.moduleResults.(moduleKeys{k});
        testMetric = @(name) lookup_phase9b_metric(phase9b.metrics, m.module, 'test', 'ALL', name);
        fprintf('Module: %s\n', m.module);
        fprintf('  train rows         : %d\n', m.trainRows);
        fprintf('  test rows          : %d\n', m.testRows);
        fprintf('  test MAE           : %.4f\n', testMetric('MAE'));
        fprintf('  test RMSE          : %.4f\n', testMetric('RMSE'));
        fprintf('  test R2            : %.4f\n', testMetric('R2'));
        fprintf('  top-1 oracle match : %.4f\n', testMetric('top1_oracle_match'));
        fprintf('  top-2 oracle match : %.4f\n', testMetric('top2_oracle_match'));
        fprintf('  mean oracle regret : %.4f\n', testMetric('mean_oracle_regret'));
        fprintf('  unsafe top-1 count : %d\n', round(testMetric('test_groups_with_unsafe_top1')));
    end
    if isfield(phase9b, 'validationTable') && ~isempty(phase9b.validationTable)
        errs = phase9b.validationTable(strcmp(phase9b.validationTable.severity, 'error') & ...
            ~phase9b.validationTable.pass_flag, :);
        warns = phase9b.validationTable(strcmp(phase9b.validationTable.severity, 'warning') & ...
            ~phase9b.validationTable.pass_flag, :);
        fprintf('Validation errors           : %d\n', height(errs));
        fprintf('Validation warnings         : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase9b_action_value_metrics.csv\n');
    fprintf('  phase9b_action_value_predictions.csv\n');
    fprintf('  phase9b_action_value_feature_importance.csv\n');
    fprintf('  phase9b_action_value_split_summary.csv\n');
    fprintf('  phase9b_action_selection_preview.csv\n');
    fprintf('  phase9b_oracle_regret_preview.csv\n');
    fprintf('  phase9b_action_value_validation.csv\n');
    fprintf('\nPhase 9B trains offline action-value regressors only. It does not apply actions, coordinate modules, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase9B_action_value_regression', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Supervised Action-Value Model Comparison
if isfield(cfg, 'enableSupervisedActionValueComparison') && cfg.enableSupervisedActionValueComparison
    fprintf('\nSupervised Action-Value Model Comparison\n');
    fprintf('----------------------------------------\n');
    supervisedComparison = run_supervised_action_value_model_comparison(cfg);
    fprintf('Compared models             : %s\n', strjoin(cellstr(unique(string(supervisedComparison.metrics.model_name))), ', '));
    fprintf('Modules compared            : %s\n', strjoin(cellstr(unique(string(supervisedComparison.metrics.module_name))), ', '));
    fprintf('Prediction rows             : %d\n', height(supervisedComparison.predictions));
    failed = supervisedComparison.validationTable(~supervisedComparison.validationTable.pass_flag, :);
    errors = failed(strcmp(failed.severity, 'error'), :);
    warnings = failed(strcmp(failed.severity, 'warning'), :);
    fprintf('Validation errors           : %d\n', height(errors));
    fprintf('Validation warnings         : %d\n', height(warnings));
    if ~isempty(errors)
        disp(errors(:, {'check_name','actual_value','expected_condition','notes'}));
    end
    if ~isempty(warnings)
        disp(warnings(:, {'check_name','actual_value','expected_condition','notes'}));
    end
    fprintf('Saved:\n');
    fprintf('  supervised_action_value_model_metrics.csv\n');
    fprintf('  supervised_action_value_model_predictions.csv\n');
    fprintf('  supervised_action_value_model_split_summary.csv\n');
    fprintf('  supervised_action_value_model_validation.csv\n');
    fprintf('  supervised_action_value_actual_vs_predicted_test.png\n');
    fprintf('\nThis comparison is supervised regression only: Linear/Ridge, Random Forest/Bagged Trees, and LSBoost use the same group-aware train/test split and the same reward target.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Supervised_action_value_model_comparison', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 10A: Safety-Enforced ML Action Selection
if isfield(cfg, 'enablePhase10A') && cfg.enablePhase10A
    fprintf('\nPhase 10A Safety-Enforced ML Action Selection\n');
    fprintf('---------------------------------------------\n');
    phase10a = run_phase10a_safety_enforced_selection(cfg);
    fprintf('Decision groups                  : %d\n', phase10a.numGroups);
    fprintf('Raw unsafe top-1 selections      : %d\n', phase10a.numRawUnsafeTop1);
    fprintf('Safety-enforced unsafe selections: %d\n', phase10a.numSafeUnsafeSelected);
    fprintf('Safety filter changed actions    : %d\n', phase10a.numFilterChanged);
    fprintf('Fallback selections              : %d\n', phase10a.numFallback);
    fprintf('No-op selections                 : %d\n', phase10a.numNoopSelected);
    fprintf('Raw mean regret                  : %.4f\n', phase10a.rawMeanRegret);
    fprintf('Safety-enforced mean regret      : %.4f\n', phase10a.safetyMeanRegret);
    fprintf('Safe top-1 oracle match          : %.4f\n', phase10a.safeTop1Rate);
    if isfield(phase10a, 'validationTable') && ~isempty(phase10a.validationTable)
        errs = phase10a.validationTable(strcmp(phase10a.validationTable.severity, 'error') & ...
            ~phase10a.validationTable.pass_flag, :);
        warns = phase10a.validationTable(strcmp(phase10a.validationTable.severity, 'warning') & ...
            ~phase10a.validationTable.pass_flag, :);
        fprintf('Validation errors                : %d\n', height(errs));
        fprintf('Validation warnings              : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase10a_safety_enforced_selected_actions.csv\n');
    fprintf('  phase10a_raw_vs_safe_selection_comparison.csv\n');
    fprintf('  phase10a_safety_enforced_regret.csv\n');
    fprintf('  phase10a_summary_by_module.csv\n');
    fprintf('  phase10a_summary_by_scenario.csv\n');
    fprintf('  phase10a_safety_filter_summary.csv\n');
    fprintf('  phase10a_safety_enforced_validation.csv\n');
    fprintf('\nPhase 10A applies a safety filter on top of offline ML predictions only. It does not coordinate modules, apply actions, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase10A_safety_enforced_selection', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 11A: Decision Coordinator Preparation and Conflict Diagnostics
if isfield(cfg, 'enablePhase11A') && cfg.enablePhase11A
    fprintf('\nPhase 11A Decision Coordinator Preparation\n');
    fprintf('------------------------------------------\n');
    phase11a = run_phase11a_decision_coordinator_preparation(cfg);
    fprintf('Coordinator input actions       : %d\n', phase11a.numInputs);
    fprintf('Detected conflicts              : %d\n', phase11a.numConflicts);
    fprintf('Accepted candidate actions      : %d\n', phase11a.numAccepted);
    fprintf('Rejected actions                : %d\n', phase11a.numRejected);
    fprintf('Safety rejections               : %d\n', phase11a.numSafetyRejections);
    fprintf('Priority rejections             : %d\n', phase11a.numPriorityRejections);
    fprintf('Fallback unsafe actions retained: %d\n', phase11a.numFallbackUnsafeRetained);
    if isfield(phase11a, 'validationTable') && ~isempty(phase11a.validationTable)
        errs = phase11a.validationTable(strcmp(phase11a.validationTable.severity, 'error') & ...
            ~phase11a.validationTable.pass_flag, :);
        warns = phase11a.validationTable(strcmp(phase11a.validationTable.severity, 'warning') & ...
            ~phase11a.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase11a_coordinator_input_actions.csv\n');
    fprintf('  phase11a_conflict_detection_log.csv\n');
    fprintf('  phase11a_conflict_resolution_log.csv\n');
    fprintf('  phase11a_coordinator_candidate_actions.csv\n');
    fprintf('  phase11a_rejected_action_log.csv\n');
    fprintf('  phase11a_summary_by_module.csv\n');
    fprintf('  phase11a_summary_by_scenario.csv\n');
    fprintf('  phase11a_coordination_validation.csv\n');
    fprintf('\nPhase 11A prepares coordinator outputs and conflict diagnostics only. It does not apply actions, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase11A_coordinator_preparation', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 11B: Final Coordinator Selection Table
if isfield(cfg, 'enablePhase11B') && cfg.enablePhase11B
    fprintf('\nPhase 11B Final Coordinator Selection\n');
    fprintf('-------------------------------------\n');
    phase11b = run_phase11b_final_coordinator_selection(cfg);
    fprintf('Final decision rows                  : %d\n', phase11b.numFinalDecisions);
    fprintf('Executable safe actions              : %d\n', phase11b.numExecutable);
    fprintf('Final no-op decisions                : %d\n', phase11b.numNoop);
    fprintf('Rejected actions                     : %d\n', phase11b.numRejected);
    fprintf('Unresolved unsafe fallback diagnostics: %d\n', phase11b.numUnresolved);
    if isfield(phase11b, 'validationTable') && ~isempty(phase11b.validationTable)
        errs = phase11b.validationTable(strcmp(phase11b.validationTable.severity, 'error') & ...
            ~phase11b.validationTable.pass_flag, :);
        warns = phase11b.validationTable(strcmp(phase11b.validationTable.severity, 'warning') & ...
            ~phase11b.validationTable.pass_flag, :);
        fprintf('Validation errors                    : %d\n', height(errs));
        fprintf('Validation warnings                  : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase11b_final_coordinator_decisions.csv\n');
    fprintf('  phase11b_final_executable_actions.csv\n');
    fprintf('  phase11b_unresolved_fallback_diagnostics.csv\n');
    fprintf('  phase11b_final_rejected_actions.csv\n');
    fprintf('  phase11b_summary_by_module.csv\n');
    fprintf('  phase11b_summary_by_scenario.csv\n');
    fprintf('  phase11b_final_coordination_validation.csv\n');
    fprintf('\nPhase 11B produces the final coordinator decision table only. It does not apply actions, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase11B_final_coordinator_selection', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 12A: One-Step Action Application Feasibility Audit
if isfield(cfg, 'enablePhase12A') && cfg.enablePhase12A
    fprintf('\nPhase 12A Action Application Feasibility Audit\n');
    fprintf('----------------------------------------------\n');
    phase12a = run_phase12a_action_application_feasibility(cfg);
    fprintf('Executable actions reviewed     : %d\n', phase12a.numExecutableReviewed);
    fprintf('Implementable now               : %d\n', phase12a.numImplementableNow);
    fprintf('Partially implementable         : %d\n', phase12a.numPartial);
    fprintf('Not implemented in simulator    : %d\n', phase12a.numNotImplemented);
    fprintf('No-parameter-change actions     : %d\n', phase12a.numNoChange);
    fprintf('Skipped non-executable rows     : %d\n', phase12a.numSkippedNonExecutable);
    if isfield(phase12a, 'validationTable') && ~isempty(phase12a.validationTable)
        errs = phase12a.validationTable(strcmp(phase12a.validationTable.severity, 'error') & ...
            ~phase12a.validationTable.pass_flag, :);
        warns = phase12a.validationTable(strcmp(phase12a.validationTable.severity, 'warning') & ...
            ~phase12a.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase12a_action_application_feasibility.csv\n');
    fprintf('  phase12a_action_parameter_mapping.csv\n');
    fprintf('  phase12a_implementability_summary_by_module.csv\n');
    fprintf('  phase12a_implementability_summary_by_action_type.csv\n');
    fprintf('  phase12a_skipped_non_executable_actions.csv\n');
    fprintf('  phase12a_feasibility_validation.csv\n');
    fprintf('\nPhase 12A is a dry-run feasibility audit only. It does not apply actions, mutate simulator state, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase12A_action_application_feasibility', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 12B: Simulator Action-State Extension
if isfield(cfg, 'enablePhase12B') && cfg.enablePhase12B
    fprintf('\nPhase 12B Simulator Action-State Extension\n');
    fprintf('------------------------------------------\n');
    phase12b = run_phase12b_simulator_action_state_extension(cfg, topology);
    fprintf('CIO state added                 : %d\n', double(phase12b.cioTest.columnExists));
    fprintf('CIO zero-bias assoc unchanged   : %d\n', double(phase12b.cioTest.zeroBiasAssocSame));
    fprintf('CIO bias test passed            : %d (%d UEs changed serving)\n', ...
        double(phase12b.cioTest.numChangedServing >= 1), phase12b.cioTest.numChangedServing);
    fprintf('Reference power offset test     : %d (mean delta %.4f dB)\n', ...
        double(phase12b.prsTest.deltaWithinTol), phase12b.prsTest.meanDelta);
    fprintf('Tilt support status             : %s (max |delta RSRP| %.4f dB)\n', ...
        phase12b.tiltTest.status, phase12b.tiltTest.maxAbsDiff);
    fprintf('State clone integrity           : %d\n', ...
        double(phase12b.cloneTest.originalStillEqual && phase12b.cloneTest.clonedHasDelta));
    fprintf('Actions newly implementable     : %d\n', phase12b.numNewlyImplementable);
    if isfield(phase12b, 'validationTable') && ~isempty(phase12b.validationTable)
        errs = phase12b.validationTable(strcmp(phase12b.validationTable.severity, 'error') & ...
            ~phase12b.validationTable.pass_flag, :);
        warns = phase12b.validationTable(strcmp(phase12b.validationTable.severity, 'warning') & ...
            ~phase12b.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase12b_action_state_support_audit.csv\n');
    fprintf('  phase12b_cio_bias_association_test.csv\n');
    fprintf('  phase12b_reference_power_offset_test.csv\n');
    fprintf('  phase12b_tilt_usage_test.csv\n');
    fprintf('  phase12b_state_clone_integrity_test.csv\n');
    fprintf('  phase12b_action_state_validation.csv\n');
    fprintf('\nPhase 12B adds simulator action-state support only. CIO biases association, not physical RSRP/SINR. No actions applied. No KPI(t+1). NOT closed-loop.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase12B_simulator_action_state_extension', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 12C: Post-Extension Feasibility Refresh and KPI(t+1) Eligible Action Set
if isfield(cfg, 'enablePhase12C') && cfg.enablePhase12C
    fprintf('\nPhase 12C Post-Extension Feasibility Refresh\n');
    fprintf('--------------------------------------------\n');
    phase12c = run_phase12c_post_extension_feasibility_refresh(cfg);
    fprintf('Executable actions reviewed     : %d\n', phase12c.numReviewed);
    fprintf('KPI-update eligible actions     : %d\n', phase12c.numEligible);
    fprintf('Excluded actions                : %d\n', phase12c.numExcluded);
    if ~isempty(phase12c.eligibleModules)
        fprintf('Eligible modules                : %s\n', strjoin(cellstr(phase12c.eligibleModules), ', '));
    else
        fprintf('Eligible modules                : (none)\n');
    end
    if ~isempty(phase12c.eligibleActionTypes)
        fprintf('Eligible action types           : %s\n', strjoin(cellstr(phase12c.eligibleActionTypes), ', '));
    else
        fprintf('Eligible action types           : (none)\n');
    end
    if isfield(phase12c, 'validationTable') && ~isempty(phase12c.validationTable)
        errs = phase12c.validationTable(strcmp(phase12c.validationTable.severity, 'error') & ...
            ~phase12c.validationTable.pass_flag, :);
        warns = phase12c.validationTable(strcmp(phase12c.validationTable.severity, 'warning') & ...
            ~phase12c.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase12c_post_extension_feasibility.csv\n');
    fprintf('  phase12c_kpi_update_eligible_actions.csv\n');
    fprintf('  phase12c_kpi_update_excluded_actions.csv\n');
    fprintf('  phase12c_eligible_summary_by_module.csv\n');
    fprintf('  phase12c_eligible_summary_by_action_type.csv\n');
    fprintf('  phase12c_kpi_eligible_validation.csv\n');
    fprintf('\nPhase 12C produces the KPI(t+1)-eligible action set only. It does not apply actions, recompute KPI, generate KPI(t+1), or implement closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase12C_post_extension_feasibility_refresh', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 12D: One-Step KPI(t)->KPI(t+1) Evaluation for Eligible Actions
if isfield(cfg, 'enablePhase12D') && cfg.enablePhase12D
    fprintf('\nPhase 12D One-Step KPI(t)->KPI(t+1) Evaluation\n');
    fprintf('----------------------------------------------\n');
    phase12d = run_phase12d_one_step_kpi_update(cfg, topology);
    fprintf('Eligible actions loaded         : %d\n', phase12d.numEligibleLoaded);
    fprintf('Applied actions                 : %d\n', phase12d.numApplied);
    fprintf('Skipped actions                 : %d\n', phase12d.numSkipped);
    fprintf('Evaluated groups                : %d\n', phase12d.numEvaluatedGroups);
    fprintf('Mean delta attach rate          : %.4f\n', phase12d.meanDeltaAttachRate);
    fprintf('Mean delta RSRP (dB)            : %.4f\n', phase12d.meanDeltaRSRP);
    fprintf('Mean delta SINR (dB)            : %.4f\n', phase12d.meanDeltaSINR);
    fprintf('Mean delta sector load          : %.4f\n', phase12d.meanDeltaLoad);
    fprintf('Mean delta QoS                  : %.4f\n', phase12d.meanDeltaQoS);
    if isfield(phase12d, 'validationTable') && ~isempty(phase12d.validationTable)
        errs = phase12d.validationTable(strcmp(phase12d.validationTable.severity, 'error') & ...
            ~phase12d.validationTable.pass_flag, :);
        warns = phase12d.validationTable(strcmp(phase12d.validationTable.severity, 'warning') & ...
            ~phase12d.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase12d_one_step_kpi_update_results.csv\n');
    fprintf('  phase12d_pre_post_sector_kpis.csv\n');
    fprintf('  phase12d_pre_post_network_kpis.csv\n');
    fprintf('  phase12d_action_application_log.csv\n');
    fprintf('  phase12d_skipped_actions_log.csv\n');
    fprintf('  phase12d_summary_by_module.csv\n');
    fprintf('  phase12d_summary_by_scenario.csv\n');
    fprintf('  phase12d_one_step_validation.csv\n');
    fprintf('\nPhase 12D is a one-step cloned-state KPI(t+1) evaluation for eligible COC/OH and LB/MLB actions only. It does not apply ES sleep or HO/MRO actions, does not iterate, and does NOT implement full closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase12D_one_step_kpi_update', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 12E: One-Step KPI Validation and Final Comparison
if isfield(cfg, 'enablePhase12E') && cfg.enablePhase12E
    fprintf('\nPhase 12E One-Step KPI Validation and Final Comparison\n');
    fprintf('------------------------------------------------------\n');
    phase12e = run_phase12e_one_step_result_validation(cfg, topology);
    fprintf('AI/ML evaluated rows            : %d\n', phase12e.numAiEvaluated);
    fprintf('Oracle-comparable rows          : %d\n', phase12e.numOracleComparable);
    fprintf('Oracle-not-comparable rows      : %d\n', phase12e.numOracleNotComparable);
    fprintf('Mean AI/ML delta attach         : %.4f\n', phase12e.meanAiDeltaAttach);
    fprintf('Mean AI/ML delta RSRP (dB)      : %.4f\n', phase12e.meanAiDeltaRsrp);
    fprintf('Mean AI/ML delta SINR (dB)      : %.4f\n', phase12e.meanAiDeltaSinr);
    fprintf('Mean AI/ML delta load           : %.4f\n', phase12e.meanAiDeltaLoad);
    fprintf('Mean AI/ML delta QoS            : %.4f\n', phase12e.meanAiDeltaQos);
    fprintf('Mean KPI gap to oracle (QoS)    : %.4f\n', phase12e.meanQosGapToOracle);
    fprintf('Tradeoff rows                   : %d\n', phase12e.numTradeoffRows);
    if isfield(phase12e, 'validationTable') && ~isempty(phase12e.validationTable)
        errs = phase12e.validationTable(strcmp(phase12e.validationTable.severity, 'error') & ...
            ~phase12e.validationTable.pass_flag, :);
        warns = phase12e.validationTable(strcmp(phase12e.validationTable.severity, 'warning') & ...
            ~phase12e.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('Saved:\n');
    fprintf('  phase12e_baseline_ai_kpi_comparison.csv\n');
    fprintf('  phase12e_baseline_ai_oracle_comparison.csv\n');
    fprintf('  phase12e_oracle_comparable_action_log.csv\n');
    fprintf('  phase12e_kpi_outcome_classification.csv\n');
    fprintf('  phase12e_summary_by_module.csv\n');
    fprintf('  phase12e_summary_by_scenario.csv\n');
    fprintf('  phase12e_tradeoff_summary.csv\n');
    fprintf('  phase12e_limitations_table.csv\n');
    fprintf('  phase12e_final_comparison_validation.csv\n');
    fprintf('\nPhase 12E is offline validation + comparison only. Oracle KPI is computed only for implementable oracle actions. NOT closed-loop control.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase12E_final_comparison', toc(phaseStart), 'completed', '');
    phaseStart = tic;
end

%% Phase 13: Final Thesis Result Package
if isfield(cfg, 'enablePhase13') && cfg.enablePhase13
    fprintf('\nPhase 13 Final Thesis Result Package\n');
    fprintf('------------------------------------\n');
    phase13 = run_phase13_final_result_package(cfg);
    fprintf('Package folder                  : %s\n', phase13.packageDir);
    fprintf('Final summary files (.md)       : %d\n', phase13.numMdFiles);
    fprintf('Final tables (.csv)             : %d\n', phase13.numCsvFiles);
    fprintf('Before/after KPI files          : phase13 wrote 3 CSVs + 1 markdown + 1 figure\n');
    fprintf('Figure manifest entries         : %d (available: %d)\n', ...
        phase13.numFigureManifestEntries, phase13.numAvailableFigures);
    fprintf('Uses corrected post-fix values  : %d\n', double(phase13.usesCorrectedPostFixValues));
    fprintf('Applied action count used       : %d\n', phase13.appliedActionCount);
    if isfield(phase13, 'validationTable') && ~isempty(phase13.validationTable)
        errs = phase13.validationTable(strcmp(phase13.validationTable.severity, 'error') & ...
            ~phase13.validationTable.pass_flag, :);
        warns = phase13.validationTable(strcmp(phase13.validationTable.severity, 'warning') & ...
            ~phase13.validationTable.pass_flag, :);
        fprintf('Validation errors               : %d\n', height(errs));
        fprintf('Validation warnings             : %d\n', height(warns));
        if ~isempty(errs)
            disp(errs(:, {'check_name','actual_value','expected_condition','notes'}));
        end
        if ~isempty(warns)
            disp(warns(:, {'check_name','actual_value','expected_condition','notes'}));
        end
    end
    fprintf('\nPhase 13 packages the completed simulation outputs into thesis-ready summaries. It does NOT train models, apply actions, or extend closed-loop behavior.\n');
    phaseTimingTable = append_phase_timing(phaseTimingTable, cfg, 'Phase13_final_thesis_result_package', toc(phaseStart), 'completed', '');
end
write_run_dependency_summary(cfg);

function write_run_log(logFile, cfg, linkBudget, summaryTable)
fid = fopen(logFile, 'w');
if fid < 0
    warning('Unable to write run log: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Phase 1B LTE RF validation run\n');
fprintf(fid, 'Phase: %s\n', cfg.rfPhaseName);
fprintf(fid, 'Topology: 7 sites / 21 sectors\n');
fprintf(fid, 'fc_GHz: %.3f\n', cfg.fc_GHz);
fprintf(fid, 'pathlossModel: %s\n', cfg.pathlossModel);
fprintf(fid, 'MAPL_dB: %.3f\n', linkBudget.MAPL_dB);
fprintf(fid, 'plannedRadius_m: %.3f\n', cfg.plannedRadius_m);
fprintf(fid, 'ISD_m: %.3f\n', cfg.ISD_m);
fprintf(fid, 'numUE: %d\n', cfg.numUE);
fprintf(fid, 'attachRate: %.6f\n', summaryTable.attachRate);
fprintf(fid, 'plannedCoverageRatio: %.6f\n', summaryTable.plannedCoverageRatio);
fprintf(fid, 'plannedSINRThresholdRatio: %.6f\n', summaryTable.plannedSINRThresholdRatio);
end

function write_phase2_log(logFile, cfg, networkKpiTable)
fid = fopen(logFile, 'w');
if fid < 0
    warning('Unable to write Phase 2 run log: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Phase 2 traffic and KPI simulation run\n');
fprintf(fid, 'Phase: %s\n', cfg.phaseName);
fprintf(fid, 'Traffic mode: %s\n', cfg.trafficMode);
fprintf(fid, 'Active UEs: %d\n', networkKpiTable.active_ues);
fprintf(fid, 'Total offered traffic Mbps: %.6f\n', networkKpiTable.total_offered_traffic_Mbps);
fprintf(fid, 'Total served traffic Mbps: %.6f\n', networkKpiTable.total_served_traffic_Mbps);
fprintf(fid, 'Total unserved traffic Mbps: %.6f\n', networkKpiTable.total_unserved_traffic_Mbps);
fprintf(fid, 'QoS satisfaction ratio: %.6f\n', networkKpiTable.qos_satisfaction_ratio);
fprintf(fid, 'Overloaded sector count: %d\n', networkKpiTable.overloaded_sector_count);
fprintf(fid, 'Mean sector load: %.6f\n', networkKpiTable.mean_sector_load);
fprintf(fid, 'Max sector load: %.6f\n', networkKpiTable.max_sector_load);
fprintf(fid, 'Jain fairness index: %.6f\n', networkKpiTable.jain_fairness_index);
end

function write_phase2c_log(logFile, calibrationSummary)
fid = fopen(logFile, 'w');
if fid < 0
    warning('Unable to write Phase 2C calibration log: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Phase 2C traffic calibration refinement summary\n');
for i = 1:height(calibrationSummary)
    fprintf(fid, '\nMode: %s\n', calibrationSummary.traffic_mode{i});
    fprintf(fid, 'Active user ratio: %.3f\n', calibrationSummary.active_user_ratio(i));
    fprintf(fid, 'Active UEs: %d\n', calibrationSummary.active_ues(i));
    fprintf(fid, 'Total offered Mbps: %.6f\n', calibrationSummary.total_offered_traffic_Mbps(i));
    fprintf(fid, 'Total served Mbps: %.6f\n', calibrationSummary.total_served_traffic_Mbps(i));
    fprintf(fid, 'QoS satisfaction ratio: %.6f\n', calibrationSummary.qos_satisfaction_ratio(i));
    fprintf(fid, 'Overloaded sectors: %d\n', calibrationSummary.overloaded_sector_count(i));
    fprintf(fid, 'Mean sector load: %.6f\n', calibrationSummary.mean_sector_load(i));
    fprintf(fid, 'Max sector load: %.6f\n', calibrationSummary.max_sector_load(i));
end
end

function write_phase3_log(logFile, scenarioSummary)
fid = fopen(logFile, 'w');
if fid < 0
    warning('Unable to write Phase 3 scenario log: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Phase 3 scenario generation summary\n');
for i = 1:height(scenarioSummary)
    fprintf(fid, '\nScenario %d: %s\n', scenarioSummary.scenario_id(i), scenarioSummary.scenario_name{i});
    fprintf(fid, 'Traffic mode: %s\n', scenarioSummary.traffic_mode{i});
    fprintf(fid, 'Impaired sector: %d\n', scenarioSummary.impaired_sector_id(i));
    fprintf(fid, 'Attach rate: %.6f\n', scenarioSummary.attach_rate(i));
    fprintf(fid, 'QoS satisfaction active: %.6f\n', scenarioSummary.qos_satisfaction_ratio_active(i));
    fprintf(fid, 'Overloaded sectors: %d\n', scenarioSummary.overloaded_sector_count(i));
    fprintf(fid, 'Mean sector load: %.6f\n', scenarioSummary.mean_sector_load(i));
    fprintf(fid, 'Boundary UE ratio: %.6f\n', scenarioSummary.boundary_ue_ratio(i));
    fprintf(fid, 'ES candidate sector count: %d\n', scenarioSummary.es_candidate_sector_count(i));
end
end

function v = lookup_phase9b_metric(metricsTable, moduleName, splitName, scenarioName, metricName)
mask = strcmp(metricsTable.module_name, moduleName) & ...
    strcmp(metricsTable.split, splitName) & ...
    strcmp(metricsTable.scenario_name, scenarioName) & ...
    strcmp(metricsTable.metric_name, metricName);
if ~any(mask)
    v = NaN;
else
    v = metricsTable.metric_value(find(mask, 1, 'first'));
end
end

function write_phase4_log(logFile, cfg, sectorStateDataset, networkStateDataset, validationTable)
fid = fopen(logFile, 'w');
if fid < 0
    warning('Unable to write Phase 4 dataset log: %s', logFile);
    return;
end

cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Phase 4 multi-scenario dataset summary\n');
fprintf(fid, 'Scenario types: %d\n', numel(cfg.phase4ScenarioTypes));
fprintf(fid, 'Realizations per scenario: %d\n', cfg.phase4NumRealizationsPerScenario);
fprintf(fid, 'Network-state rows: %d\n', height(networkStateDataset));
fprintf(fid, 'Sector-state rows: %d\n', height(sectorStateDataset));
fprintf(fid, 'Validation passed checks: %d\n', sum(validationTable.pass_flag));
fprintf(fid, 'Validation failed checks: %d\n', height(validationTable) - sum(validationTable.pass_flag));
end
