function sectorState = build_sector_state_table(planRow, topologyScenario, sectorKpiTable)
%BUILD_SECTOR_STATE_TABLE Add Phase 4 scenario labels to sector KPI rows.

numRows = height(sectorKpiTable);
sectorState = sectorKpiTable;

sectorState = addvars(sectorState, ...
    repmat(planRow.dataset_id, numRows, 1), ...
    repmat(planRow.scenario_id, numRows, 1), ...
    repmat(planRow.realization_id, numRows, 1), ...
    repmat(planRow.scenario_name, numRows, 1), ...
    repmat(planRow.traffic_mode, numRows, 1), ...
    repmat(planRow.impaired_sector_id, numRows, 1), ...
    repmat(planRow.impaired_sector_status, numRows, 1), ...
    'Before', 1, ...
    'NewVariableNames', {'dataset_id','scenario_id','realization_id','scenario_name', ...
    'traffic_mode','impaired_sector_id','impaired_sector_status'});

sectorState.is_target_impaired_sector = sectorState.sector_id == planRow.impaired_sector_id;
sectorState.outage_label = strcmp(sectorState.impaired_sector_status, 'outage') & sectorState.is_target_impaired_sector;
sectorState.degraded_label = strcmp(sectorState.impaired_sector_status, 'degraded') & sectorState.is_target_impaired_sector;

if ismember('referencePowerOffset_dB', topologyScenario.sectors.Properties.VariableNames)
    sectorState.referencePowerOffset_dB = topologyScenario.sectors.referencePowerOffset_dB;
else
    sectorState.referencePowerOffset_dB = zeros(numRows, 1);
end

if ismember('txPowerOffset_dB', topologyScenario.sectors.Properties.VariableNames)
    sectorState.txPowerOffset_dB = topologyScenario.sectors.txPowerOffset_dB;
else
    sectorState.txPowerOffset_dB = zeros(numRows, 1);
end
end
