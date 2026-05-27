function inputTable = prepare_phase11a_coordinator_inputs(phase10aSelected)
%PREPARE_PHASE11A_COORDINATOR_INPUTS Annotate Phase 10A picks with coordinator metadata.
%
% One row per Phase 10A safety-enforced selection plus:
%   coordinator_group_id : one per (scenario_name, realization_id) tick
%   module_priority      : 2 COC/OH, 3 LB/MLB, 4 HO/MRO, 6 ES (smaller wins)
%   decision_source_sector_id / decision_target_sector_id:
%                          original source/target pair selected by ML
%   coordinator_affected_sector_id:
%                          logical sector used by the coordinator narrative
%   application_affected_sector_id:
%                          actual simulator sector whose state is mutated
%   application_state_variable:
%                          simulator state variable written by this action
%   affected_parameter   : pipe-joined parameter scope string
%                          ('RS_power','tilt','CIO','HOM','TTT','ES_state','none')
%   action_scope         : 'source_only' | 'source_neighbor' | 'no_op'
%   predicted_reward     : Phase 10A safe_predicted_reward
%   true_reward          : Phase 10A safe_true_reward (= Phase 8B reward)
%
% This function does NOT change any selection; it only attaches metadata
% used by the conflict detector and resolver.

n = height(phase10aSelected);
if n == 0
    inputTable = build_empty_input_table();
    return;
end

scenarios = string(phase10aSelected.scenario_name);
realizations = phase10aSelected.realization_id;
modules = string(phase10aSelected.module_name);
actionTypes = string(phase10aSelected.safe_action_type);
sources = phase10aSelected.source_sector_id;
targets = phase10aSelected.target_sector_id;

% Coordinator tick = (scenario, realization).
tickKey = strcat(scenarios, '|', string(realizations));
[uniqueTicks, ~, tickIdx] = unique(tickKey, 'stable');
coordGroup = tickIdx;

modulePriority = nan(n, 1);
modulePriority(modules == "COC/OH") = 2;
modulePriority(modules == "LB/MLB") = 3;
modulePriority(modules == "HO/MRO") = 4;
modulePriority(modules == "ES") = 6;

deltaPrs = pull_col(phase10aSelected, 'delta_prs_dB');
deltaTilt = pull_col(phase10aSelected, 'delta_tilt_deg');
deltaCio = pull_col(phase10aSelected, 'delta_cio_dB');
deltaHom = pull_col(phase10aSelected, 'delta_hom_dB');
deltaTtt = pull_col(phase10aSelected, 'delta_ttt_ms');
esActionStr = pull_string_col(phase10aSelected, 'es_action');

coordinatorAffectedSector = zeros(n, 1);
applicationAffectedSector = zeros(n, 1);
affectedParameter = strings(n, 1);
applicationStateVariable = strings(n, 1);
actionScope = strings(n, 1);

for i = 1:n
    [coordinatorAffectedSector(i), affectedParameter(i), actionScope(i), ...
        applicationAffectedSector(i), applicationStateVariable(i)] = ...
        classify_action(modules(i), actionTypes(i), sources(i), targets(i), ...
        deltaPrs(i), deltaTilt(i), deltaCio(i), deltaHom(i), deltaTtt(i), esActionStr(i));
end

inputTable = table( ...
    coordGroup, phase10aSelected.oracle_group_id, ...
    cellstr(scenarios), realizations, cellstr(modules), modulePriority, ...
    sources, targets, ...
    sources, targets, ...
    phase10aSelected.selected_action_id_safe, cellstr(actionTypes), ...
    phase10aSelected.safe_selected_safety_valid, phase10aSelected.fallback_used, ...
    phase10aSelected.noop_selected, phase10aSelected.safety_enforced_regret, ...
    phase10aSelected.safe_predicted_reward, phase10aSelected.safe_true_reward, ...
    deltaPrs, deltaTilt, deltaCio, deltaHom, deltaTtt, cellstr(esActionStr), ...
    coordinatorAffectedSector, applicationAffectedSector, ...
    cellstr(applicationStateVariable), cellstr(affectedParameter), cellstr(actionScope), ...
    'VariableNames', {'coordinator_group_id','oracle_group_id', ...
    'scenario_name','realization_id','module_name','module_priority', ...
    'decision_source_sector_id','decision_target_sector_id', ...
    'source_sector_id','target_sector_id', ...
    'selected_action_id_safe','safe_action_type', ...
    'safe_selected_safety_valid','fallback_used','noop_selected', ...
    'safety_enforced_regret','predicted_reward','true_reward', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms','es_action', ...
    'coordinator_affected_sector_id','application_affected_sector_id', ...
    'application_state_variable','affected_parameter','action_scope'});

