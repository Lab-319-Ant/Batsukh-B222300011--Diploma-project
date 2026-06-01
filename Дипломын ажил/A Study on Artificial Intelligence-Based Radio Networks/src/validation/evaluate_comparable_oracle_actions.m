function [oracleLog, oracleKpiByGroup] = evaluate_comparable_oracle_actions(cfg, baseTopology, phase12dResults, oracleTable, scenarioPlan)
%EVALUATE_COMPARABLE_ORACLE_ACTIONS Run cloned-state KPI for oracle actions when implementable.
%
% Inputs:
%   baseTopology     - simulator topology (must have Phase 12B columns).
%   phase12dResults  - Phase 12D one-step KPI update result rows (AI side).
%   oracleTable      - phase8c_oracle_selected_actions.csv contents.
%   scenarioPlan     - phase4_scenario_plan.csv contents.
%
% Outputs:
%   oracleLog        - per-AI-row oracle implementability + KPI status
%   oracleKpiByGroup - cached KPI struct per (scenario, realization, source, module)

oracleLog = build_empty_log();
oracleKpiByGroup = containers.Map('KeyType', 'char', 'ValueType', 'any');
if isempty(phase12dResults) || isempty(oracleTable)
    return;
end

extendedBase = baseTopology;
if ~ismember('cio_dB', extendedBase.sectors.Properties.VariableNames)
    extendedBase = initialize_action_state_columns(extendedBase);
end

n = height(phase12dResults);
rows = cell(n, 16);

for i = 1:n
    aiRow = phase12dResults(i, :);
    scenarioName = char(string(aiRow.scenario_name{1}));
    realizationId = double(aiRow.realization_id);
    sourceSector = double(aiRow.source_sector_id);
    moduleName = char(string(aiRow.module_name{1}));

    oracleRow = find_oracle_row(oracleTable, scenarioName, realizationId, sourceSector, moduleName);
    aiActionId = double(aiRow.action_id);

    if isempty(oracleRow)
        rows(i, :) = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
            aiActionId, NaN, 'no_oracle_row_for_group', false, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN);
        continue;
    end

    oracleActionId = double(oracleRow.selected_action_id);
    oracleActionType = char(string(oracleRow.selected_action_type{1}));
    oracleEsAction = safe_to_char(extract_value(oracleRow, 'es_action'));
    oracleSafetyValid = logical(extract_value(oracleRow, 'safety_valid'));
    oracleIsNoop = logical(extract_value(oracleRow, 'is_noop'));
    oracleDeltaHom = double(extract_value(oracleRow, 'delta_hom_dB'));
    oracleDeltaTtt = double(extract_value(oracleRow, 'delta_ttt_ms'));

    [comparable, comparisonStatus, implementableFlag] = classify_oracle_action(...
        moduleName, oracleActionType, oracleIsNoop, oracleDeltaHom, oracleDeltaTtt, ...
        oracleEsAction, oracleSafetyValid);

    if ~comparable
        rows(i, :) = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
            aiActionId, oracleActionId, comparisonStatus, implementableFlag, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN);
        continue;
    end

    cacheKey = sprintf('%s|%d|%d|%s', scenarioName, realizationId, sourceSector, moduleName);
    if ~oracleKpiByGroup.isKey(cacheKey)
        try
            oracleKpiStruct = evaluate_one_oracle_group(cfg, extendedBase, oracleRow, scenarioPlan);
            oracleKpiByGroup(cacheKey) = oracleKpiStruct;
        catch ME
            oracleKpiByGroup(cacheKey) = struct('error', ME.message);
            rows(i, :) = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
                aiActionId, oracleActionId, ...
                sprintf('evaluator_error:%s', ME.message), implementableFlag, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN);
            continue;
        end
    end

    cached = oracleKpiByGroup(cacheKey);
    if isfield(cached, 'error')
        rows(i, :) = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
            aiActionId, oracleActionId, ...
            sprintf('cached_error:%s', cached.error), implementableFlag, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN);
        continue;
    end

    rows(i, :) = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
        aiActionId, oracleActionId, comparisonStatus, implementableFlag, ...
        cached.attach_rate, cached.mean_rsrp_dBm, cached.mean_sinr_dB, ...
        cached.mean_sector_load, cached.qos_satisfaction_ratio, cached.total_served_traffic_Mbps, ...
        oracleActionType, oracleEsAction);
