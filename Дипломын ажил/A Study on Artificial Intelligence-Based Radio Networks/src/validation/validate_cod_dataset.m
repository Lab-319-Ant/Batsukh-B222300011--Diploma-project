function validationTable = validate_cod_dataset(cfg, codTable, featureList, inputFeatures)
%VALIDATE_COD_DATASET Validate Phase 6A balanced COD dataset.

rows = {};
minRequiredCount = min(150, cfg.phase6NumCODRealizationsPerClass);
forbiddenColumns = {'scenario_id','scenario_name','scenario_label','traffic_mode', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB', ...
    'outage_flag','degradation_flag','cod_label'};

rows = add_check(rows, 'cod_dataset_exists_in_memory', 'error', height(codTable) > 0, ...
    sprintf('%d rows', height(codTable)), 'Balanced COD dataset must contain rows.', '');

labels = categorical(codTable.cod_label, {'normal','degraded','outage'});
counts = [sum(labels == 'normal'), sum(labels == 'degraded'), sum(labels == 'outage')];
rows = add_check(rows, 'cod_labels_include_all_classes', 'error', all(counts > 0), ...
    sprintf('normal=%d degraded=%d outage=%d', counts(1), counts(2), counts(3)), ...
    'COD labels must include normal, degraded, and outage.', '');
rows = add_check(rows, 'cod_each_class_minimum_count', 'error', all(counts >= minRequiredCount), ...
    sprintf('normal=%d degraded=%d outage=%d', counts(1), counts(2), counts(3)), ...
    sprintf('Each COD class must have at least %d rows.', minRequiredCount), '');
imbalanceRatio = max(counts) / max(min(counts), 1);
rows = add_check(rows, 'cod_class_imbalance_ratio', 'error', imbalanceRatio <= 3.0, ...
    sprintf('%.3f', imbalanceRatio), 'max_count / min_count must be <= 3.0.', '');

forbiddenInputs = intersect(inputFeatures, forbiddenColumns);
rows = add_check(rows, 'cod_inputs_no_forbidden_leakage', 'error', isempty(forbiddenInputs), ...
    strjoin(forbiddenInputs, ', '), 'Forbidden leakage columns must not be COD input features.', '');

rows = validate_input_features(rows, codTable, inputFeatures);

rows = add_check(rows, 'cod_label_excluded_from_inputs', 'error', ~any(strcmp(inputFeatures, 'cod_label')), ...
    join_flag(any(strcmp(inputFeatures, 'cod_label'))), 'cod_label must not be included in input features.', '');

metadataColumns = {'realization_id','scenario_name','site_id','sector_id','impaired_sector_id'};
missingMetadata = setdiff(metadataColumns, codTable.Properties.VariableNames);
metadataInInputs = intersect(metadataColumns, inputFeatures);
rows = add_check(rows, 'cod_metadata_present', 'error', isempty(missingMetadata), ...
    strjoin(missingMetadata, ', '), 'Traceability metadata columns must be present.', '');
rows = add_check(rows, 'cod_metadata_excluded_from_inputs', 'error', isempty(metadataInInputs), ...
    strjoin(metadataInInputs, ', '), 'Metadata columns must be excluded from COD inputs.', '');

degradedRowsValid = all(strcmp(string(codTable.scenario_name(labels == 'degraded')), 'degraded_sector') & ...
    codTable.sector_id(labels == 'degraded') == codTable.impaired_sector_id(labels == 'degraded'));
outageRowsValid = all(strcmp(string(codTable.scenario_name(labels == 'outage')), 'outage_sector') & ...
    codTable.sector_id(labels == 'outage') == codTable.impaired_sector_id(labels == 'outage'));
normalRowsValid = all(labels ~= 'normal' | codTable.sector_id ~= codTable.impaired_sector_id | codTable.impaired_sector_id == 0);

rows = add_check(rows, 'degraded_labels_from_impaired_sector_rows', 'error', degradedRowsValid, ...
    join_flag(degradedRowsValid), 'Degraded labels must come only from impaired degraded-sector rows.', '');
rows = add_check(rows, 'outage_labels_from_impaired_sector_rows', 'error', outageRowsValid, ...
    join_flag(outageRowsValid), 'Outage labels must come only from impaired outage-sector rows.', '');
rows = add_check(rows, 'normal_rows_not_impaired_labels', 'error', normalRowsValid, ...
    join_flag(normalRowsValid), 'Normal rows must not be impaired-sector labels.', '');

allowedInputRows = featureList(strcmp(featureList.role, 'input_feature'), :);
rows = add_check(rows, 'feature_list_matches_input_features', 'error', ...
    isempty(setxor(allowedInputRows.feature_name, inputFeatures')), ...
    sprintf('%d feature-list inputs', height(allowedInputRows)), ...
    'Feature-list input rows must match the selected COD input features.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase6a_cod_dataset_validation.csv'));
end

function rows = validate_input_features(rows, codTable, inputFeatures)
missing = setdiff(inputFeatures, codTable.Properties.VariableNames);
rows = add_check(rows, 'cod_input_columns_present', 'error', isempty(missing), ...
    strjoin(missing, ', '), 'All COD input features must exist.', '');
if ~isempty(missing)
    return;
end

nonNumeric = {};
missingCount = 0;
infCount = 0;
for i = 1:numel(inputFeatures)
    values = codTable.(inputFeatures{i});
    if ~(isnumeric(values) || islogical(values))
        nonNumeric{end+1} = inputFeatures{i}; %#ok<AGROW>
        continue;
    end
    values = double(values);
    missingCount = missingCount + sum(ismissing(values));
    infCount = infCount + sum(isinf(values));
end
rows = add_check(rows, 'cod_inputs_numeric_only', 'error', isempty(nonNumeric), ...
    strjoin(nonNumeric, ', '), 'All COD input features must be numeric.', '');
rows = add_check(rows, 'cod_inputs_no_missing_values', 'error', missingCount == 0, ...
    sprintf('%d missing values', missingCount), 'COD input features must not contain missing values.', '');
rows = add_check(rows, 'cod_inputs_no_infinite_values', 'error', infCount == 0, ...
    sprintf('%d infinite values', infCount), 'COD input features must not contain infinite values.', '');
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
