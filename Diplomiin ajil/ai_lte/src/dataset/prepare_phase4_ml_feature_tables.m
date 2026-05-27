function [clusteringTable, codTable, tpqpTable, featureDictionary, featureSets] = ...
    prepare_phase4_ml_feature_tables(cfg, sectorStateDataset, networkStateDataset)
%PREPARE_PHASE4_ML_FEATURE_TABLES Build leakage-controlled Phase 4B tables.
%
% Phase 4B prepares feature tables only. It does not train clustering, COD,
% TP, QP, action-value models, oracle benchmarks, or closed-loop control.

featureSets = define_feature_sets();
sectorStateDataset = normalize_sector_state_columns(sectorStateDataset);
networkStateDataset = normalize_network_state_columns(networkStateDataset);

sectorStateDataset = impute_numeric_features(sectorStateDataset, ...
    unique([featureSets.clustering.inputs, featureSets.cod.inputs]));
networkStateDataset = impute_numeric_features(networkStateDataset, ...
    unique([featureSets.tpqp.inputs, featureSets.tpqp.targets]));

codLabels = build_cod_labels(sectorStateDataset);
sectorStateDataset.cod_label = codLabels;

clusteringColumns = [featureSets.clustering.metadata, featureSets.clustering.inputs];
codColumns = [featureSets.cod.metadata, featureSets.cod.inputs, featureSets.cod.targets];
tpqpColumns = [featureSets.tpqp.metadata, featureSets.tpqp.inputs, {'qos_satisfaction_ratio_active'}];

assert_required_columns(sectorStateDataset, clusteringColumns, 'sector clustering feature table');
assert_required_columns(sectorStateDataset, codColumns, 'COD feature table');
assert_required_columns(networkStateDataset, tpqpColumns, 'TP/QP network feature table');

clusteringTable = sectorStateDataset(:, clusteringColumns);
codTable = sectorStateDataset(:, codColumns);
tpqpTable = networkStateDataset(:, tpqpColumns);

featureDictionary = build_feature_dictionary(clusteringTable, codTable, tpqpTable, featureSets);

writetable(clusteringTable, fullfile(cfg.tablesDir, 'phase4b_sector_features_clustering.csv'));
writetable(codTable, fullfile(cfg.tablesDir, 'phase4b_sector_features_cod.csv'));
writetable(tpqpTable, fullfile(cfg.tablesDir, 'phase4b_network_features_tp_qp.csv'));
writetable(featureDictionary, fullfile(cfg.tablesDir, 'phase4b_feature_dictionary.csv'));
end

function tbl = normalize_sector_state_columns(tbl)
if ismember('is_target_impaired_sector', tbl.Properties.VariableNames) && ...
        ~ismember('is_impaired_sector', tbl.Properties.VariableNames)
    tbl.is_impaired_sector = tbl.is_target_impaired_sector;
end

if ~ismember('sector_status', tbl.Properties.VariableNames)
    status = repmat("normal", height(tbl), 1);
    if ismember('impaired_sector_status', tbl.Properties.VariableNames) && ...
            ismember('is_impaired_sector', tbl.Properties.VariableNames)
        isImpaired = logical(tbl.is_impaired_sector);
        status(isImpaired) = string(tbl.impaired_sector_status(isImpaired));
    end
    tbl.sector_status = cellstr(status);
end

if ~ismember('boundary_ue_ratio', tbl.Properties.VariableNames)
    tbl.boundary_ue_ratio = zeros(height(tbl), 1);
end
if ~ismember('handover_risk_score', tbl.Properties.VariableNames)
    tbl.handover_risk_score = tbl.boundary_ue_ratio;
end
if ~ismember('attach_rate_sector', tbl.Properties.VariableNames)
    tbl.attach_rate_sector = double(tbl.attached_ue_count > 0);
end
end

function tbl = normalize_network_state_columns(tbl)
if ~ismember('qos_satisfaction_ratio_active', tbl.Properties.VariableNames)
    tbl.qos_satisfaction_ratio_active = tbl.qos_satisfaction_ratio;
end
end

function tbl = impute_numeric_features(tbl, featureNames)
for i = 1:numel(featureNames)
    name = featureNames{i};
    if ~ismember(name, tbl.Properties.VariableNames)
        continue;
    end
    values = tbl.(name);
    if ~(isnumeric(values) || islogical(values))
        continue;
    end

    replacement = 0;
    if strcmp(name, 'qos_satisfaction_ratio')
        replacement = 1;
    elseif contains(name, 'RSRP')
        replacement = -125;
    elseif contains(name, 'SINR')
        replacement = -20;
    end

    values = double(values);
    values(ismissing(values) | isinf(values)) = replacement;
    tbl.(name) = values;
end
end

function codLabels = build_cod_labels(tbl)
codLabels = repmat("normal", height(tbl), 1);

isImpaired = false(height(tbl), 1);
if ismember('is_impaired_sector', tbl.Properties.VariableNames)
    isImpaired = logical(tbl.is_impaired_sector);
end

scenarioName = string(tbl.scenario_name);
sectorStatus = string(tbl.sector_status);

codLabels(scenarioName == "degraded_sector" & isImpaired) = "degraded";
codLabels(scenarioName == "outage_sector" & isImpaired) = "outage";

mixedImpaired = scenarioName == "mixed_conflict" & isImpaired;
codLabels(mixedImpaired & sectorStatus == "outage") = "outage";
codLabels(mixedImpaired & sectorStatus ~= "outage") = "degraded";

codLabels = categorical(codLabels, ["normal","degraded","outage"]);
end

function assert_required_columns(tbl, columns, contextName)
missing = setdiff(columns, tbl.Properties.VariableNames);
if ~isempty(missing)
    error('Phase4B:MissingColumns', '%s missing required columns: %s', ...
        contextName, strjoin(missing, ', '));
end
end

function dictionary = build_feature_dictionary(clusteringTable, codTable, tpqpTable, featureSets)
rows = {};
rows = append_table_dictionary(rows, clusteringTable, featureSets.clustering.tableName, ...
    featureSets.clustering, featureSets);
rows = append_table_dictionary(rows, codTable, featureSets.cod.tableName, ...
    featureSets.cod, featureSets);
rows = append_table_dictionary(rows, tpqpTable, featureSets.tpqp.tableName, ...
    featureSets.tpqp, featureSets);

dictionary = cell2table(rows, 'VariableNames', ...
    {'feature_name','table_name','feature_role','intended_module','reason'});
end

function rows = append_table_dictionary(rows, tbl, tableName, tableSet, featureSets)
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    name = vars{i};
    if any(strcmp(name, tableSet.inputs))
        role = 'input_feature';
        reason = 'Allowed KPI-derived input feature for this later module.';
    elseif any(strcmp(name, tableSet.targets))
        role = 'target_label';
        reason = 'Target or future target column; excluded from input matrix.';
    elseif any(strcmp(name, tableSet.metadata))
        role = 'metadata';
        if any(strcmp(name, featureSets.forbiddenInputColumns))
            reason = 'Traceability metadata only; forbidden as ML input.';
        else
            reason = 'Traceability metadata excluded from input matrix.';
        end
    elseif any(strcmp(name, featureSets.forbiddenInputColumns))
        role = 'forbidden_leakage';
        reason = 'Direct label, scenario, status, or impairment metadata; not allowed as input.';
    else
        role = 'diagnostic_only';
        reason = 'Diagnostic column retained for review, not part of the input feature list.';
    end
    rows(end+1, :) = {name, tableName, role, tableSet.intendedModule, reason}; %#ok<AGROW>
end
end
