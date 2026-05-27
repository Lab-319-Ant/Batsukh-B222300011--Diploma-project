function phase10a = run_phase10a_safety_enforced_selection(cfg)
%RUN_PHASE10A_SAFETY_ENFORCED_SELECTION Offline ML + safety filter wrapper.
%
% Phase 10A is OFFLINE only. It ranks Phase 9B predicted rewards, then
% rejects candidate actions flagged unsafe by Phase 8B before recording
% the final ML-selected action. It compares both the raw top-1 ML
% selection and the safety-enforced selection against the Phase 8C
% oracle. It does NOT apply actions, NOT coordinate modules, NOT
% produce KPI(t+1), NOT constitute closed-loop control.
%
% Inputs read from cfg.tablesDir:
%   phase9b_action_value_predictions.csv (must include 'split' column)
%   phase8b_safety_check.csv
%   phase8c_oracle_selected_actions.csv
%   phase9a_action_value_dataset_all.csv
%
% Outputs written to cfg.tablesDir:
%   phase10a_safety_enforced_selected_actions.csv
%   phase10a_raw_vs_safe_selection_comparison.csv
%   phase10a_safety_enforced_regret.csv
%   phase10a_summary_by_module.csv
%   phase10a_summary_by_scenario.csv
%   phase10a_safety_filter_summary.csv
%   phase10a_safety_enforced_validation.csv

requiredFiles = { ...
    'phase9b_action_value_predictions.csv', ...
    'phase8b_safety_check.csv', ...
    'phase8c_oracle_selected_actions.csv', ...
    'phase9a_action_value_dataset_all.csv'};
for i = 1:numel(requiredFiles)
    p = fullfile(cfg.tablesDir, requiredFiles{i});
    if ~isfile(p)
        error('Phase 10A: required input missing: %s', p);
    end
end

predictions = readtable(fullfile(cfg.tablesDir, 'phase9b_action_value_predictions.csv'));
safetyTable = readtable(fullfile(cfg.tablesDir, 'phase8b_safety_check.csv'));
oracleTable = readtable(fullfile(cfg.tablesDir, 'phase8c_oracle_selected_actions.csv'));
datasetAll = readtable(fullfile(cfg.tablesDir, 'phase9a_action_value_dataset_all.csv'));

% Evaluate offline on the test split only (out-of-sample).
testPred = predictions(strcmp(predictions.split, 'test'), :);

joined = build_joined_table(testPred, safetyTable, datasetAll);
joined = joined(~isnan(joined.oracle_group_id), :);

selectionRaw = select_safety_enforced_ml_actions(joined);
[selectedFinal, regretTable, comparisonTable] = evaluate_safety_enforced_selection( ...
    selectionRaw, joined, oracleTable);

if ismember('raw_action_id_for_top2', selectedFinal.Properties.VariableNames)
    selectedFinal = removevars(selectedFinal, ...
        intersect({'raw_action_id_for_top2','safe_action_id_for_top2'}, selectedFinal.Properties.VariableNames));
end

[moduleSummary, scenarioSummary, filterSummary] = summarize_phase10a_selection(selectedFinal);

writetable(selectedFinal, fullfile(cfg.tablesDir, 'phase10a_safety_enforced_selected_actions.csv'));
writetable(comparisonTable, fullfile(cfg.tablesDir, 'phase10a_raw_vs_safe_selection_comparison.csv'));
writetable(regretTable, fullfile(cfg.tablesDir, 'phase10a_safety_enforced_regret.csv'));
writetable(moduleSummary, fullfile(cfg.tablesDir, 'phase10a_summary_by_module.csv'));
writetable(scenarioSummary, fullfile(cfg.tablesDir, 'phase10a_summary_by_scenario.csv'));
writetable(filterSummary, fullfile(cfg.tablesDir, 'phase10a_safety_filter_summary.csv'));

try_plot('plot_phase10a_regret_by_module', cfg, regretTable);
try_plot('plot_phase10a_safe_vs_raw_selection', cfg, comparisonTable);
try_plot('plot_phase10a_selection_outcomes', cfg, selectedFinal);

validationTable = validate_phase10a_safety_enforced_selection(cfg, selectedFinal, ...
    joined, oracleTable, moduleSummary, filterSummary);

phase10a = struct();
phase10a.selectedTable = selectedFinal;
phase10a.comparisonTable = comparisonTable;
phase10a.regretTable = regretTable;
phase10a.moduleSummary = moduleSummary;
phase10a.scenarioSummary = scenarioSummary;
phase10a.filterSummary = filterSummary;
phase10a.validationTable = validationTable;
phase10a.numGroups = height(selectedFinal);
phase10a.numRawUnsafeTop1 = sum(~selectedFinal.raw_selected_safety_valid);
phase10a.numSafeUnsafeSelected = sum(~selectedFinal.safe_selected_safety_valid);
phase10a.numFilterChanged = sum(selectedFinal.safety_filter_changed_action);
phase10a.numFallback = sum(selectedFinal.fallback_used);
phase10a.numNoopSelected = sum(selectedFinal.noop_selected);
phase10a.rawMeanRegret = mean(selectedFinal.raw_regret, 'omitnan');
phase10a.safetyMeanRegret = mean(selectedFinal.safety_enforced_regret, 'omitnan');
phase10a.safeTop1Rate = mean(selectedFinal.safe_top1_oracle_match, 'omitnan');
end

function joined = build_joined_table(testPred, safetyTable, datasetAll)
%BUILD_JOINED_TABLE Attach safety flags and action parameters to predictions.
safetyCols = {'action_id','safety_attach_loss','safety_qos_loss','safety_sinr_loss', ...
    'safety_rsrp_loss','safety_neighbor_overload','safety_handover_risk', ...
    'safety_es_sleep_impaired','safety_is_unsafe','invalid_reason'};
keepSafety = intersect(safetyCols, safetyTable.Properties.VariableNames, 'stable');
joined = outerjoin(testPred, safetyTable(:, keepSafety), 'Keys', 'action_id', ...
    'MergeKeys', true, 'Type', 'left');

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

paramCols = {'action_id','delta_prs_dB','delta_tilt_deg','delta_cio_dB', ...
    'delta_hom_dB','delta_ttt_ms','sleep_flag','is_no_op','es_action_code'};
keepParams = intersect(paramCols, datasetAll.Properties.VariableNames, 'stable');
joined = outerjoin(joined, datasetAll(:, keepParams), 'Keys', 'action_id', ...
    'MergeKeys', true, 'Type', 'left');

% Build a string es_action column from es_action_code for the output.
if ismember('es_action_code', joined.Properties.VariableNames)
    code = joined.es_action_code;
    es = strings(height(joined), 1);
    es(code == 0) = "keep_active";
    es(code == 1) = "sleep";
    es(code == 2) = "wake_up";
    es(code < 0 | ~isfinite(code)) = "";
    joined.es_action = cellstr(es);
else
    joined.es_action = repmat({''}, height(joined), 1);
end

% Coerce numeric param columns to finite zeros where missing.
numericParams = {'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms','sleep_flag','is_no_op'};
for i = 1:numel(numericParams)
    c = numericParams{i};
    if ismember(c, joined.Properties.VariableNames)
        v = double(joined.(c));
        v(~isfinite(v)) = 0;
        joined.(c) = v;
    else
        joined.(c) = zeros(height(joined), 1);
    end
end
end

function try_plot(fnName, cfg, T)
if exist(fnName, 'file') ~= 2 || isempty(T)
    return;
end
try
    feval(fnName, cfg, T);
catch ME
    warning('Phase 10A plot %s failed: %s', fnName, ME.message);
end
end
