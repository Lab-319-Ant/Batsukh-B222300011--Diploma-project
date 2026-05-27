function leakageAudit = audit_feature_leakage(cfg, clusteringTable, codTable, tpqpTable, featureSets)
%AUDIT_FEATURE_LEAKAGE Check Phase 4B prepared tables for forbidden inputs.
%
% Two leakage modes are flagged:
%  1) Forbidden direct-label/metadata column used as input.
%  2) The same column listed as both input and target in a feature set
%     (input == target self-leakage).

rows = {};
rows = audit_one_table(rows, clusteringTable, featureSets.clustering.tableName, ...
    featureSets.clustering, featureSets.forbiddenInputColumns);
rows = audit_one_table(rows, codTable, featureSets.cod.tableName, ...
    featureSets.cod, featureSets.forbiddenInputColumns);
rows = audit_one_table(rows, tpqpTable, featureSets.tpqp.tableName, ...
    featureSets.tpqp, featureSets.forbiddenInputColumns);

rows = audit_input_target_overlap(rows, featureSets.clustering);
rows = audit_input_target_overlap(rows, featureSets.cod);
rows = audit_input_target_overlap(rows, featureSets.tpqp);

leakageAudit = cell2table(rows, 'VariableNames', ...
    {'table_name','column_name','role','leakage_risk','allowed_as_input','notes'});
writetable(leakageAudit, fullfile(cfg.tablesDir, 'phase4b_feature_leakage_audit.csv'));
end

function rows = audit_one_table(rows, tbl, tableName, tableSet, forbiddenColumns)
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    columnName = vars{i};
    isInput = any(strcmp(columnName, tableSet.inputs));
    isTarget = any(strcmp(columnName, tableSet.targets));
    isMetadata = any(strcmp(columnName, tableSet.metadata));
    isForbidden = any(strcmp(columnName, forbiddenColumns));

    if isInput
        role = 'input_feature';
    elseif isTarget
        role = 'target_label';
    elseif isMetadata
        role = 'metadata';
    else
        role = 'diagnostic_only';
    end

    leakageRisk = isInput && isForbidden;
    allowedAsInput = isInput && ~isForbidden;
    if leakageRisk
        notes = 'Forbidden leakage column is incorrectly included as an input feature.';
    elseif isForbidden
        notes = 'Forbidden as ML input; retained only as metadata or target if present.';
    elseif isInput
        notes = 'Allowed KPI-derived input feature.';
    else
        notes = 'Excluded from input feature matrix.';
    end

    rows(end+1, :) = {tableName, columnName, role, leakageRisk, allowedAsInput, notes}; %#ok<AGROW>
end
end

function rows = audit_input_target_overlap(rows, tableSet)
overlap = intersect(tableSet.inputs, tableSet.targets);
if isempty(overlap)
    rows(end+1, :) = {tableSet.tableName, '__inputs_target_overlap__', 'audit_check', false, false, ...
        'inputs and targets are disjoint.'}; %#ok<AGROW>
    return;
end
for k = 1:numel(overlap)
    rows(end+1, :) = {tableSet.tableName, overlap{k}, 'input_and_target_self_leakage', true, false, ...
        'Column is listed as both input and target; forbidden self-leakage.'}; %#ok<AGROW>
end
end
