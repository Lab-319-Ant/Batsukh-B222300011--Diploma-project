function phase9a = prepare_phase9a_action_value_datasets(cfg)
%PREPARE_PHASE9A_ACTION_VALUE_DATASETS Build leakage-controlled datasets.
%
% Reads:
%   phase8b_counterfactual_action_table.csv
%   phase8b_safety_check.csv
%   phase8c_oracle_selected_actions.csv
%
% Writes (under cfg.tablesDir):
%   phase9a_action_value_dataset_all.csv
%   phase9a_action_value_dataset_coc.csv
%   phase9a_action_value_dataset_lb.csv
%   phase9a_action_value_dataset_es.csv
%   phase9a_action_value_dataset_mro.csv
%   phase9a_action_value_feature_dictionary.csv
%   phase9a_action_value_leakage_audit.csv
%   phase9a_action_value_dataset_summary.csv
%   phase9a_action_value_validation.csv (written by validator)
%
% This phase does NOT train ML, coordinate modules, apply actions, or
% produce KPI(t+1). It only assembles the training-ready dataset.

cfFile = fullfile(cfg.tablesDir, 'phase8b_counterfactual_action_table.csv');
safetyFile = fullfile(cfg.tablesDir, 'phase8b_safety_check.csv');
oracleFile = fullfile(cfg.tablesDir, 'phase8c_oracle_selected_actions.csv');
for fp = {cfFile, safetyFile, oracleFile}
    if ~isfile(fp{1})
        error('Phase 9A required input missing: %s', fp{1});
    end
end

cfTable = readtable(cfFile);
safetyTable = readtable(safetyFile);
oracleTable = readtable(oracleFile);

featureSets = define_action_value_feature_sets();
datasetAll = build_action_value_table(cfTable, safetyTable, oracleTable);

% Module-specific subsets
modules = featureSets.modules;
moduleTables = struct();
for k = 1:numel(modules)
    mName = modules{k};
    mask = strcmp(datasetAll.module_name, mName);
    moduleTables.(matlab.lang.makeValidName(mName)) = datasetAll(mask, :);
end

