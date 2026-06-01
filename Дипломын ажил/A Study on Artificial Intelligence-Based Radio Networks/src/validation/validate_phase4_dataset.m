function validationTable = validate_phase4_dataset(cfg, sectorStateDataset, networkStateDataset, scenarioPlan)
%VALIDATE_PHASE4_DATASET Basic integrity checks for Phase 4 KPI datasets.

rows = {};

expectedNetworkRows = numel(cfg.phase4ScenarioTypes) * cfg.phase4NumRealizationsPerScenario;
expectedSectorRows = expectedNetworkRows * 21;

rows = add_check(rows, 'network_row_count', 'network rows match scenario plan', ...
    height(networkStateDataset), expectedNetworkRows, height(networkStateDataset) == expectedNetworkRows, '');

rows = add_check(rows, 'sector_row_count', 'sector rows = network rows * 21', ...
    height(sectorStateDataset), expectedSectorRows, height(sectorStateDataset) == expectedSectorRows, '');

rows = add_check(rows, 'scenario_plan_row_count', 'scenario plan rows match expected rows', ...
    height(scenarioPlan), expectedNetworkRows, height(scenarioPlan) == expectedNetworkRows, '');

rows = add_check(rows, 'no_missing_network_values', 'numeric network KPI columns contain no missing values', ...
    count_missing_numeric(networkStateDataset), 0, count_missing_numeric(networkStateDataset) == 0, '');

allowedSectorNaN = {'mean_RSRP_dBm','median_RSRP_dBm','mean_SINR_dB','median_SINR_dB', ...
    'mean_UE_throughput_Mbps','median_UE_throughput_Mbps','qos_satisfaction_ratio'};
missingRequiredSectorValues = count_missing_numeric_excluding(sectorStateDataset, allowedSectorNaN);
rows = add_check(rows, 'no_missing_required_sector_values', ...
    'required numeric sector columns contain no missing values; NaN is allowed for undefined per-sector means/medians', ...
    missingRequiredSectorValues, 0, missingRequiredSectorValues == 0, ...
    'Undefined means/medians are expected when a sector has no attached or active UEs.');

scenarioCounts = groupcounts(categorical(networkStateDataset.scenario_name));
rows = add_check(rows, 'balanced_scenario_counts', 'each scenario has configured number of realizations', ...
    min(scenarioCounts), cfg.phase4NumRealizationsPerScenario, ...
    all(scenarioCounts == cfg.phase4NumRealizationsPerScenario), '');

hasHeavyCollapse = any(strcmp(networkStateDataset.scenario_name, 'heavy_overload')) || ...
    any(strcmp(networkStateDataset.traffic_mode, 'heavy_overload'));
rows = add_check(rows, 'no_heavy_overload_in_phase4', 'heavy_overload is not part of Phase 4 scenario set', ...
    double(hasHeavyCollapse), 0, ~hasHeavyCollapse, '');

normalRows = strcmp(networkStateDataset.scenario_name, 'normal');
overloadRows = strcmp(networkStateDataset.scenario_name, 'overload');
lowLoadRows = strcmp(networkStateDataset.scenario_name, 'low_load');
handoverRows = strcmp(networkStateDataset.scenario_name, 'handover_stress');
esRows = strcmp(networkStateDataset.scenario_name, 'low_load_energy_saving_candidate');
outageRows = strcmp(networkStateDataset.scenario_name, 'outage_sector');

rows = add_check(rows, 'low_load_below_normal_load', 'mean low_load load < mean normal load', ...
    mean(networkStateDataset.mean_sector_load(lowLoadRows), 'omitnan'), ...
    mean(networkStateDataset.mean_sector_load(normalRows), 'omitnan'), ...
    mean(networkStateDataset.mean_sector_load(lowLoadRows), 'omitnan') < mean(networkStateDataset.mean_sector_load(normalRows), 'omitnan'), '');

rows = add_check(rows, 'normal_qos_above_overload_qos', 'mean normal QoS > mean overload QoS', ...
    mean(networkStateDataset.qos_satisfaction_ratio(normalRows), 'omitnan'), ...
    mean(networkStateDataset.qos_satisfaction_ratio(overloadRows), 'omitnan'), ...
    mean(networkStateDataset.qos_satisfaction_ratio(normalRows), 'omitnan') > mean(networkStateDataset.qos_satisfaction_ratio(overloadRows), 'omitnan'), '');

rows = add_check(rows, 'overload_count_above_normal', 'mean overload overloaded sector count > normal', ...
    mean(networkStateDataset.overloaded_sector_count(overloadRows), 'omitnan'), ...
    mean(networkStateDataset.overloaded_sector_count(normalRows), 'omitnan'), ...
    mean(networkStateDataset.overloaded_sector_count(overloadRows), 'omitnan') > mean(networkStateDataset.overloaded_sector_count(normalRows), 'omitnan'), '');

rows = add_check(rows, 'handover_risk_above_normal', 'mean handover_stress risk > mean normal risk', ...
    mean(networkStateDataset.handover_risk_score(handoverRows), 'omitnan'), ...
    mean(networkStateDataset.handover_risk_score(normalRows), 'omitnan'), ...
    mean(networkStateDataset.handover_risk_score(handoverRows), 'omitnan') > mean(networkStateDataset.handover_risk_score(normalRows), 'omitnan'), '');

rows = add_check(rows, 'energy_saving_candidates_exist', 'ES candidate scenario has at least one candidate sector on average', ...
    mean(networkStateDataset.es_candidate_sector_count(esRows), 'omitnan'), 0, ...
    mean(networkStateDataset.es_candidate_sector_count(esRows), 'omitnan') > 0, '');

rows = add_check(rows, 'outage_attach_not_above_normal', 'mean outage attach rate <= mean normal attach rate', ...
    mean(networkStateDataset.attach_rate(outageRows), 'omitnan'), ...
    mean(networkStateDataset.attach_rate(normalRows), 'omitnan'), ...
    mean(networkStateDataset.attach_rate(outageRows), 'omitnan') <= mean(networkStateDataset.attach_rate(normalRows), 'omitnan'), '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','expected_condition','actual_value','reference_value','pass_flag','notes'});

writetable(validationTable, fullfile(cfg.tablesDir, 'phase4_dataset_validation.csv'));
end

function nMissing = count_missing_numeric(tbl)
nMissing = count_missing_numeric_excluding(tbl, {});
end

function nMissing = count_missing_numeric_excluding(tbl, excludeNames)
nMissing = 0;
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    name = vars{i};
    if any(strcmp(name, excludeNames))
        continue;
    end
    values = tbl.(name);
    if isnumeric(values) || islogical(values)
        nMissing = nMissing + sum(ismissing(values));
    end
end
end

function rows = add_check(rows, checkName, expectedCondition, actualValue, referenceValue, passFlag, notes)
rows(end+1, :) = {checkName, expectedCondition, actualValue, referenceValue, logical(passFlag), notes}; %#ok<AGROW>
end
