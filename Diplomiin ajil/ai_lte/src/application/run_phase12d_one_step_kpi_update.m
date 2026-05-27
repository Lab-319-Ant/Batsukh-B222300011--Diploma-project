function phase12d = run_phase12d_one_step_kpi_update(cfg, baseTopology)
%RUN_PHASE12D_ONE_STEP_KPI_UPDATE One-step KPI(t)->KPI(t+1) for eligible actions.
%
% Phase 12D is a LIMITED one-step cloned-state evaluation. It does NOT
% implement multi-step control, NOT mutate the original simulator, NOT
% touch ES sleep / HO-MRO HOM-TTT, and NOT constitute closed-loop SON.
% It only applies the Phase 12C eligible action set (COC/OH compensate
% neighbor with P_RS/tilt/CIO and LB/MLB CIO bias) to cloned topologies
% and reports pre vs post KPI deltas using the same seeds as Phase 4.

eligibleFile = fullfile(cfg.tablesDir, 'phase12c_kpi_update_eligible_actions.csv');
planFile = fullfile(cfg.tablesDir, 'phase4_scenario_plan.csv');
if ~isfile(eligibleFile) || ~isfile(planFile)
    error('Phase 12D: required inputs missing (%s, %s)', eligibleFile, planFile);
end
eligible = readtable(eligibleFile);
scenarioPlan = readtable(planFile);

extendedTopology = initialize_action_state_columns(baseTopology);
% Snapshot for "original_state_unchanged" verification.
originalSectorsSnapshot = extendedTopology.sectors;

resultRows = build_empty_result_table();
sectorKpiAggregate = table();
networkKpiAggregate = table();
appliedLog = build_empty_applied_log();
skippedLog = build_empty_skipped_log();

if isempty(eligible)
    write_all_tables(cfg, resultRows, sectorKpiAggregate, networkKpiAggregate, ...
        appliedLog, skippedLog);
    phase12d = empty_phase12d_struct();
    phase12d.validationTable = validate_phase12d_one_step_kpi_update(cfg, ...
        resultRows, eligible, appliedLog, skippedLog, ...
        extendedTopology, originalSectorsSnapshot);
    return;
end

% Group eligible actions by (scenario_name, realization_id).
gKey = strcat(string(eligible.scenario_name), '|', string(eligible.realization_id));
[uniqueGroups, ~, gIdx] = unique(gKey, 'stable');
nGroups = numel(uniqueGroups);

numEvaluatedGroups = 0;
numAppliedActions = 0;
numSkippedActions = 0;

for g = 1:nGroups
    groupActions = eligible(gIdx == g, :);
    scenarioName = char(string(groupActions.scenario_name{1}));
    realizationId = double(groupActions.realization_id(1));

    planRow = find_plan_row(scenarioPlan, scenarioName, realizationId);
    if isempty(planRow)
        for r = 1:height(groupActions)
            skippedLog = append_skipped(skippedLog, groupActions(r, :), ...
                'no matching Phase 4 scenario plan row');
            numSkippedActions = numSkippedActions + 1;
        end
        continue;
    end

    try
        preState = run_phase4_style_realization(cfg, extendedTopology, planRow);
        clonedTopo = apply_eligible_actions_to_cloned_state(preState.topologyScenario, groupActions);
        postState = run_phase4_style_realization(cfg, clonedTopo, planRow, true);
    catch ME
        for r = 1:height(groupActions)
            skippedLog = append_skipped(skippedLog, groupActions(r, :), ...
                sprintf('evaluator error: %s', ME.message));
            numSkippedActions = numSkippedActions + 1;
        end
        continue;
    end

    deltas = compare_pre_post_kpis(preState, postState);
    numEvaluatedGroups = numEvaluatedGroups + 1;

    for r = 1:height(groupActions)
        action = groupActions(r, :);
        resultRows = append_result(resultRows, action, deltas, scenarioName, realizationId);
        appliedLog = append_applied(appliedLog, action);
        numAppliedActions = numAppliedActions + 1;
    end

    sectorKpiAggregate = [sectorKpiAggregate; ...
        tag_kpi(preState.sectorKpiTable, scenarioName, realizationId, 'pre'); ...
        tag_kpi(postState.sectorKpiTable, scenarioName, realizationId, 'post')]; %#ok<AGROW>
    networkKpiAggregate = [networkKpiAggregate; ...
        tag_kpi(preState.networkKpiTable, scenarioName, realizationId, 'pre'); ...
        tag_kpi(postState.networkKpiTable, scenarioName, realizationId, 'post')]; %#ok<AGROW>