writetable(datasetAll, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_all.csv'));
writetable(moduleTables.COC_OH, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_coc.csv'));
writetable(moduleTables.LB_MLB, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_lb.csv'));
writetable(moduleTables.ES,     fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_es.csv'));
writetable(moduleTables.HO_MRO, fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_mro.csv'));

dictionary = build_feature_dictionary(datasetAll, featureSets);
writetable(dictionary, fullfile(cfg.tablesDir, 'phase9a_action_value_feature_dictionary.csv'));

leakageAudit = audit_action_value_leakage(cfg, datasetAll, dictionary, featureSets);
summary = summarize_phase9a_action_datasets(cfg, datasetAll, modules);

validationTable = validate_phase9a_action_value_datasets(cfg, datasetAll, moduleTables, ...
    dictionary, leakageAudit, summary, featureSets);

phase9a = struct();
phase9a.datasetAll = datasetAll;
phase9a.moduleTables = moduleTables;
phase9a.featureDictionary = dictionary;
phase9a.leakageAudit = leakageAudit;
phase9a.summary = summary;
phase9a.validationTable = validationTable;
phase9a.totalRows = height(datasetAll);
phase9a.safeRows = sum(datasetAll.safety_valid);
phase9a.unsafeRows = phase9a.totalRows - phase9a.safeRows;
phase9a.oracleSelectedRows = sum(datasetAll.oracle_selected);
phase9a.rowsByModule = countByGroup(datasetAll.module_name);
phase9a.safeRowsByModule = countByGroup(datasetAll.module_name(datasetAll.safety_valid));
phase9a.oracleByModule = countByGroup(datasetAll.module_name(datasetAll.oracle_selected));
end

function T = build_action_value_table(cfTable, safetyTable, oracleTable)
% Left-join safety table on action_id (Phase 8B already has matching ids).
safetyCols = {'action_id','safety_attach_loss','safety_qos_loss', ...
    'safety_sinr_loss','safety_rsrp_loss','safety_neighbor_overload', ...
    'safety_handover_risk','safety_es_sleep_impaired','safety_is_unsafe', ...
    'invalid_reason'};
keep = intersect(safetyCols, safetyTable.Properties.VariableNames, 'stable');
joined = outerjoin(cfTable, safetyTable(:, keep), 'Keys', 'action_id', ...
    'MergeKeys', true, 'Type', 'left');

% Coerce safety flags to logical and fill missing with false / 'ok'.
flagCols = {'safety_attach_loss','safety_qos_loss','safety_sinr_loss', ...
    'safety_rsrp_loss','safety_neighbor_overload','safety_handover_risk', ...
    'safety_es_sleep_impaired','safety_is_unsafe'};
for i = 1:numel(flagCols)
    c = flagCols{i};
    if ismember(c, joined.Properties.VariableNames)
        v = joined.(c);
        if iscell(v), v = str2double(v); end
        v(~isfinite(v)) = 0;
        joined.(c) = logical(v);
    else
        joined.(c) = false(height(joined), 1);
    end
end
if ~ismember('invalid_reason', joined.Properties.VariableNames)
    joined.invalid_reason = repmat({'ok'}, height(joined), 1);
end

% Add oracle metadata.
%   oracle_group_id is shared by every candidate row in the same oracle
%   decision group (scenario, realization, source, module) - not just by
%   the oracle-selected row. Without this, downstream top-1 / top-2 /
%   regret evaluation would only see the oracle pick itself and produce
%   a trivially perfect match.
%   oracle_selected is true only for the row whose action_id matches the
%   oracle's selected_action_id.
%   oracle_selection_reason is the oracle's reason string, broadcast to
%   every row in the same group.
%   unsafe_fallback_group is true if the oracle row for that group is
%   safety_valid == false.
oracleSelectedIds = oracleTable.selected_action_id;
oracleReason = string(oracleTable.oracle_selection_reason);
oracleSafetyValid = logical(oracleTable.safety_valid);

oracleGroupKey = strcat(string(oracleTable.scenario_name), "|", ...
    string(oracleTable.realization_id), "|", ...
    string(oracleTable.source_sector_id), "|", ...
    string(oracleTable.module_name));
rowGroupKey = strcat(string(joined.scenario_name), "|", ...
    string(joined.realization_id), "|", ...
    string(joined.source_sector_id), "|", ...
    string(joined.module_name));

[groupMatch, groupLoc] = ismember(rowGroupKey, oracleGroupKey);
oracle_group_id_col = nan(height(joined), 1);
oracle_selection_reason_col = strings(height(joined), 1);
oracle_group_id_col(groupMatch) = oracleTable.oracle_group_id(groupLoc(groupMatch));
oracle_selection_reason_col(groupMatch) = oracleReason(groupLoc(groupMatch));

oracle_selected_col = ismember(joined.action_id, oracleSelectedIds);

unsafeGroupKeys = oracleGroupKey(~oracleSafetyValid);
unsafe_fallback_group_col = ismember(rowGroupKey, unsafeGroupKeys);

% Derived booleans.
safety_valid_col = ~logical(joined.safety_is_unsafe);
safe_training_candidate_col = safety_valid_col;

% ES action code: 0 keep_active, 1 sleep, 2 wake_up, -1 otherwise.
es_action_code_col = -ones(height(joined), 1);
actionType = string(joined.action_type);
moduleStr = string(joined.module_name);
es_action_code_col(moduleStr == "ES" & actionType == "keep_active") = 0;
es_action_code_col(moduleStr == "ES" & actionType == "sleep") = 1;
es_action_code_col(moduleStr == "ES" & actionType == "wake_up") = 2;

T = table();
T.action_id = joined.action_id;
T.oracle_group_id = oracle_group_id_col;
T.dataset_id = joined.dataset_id;
T.scenario_id = joined.scenario_id;
T.realization_id = joined.realization_id;
T.scenario_name = cellstr(string(joined.scenario_name));
T.source_sector_id = joined.source_sector_id;
T.target_sector_id = joined.target_sector_id;
T.module_name = cellstr(string(joined.module_name));
T.action_type = cellstr(string(joined.action_type));

% Pre-action state features renamed to the spec column names.
T.source_sector_load = joined.pre_source_load_ratio;
T.target_sector_load = joined.pre_target_load_ratio;
T.source_mean_RSRP_dBm = joined.pre_source_RSRP_dBm;
T.source_mean_SINR_dB = joined.pre_source_SINR_dB;
T.source_qos_satisfaction_ratio = joined.pre_source_qos_satisfaction_ratio;
T.source_handover_risk_score = joined.pre_source_handover_risk_score;
T.source_attach_rate_sector = joined.pre_source_attach_rate;

% Action-parameter features (already in cfTable).
T.delta_prs_dB = pull_numeric(joined, 'delta_prs_dB');
T.delta_tilt_deg = pull_numeric(joined, 'delta_tilt_deg');
T.delta_cio_dB = pull_numeric(joined, 'delta_cio_dB');
T.delta_hom_dB = pull_numeric(joined, 'delta_hom_dB');
T.delta_ttt_ms = pull_numeric(joined, 'delta_ttt_ms');
T.sleep_flag = pull_numeric(joined, 'sleep_flag');
T.is_no_op = logical(joined.is_no_op);
T.es_action_code = es_action_code_col;

% Target.
T.reward = joined.reward;

% Evaluation metadata.
T.safety_valid = safety_valid_col;
T.oracle_selected = oracle_selected_col;
T.oracle_selection_reason = cellstr(oracle_selection_reason_col);
T.unsafe_fallback_group = unsafe_fallback_group_col;
T.safe_training_candidate = safe_training_candidate_col;
T.invalid_reason = cellstr(string(joined.invalid_reason));
T.safety_attach_loss = joined.safety_attach_loss;
T.safety_qos_loss = joined.safety_qos_loss;
T.safety_sinr_loss = joined.safety_sinr_loss;
T.safety_rsrp_loss = joined.safety_rsrp_loss;
T.safety_neighbor_overload = joined.safety_neighbor_overload;
T.safety_handover_risk = joined.safety_handover_risk;
T.safety_es_sleep_impaired = joined.safety_es_sleep_impaired;
T.safety_is_unsafe = joined.safety_is_unsafe;
if ismember('evaluation_note', joined.Properties.VariableNames)
    T.evaluation_note = cellstr(string(joined.evaluation_note));
else
    T.evaluation_note = repmat({''}, height(T), 1);
end
end

function v = pull_numeric(T, colName)
if ismember(colName, T.Properties.VariableNames)
    v = double(T.(colName));
    v(~isfinite(v)) = 0;
else
    v = zeros(height(T), 1);
end
end

function dict = build_feature_dictionary(datasetAll, featureSets)
vars = datasetAll.Properties.VariableNames;
rows = cell(numel(vars), 5);
for i = 1:numel(vars)
    name = vars{i};
    [role, reason] = classify_column(name, featureSets);
    rows(i, :) = {name, 'phase9a_action_value_dataset_all', role, 'all', reason};
end
dict = cell2table(rows, 'VariableNames', ...
    {'column_name','table_name','role','module','reason'});
end

function [role, reason] = classify_column(name, featureSets)
% Precedence (semantic role wins over the forbidden-input guard list):
%   1) target
%   2) evaluation_metadata - post-hoc audit flag (also excluded as input)
%   3) forbidden_leakage   - operationally banned input that has no other role
%   4) input_feature_candidate
%   5) metadata
%   6) diagnostic_only
% Columns like oracle_selected and safety_valid intentionally appear in
% both evaluationMetadata and forbiddenInputs - the role is the semantic
% truth, and the forbiddenInputs list is the operational guard rail.