end

oracleLog = cell2table(rows, 'VariableNames', ...
    {'scenario_name','realization_id','source_sector_id','module_name', ...
    'ai_action_id','oracle_action_id','oracle_kpi_comparison_status', ...
    'oracle_implementable_flag','oracle_attach_rate','oracle_mean_rsrp_dBm', ...
    'oracle_mean_sinr_dB','oracle_mean_sector_load','oracle_qos_satisfaction_ratio', ...
    'oracle_served_traffic_Mbps','oracle_action_type','oracle_es_action'});
end

function row = find_oracle_row(oracleTable, scenarioName, realizationId, sourceSector, moduleName)
mask = strcmp(oracleTable.scenario_name, scenarioName) & ...
    oracleTable.realization_id == realizationId & ...
    oracleTable.source_sector_id == sourceSector & ...
    strcmp(oracleTable.module_name, moduleName);
if ~any(mask)
    row = [];
else
    row = oracleTable(find(mask, 1, 'first'), :);
end
end

function [comparable, status, implementableFlag] = classify_oracle_action(moduleName, actionType, isNoop, dHom, dTtt, esAction, safetyValid)
implementableFlag = false;
comparable = false;
status = '';

if ~safetyValid
    status = 'oracle_action_unsafe';
    return;
end
if isNoop
    status = 'oracle_is_noop_baseline';
    comparable = true;
    implementableFlag = true;
    return;
end

if ~ismember(moduleName, {'COC/OH','LB/MLB'})
    status = sprintf('oracle_module_%s_not_implementable', moduleName);
    return;
end
if ismember(moduleName, {'COC/OH'}) && ~strcmp(actionType, 'compensate_neighbor')
    status = sprintf('oracle_action_type_%s_not_implementable', actionType);
    return;
end
if ismember(moduleName, {'LB/MLB'}) && ~strcmp(actionType, 'cio_bias_to_neighbor')
    status = sprintf('oracle_action_type_%s_not_implementable', actionType);
    return;
end
if dHom ~= 0 || dTtt ~= 0
    status = 'oracle_carries_hom_ttt_placeholder';
    return;
end
if ~isempty(esAction) && ~strcmp(esAction, 'keep_active')
    status = sprintf('oracle_es_action_%s_not_implementable', esAction);
    return;
end

implementableFlag = true;
comparable = true;
status = 'comparable_oracle_action';
end

function out = evaluate_one_oracle_group(cfg, baseTopology, oracleRow, scenarioPlan)
scenarioName = char(string(oracleRow.scenario_name{1}));
realizationId = double(oracleRow.realization_id);
planRow = find_plan_row(scenarioPlan, scenarioName, realizationId);
if isempty(planRow)
    error('no plan row for %s realization %d', scenarioName, realizationId);
end

% If oracle is a no-op, oracle KPIs == baseline KPIs (replay without action)
if logical(extract_value(oracleRow, 'is_noop'))
    pre = replay_phase4_realization_on_topology(cfg, baseTopology, planRow);
    out = collect_state_kpis(pre);
    return;
end