end

% Verify original state unchanged.
originalUnchanged = isequal(extendedTopology.sectors, originalSectorsSnapshot);
if ~originalUnchanged
    warning('Phase 12D: extendedTopology.sectors changed during evaluation.');
end

write_all_tables(cfg, resultRows, sectorKpiAggregate, networkKpiAggregate, ...
    appliedLog, skippedLog);
[moduleSummary, scenarioSummary] = summarize_phase12d_kpi_update(resultRows);
writetable(moduleSummary,   fullfile(cfg.tablesDir, 'phase12d_summary_by_module.csv'));
writetable(scenarioSummary, fullfile(cfg.tablesDir, 'phase12d_summary_by_scenario.csv'));

try_plot('plot_phase12d_pre_post_kpi_by_module', cfg, resultRows);
try_plot('plot_phase12d_load_change_by_scenario', cfg, resultRows);
try_plot('plot_phase12d_rsrp_sinr_change', cfg, resultRows);
try_plot('plot_phase12d_kpi_update_outcomes', cfg, resultRows);

validationTable = validate_phase12d_one_step_kpi_update(cfg, resultRows, eligible, ...
    appliedLog, skippedLog, extendedTopology, originalSectorsSnapshot);

phase12d = empty_phase12d_struct();
phase12d.resultRows = resultRows;
phase12d.moduleSummary = moduleSummary;
phase12d.scenarioSummary = scenarioSummary;
phase12d.appliedLog = appliedLog;
phase12d.skippedLog = skippedLog;
phase12d.validationTable = validationTable;
phase12d.numEligibleLoaded = height(eligible);
phase12d.numApplied = numAppliedActions;
phase12d.numSkipped = numSkippedActions;
phase12d.numEvaluatedGroups = numEvaluatedGroups;
phase12d.originalStateUnchanged = originalUnchanged;
if ~isempty(resultRows)
    phase12d.meanDeltaAttachRate = mean(resultRows.delta_attach_rate, 'omitnan');
    phase12d.meanDeltaRSRP = mean(resultRows.delta_mean_rsrp_dB, 'omitnan');
    phase12d.meanDeltaSINR = mean(resultRows.delta_mean_sinr_dB, 'omitnan');
    phase12d.meanDeltaLoad = mean(resultRows.delta_mean_sector_load, 'omitnan');
    phase12d.meanDeltaQoS = mean(resultRows.delta_qos_satisfaction_ratio, 'omitnan');
end
end

function s = empty_phase12d_struct()
s = struct('resultRows', table(), 'moduleSummary', table(), 'scenarioSummary', table(), ...
    'appliedLog', table(), 'skippedLog', table(), 'validationTable', table(), ...
    'numEligibleLoaded', 0, 'numApplied', 0, 'numSkipped', 0, ...
    'numEvaluatedGroups', 0, 'originalStateUnchanged', true, ...
    'meanDeltaAttachRate', NaN, 'meanDeltaRSRP', NaN, 'meanDeltaSINR', NaN, ...
    'meanDeltaLoad', NaN, 'meanDeltaQoS', NaN);
end

function row = find_plan_row(scenarioPlan, scenarioName, realizationId)
mask = strcmp(scenarioPlan.scenario_name, scenarioName) & ...
    scenarioPlan.realization_id == realizationId;
if ~any(mask)
    row = [];
else
    row = scenarioPlan(find(mask, 1, 'first'), :);
end
end

function out = run_phase4_style_realization(cfg, baseTopology, planRow, suppressVariantUes)
%RUN_PHASE4_STYLE_REALIZATION Replay one Phase 4 realization on a topology.
%
% baseTopology is either:
%   - the pre-action topology (for the pre run)
%   - the cloned topology with actions applied (for the post run)
% In both cases we reapply the scenario's referencePowerOffset_dB,
% txPowerOffset_dB, and impaired-sector status to remain consistent with
% Phase 4. The cloned topology's action-delta columns are PRESERVED
% because apply_scenario_to_network only touches the impaired sector.

if nargin < 4, suppressVariantUes = false; end

scenario = struct();
scenario.scenario_id = planRow.scenario_id;
scenario.scenario_name = planRow.scenario_name{1};
scenario.traffic_mode = planRow.traffic_mode{1};
scenario.impaired_sector_id = planRow.impaired_sector_id;
scenario.impaired_sector_status = planRow.impaired_sector_status{1};
scenario.referencePowerOffset_dB = planRow.referencePowerOffset_dB;
scenario.txPowerOffset_dB = planRow.txPowerOffset_dB;
scenario.enable_es_candidate_flag = planRow.enable_es_candidate_flag;
scenario.enable_handover_stress_metrics = planRow.enable_handover_stress_metrics;

[cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, baseTopology, scenario);

if scenario.enable_handover_stress_metrics
    cfgScenario.boundaryRiskThreshold_dB = cfg.handoverStressMarginRisk_dB;
else
    cfgScenario.boundaryRiskThreshold_dB = cfg.handoverMarginRisk_dB;
end

% Make sure Phase 12B action columns survive the scenario application.
topologyScenario.sectors = inherit_phase12b_columns(topologyScenario.sectors, baseTopology.sectors);

rng(planRow.ue_seed);
baseUes = generate_ues(cfgScenario, topologyScenario);
if scenario.enable_handover_stress_metrics && ~suppressVariantUes
    cfgScenario.handoverStressSeed = planRow.ue_seed + 7000;
    scenarioUes = generate_handover_stress_ues(cfgScenario, topologyScenario, baseUes);
elseif scenario.enable_handover_stress_metrics && suppressVariantUes
    % Keep variant generation deterministic across pre/post.
    cfgScenario.handoverStressSeed = planRow.ue_seed + 7000;
    scenarioUes = generate_handover_stress_ues(cfgScenario, topologyScenario, baseUes);
else
    scenarioUes = baseUes;
end

rng(planRow.shadowing_seed);
rf = calc_rsrp_sinr(cfgScenario, topologyScenario, scenarioUes);

% Phase 12B CIO re-association: applied only when at least one sector has
% non-zero cio_dB. The pre run will always see cio_dB = 0.
cioRow = reshape(double(topologyScenario.sectors.cio_dB), 1, []);
if any(cioRow ~= 0)
    rf = apply_cio_reassociation(cfgScenario, rf, cioRow);
end

rng(planRow.traffic_seed);
ueTraffic = assign_ue_traffic_demand(cfgScenario, scenarioUes, rf);
[ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgScenario, ueTraffic, rf, topologyScenario);
sectorKpiTable = compute_sector_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorCapacity_Mbps);

rfMap = struct();
rfMap.plannedCoverageRatio = mean(rf.isAttached);
rfMap.plannedRSRPCoverageRatio = mean(rf.bestRSRP_dBm >= cfg.minRSRP_dBm);
rfMap.plannedSINRThresholdRatio = mean(rf.bestSINR_dB >= cfg.minSINR_dB);
rfMap.studyCoverageRatio = NaN;
networkKpiTable = compute_network_kpis(cfgScenario, topologyScenario, ueTrafficResult, sectorKpiTable, rfMap);

out = struct();
out.topologyScenario = topologyScenario;
out.ues = scenarioUes;
out.rf = rf;
out.sectorKpiTable = sectorKpiTable;
out.networkKpiTable = networkKpiTable;
end

