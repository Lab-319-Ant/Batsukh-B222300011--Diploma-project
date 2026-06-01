function timingTable = run_phase4_only_workflow(cfg, topology)
%RUN_PHASE4_ONLY_WORKFLOW Regenerate only the Phase 4 scenario dataset.

timingTable = table();
fprintf('\nRun mode: phase4_only\n');
fprintf('Phase 4 realizations per scenario: %d\n', cfg.phase4NumRealizationsPerScenario);

t = tic;
[sectorStateDataset, networkStateDataset, phase4ScenarioPlan] = generate_phase4_dataset(cfg, topology);
phase4ValidationTable = validate_phase4_dataset(cfg, sectorStateDataset, networkStateDataset, phase4ScenarioPlan);
writetable(phase4ScenarioPlan, fullfile(cfg.tablesDir, 'phase4_scenario_plan.csv'));
writetable(sectorStateDataset, fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv'));
writetable(networkStateDataset, fullfile(cfg.tablesDir, 'phase4_network_state_dataset.csv'));
plot_phase4_dataset_summary(cfg, networkStateDataset);
timingTable = append_phase_timing(timingTable, cfg, 'Phase4_dataset_generation', toc(t), 'completed', '');

failed = phase4ValidationTable(~phase4ValidationTable.pass_flag, :);
fprintf('Phase 4 network rows       : %d\n', height(networkStateDataset));
fprintf('Phase 4 sector rows        : %d\n', height(sectorStateDataset));
fprintf('Phase 4 validation failures: %d\n', height(failed));
if ~isempty(failed)
    disp(failed(:, {'check_name','actual_value','expected_condition','notes'}));
end
end
