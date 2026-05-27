function validationTable = validate_phase8a_candidate_actions(cfg, candidateActions, summaryTable)
%VALIDATE_PHASE8A_CANDIDATE_ACTIONS Validate candidate action definitions.

rows = {};
requiredModules = {'COC/OH','LB/MLB','ES','HO/MRO'};
rows = add_check(rows, 'candidate_action_table_exists', 'error', height(candidateActions) > 0, ...
    sprintf('%d rows', height(candidateActions)), 'Candidate action table must contain rows.', '');

presentModules = unique(string(candidateActions.module_name));
rows = add_check(rows, 'all_required_modules_present', 'error', all(ismember(requiredModules, presentModules)), ...
    strjoin(cellstr(presentModules), ', '), 'COC/OH, LB/MLB, ES, and HO/MRO candidates must be present.', '');

rows = add_check(rows, 'tp_qp_have_no_direct_actions', 'error', ...
    ~any(ismember(presentModules, ["TP","QP","TP/QP"])), strjoin(cellstr(presentModules), ', '), ...
    'TP and QP must not have direct candidate actions.', '');

rows = add_check(rows, 'no_reward_columns_present', 'error', ...
    ~any(ismember(candidateActions.Properties.VariableNames, {'reward','oracle_selected','predicted_reward'})), ...
    'no reward/oracle columns', 'Phase 8A must not evaluate reward or oracle selection.', '');

rows = add_check(rows, 'no_selected_action_flag_present', 'error', ...
    ~any(ismember(candidateActions.Properties.VariableNames, {'selected_action','is_selected','apply_action'})), ...
    'no selected/apply columns', 'Phase 8A must not select or apply actions.', '');

rows = add_check(rows, 'coc_action_space_valid', 'error', validate_coc_space(cfg, candidateActions), ...
    'checked COC deltas', 'COC/OH deltas must be from configured action space.', '');
rows = add_check(rows, 'lb_action_space_valid', 'error', validate_lb_space(cfg, candidateActions), ...
    'checked LB deltas', 'LB/MLB CIO deltas must be from configured action space.', '');
rows = add_check(rows, 'es_action_space_valid', 'error', validate_es_space(cfg, candidateActions), ...
    'checked ES actions', 'ES actions must match configured action strings.', '');
rows = add_check(rows, 'mro_action_space_valid', 'error', validate_mro_space(cfg, candidateActions), ...
    'checked MRO deltas', 'MRO HOM/TTT/CIO deltas must be from configured action space.', '');

rows = add_check(rows, 'summary_table_nonempty', 'error', height(summaryTable) > 0, ...
    sprintf('%d rows', height(summaryTable)), 'Candidate action summary must not be empty.', '');

[engineeringRows, targetDiagnostics] = validate_target_engineering(cfg, candidateActions);
rows = [rows; engineeringRows]; %#ok<AGROW>
if ~isempty(targetDiagnostics)
    writetable(targetDiagnostics, fullfile(cfg.tablesDir, 'phase8a_candidate_target_diagnostics.csv'));
end

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase8a_candidate_action_validation.csv'));
end

function ok = validate_coc_space(cfg, actions)
idx = strcmp(actions.module_name, 'COC/OH') & ~actions.is_no_op;
ok = all(ismember(actions.delta_prs_dB(idx), cfg.cocDeltaPRS_dB)) && ...
    all(ismember(actions.delta_tilt_deg(idx), cfg.cocDeltaTilt_deg)) && ...
    all(ismember(actions.delta_cio_dB(idx), cfg.cocDeltaCIO_dB));
end

function ok = validate_lb_space(cfg, actions)
idx = strcmp(actions.module_name, 'LB/MLB') & ~actions.is_no_op;
ok = all(actions.delta_prs_dB(idx) == 0) && all(actions.delta_tilt_deg(idx) == 0) && ...
    all(ismember(actions.delta_cio_dB(idx), cfg.lbDeltaCIO_dB));
end

function ok = validate_es_space(cfg, actions)
idx = strcmp(actions.module_name, 'ES');
ok = all(ismember(actions.action_type(idx), cfg.esActions));
end

function ok = validate_mro_space(cfg, actions)
idx = strcmp(actions.module_name, 'HO/MRO') & ~actions.is_no_op;
ok = all(ismember(actions.delta_hom_dB(idx), cfg.mroDeltaHOM_dB)) && ...
    all(ismember(actions.delta_ttt_ms(idx), cfg.mroDeltaTTT_ms)) && ...
    all(ismember(actions.delta_cio_dB(idx), cfg.mroDeltaCIO_dB));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [rows, diagnostics] = validate_target_engineering(cfg, actions)
rows = {};
diagnostics = table();
neighborFile = fullfile(cfg.tablesDir, 'phase8a_neighbor_ranking.csv');
hasNeighborFile = isfile(neighborFile);
rows = add_check(rows, 'rf_aware_neighbor_ranking_exists', 'error', hasNeighborFile, ...
    logical_to_text(hasNeighborFile), 'phase8a_neighbor_ranking.csv must be saved.', ...
    'Neighbor ranking should include RF second-best and geometry fields.');
if ~hasNeighborFile || isempty(actions)
    return;
end

neighbors = readtable(neighborFile);
requiredNeighborCols = {'source_sector_id','neighbor_sector_id','is_same_site','distance_m', ...
    'source_target_azimuth_offset_deg','target_source_azimuth_offset_deg', ...
    'ue_second_best_count','boundary_ue_second_best_count','neighbor_score'};