% Build action struct compatible with apply_single_action_to_cloned_state
action.module_name = oracleRow.module_name{1};
action.safe_action_type = oracleRow.selected_action_type{1};
action.accepted_action_type = action.safe_action_type;
action.action_type = action.safe_action_type;
action.source_sector_id = double(oracleRow.source_sector_id);
action.target_sector_id = double(oracleRow.target_sector_id);
action.delta_prs_dB = double(extract_value(oracleRow, 'delta_prs_dB'));
action.delta_tilt_deg = double(extract_value(oracleRow, 'delta_tilt_deg'));
action.delta_cio_dB = double(extract_value(oracleRow, 'delta_cio_dB'));
action.delta_hom_dB = 0;
action.delta_ttt_ms = 0;
action.es_action = '';

% Pre baseline replay (informational, kept for parity) then clone+apply.
pre = replay_phase4_realization_on_topology(cfg, baseTopology, planRow);
clonedTopo = apply_single_action_to_cloned_state(pre.topologyScenario, action);
post = replay_phase4_realization_on_topology(cfg, clonedTopo, planRow);
out = collect_state_kpis(post);
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

function k = collect_state_kpis(state)
k = struct();
k.attach_rate = mean(state.rf.isAttached);
attached = state.rf.isAttached;
if any(attached)
    k.mean_rsrp_dBm = mean(state.rf.bestRSRP_dBm(attached), 'omitnan');
    k.mean_sinr_dB = mean(state.rf.bestSINR_dB(attached), 'omitnan');
else
    k.mean_rsrp_dBm = mean(state.rf.bestRSRP_dBm, 'omitnan');
    k.mean_sinr_dB = mean(state.rf.bestSINR_dB, 'omitnan');
end
k.mean_sector_load = mean(state.sectorKpiTable.sector_load_ratio, 'omitnan');
k.qos_satisfaction_ratio = state.networkKpiTable.qos_satisfaction_ratio;
k.total_served_traffic_Mbps = state.networkKpiTable.total_served_traffic_Mbps;
end

function s = safe_to_char(value)
%SAFE_TO_CHAR Robust conversion to char that returns '' for missing/empty.
if ischar(value)
    s = value;
elseif isstring(value)
    if isempty(value) || (isscalar(value) && ismissing(value))
        s = '';
    else
        s = char(value);
    end
elseif iscell(value) && ~isempty(value)
    s = safe_to_char(value{1});
elseif isnumeric(value) && all(isnan(value))
    s = '';
else
    try
        s = char(string(value));
    catch
        s = '';
    end
end
end

function v = extract_value(rowTable, colName)
v = NaN;
if ~ismember(colName, rowTable.Properties.VariableNames)
    return;
end
x = rowTable.(colName);
if iscell(x), x = x{1}; end
if isstring(x)
    if ismissing(x)
        v = '';
    else
        v = char(x);
    end
elseif ischar(x)
    v = x;
elseif islogical(x)
    v = double(x);
else
    v = double(x);
end
end

function row = make_row(scenarioName, realizationId, sourceSector, moduleName, ...
    aiActionId, oracleActionId, status, implementableFlag, attach, rsrp, sinr, load, qos, traffic, actionType, esAction)
if ~exist('actionType','var') || isempty(actionType), actionType = ''; end
if ~exist('esAction','var') || isempty(esAction), esAction = ''; end
row = {scenarioName, realizationId, sourceSector, moduleName, ...
    aiActionId, oracleActionId, status, logical(implementableFlag), ...
    attach, rsrp, sinr, load, qos, traffic, actionType, esAction};
end

function T = build_empty_log()
T = table('Size', [0 16], ...
    'VariableTypes', {'cell','double','double','cell','double','double','cell','logical', ...
    'double','double','double','double','double','double','cell','cell'}, ...
    'VariableNames', {'scenario_name','realization_id','source_sector_id','module_name', ...
    'ai_action_id','oracle_action_id','oracle_kpi_comparison_status', ...
    'oracle_implementable_flag','oracle_attach_rate','oracle_mean_rsrp_dBm', ...
    'oracle_mean_sinr_dB','oracle_mean_sector_load','oracle_qos_satisfaction_ratio', ...
    'oracle_served_traffic_Mbps','oracle_action_type','oracle_es_action'});
end
