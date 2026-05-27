function [cfgScenario, topologyScenario] = apply_scenario_to_network(cfg, topology, scenario)
%APPLY_SCENARIO_TO_NETWORK Apply traffic mode and sector impairment settings.

cfgScenario = cfg;
cfgScenario.trafficMode = scenario.traffic_mode;
cfgScenario.scenario_id = scenario.scenario_id;
cfgScenario.scenario_name = scenario.scenario_name;

topologyScenario = topology;
topologyScenario.sectors = ensure_scenario_columns(topologyScenario.sectors);

if scenario.impaired_sector_id > 0
    rowIdx = topologyScenario.sectors.sectorId == scenario.impaired_sector_id;
    if ~any(rowIdx)
        error('Scenario %s refers to missing sectorId %d.', ...
            scenario.scenario_name, scenario.impaired_sector_id);
    end

    topologyScenario.sectors.sector_status(rowIdx) = {scenario.impaired_sector_status};
    topologyScenario.sectors.status(rowIdx) = {scenario.impaired_sector_status};
    topologyScenario.sectors.referencePowerOffset_dB(rowIdx) = scenario.referencePowerOffset_dB;
    topologyScenario.sectors.txPowerOffset_dB(rowIdx) = scenario.txPowerOffset_dB;
    topologyScenario.sectors.is_impaired(rowIdx) = true;
end
end

function sectors = ensure_scenario_columns(sectors)
numSectors = height(sectors);

if ~ismember('sector_status', sectors.Properties.VariableNames)
    if ismember('status', sectors.Properties.VariableNames)
        sectors.sector_status = sectors.status;
    else
        sectors.sector_status = repmat({'normal'}, numSectors, 1);
    end
end

if ~ismember('referencePowerOffset_dB', sectors.Properties.VariableNames)
    sectors.referencePowerOffset_dB = zeros(numSectors, 1);
end

if ~ismember('txPowerOffset_dB', sectors.Properties.VariableNames)
    sectors.txPowerOffset_dB = zeros(numSectors, 1);
end

if ~ismember('is_impaired', sectors.Properties.VariableNames)
    sectors.is_impaired = false(numSectors, 1);
end

if ~ismember('es_candidate', sectors.Properties.VariableNames)
    sectors.es_candidate = false(numSectors, 1);
end
end
