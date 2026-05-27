function phase8a = run_phase8a_candidate_action_generation(cfg, topology)
%RUN_PHASE8A_CANDIDATE_ACTION_GENERATION Generate unevaluated action tables.

sectorState = readtable(fullfile(cfg.tablesDir, 'phase4_sector_state_dataset.csv'));
codPredictions = readtable(fullfile(cfg.tablesDir, 'phase6b_cod_predictions_external.csv'));

useClustering = ~isfield(cfg, 'enableUnsupervisedClustering') || cfg.enableUnsupervisedClustering;
if useClustering
    clusterAssignments = readtable(fullfile(cfg.tablesDir, 'phase5_sector_cluster_assignments.csv'));
    triggerSupport = readtable(fullfile(cfg.tablesDir, 'phase5_cluster_trigger_support.csv'));
else
    clusterAssignments = table();
    triggerSupport = table();
end

stateTable = build_phase8a_state_table(cfg, sectorState, clusterAssignments, triggerSupport, codPredictions);
candidateActions = generate_candidate_actions(cfg, topology, stateTable);
candidateActions = validate_candidate_action_table(candidateActions);
summaryTable = summarize_phase8a_actions(candidateActions);
moduleDiagnostics = summarize_phase8a_by_module(candidateActions);
scenarioDiagnostics = summarize_phase8a_by_scenario(candidateActions);
validationTable = validate_phase8a_candidate_actions(cfg, candidateActions, summaryTable);

writetable(candidateActions, fullfile(cfg.tablesDir, 'phase8a_candidate_actions.csv'));
writetable(summaryTable, fullfile(cfg.tablesDir, 'phase8a_candidate_action_summary.csv'));
writetable(moduleDiagnostics, fullfile(cfg.tablesDir, 'phase8a_candidate_diagnostics_by_module.csv'));
writetable(scenarioDiagnostics, fullfile(cfg.tablesDir, 'phase8a_candidate_actions_by_scenario.csv'));
plot_phase8a_candidate_action_counts(cfg, summaryTable);

phase8a = struct();
phase8a.stateTable = stateTable;
phase8a.candidateActions = candidateActions;
phase8a.summaryTable = summaryTable;
phase8a.moduleDiagnostics = moduleDiagnostics;
phase8a.scenarioDiagnostics = scenarioDiagnostics;
phase8a.validationTable = validationTable;
end

function stateTable = build_phase8a_state_table(cfg, sectorState, clusterAssignments, triggerSupport, codPredictions)
stateTable = sectorState;

codCols = {'realization_id','scenario_name','sector_id','predicted_label','score_normal','score_degraded','score_outage'};
codPredictions = renamevars(codPredictions(:, codCols), 'predicted_label', 'cod_predicted_label');
stateTable = outerjoin(stateTable, codPredictions, ...
    'Keys', {'realization_id','scenario_name','sector_id'}, 'MergeKeys', true, 'Type', 'left');

useClustering = ~isfield(cfg, 'enableUnsupervisedClustering') || cfg.enableUnsupervisedClustering;
if useClustering
    clusterColumns = {'realization_id','scenario_name','sector_id','cluster_id'};
    stateTable = outerjoin(stateTable, clusterAssignments(:, clusterColumns), ...
        'Keys', {'realization_id','scenario_name','sector_id'}, 'MergeKeys', true, 'Type', 'left');

    triggerSupport = renamevars(triggerSupport, {'trigger_candidate','suggested_state_name'}, ...
        {'cluster_trigger_candidate','cluster_state_name'});
    stateTable = outerjoin(stateTable, triggerSupport(:, {'cluster_id','cluster_state_name','cluster_trigger_candidate'}), ...
        'Keys', 'cluster_id', 'MergeKeys', true, 'Type', 'left');
else
    stateTable.cluster_id = zeros(height(stateTable), 1);
    [stateTable.cluster_trigger_candidate, stateTable.cluster_state_name] = build_supervised_trigger_metadata(cfg, stateTable);
end

stateTable.cluster_trigger_candidate = fill_missing_text(stateTable.cluster_trigger_candidate, 'no_action_monitoring');
stateTable.cluster_state_name = fill_missing_text(stateTable.cluster_state_name, 'supervised_kpi_trigger');
stateTable.cod_predicted_label = fill_missing_text(stateTable.cod_predicted_label, 'normal');
end

function [triggerCandidate, stateName] = build_supervised_trigger_metadata(cfg, stateTable)
n = height(stateTable);
triggerCandidate = repmat("no_action_monitoring", n, 1);
stateName = repmat("normal_like", n, 1);

codLabel = repmat("normal", n, 1);
if ismember('cod_predicted_label', stateTable.Properties.VariableNames)
    codLabel = string(stateTable.cod_predicted_label);
    codLabel(ismissing(codLabel) | codLabel == "") = "normal";
end

isImpaired = false(n, 1);
if ismember('outage_label', stateTable.Properties.VariableNames)
    isImpaired = isImpaired | logical(stateTable.outage_label);
end
if ismember('degraded_label', stateTable.Properties.VariableNames)
    isImpaired = isImpaired | logical(stateTable.degraded_label);
end
if ismember('is_target_impaired_sector', stateTable.Properties.VariableNames)
    isImpaired = isImpaired | logical(stateTable.is_target_impaired_sector);
end
isImpaired = isImpaired | codLabel == "outage" | codLabel == "degraded";

