function validationTable = validate_phase7_temporal_dataset(cfg, sectorTemporal, networkTemporal, featureTable, sectorFeatureTable, sectorFeatureDictionary)
%VALIDATE_PHASE7_TEMPORAL_DATASET Validate temporal TP/QP dataset integrity.

rows = {};
expectedNetworkRows = numel(cfg.phase7ScenarioTypes) * cfg.phase7TimeStepsPerDay * cfg.phase7NumDays;
expectedSectorRows = expectedNetworkRows * 21;
expectedFeatureRows = numel(cfg.phase7ScenarioTypes) * ...
    (cfg.phase7TimeStepsPerDay * cfg.phase7NumDays - max(cfg.phase7LagSteps) - cfg.phase7PredictionHorizonSteps);
expectedSectorFeatureRows = expectedFeatureRows * 21;

rows = add_check(rows, 'network_temporal_row_count', 'error', height(networkTemporal) == expectedNetworkRows, ...
    sprintf('%d rows', height(networkTemporal)), sprintf('%d expected rows', expectedNetworkRows), '');
rows = add_check(rows, 'sector_temporal_row_count', 'error', height(sectorTemporal) == expectedSectorRows, ...
    sprintf('%d rows', height(sectorTemporal)), sprintf('%d expected rows', expectedSectorRows), '');
rows = add_check(rows, 'tp_qp_feature_row_count', 'error', height(featureTable) == expectedFeatureRows, ...
    sprintf('%d rows', height(featureTable)), sprintf('%d expected rows', expectedFeatureRows), '');
rows = add_check(rows, 'sector_lag_feature_table_exists', 'error', height(sectorFeatureTable) > 0, ...
    sprintf('%d rows', height(sectorFeatureTable)), 'Sector-level lag feature table must exist.', '');
rows = add_check(rows, 'sector_lag_feature_row_count', 'error', height(sectorFeatureTable) == expectedSectorFeatureRows, ...
    sprintf('%d rows', height(sectorFeatureTable)), sprintf('%d expected rows', expectedSectorFeatureRows), '');

targetColumns = {'target_next_total_offered_traffic_Mbps','target_next_total_served_traffic_Mbps', ...
    'target_next_mean_sector_load','target_next_qos_satisfaction_ratio','target_next_mean_ue_throughput_Mbps'};
rows = add_check(rows, 'future_targets_exist', 'error', all(ismember(targetColumns, featureTable.Properties.VariableNames)), ...
    sprintf('%d/%d targets found', sum(ismember(targetColumns, featureTable.Properties.VariableNames)), numel(targetColumns)), ...
    'TP/QP future target columns must exist.', '');

targetInInputs = any(startsWith(featureTable.Properties.VariableNames, 'target_') & ...
    ~ismember(featureTable.Properties.VariableNames, targetColumns));
rows = add_check(rows, 'no_unexpected_future_target_columns', 'error', ~targetInInputs, ...
    join_flag(~targetInInputs), 'Unexpected target-like columns should not appear as inputs.', '');

numericMissing = count_missing_numeric(featureTable);
numericInf = count_infinite_numeric(featureTable);
rows = add_check(rows, 'feature_table_no_missing_numeric', 'error', numericMissing == 0, ...
    sprintf('%d missing numeric values', numericMissing), 'Numeric temporal feature/target values must not be missing.', '');
rows = add_check(rows, 'feature_table_no_infinite_numeric', 'error', numericInf == 0, ...
    sprintf('%d infinite numeric values', numericInf), 'Numeric temporal feature/target values must not be infinite.', '');

scenarioCounts = groupcounts(categorical(networkTemporal.scenario_name));
rows = add_check(rows, 'balanced_time_rows_by_scenario', 'error', ...
    all(scenarioCounts == cfg.phase7TimeStepsPerDay * cfg.phase7NumDays), ...
    sprintf('min=%d max=%d', min(scenarioCounts), max(scenarioCounts)), ...
    'Each Phase 7 scenario must have the same number of time rows.', '');

hasVariation = std(networkTemporal.total_offered_traffic_Mbps) > 0;
rows = add_check(rows, 'time_varying_traffic_exists', 'error', hasVariation, ...
    sprintf('std offered=%.3f', std(networkTemporal.total_offered_traffic_Mbps)), ...
    'Temporal offered traffic must vary across time.', '');