function newSectors = inherit_phase12b_columns(newSectors, refSectors)
%INHERIT_PHASE12B_COLUMNS Copy action-state columns from ref into new if absent or zero.
cols = {'cio_dB','hom_offset_dB','ttt_offset_ms','is_sleeping'};
n = height(newSectors);
for k = 1:numel(cols)
    c = cols{k};
    if ~ismember(c, newSectors.Properties.VariableNames)
        if ismember(c, refSectors.Properties.VariableNames)
            newSectors.(c) = refSectors.(c);
        elseif strcmp(c, 'is_sleeping')
            newSectors.(c) = false(n, 1);
        else
            newSectors.(c) = zeros(n, 1);
        end
    elseif ismember(c, refSectors.Properties.VariableNames)
        % If apply_scenario_to_network left cio_dB unchanged we still want
        % the values from refSectors (the cloned topology's modified state).
        newSectors.(c) = refSectors.(c);
    end
end
end

function rf = apply_cio_reassociation(cfg, rf, cioRow)
biasedMetric = rf.RSRP_dBm + cioRow;
[~, servingBiased] = max(biasedMetric, [], 2);
numUE = numel(servingBiased);

RxTotal_mW = 10 .^ (rf.RxTotal_dBm ./ 10);
noise_mW = 10 .^ (rf.noise_dBm ./ 10);

servingPower_mW = zeros(numUE, 1);
interference_mW = zeros(numUE, 1);
for u = 1:numUE
    ss = servingBiased(u);
    servingPower_mW(u) = RxTotal_mW(u, ss);
    interference_mW(u) = sum(RxTotal_mW(u, :)) - servingPower_mW(u);
end
sinrLinear = servingPower_mW ./ (interference_mW + noise_mW);
bestSINR_dB = 10 * log10(sinrLinear);

servingRSRP_dBm = zeros(numUE, 1);
for u = 1:numUE
    servingRSRP_dBm(u) = rf.RSRP_dBm(u, servingBiased(u));
end

isAttached = servingRSRP_dBm >= cfg.minRSRP_dBm & bestSINR_dB >= cfg.minSINR_dB;
servingBiased(~isAttached) = 0;

secondBest_dBm = zeros(numUE, 1);
rsrpMat = rf.RSRP_dBm;
for u = 1:numUE
    row = rsrpMat(u, :);
    ss = max(servingBiased(u), 1);
    row(ss) = -Inf;
    secondBest_dBm(u) = max(row);
end

rf.bestRSRP_dBm = servingRSRP_dBm;
rf.secondBestRSRP_dBm = secondBest_dBm;
rf.rsrpGapBestSecond_dB = servingRSRP_dBm - secondBest_dBm;
rf.bestSINR_dB = bestSINR_dB;
rf.bestServer = servingBiased;
rf.servingSector = servingBiased;
rf.isAttached = isAttached;
rf.isBoundaryUE = isAttached & rf.rsrpGapBestSecond_dB < cfg.handoverMarginRisk_dB;
end

function T = build_empty_result_table()
T = table('Size', [0 28], ...
    'VariableTypes', {'cell','double','double','cell','double','cell','double','double', ...
    'double','double','double','double','double','double','double','double','double', ...
    'double','double','double','double','double','double','double','double','double','logical','logical'}, ...
    'VariableNames', {'scenario_name','realization_id','coordinator_group_id', ...
    'module_name','action_id','action_type','source_sector_id','target_sector_id', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB', ...
    'pre_attach_rate','post_attach_rate','delta_attach_rate', ...
    'pre_mean_rsrp_dBm','post_mean_rsrp_dBm','delta_mean_rsrp_dB', ...
    'pre_mean_sinr_dB','post_mean_sinr_dB','delta_mean_sinr_dB', ...
    'pre_mean_sector_load','post_mean_sector_load','delta_mean_sector_load', ...
    'pre_qos_satisfaction_ratio','post_qos_satisfaction_ratio','delta_qos_satisfaction_ratio', ...
    'action_applied_to_clone','kpi_t_plus_1_generated'});
% Append the served-traffic, pre/post network total columns explicitly to
% keep VariableTypes sane (cell types for strings preserved).
T.pre_total_served_traffic_Mbps = zeros(0, 1);
T.post_total_served_traffic_Mbps = zeros(0, 1);
T.delta_served_traffic_Mbps = zeros(0, 1);
T.decision_source_sector_id = zeros(0, 1);
T.decision_target_sector_id = zeros(0, 1);
T.application_affected_sector_id = zeros(0, 1);
T.application_state_variable = cell(0, 1);
T.original_state_unchanged = false(0, 1);
end

function T = append_result(T, action, deltas, scenarioName, realizationId)
coordId = lookup_number(action, 'coordinator_group_id');
row = table( ...
    {scenarioName}, realizationId, coordId, ...
    {action.module_name{1}}, action.selected_action_id_safe, {action.action_type{1}}, ...
    action.source_sector_id, action.target_sector_id, ...
    action.delta_prs_dB, action.delta_tilt_deg, action.delta_cio_dB, ...
    deltas.pre_attach_rate, deltas.post_attach_rate, deltas.delta_attach_rate, ...
    deltas.pre_mean_rsrp_dBm, deltas.post_mean_rsrp_dBm, deltas.delta_mean_rsrp_dB, ...
    deltas.pre_mean_sinr_dB, deltas.post_mean_sinr_dB, deltas.delta_mean_sinr_dB, ...
    deltas.pre_mean_sector_load, deltas.post_mean_sector_load, deltas.delta_mean_sector_load, ...
    deltas.pre_qos_satisfaction_ratio, deltas.post_qos_satisfaction_ratio, deltas.delta_qos_satisfaction_ratio, ...
    true, true, ...
    'VariableNames', {'scenario_name','realization_id','coordinator_group_id', ...
    'module_name','action_id','action_type','source_sector_id','target_sector_id', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB', ...
    'pre_attach_rate','post_attach_rate','delta_attach_rate', ...
    'pre_mean_rsrp_dBm','post_mean_rsrp_dBm','delta_mean_rsrp_dB', ...
    'pre_mean_sinr_dB','post_mean_sinr_dB','delta_mean_sinr_dB', ...
    'pre_mean_sector_load','post_mean_sector_load','delta_mean_sector_load', ...
    'pre_qos_satisfaction_ratio','post_qos_satisfaction_ratio','delta_qos_satisfaction_ratio', ...
    'action_applied_to_clone','kpi_t_plus_1_generated'});
row.pre_total_served_traffic_Mbps = deltas.pre_total_served_traffic_Mbps;
row.post_total_served_traffic_Mbps = deltas.post_total_served_traffic_Mbps;
row.delta_served_traffic_Mbps = deltas.delta_served_traffic_Mbps;
row.decision_source_sector_id = lookup_number(action, 'decision_source_sector_id');
row.decision_target_sector_id = lookup_number(action, 'decision_target_sector_id');
row.application_affected_sector_id = lookup_number(action, 'application_affected_sector_id');
row.application_state_variable = {lookup_text(action, 'application_state_variable')};
row.original_state_unchanged = true;
T = [T; row];
end

function T = build_empty_applied_log()
T = table('Size', [0 11], ...
    'VariableTypes', {'double','cell','cell','double','double','double','double','double','double','cell','logical'}, ...
    'VariableNames', {'action_id','module_name','action_type','source_sector_id', ...
    'target_sector_id','decision_source_sector_id','decision_target_sector_id', ...
    'coordinator_group_id','application_affected_sector_id','application_state_variable', ...
    'applied_to_clone'});
end

function T = append_applied(T, action)
row = table(action.selected_action_id_safe, {action.module_name{1}}, ...
    {action.action_type{1}}, action.source_sector_id, action.target_sector_id, ...
    lookup_number(action, 'decision_source_sector_id'), ...
    lookup_number(action, 'decision_target_sector_id'), ...
    lookup_number(action, 'coordinator_group_id'), ...
    lookup_number(action, 'application_affected_sector_id'), ...
    {lookup_text(action, 'application_state_variable')}, true, ...
    'VariableNames', T.Properties.VariableNames);
T = [T; row];
end

function T = build_empty_skipped_log()
T = table('Size', [0 5], ...
    'VariableTypes', {'double','cell','cell','double','cell'}, ...
    'VariableNames', {'action_id','module_name','scenario_name','realization_id','skip_reason'});
end

function T = append_skipped(T, action, reason)
row = table(action.selected_action_id_safe, {action.module_name{1}}, ...
    {action.scenario_name{1}}, action.realization_id, {reason}, ...
    'VariableNames', T.Properties.VariableNames);
T = [T; row];
end

function tagged = tag_kpi(kpiTable, scenarioName, realizationId, phaseTag)
if isempty(kpiTable)
    tagged = kpiTable;
    return;
end
tagged = kpiTable;
n = height(kpiTable);
tagged.scenario_name = repmat({scenarioName}, n, 1);
tagged.realization_id = repmat(realizationId, n, 1);
tagged.phase_tag = repmat({phaseTag}, n, 1);
end

function write_all_tables(cfg, resultRows, sectorKpis, networkKpis, appliedLog, skippedLog)
writetable(resultRows,   fullfile(cfg.tablesDir, 'phase12d_one_step_kpi_update_results.csv'));
writetable(sectorKpis,   fullfile(cfg.tablesDir, 'phase12d_pre_post_sector_kpis.csv'));
writetable(networkKpis,  fullfile(cfg.tablesDir, 'phase12d_pre_post_network_kpis.csv'));
writetable(appliedLog,   fullfile(cfg.tablesDir, 'phase12d_action_application_log.csv'));
writetable(skippedLog,   fullfile(cfg.tablesDir, 'phase12d_skipped_actions_log.csv'));
end

function try_plot(fnName, cfg, T)
if exist(fnName, 'file') ~= 2 || isempty(T)
    return;
end
try
    feval(fnName, cfg, T);
catch ME
    warning('Phase 12D plot %s failed: %s', fnName, ME.message);
end
end

function v = lookup_number(T, name)
v = 0;
if istable(T) && ismember(name, T.Properties.VariableNames)
    raw = T.(name);
    if iscell(raw), raw = raw{1}; end
    v = double(raw);
end
if isempty(v) || ~isfinite(v), v = 0; end
end

function s = lookup_text(T, name)
s = '';
if istable(T) && ismember(name, T.Properties.VariableNames)
    raw = T.(name);
    if iscell(raw), raw = raw{1}; end
    s = char(string(raw));
end
end