isOverload = false(n, 1);
if ismember('overload_flag', stateTable.Properties.VariableNames)
    isOverload = isOverload | logical(stateTable.overload_flag);
end
if ismember('sector_load_ratio', stateTable.Properties.VariableNames)
    isOverload = isOverload | stateTable.sector_load_ratio > cfg.lbOverloadThreshold;
end

isLowLoad = false(n, 1);
if ismember('es_candidate', stateTable.Properties.VariableNames)
    isLowLoad = isLowLoad | logical(stateTable.es_candidate);
end
if ismember('sector_load_ratio', stateTable.Properties.VariableNames)
    isLowLoad = isLowLoad | stateTable.sector_load_ratio < cfg.esLowLoadThreshold;
end

isHandoverRisk = false(n, 1);
if ismember('handover_risk_score', stateTable.Properties.VariableNames)
    isHandoverRisk = stateTable.handover_risk_score > cfg.mroHandoverRiskThreshold;
end

for i = 1:n
    tags = strings(0, 1);
    if isImpaired(i), tags(end+1) = "COC/OH"; end %#ok<AGROW>
    if isOverload(i), tags(end+1) = "LB/MLB"; end %#ok<AGROW>
    if isLowLoad(i), tags(end+1) = "ES"; end %#ok<AGROW>
    if isHandoverRisk(i), tags(end+1) = "HO/MRO"; end %#ok<AGROW>
    if ~isempty(tags)
        triggerCandidate(i) = strjoin(cellstr(tags), ';');
    end
    if isImpaired(i)
        stateName(i) = "impaired_like";
    elseif isOverload(i)
        stateName(i) = "congested_like";
    elseif isLowLoad(i)
        stateName(i) = "low_load_like";
    elseif isHandoverRisk(i)
        stateName(i) = "handover_risk_like";
    end
end

triggerCandidate = cellstr(triggerCandidate);
stateName = cellstr(stateName);
end

function values = fill_missing_text(values, replacement)
values = string(values);
values(ismissing(values) | values == "") = replacement;
values = cellstr(values);
end

function summaryTable = summarize_phase8a_actions(candidateActions)
if isempty(candidateActions)
    summaryTable = table();
    return;
end
[groups, moduleName, actionType] = findgroups(candidateActions.module_name, candidateActions.action_type);
candidate_count = splitapply(@numel, candidateActions.action_id, groups);
summaryTable = table(moduleName, actionType, candidate_count, ...
    'VariableNames', {'module_name','action_type','candidate_count'});
end

function diagnostics = summarize_phase8a_by_module(candidateActions)
if isempty(candidateActions)
    diagnostics = table();
    return;
end

[groups, moduleName] = findgroups(candidateActions.module_name);
candidate_count = splitapply(@numel, candidateActions.action_id, groups);
no_op_count = splitapply(@sum, double(candidateActions.is_no_op), groups);
non_no_op_count = candidate_count - no_op_count;
unique_source_sectors = splitapply(@(x) numel(unique(x)), candidateActions.source_sector_id, groups);
unique_target_sectors = splitapply(@(x) numel(unique(x)), candidateActions.target_sector_id, groups);
mean_source_load = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_load_ratio, groups);
mean_source_qos = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_qos_satisfaction_ratio, groups);
mean_source_handover_risk = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_handover_risk_score, groups);
same_sector_target_ratio = splitapply(@(src,tgt,isNoOp) mean((src == tgt) & ~logical(isNoOp)), ...
    candidateActions.source_sector_id, candidateActions.target_sector_id, double(candidateActions.is_no_op), groups);

diagnostics = table(moduleName, candidate_count, no_op_count, non_no_op_count, ...
    unique_source_sectors, unique_target_sectors, mean_source_load, mean_source_qos, ...
    mean_source_handover_risk, same_sector_target_ratio, ...
    'VariableNames', {'module_name','candidate_count','no_op_count','non_no_op_count', ...
    'unique_source_sectors','unique_target_sectors','mean_source_load_ratio', ...
    'mean_source_qos_satisfaction_ratio','mean_source_handover_risk_score', ...
    'same_sector_target_ratio'});
end

function diagnostics = summarize_phase8a_by_scenario(candidateActions)
if isempty(candidateActions)
    diagnostics = table();
    return;
end

[groups, scenarioName, moduleName] = findgroups(candidateActions.scenario_name, candidateActions.module_name);
candidate_count = splitapply(@numel, candidateActions.action_id, groups);
no_op_count = splitapply(@sum, double(candidateActions.is_no_op), groups);
non_no_op_count = candidate_count - no_op_count;
unique_realizations = splitapply(@(x) numel(unique(x)), candidateActions.realization_id, groups);
unique_source_sectors = splitapply(@(x) numel(unique(x)), candidateActions.source_sector_id, groups);
mean_source_load = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_load_ratio, groups);
mean_source_qos = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_qos_satisfaction_ratio, groups);
mean_source_handover_risk = splitapply(@(x) mean(x, 'omitnan'), candidateActions.source_handover_risk_score, groups);

diagnostics = table(scenarioName, moduleName, candidate_count, no_op_count, ...
    non_no_op_count, unique_realizations, unique_source_sectors, mean_source_load, ...
    mean_source_qos, mean_source_handover_risk, ...
    'VariableNames', {'scenario_name','module_name','candidate_count','no_op_count', ...
    'non_no_op_count','unique_realizations','unique_source_sectors', ...
    'mean_source_load_ratio','mean_source_qos_satisfaction_ratio', ...
    'mean_source_handover_risk_score'});
end