sectorTargets = {'next_offered_traffic_Mbps','next_sector_load_ratio', ...
    'next_qos_satisfaction_ratio','next_mean_UE_throughput_Mbps','next_served_traffic_Mbps'};
rows = add_check(rows, 'sector_target_columns_exist', 'error', ...
    all(ismember(sectorTargets, sectorFeatureTable.Properties.VariableNames)), ...
    sprintf('%d/%d targets found', sum(ismember(sectorTargets, sectorFeatureTable.Properties.VariableNames)), numel(sectorTargets)), ...
    'Sector-level next-step target columns must exist.', '');

inputRows = sectorFeatureDictionary(strcmp(sectorFeatureDictionary.role, 'input_feature_candidate'), :);
targetMarkedInput = any(startsWith(inputRows.column_name, 'next_'));
rows = add_check(rows, 'sector_next_targets_not_inputs', 'error', ~targetMarkedInput, ...
    join_flag(~targetMarkedInput), 'Sector-level next_* target columns must not be input features.', '');

scenarioMetaOnly = all(strcmp(sectorFeatureDictionary.role(strcmp(sectorFeatureDictionary.column_name, 'scenario_name')), 'metadata'));
rows = add_check(rows, 'sector_scenario_name_metadata_only', 'error', scenarioMetaOnly, ...
    join_flag(scenarioMetaOnly), 'scenario_name must be metadata only.', '');

siteSectorMetaOnly = all(strcmp(sectorFeatureDictionary.role(ismember(sectorFeatureDictionary.column_name, {'site_id','sector_id'})), 'metadata'));
rows = add_check(rows, 'sector_site_sector_metadata_only', 'error', siteSectorMetaOnly, ...
    join_flag(siteSectorMetaOnly), 'site_id and sector_id must be metadata only unless explicitly used later.', '');

sectorInputMissing = count_missing_selected(sectorFeatureTable, inputRows.column_name);
sectorInputInf = count_infinite_selected(sectorFeatureTable, inputRows.column_name);
rows = add_check(rows, 'sector_lag_inputs_no_missing', 'error', sectorInputMissing == 0, ...
    sprintf('%d missing values', sectorInputMissing), 'Sector-level lag input candidates must not contain missing values.', '');
rows = add_check(rows, 'sector_lag_inputs_no_infinite', 'error', sectorInputInf == 0, ...
    sprintf('%d infinite values', sectorInputInf), 'Sector-level lag input candidates must not contain infinite values.', '');

timeOrderingValid = validate_sector_time_ordering(sectorFeatureTable);
rows = add_check(rows, 'sector_group_time_ordering_valid', 'error', timeOrderingValid, ...
    join_flag(timeOrderingValid), 'Time ordering must be valid within each scenario-sector group.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase7a_dataset_validation.csv'));
end

function n = count_missing_selected(tbl, vars)
n = 0;
for i = 1:numel(vars)
    values = tbl.(vars{i});
    if isnumeric(values) || islogical(values)
        n = n + sum(ismissing(values));
    end
end
end

function n = count_infinite_selected(tbl, vars)
n = 0;
for i = 1:numel(vars)
    values = tbl.(vars{i});
    if isnumeric(values) || islogical(values)
        n = n + sum(isinf(double(values)));
    end
end
end

function isValid = validate_sector_time_ordering(tbl)
isValid = true;
scenarioNames = unique(tbl.scenario_name, 'stable');
for s = 1:numel(scenarioNames)
    sectorIds = unique(tbl.sector_id(strcmp(tbl.scenario_name, scenarioNames{s})));
    for sec = sectorIds(:)'
        idx = strcmp(tbl.scenario_name, scenarioNames{s}) & tbl.sector_id == sec;
        t = tbl.time_step(idx);
        if any(diff(t) <= 0)
            isValid = false;
            return;
        end
    end
end
end

function n = count_missing_numeric(tbl)
n = 0;
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    values = tbl.(vars{i});
    if isnumeric(values) || islogical(values)
        n = n + sum(ismissing(values));
    end
end
end

function n = count_infinite_numeric(tbl)
n = 0;
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    values = tbl.(vars{i});
    if isnumeric(values) || islogical(values)
        n = n + sum(isinf(double(values)));
    end
end
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function value = join_flag(flag)
if flag
    value = 'true';
else
    value = 'false';
end
end
