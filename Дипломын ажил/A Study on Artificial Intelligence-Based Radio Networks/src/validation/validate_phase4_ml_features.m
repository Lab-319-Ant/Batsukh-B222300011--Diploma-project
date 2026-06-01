function validationTable = validate_phase4_ml_features(cfg, clusteringTable, codTable, tpqpTable, featureDictionary, leakageAudit, featureSets)
%VALIDATE_PHASE4_ML_FEATURES Validate Phase 4B leakage-controlled tables.

rows = {};
rows = validate_input_block(rows, 'clustering', clusteringTable, featureSets.clustering.inputs);
rows = validate_input_block(rows, 'cod', codTable, featureSets.cod.inputs);
rows = validate_input_block(rows, 'tp_qp', tpqpTable, featureSets.tpqp.inputs);

codLabels = categorical(codTable.cod_label);
codCounts = groupcounts(codLabels);
hasNormal = any(codLabels == 'normal');
hasImpaired = any(codLabels == 'degraded') || any(codLabels == 'outage');
rows = add_check(rows, 'cod_label_distribution_nonempty', 'error', ...
    ~isempty(codCounts), sprintf('%d labels', numel(codLabels)), ...
    'COD label vector must not be empty.', '');
rows = add_check(rows, 'cod_has_normal_and_impaired_examples', 'error', ...
    hasNormal && hasImpaired, sprintf('normal=%d impaired=%d', sum(codLabels == 'normal'), sum(codLabels ~= 'normal')), ...
    'COD table must contain normal and impaired sector examples.', '');

clusterForbiddenInputs = intersect(featureSets.clustering.inputs, featureSets.forbiddenInputColumns);
rows = add_check(rows, 'clustering_inputs_exclude_direct_labels', 'error', ...
    isempty(clusterForbiddenInputs), strjoin(clusterForbiddenInputs, ', '), ...
    'Clustering input list must exclude scenario labels and direct status flags.', '');

rows = add_check(rows, 'tp_qp_target_available', 'error', ...
    ismember('qos_satisfaction_ratio_active', tpqpTable.Properties.VariableNames), ...
    join_value(ismember('qos_satisfaction_ratio_active', tpqpTable.Properties.VariableNames)), ...
    'TP/QP table must include QoS prediction target.', '');

rows = validate_metadata(rows, 'clustering', clusteringTable, featureSets.clustering);
rows = validate_metadata(rows, 'cod', codTable, featureSets.cod);
rows = validate_metadata(rows, 'tp_qp', tpqpTable, featureSets.tpqp);

allPreparedColumns = [ ...
    strcat(featureSets.clustering.tableName, "::", clusteringTable.Properties.VariableNames), ...
    strcat(featureSets.cod.tableName, "::", codTable.Properties.VariableNames), ...
    strcat(featureSets.tpqp.tableName, "::", tpqpTable.Properties.VariableNames)];
dictColumns = strcat(featureDictionary.table_name, "::", featureDictionary.feature_name);
missingDictionaryColumns = setdiff(allPreparedColumns, dictColumns);
rows = add_check(rows, 'feature_dictionary_covers_prepared_columns', 'error', ...
    isempty(missingDictionaryColumns), sprintf('%d missing', numel(missingDictionaryColumns)), ...
    'Feature dictionary must include every column from prepared Phase 4B tables.', ...
    strjoin(missingDictionaryColumns, ', '));

leakageRiskCount = sum(leakageAudit.leakage_risk);
rows = add_check(rows, 'leakage_audit_no_forbidden_inputs', 'error', ...
    leakageRiskCount == 0, sprintf('%d leakage-risk input columns', leakageRiskCount), ...
    'Forbidden columns must not be listed as ML input features.', '');

overlapCluster = intersect(featureSets.clustering.inputs, featureSets.clustering.targets);
overlapCod = intersect(featureSets.cod.inputs, featureSets.cod.targets);
overlapTpqp = intersect(featureSets.tpqp.inputs, featureSets.tpqp.targets);
allOverlap = unique([overlapCluster(:); overlapCod(:); overlapTpqp(:)]);
rows = add_check(rows, 'feature_inputs_targets_disjoint', 'error', ...
    isempty(allOverlap), strjoin(allOverlap, ', '), ...
    'No column may appear in both input and target lists for any feature set.', '');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase4b_ml_feature_validation.csv'));
end

function rows = validate_input_block(rows, prefix, tbl, inputFeatures)
missing = setdiff(inputFeatures, tbl.Properties.VariableNames);
rows = add_check(rows, [prefix '_input_columns_present'], 'error', isempty(missing), ...
    sprintf('%d missing', numel(missing)), 'All selected input features must exist.', strjoin(missing, ', '));

if isempty(missing)
    inputTbl = tbl(:, inputFeatures);
    nonNumeric = {};
    missingCount = 0;
    infCount = 0;
    for i = 1:numel(inputFeatures)
        values = inputTbl.(inputFeatures{i});
        if ~(isnumeric(values) || islogical(values))
            nonNumeric{end+1} = inputFeatures{i}; %#ok<AGROW>
            continue;
        end
        values = double(values);
        missingCount = missingCount + sum(ismissing(values));
        infCount = infCount + sum(isinf(values));
    end

    rows = add_check(rows, [prefix '_inputs_numeric_only'], 'error', isempty(nonNumeric), ...
        strjoin(nonNumeric, ', '), 'Selected ML inputs must be numeric.', '');
    rows = add_check(rows, [prefix '_inputs_no_missing_values'], 'error', missingCount == 0, ...
        sprintf('%d missing values', missingCount), 'Selected ML inputs must not contain missing values.', '');
    rows = add_check(rows, [prefix '_inputs_no_infinite_values'], 'error', infCount == 0, ...
        sprintf('%d infinite values', infCount), 'Selected ML inputs must not contain infinite values.', '');
end
end

function rows = validate_metadata(rows, prefix, tbl, tableSet)
missingMetadata = setdiff(tableSet.metadata, tbl.Properties.VariableNames);
metadataInInputs = intersect(tableSet.metadata, tableSet.inputs);
rows = add_check(rows, [prefix '_metadata_present'], 'warning', isempty(missingMetadata), ...
    sprintf('%d missing metadata columns', numel(missingMetadata)), ...
    'Traceability metadata should be present.', strjoin(missingMetadata, ', '));
rows = add_check(rows, [prefix '_metadata_excluded_from_inputs'], 'error', isempty(metadataInInputs), ...
    strjoin(metadataInInputs, ', '), 'Metadata columns must be excluded from selected input features.', '');
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function value = join_value(x)
if x
    value = 'present';
else
    value = 'missing';
end
end
