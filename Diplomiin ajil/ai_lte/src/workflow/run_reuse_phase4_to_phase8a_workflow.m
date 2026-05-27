function timingTable = run_reuse_phase4_to_phase8a_workflow(cfg, topology)
%RUN_REUSE_PHASE4_TO_PHASE8A_WORKFLOW Reuse Phase 4 and rebuild downstream Phase 8A/B inputs.

timingTable = table();
fprintf('\nRun mode: reuse_phase4_to_phase8a\n');

sectorFile = fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv');
networkFile = fullfile(cfg.tablesDir, 'phase4_network_state_dataset.csv');
if ~isfile(sectorFile) || ~isfile(networkFile)
    error('Phase 4 dataset files are required. Run with cfg.runMode = phase4_only first.');
end

sectorStateDataset = readtable(sectorFile);
networkStateDataset = readtable(networkFile);

t = tic;
[clusteringFeatures, codFeatures, tpqpFeatures, featureDictionary, featureSets] = ...
    prepare_phase4_ml_feature_tables(cfg, sectorStateDataset, networkStateDataset);
leakageAudit = audit_feature_leakage(cfg, clusteringFeatures, codFeatures, tpqpFeatures, featureSets);
phase4bValidationTable = validate_phase4_ml_features(cfg, clusteringFeatures, ...
    codFeatures, tpqpFeatures, featureDictionary, leakageAudit, featureSets);
timingTable = append_phase_timing(timingTable, cfg, 'Phase4B_feature_preparation', toc(t), 'completed', '');
print_failed('Phase 4B', phase4bValidationTable);

if ~isfield(cfg, 'enableUnsupervisedClustering') || cfg.enableUnsupervisedClustering
    t = tic;
    phase5 = run_phase5_clustering_state_monitor(cfg);
    timingTable = append_phase_timing(timingTable, cfg, 'Phase5_clustering_state_monitor', toc(t), 'completed', '');
    print_failed('Phase 5', phase5.validationTable);
else
    timingTable = append_phase_timing(timingTable, cfg, 'Phase5_clustering_state_monitor', 0, 'skipped', ...
        'cfg.enableUnsupervisedClustering=false');
end

t = tic;
phase6a = prepare_cod_balanced_dataset(cfg, topology);
timingTable = append_phase_timing(timingTable, cfg, 'Phase6A_cod_dataset_preparation', toc(t), 'completed', '');
print_failed('Phase 6A', phase6a.validationTable);

t = tic;
phase6b = run_phase6b_cod_training(cfg);
timingTable = append_phase_timing(timingTable, cfg, 'Phase6B_cod_random_forest', toc(t), 'completed', '');
print_failed('Phase 6B', phase6b.validationTable);

t = tic;
phase8a = run_phase8a_candidate_action_generation(cfg, topology);
timingTable = append_phase_timing(timingTable, cfg, 'Phase8A_candidate_action_generation', toc(t), 'completed', '');
print_failed('Phase 8A', phase8a.validationTable);
fprintf('Phase 8A candidate rows    : %d\n', height(phase8a.candidateActions));

if isfield(cfg, 'enablePhase8B') && cfg.enablePhase8B
    t = tic;
    phase8b = run_phase8b_counterfactual_evaluation(cfg);
    timingTable = append_phase_timing(timingTable, cfg, 'Phase8B_counterfactual_action_evaluation', toc(t), 'completed', '');
    fprintf('Phase 8B evaluated rows    : %d\n', height(phase8b.counterfactualTable));
    if isfield(phase8b, 'validationTable')
        print_failed('Phase 8B', phase8b.validationTable);
    end
end

if isfield(cfg, 'enablePhase8C') && cfg.enablePhase8C
    t = tic;
    phase8c = run_phase8c_safety_constrained_oracle(cfg);
    timingTable = append_phase_timing(timingTable, cfg, 'Phase8C_safety_constrained_oracle', toc(t), 'completed', '');
    fprintf('Phase 8C oracle groups     : %d (safe=%d, unsafe_fallback=%d, noop=%d, mean=%.4f)\n', ...
        phase8c.numGroups, phase8c.numSafeSelected, phase8c.numUnsafeFallback, ...
        phase8c.numNoopSelected, phase8c.meanOracleReward);
    if isfield(phase8c, 'validationTable')
        print_failed('Phase 8C', phase8c.validationTable);
    end
end
end

function print_failed(label, validationTable)
if isempty(validationTable)
    return;
end
failed = validationTable(~validationTable.pass_flag, :);
fprintf('%s validation failures     : %d\n', label, height(failed));
if ~isempty(failed)
    disp(failed(:, {'check_name','severity','actual_value','expected_condition','notes'}));
end
end