% Backward-compatible alias. New duplicate/conflict checks must use
% application_affected_sector_id + application_state_variable.
inputTable.affected_sector_id = inputTable.coordinator_affected_sector_id;

uniqueTicks = uniqueTicks; %#ok<ASGSL,NASGU>
end

function [coordSector, paramStr, scope, appSector, appVar] = classify_action(module, actionType, src, tgt, dPrs, dTilt, dCio, dHom, dTtt, esStr)
paramStr = "";
scope = "no_op";
appVar = "";
coordSector = 0;
appSector = 0;
switch module
    case "COC/OH"
        if actionType == "compensate_neighbor"
            coordSector = tgt;
            appSector = tgt;
            params = strings(1, 0);
            vars = strings(1, 0);
            if dPrs ~= 0, params(end+1) = "RS_power"; vars(end+1) = "sectors.referencePowerOffset_dB"; end
            if dTilt ~= 0, params(end+1) = "tilt"; vars(end+1) = "sectors.electricalTilt_deg"; end
            if dCio ~= 0, params(end+1) = "CIO"; vars(end+1) = "sectors.cio_dB"; end
            if isempty(params), params(end+1) = "none"; end
            if isempty(vars), vars(end+1) = "none"; end
            paramStr = strjoin(params, '|');
            appVar = strjoin(vars, '|');
            scope = "source_neighbor";
        end
    case "LB/MLB"
        if actionType == "cio_bias_to_neighbor"
            coordSector = src;
            appSector = tgt;
            paramStr = "CIO_bias";
            appVar = "sectors.cio_dB";
            scope = "source_neighbor";
        end
    case "HO/MRO"
        if actionType == "handover_parameter_adjustment"
            coordSector = src;
            appSector = src;
            params = strings(1, 0);
            vars = strings(1, 0);
            if dHom ~= 0, params(end+1) = "HOM"; vars(end+1) = "sectors.hom_offset_dB"; end
            if dTtt ~= 0, params(end+1) = "TTT"; vars(end+1) = "sectors.ttt_offset_ms"; end
            if dCio ~= 0
                params(end+1) = "CIO";
                vars(end+1) = "sectors.cio_dB";
                appSector = tgt;
            end
            if isempty(params), params(end+1) = "none"; end
            if isempty(vars), vars(end+1) = "none"; end
            paramStr = strjoin(params, '|');
            appVar = strjoin(vars, '|');
            scope = "source_neighbor";
        end
    case "ES"
        if esStr == "sleep" || esStr == "wake_up"
            coordSector = src;
            appSector = src;
            paramStr = "ES_state";
            appVar = "sectors.is_sleeping";
            scope = "source_only";
        elseif esStr == "keep_active"
            coordSector = src;
            appSector = src;
            paramStr = "none";
            appVar = "none";
            scope = "no_op";
        end
end
if actionType == "no_op"
    coordSector = 0;
    appSector = 0;
    paramStr = "none";
    appVar = "none";
    scope = "no_op";
end
if paramStr == "", paramStr = "none"; end
if appVar == "", appVar = "none"; end
end

function v = pull_col(T, name)
if ismember(name, T.Properties.VariableNames)
    v = double(T.(name));
    v(~isfinite(v)) = 0;
else
    v = zeros(height(T), 1);
end
end

function s = pull_string_col(T, name)
if ismember(name, T.Properties.VariableNames)
    s = string(T.(name));
    s(ismissing(s)) = "";
else
    s = strings(height(T), 1);
end
end

function T = build_empty_input_table()
T = table('Size', [0 31], ...
    'VariableTypes', {'double','double','cell','double','cell','double', ...
    'double','double','double','double','double','cell','logical','logical','logical', ...
    'double','double','double','double','double','double','double','double','cell', ...
    'double','double','cell','cell','cell','double'}, ...
    'VariableNames', {'coordinator_group_id','oracle_group_id', ...
    'scenario_name','realization_id','module_name','module_priority', ...
    'decision_source_sector_id','decision_target_sector_id', ...
    'source_sector_id','target_sector_id', ...
    'selected_action_id_safe','safe_action_type', ...
    'safe_selected_safety_valid','fallback_used','noop_selected', ...
    'safety_enforced_regret','predicted_reward','true_reward', ...
    'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms','es_action', ...
    'coordinator_affected_sector_id','application_affected_sector_id', ...
    'application_state_variable','affected_parameter','action_scope','affected_sector_id'});
end
