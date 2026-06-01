function timingTable = run_phase8a_only_workflow(cfg, topology)
%RUN_PHASE8A_ONLY_WORKFLOW Regenerate Phase 8A and optional Phase 8B only.

timingTable = table();
fprintf('\nRun mode: phase8a_only\n');
requiredFiles = {'phase4_sector_state_dataset.csv', 'phase6b_cod_predictions_external.csv'};
if ~isfield(cfg, 'enableUnsupervisedClustering') || cfg.enableUnsupervisedClustering
    requiredFiles = [requiredFiles, {'phase5_sector_cluster_assignments.csv', ...
        'phase5_cluster_trigger_support.csv'}];
end
assert_required_files(cfg, requiredFiles);

t = tic;
phase8a = run_phase8a_candidate_action_generation(cfg, topology);
timingTable = append_phase_timing(timingTable, cfg, 'Phase8A_candidate_action_generation', toc(t), 'completed', '');
print_phase8a_summary(phase8a);

if isfield(cfg, 'enablePhase8B') && cfg.enablePhase8B
    t = tic;
    phase8b = run_phase8b_counterfactual_evaluation(cfg);
    timingTable = append_phase_timing(timingTable, cfg, 'Phase8B_counterfactual_action_evaluation', toc(t), 'completed', '');
    print_phase8b_summary(phase8b);
end

if isfield(cfg, 'enablePhase8C') && cfg.enablePhase8C
    t = tic;
    phase8c = run_phase8c_safety_constrained_oracle(cfg);
    timingTable = append_phase_timing(timingTable, cfg, 'Phase8C_safety_constrained_oracle', toc(t), 'completed', '');
    print_phase8c_summary(phase8c);
end
end

function assert_required_files(cfg, fileNames)
for i = 1:numel(fileNames)
    p = fullfile(cfg.tablesDir, fileNames{i});
    if ~isfile(p)
        error('Required input file is missing for phase8a_only: %s', p);
    end
end
end

function print_phase8a_summary(phase8a)
failed = phase8a.validationTable(~phase8a.validationTable.pass_flag, :);
fprintf('Phase 8A candidate rows    : %d\n', height(phase8a.candidateActions));
fprintf('Phase 8A validation failed : %d\n', height(failed));
disp(phase8a.summaryTable);
if ~isempty(failed)
    disp(failed(:, {'check_name','severity','actual_value','expected_condition','notes'}));
end
end

function print_phase8b_summary(phase8b)
fprintf('Phase 8B evaluated rows    : %d\n', height(phase8b.counterfactualTable));
fprintf('Phase 8B mean reward       : %.4f\n', mean(phase8b.counterfactualTable.reward, 'omitnan'));
if isfield(phase8b, 'validationTable') && ~isempty(phase8b.validationTable)
    failed = phase8b.validationTable(~phase8b.validationTable.pass_flag, :);
    fprintf('Phase 8B validation failures: %d\n', height(failed));
    if ~isempty(failed)
        disp(failed(:, {'check_name','severity','actual_value','expected_condition','notes'}));
    end
end
end

function print_phase8c_summary(phase8c)
fprintf('Phase 8C oracle groups     : %d\n', phase8c.numGroups);
fprintf('Phase 8C safe selected     : %d\n', phase8c.numSafeSelected);
fprintf('Phase 8C unsafe fallback   : %d\n', phase8c.numUnsafeFallback);
fprintf('Phase 8C no-op selected    : %d\n', phase8c.numNoopSelected);
fprintf('Phase 8C mean oracle reward: %.4f\n', phase8c.meanOracleReward);
if isfield(phase8c, 'validationTable') && ~isempty(phase8c.validationTable)
    failed = phase8c.validationTable(~phase8c.validationTable.pass_flag & ...
        strcmp(phase8c.validationTable.severity, 'error'), :);
    fprintf('Phase 8C validation errors : %d\n', height(failed));
    if ~isempty(failed)
        disp(failed(:, {'check_name','severity','actual_value','expected_condition','notes'}));
    end
end
end
