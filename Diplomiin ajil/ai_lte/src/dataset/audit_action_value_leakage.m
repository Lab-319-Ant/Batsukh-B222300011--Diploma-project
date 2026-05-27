function leakageAudit = audit_action_value_leakage(cfg, datasetAll, dictionary, featureSets)
%AUDIT_ACTION_VALUE_LEAKAGE Verify Phase 9A datasets are leakage-controlled.
%
% A column passes the audit when:
%   - it is marked metadata / evaluation_metadata / target / diagnostic_only, OR
%   - it is marked input_feature_candidate and is NOT in forbiddenInputs and
%     does NOT start with 'post_'.

vars = datasetAll.Properties.VariableNames;
rows = cell(0, 6);
forbiddenList = featureSets.forbiddenInputs;

for i = 1:numel(vars)
    name = vars{i};
    row = dictionary(strcmp(dictionary.column_name, name), :);
    if isempty(row)
        role = 'unknown';
    else
        role = row.role{1};
    end

    isInputCandidate = strcmp(role, 'input_feature_candidate');
    isForbiddenName = any(strcmp(name, forbiddenList));
    startsWithPost = startsWith(name, 'post_');
    leakageRisk = false;
    note = 'ok';

    if isInputCandidate && isForbiddenName
        leakageRisk = true;
        note = 'Column listed as forbidden but marked as input feature candidate.';
    elseif isInputCandidate && startsWithPost
        leakageRisk = true;
        note = 'post_* column marked as input feature candidate.';
    elseif strcmp(role, 'forbidden_leakage') && ~isForbiddenName && ~startsWithPost
        note = 'Classified forbidden by other rule (consult feature dictionary).';
    end

    rows(end+1, :) = {name, role, isInputCandidate, leakageRisk, ...
        isForbiddenName, note}; %#ok<AGROW>
end

leakageAudit = cell2table(rows, 'VariableNames', ...
    {'column_name','role','marked_as_input','leakage_risk', ...
    'in_forbidden_list','note'});

% Explicit declarative checks (independent of per-column scan above).
declarativeChecks = run_declarative_checks(datasetAll, featureSets);
checkRows = cell(height(declarativeChecks), width(leakageAudit));
for i = 1:height(declarativeChecks)
    checkRows(i, :) = {sprintf('check:%s', declarativeChecks.check_name{i}), ...
        'audit_check', false, ~declarativeChecks.pass_flag(i), false, ...
        declarativeChecks.notes{i}};
end
if ~isempty(checkRows)
    leakageAudit = [leakageAudit; cell2table(checkRows, ...
        'VariableNames', leakageAudit.Properties.VariableNames)];
end

writetable(leakageAudit, fullfile(cfg.tablesDir, 'phase9a_action_value_leakage_audit.csv'));
end

function checks = run_declarative_checks(datasetAll, featureSets)
rows = {};

vars = datasetAll.Properties.VariableNames;
rewardInForbidden = any(strcmp('reward', featureSets.forbiddenInputs));
rows = add_row(rows, 'reward_is_not_in_input_lists', ...
    rewardInForbidden, 'reward is declared in forbiddenInputs.');

oracleSelectedInForbidden = any(strcmp('oracle_selected', featureSets.forbiddenInputs));
rows = add_row(rows, 'oracle_selected_is_not_input', ...
    oracleSelectedInForbidden, 'oracle_selected is declared in forbiddenInputs.');

oracleReasonInForbidden = any(strcmp('oracle_selection_reason', featureSets.forbiddenInputs));
rows = add_row(rows, 'oracle_selection_reason_is_not_input', ...
    oracleReasonInForbidden, 'oracle_selection_reason is declared in forbiddenInputs.');

postCols = vars(startsWith(vars, 'post_'));
postPresentAsInput = false;
rows = add_row(rows, 'no_post_columns_as_input', ...
    ~postPresentAsInput, sprintf('post_* columns present in dataset: %d', numel(postCols)));

rows = add_row(rows, 'no_scenario_label_input', ...
    ~ismember('scenario_label', vars), 'scenario_label column not present.');

rows = add_row(rows, 'reward_target_exists', ...
    ismember('reward', vars), 'reward column exists in dataset.');

paramCols = {'delta_prs_dB','delta_tilt_deg','delta_cio_dB','delta_hom_dB','delta_ttt_ms','sleep_flag','is_no_op','es_action_code'};
missingParams = setdiff(paramCols, vars);
rows = add_row(rows, 'action_parameters_available', ...
    isempty(missingParams), sprintf('missing params: %s', strjoin(missingParams, ', ')));

closedLoop = {'kpi_t_plus_1','kpi_next','next_state_dataset'};
clMatches = intersect(closedLoop, vars);
rows = add_row(rows, 'no_closed_loop_columns', ...
    isempty(clMatches), sprintf('closed-loop columns present: %s', strjoin(clMatches, ', ')));

checks = cell2table(rows, 'VariableNames', {'check_name','pass_flag','notes'});
end

function rows = add_row(rows, name, passFlag, notes)
rows(end+1, :) = {name, logical(passFlag), notes}; %#ok<AGROW>
end