if any(strcmp(name, featureSets.targets))
    role = 'target';
    reason = 'Regression target (counterfactual reward).';
    return;
end
if any(strcmp(name, featureSets.evaluationMetadata))
    role = 'evaluation_metadata';
    reason = 'Post-hoc audit / oracle / safety flag; never a model input.';
    return;
end
if any(strcmp(name, featureSets.forbiddenInputs))
    role = 'forbidden_leakage';
    reason = 'Excluded from model input (post-action / future KPI / scenario label).';
    return;
end
if any(strcmp(name, featureSets.stateInputs)) || any(strcmp(name, featureSets.actionInputs))
    role = 'input_feature_candidate';
    reason = 'Pre-action state feature or action parameter.';
    return;
end
if any(strcmp(name, featureSets.metadata))
    role = 'metadata';
    reason = 'Traceability metadata; not a model input.';
    return;
end
if startsWith(name, 'post_')
    role = 'forbidden_leakage';
    reason = 'Post-action KPI; forbidden as model input.';
    return;
end
role = 'diagnostic_only';
reason = 'Unclassified column kept for debugging.';
end

function counts = countByGroup(values)
if isempty(values)
    counts = struct();
    return;
end
values = string(values);
[uniqueVals, ~, idx] = unique(values, 'stable');
counts = struct();
for k = 1:numel(uniqueVals)
    counts.(matlab.lang.makeValidName(char(uniqueVals(k)))) = sum(idx == k);
end
end