hasRequiredCols = all(ismember(requiredNeighborCols, neighbors.Properties.VariableNames));
rows = add_check(rows, 'neighbor_ranking_has_engineering_columns', 'error', hasRequiredCols, ...
    strjoin(neighbors.Properties.VariableNames, ', '), ...
    'Neighbor ranking must include same-site, distance, azimuth, RF second-best, and score columns.', '');
if ~hasRequiredCols
    return;
end

targeted = actions(~actions.is_no_op & ismember(string(actions.module_name), ["COC/OH","LB/MLB","HO/MRO"]), :);
if isempty(targeted)
    rows = add_check(rows, 'targeted_actions_present', 'error', false, '0 rows', ...
        'COC/OH, LB/MLB, and HO/MRO should have targeted non-no-op candidates.', '');
    return;
end

targetPairs = targeted(:, {'source_sector_id','target_sector_id','module_name'});
targetPairs = renamevars(targetPairs, 'target_sector_id', 'neighbor_sector_id');
targetPairs = outerjoin(targetPairs, neighbors(:, requiredNeighborCols), ...
    'Keys', {'source_sector_id','neighbor_sector_id'}, 'MergeKeys', true, 'Type', 'left');

matched = ~isnan(targetPairs.distance_m);
rows = add_check(rows, 'targeted_actions_match_neighbor_ranking', 'error', all(matched), ...
    sprintf('%d/%d matched', sum(matched), height(targetPairs)), ...
    'Every targeted action should map to the RF-aware neighbor table.', '');
targetPairs = targetPairs(matched, :);
if isempty(targetPairs)
    return;
end

sameSiteRatio = mean(logical(targetPairs.is_same_site));
interSiteRatio = 1 - sameSiteRatio;
meanDistance = mean(targetPairs.distance_m, 'omitnan');
meanSourceAzOffset = mean(targetPairs.source_target_azimuth_offset_deg, 'omitnan');
meanTargetAzOffset = mean(targetPairs.target_source_azimuth_offset_deg, 'omitnan');
secondBestSupportedRatio = mean(targetPairs.ue_second_best_count > 0);
meanSecondBestCount = mean(targetPairs.ue_second_best_count, 'omitnan');
boundarySupportedRatio = mean(targetPairs.boundary_ue_second_best_count > 0);

maxSameSiteRatio = get_cfg_value(cfg, 'phase8MaxSameSiteTargetRatio', 0.50);
minSecondBestSupportRatio = get_cfg_value(cfg, 'phase8MinSecondBestSupportRatio', 0.20);

rows = add_check(rows, 'same_site_target_ratio_reasonable', 'warning', sameSiteRatio <= maxSameSiteRatio, ...
    sprintf('%.4f', sameSiteRatio), sprintf('<= %.2f', maxSameSiteRatio), ...
    'Same-site sectors may be valid, but they should not dominate because of zero coordinate distance.');
rows = add_check(rows, 'inter_site_targets_present', 'error', interSiteRatio > 0, ...
    sprintf('%.4f', interSiteRatio), '> 0', ...
    'At least some targeted actions should point to inter-site neighbors.');
rows = add_check(rows, 'rf_second_best_support_present', 'warning', secondBestSupportedRatio >= minSecondBestSupportRatio, ...
    sprintf('%.4f', secondBestSupportedRatio), sprintf('>= %.2f', minSecondBestSupportRatio), ...
    'Target sectors should often appear as second-best RSRP sectors for baseline UEs.');

metric_name = {'same_site_target_ratio'; 'inter_site_target_ratio'; 'average_target_distance_m'; ...
    'average_source_target_azimuth_offset_deg'; 'average_target_source_azimuth_offset_deg'; ...
    'second_best_supported_target_ratio'; 'average_ue_second_best_count'; ...
    'boundary_second_best_supported_target_ratio'};
actual_value = [sameSiteRatio; interSiteRatio; meanDistance; meanSourceAzOffset; meanTargetAzOffset; ...
    secondBestSupportedRatio; meanSecondBestCount; boundarySupportedRatio];
reference_value = {sprintf('<= %.2f', maxSameSiteRatio); '> 0'; 'diagnostic'; ...
    'lower is better'; 'lower is better'; sprintf('>= %.2f', minSecondBestSupportRatio); ...
    'higher is better'; 'higher is better'};
notes = {'Share of non-no-op COC/LB/MRO targets at the same site as the source.'; ...
    'Share of non-no-op COC/LB/MRO targets at another site.'; ...
    'Mean source-to-target site distance; same-site distance is zero but no longer dominates ranking.'; ...
    'Azimuth offset from source sector boresight toward target site or co-site sector azimuth separation.'; ...
    'Azimuth offset from target sector boresight back toward source site or co-site sector azimuth separation.'; ...
    'Share of target pairs observed as second-best RSRP sector for baseline UE locations.'; ...
    'Mean baseline UE count where target is the second-best RSRP sector for the source best-server region.'; ...
    'Share of target pairs with near-boundary second-best UE evidence.'};
diagnostics = table(metric_name, actual_value, reference_value, notes);
end

function value = get_cfg_value(cfg, fieldName, defaultValue)
if isfield(cfg, fieldName)
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end

function text = logical_to_text(value)
if value
    text = 'true';
else
    text = 'false';
end
end
