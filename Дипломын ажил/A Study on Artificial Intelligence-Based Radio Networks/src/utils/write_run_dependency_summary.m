function dependencySummary = write_run_dependency_summary(cfg, outputName)
%WRITE_RUN_DEPENDENCY_SUMMARY Save active input/output artifact timestamps.
%
% This helps confirm that stale legacy artifacts are not mixed into the
% active 7-site workflow. It records presence, size, and modified time for
% the files used by the current staged run.

if nargin < 2
    outputName = 'run_dependency_summary.csv';
end

projectRoot = fileparts(cfg.resultsDir);
artifactPaths = { ...
    fullfile(projectRoot, 'config', 'sim_config.m'), 'active_config'; ...
    fullfile(cfg.tablesDir, 'phase1b_ue_rf_results.csv'), 'phase8a_neighbor_rf_evidence'; ...
    fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv'), 'phase8a_phase8b_state_input'; ...
    fullfile(cfg.tablesDir, 'phase4_network_state_dataset.csv'), 'phase4_network_input'; ...
    fullfile(cfg.tablesDir, 'phase5_sector_cluster_assignments.csv'), 'phase8a_cluster_input'; ...
    fullfile(cfg.tablesDir, 'phase5_cluster_trigger_support.csv'), 'phase8a_trigger_input'; ...
    fullfile(cfg.tablesDir, 'phase6b_cod_predictions_external.csv'), 'phase8a_cod_support_input'; ...
    fullfile(cfg.tablesDir, 'phase8a_candidate_actions.csv'), 'phase8b_candidate_input'; ...
    fullfile(cfg.tablesDir, 'phase8a_neighbor_ranking.csv'), 'phase8a_neighbor_output'; ...
    fullfile(cfg.tablesDir, 'phase8b_counterfactual_action_table.csv'), 'phase8b_output'; ...
    fullfile(projectRoot, 'archive', 'legacy_single_site'), 'legacy_archive_folder' ...
    };

n = size(artifactPaths, 1);
artifact_path = strings(n, 1);
artifact_role = strings(n, 1);
exists_flag = false(n, 1);
is_folder = false(n, 1);
bytes = nan(n, 1);
modified_time = strings(n, 1);

for i = 1:n
    p = string(artifactPaths{i, 1});
    artifact_path(i) = p;
    artifact_role(i) = string(artifactPaths{i, 2});
    exists_flag(i) = isfile(p) || isfolder(p);
    is_folder(i) = isfolder(p);
    if exists_flag(i)
        info = dir(p);
        if ~isempty(info)
            bytes(i) = sum([info.bytes]);
            modified_time(i) = string(datestr(max([info.datenum]), 'yyyy-mm-dd HH:MM:SS'));
        end
    end
end

run_mode = repmat(string(cfg.runMode), n, 1);
phase4_realizations_per_scenario = repmat(cfg.phase4NumRealizationsPerScenario, n, 1);
dependencySummary = table(run_mode, artifact_role, artifact_path, exists_flag, is_folder, ...
    bytes, modified_time, phase4_realizations_per_scenario);
writetable(dependencySummary, fullfile(cfg.tablesDir, outputName));
end
