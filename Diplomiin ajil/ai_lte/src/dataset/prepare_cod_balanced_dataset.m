function phase6a = prepare_cod_balanced_dataset(cfg, topology)
%PREPARE_COD_BALANCED_DATASET Build leakage-controlled balanced COD dataset.
%
% This phase prepares data only. It does not train a COD classifier.

inputFile = fullfile(cfg.tablesDir, 'phase4b_sector_features_cod.csv');
if ~isfile(inputFile)
    error('Phase6A:MissingCODInput', 'Missing Phase 4B COD table: %s', inputFile);
end

originalCodTable = readtable(inputFile);
featureSets = define_feature_sets();
inputFeatures = featureSets.cod.inputs;
metadataColumns = {'realization_id','scenario_name','site_id','sector_id','impaired_sector_id'};

originalCodTable = normalize_cod_source_table(originalCodTable, inputFeatures);
originalDistribution = summarize_cod_dataset_balance(originalCodTable);

focusedRows = generate_cod_focused_dataset(cfg, topology);

rng(cfg.seed + 6100);
normalSource = originalCodTable(strcmp(string(originalCodTable.scenario_name), 'normal') & ...
    strcmp(string(originalCodTable.cod_label), 'normal'), :);
normalSource = normalSource(randperm(height(normalSource)), :);
targetPerClass = cfg.phase6NumCODRealizationsPerClass;
normalRows = normalSource(1:min(targetPerClass, height(normalSource)), ...
    [metadataColumns, inputFeatures, {'cod_label'}]);

degradedRows = focusedRows(strcmp(string(focusedRows.cod_label), 'degraded'), :);
outageRows = focusedRows(strcmp(string(focusedRows.cod_label), 'outage'), :);

balancedCodTable = [normalRows; degradedRows; outageRows];
balancedCodTable.row_id = (1:height(balancedCodTable))';
balancedCodTable = movevars(balancedCodTable, 'row_id', 'Before', 1);

featureList = build_cod_feature_list(balancedCodTable, inputFeatures, metadataColumns);
labelDistribution = summarize_cod_dataset_balance(balancedCodTable);
splitPlan = build_cod_split_plan(cfg, balancedCodTable);
validationTable = validate_cod_dataset(cfg, balancedCodTable, featureList, inputFeatures);

writetable(balancedCodTable, fullfile(cfg.tablesDir, 'phase6a_cod_balanced_dataset.csv'));
writetable(featureList, fullfile(cfg.tablesDir, 'phase6a_cod_feature_list.csv'));
writetable(labelDistribution, fullfile(cfg.tablesDir, 'phase6a_cod_label_distribution.csv'));
writetable(splitPlan, fullfile(cfg.tablesDir, 'phase6a_cod_split_plan.csv'));

plot_cod_label_distribution(cfg, labelDistribution);

phase6a = struct();
phase6a.originalCodTable = originalCodTable;
phase6a.originalDistribution = originalDistribution;
phase6a.balancedCodTable = balancedCodTable;
phase6a.featureList = featureList;
phase6a.labelDistribution = labelDistribution;
phase6a.splitPlan = splitPlan;
phase6a.validationTable = validationTable;
phase6a.inputFeatures = inputFeatures;
end

function tbl = normalize_cod_source_table(tbl, inputFeatures)
if ~ismember('impaired_sector_id', tbl.Properties.VariableNames)
    tbl.impaired_sector_id = zeros(height(tbl), 1);
end
for i = 1:numel(inputFeatures)
    name = inputFeatures{i};
    values = double(tbl.(name));
    replacement = 0;
    if strcmp(name, 'qos_satisfaction_ratio')
        replacement = 1;
    elseif contains(name, 'RSRP')
        replacement = -125;
    elseif contains(name, 'SINR')
        replacement = -20;
    end
    values(ismissing(values) | isinf(values)) = replacement;
    tbl.(name) = values;
end
tbl.cod_label = categorical(string(tbl.cod_label), {'normal','degraded','outage'});
end

function featureList = build_cod_feature_list(tbl, inputFeatures, metadataColumns)
forbiddenColumns = {'scenario_id','scenario_name','scenario_label','traffic_mode', ...
    'sector_status','impaired_sector_id','impaired_site_id','impaired_sector_status', ...
    'is_impaired_sector','referencePowerOffset_dB','txPowerOffset_dB', ...
    'outage_flag','degradation_flag','cod_label'};

rows = {};
vars = tbl.Properties.VariableNames;
for i = 1:numel(vars)
    name = vars{i};
    if any(strcmp(name, inputFeatures))
        role = 'input_feature';
        allowed = true;
        reason = 'Allowed KPI-derived COD input feature.';
    elseif strcmp(name, 'cod_label')
        role = 'target_label';
        allowed = false;
        reason = 'COD target label, not an input feature.';
    elseif any(strcmp(name, metadataColumns)) || strcmp(name, 'row_id')
        role = 'metadata';
        allowed = false;
        reason = 'Traceability metadata only; excluded from COD input matrix.';
    elseif any(strcmp(name, forbiddenColumns))
        role = 'forbidden_leakage';
        allowed = false;
        reason = 'Direct label, scenario, status, or impairment metadata; forbidden as input.';
    else
        role = 'metadata';
        allowed = false;
        reason = 'Not selected as a COD input feature.';
    end
    rows(end+1, :) = {name, role, allowed, reason}; %#ok<AGROW>
end

featureList = cell2table(rows, 'VariableNames', ...
    {'feature_name','role','allowed_as_input','reason'});
end

function splitPlan = build_cod_split_plan(cfg, codTable)
rng(cfg.seed + 6200);
labels = categories(categorical(codTable.cod_label));
split = strings(height(codTable), 1);

for i = 1:numel(labels)
    label = labels{i};
    labelIdx = find(codTable.cod_label == label);
    groups = unique(codTable.realization_id(labelIdx));
    groups = groups(randperm(numel(groups)));
    nGroups = numel(groups);
    nTrain = round(0.70 * nGroups);
    nValidation = round(0.15 * nGroups);
    trainGroups = groups(1:nTrain);
    validationGroups = groups(nTrain + 1:min(nTrain + nValidation, nGroups));
    testGroups = groups(min(nTrain + nValidation, nGroups) + 1:end);

    split(ismember(codTable.realization_id, trainGroups) & codTable.cod_label == label) = "train";
    split(ismember(codTable.realization_id, validationGroups) & codTable.cod_label == label) = "validation";
    split(ismember(codTable.realization_id, testGroups) & codTable.cod_label == label) = "test";
end

split(split == "") = "test";
splitPlan = table(codTable.row_id, codTable.realization_id, codTable.sector_id, ...
    codTable.cod_label, cellstr(split), ...
    'VariableNames', {'row_id','realization_id','sector_id','cod_label','split'});
end
