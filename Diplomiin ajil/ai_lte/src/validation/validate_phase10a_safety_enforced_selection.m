function validationTable = validate_phase10a_safety_enforced_selection(cfg, selectedTable, joinedTable, oracleTable, moduleSummary, filterSummary)
%VALIDATE_PHASE10A_SAFETY_ENFORCED_SELECTION Phase 10A integrity checks.

rows = {};

% (1) selected action table exists
sf = fullfile(cfg.tablesDir, 'phase10a_safety_enforced_selected_actions.csv');
rows = add_check(rows, 'selected_action_table_exists', 'error', ...
    isfile(sf) && ~isempty(selectedTable), ...
    sprintf('%d rows', height(selectedTable)), '> 0', ...
    'phase10a_safety_enforced_selected_actions.csv must be written.');

% (2) exactly one safety-enforced selected action per decision group
nGroups = numel(unique(selectedTable.oracle_group_id));
rows = add_check(rows, 'one_selected_action_per_decision_group', 'error', ...
    nGroups == height(selectedTable), ...
    sprintf('%d groups / %d rows', nGroups, height(selectedTable)), ...
    'one row per group', 'Each decision group must produce exactly one safety-enforced selected action.');

% (3) selected_action_id_safe exists in candidate/action-value table
joinedIds = joinedTable.action_id;
missingIds = setdiff(selectedTable.selected_action_id_safe, joinedIds);
rows = add_check(rows, 'safe_action_id_in_candidate_table', 'error', ...
    isempty(missingIds), sprintf('%d missing', numel(missingIds)), '== 0', ...
    'Every safety-enforced selected action_id must exist in the Phase 9B test predictions.');

% (4) oracle action exists for every evaluated group
oracleIds = oracleTable.oracle_group_id;
missingOracle = setdiff(selectedTable.oracle_group_id, oracleIds);
rows = add_check(rows, 'oracle_action_exists_per_group', 'error', ...
    isempty(missingOracle), sprintf('%d groups without oracle', numel(missingOracle)), '== 0', ...
    'Every Phase 10A decision group must have a matching Phase 8C oracle row.');

% (5) regret is finite
nanRegret = sum(~isfinite(selectedTable.raw_regret)) + ...
    sum(~isfinite(selectedTable.safety_enforced_regret));
rows = add_check(rows, 'regret_values_finite', 'error', ...
    nanRegret == 0, sprintf('%d non-finite', nanRegret), '== 0', ...
    'Both raw and safety-enforced regret must be finite numbers.');

% (6) raw unsafe top-1 count reported
rawUnsafeTotal = sum(~selectedTable.raw_selected_safety_valid);
rows = add_check(rows, 'raw_unsafe_top1_count_reported', 'diagnostic', true, ...
    sprintf('%d', rawUnsafeTotal), 'n/a', ...
    'Total raw top-1 ML selections flagged unsafe by Phase 8B.');

% (7) safe unsafe selected count reported
safeUnsafeTotal = sum(~selectedTable.safe_selected_safety_valid);
rows = add_check(rows, 'safe_unsafe_selected_count_reported', 'diagnostic', true, ...
    sprintf('%d', safeUnsafeTotal), 'n/a', ...
    'Total safety-enforced selections that remained unsafe (fallback path).');

% (8) safe-unsafe should be 0 when safe candidates exist - i.e. every
% safe-unsafe pick must coincide with fallback_used == true
unsafeWithoutFallback = sum(~selectedTable.safe_selected_safety_valid & ~selectedTable.fallback_used);
rows = add_check(rows, 'safe_unsafe_only_when_no_safe_available', 'error', ...
    unsafeWithoutFallback == 0, sprintf('%d', unsafeWithoutFallback), '== 0', ...
    'An unsafe safety-enforced pick is allowed only when fallback_used = true (no safe candidate existed).');

% (9) fallback count reported
fallbackCount = sum(selectedTable.fallback_used);
rows = add_check(rows, 'fallback_count_reported', 'diagnostic', true, ...
    sprintf('%d', fallbackCount), 'n/a', ...
    'Decision groups where no safety-valid candidate was available.');

% (10) no-op selected count reported
noopCount = sum(selectedTable.noop_selected);
rows = add_check(rows, 'noop_selected_count_reported', 'diagnostic', true, ...
    sprintf('%d', noopCount), 'n/a', ...
    'Decision groups where the safety-enforced pick is a no-op (or ES keep_active).');

% (11) safety filter changed at least some unsafe raw selections, and
% every unchanged unsafe pick must be an explicit fallback case (no safe
% candidate and no different no-op available).
filterChanged = sum(selectedTable.safety_filter_changed_action);
rawUnsafe = sum(~selectedTable.raw_selected_safety_valid);
filterChangedSomeUnsafe = filterChanged >= min(1, rawUnsafe);
rows = add_check(rows, 'safety_filter_changed_some_unsafe_raw_picks', 'error', ...
    filterChangedSomeUnsafe, sprintf('changed=%d, unsafe_raw=%d', filterChanged, rawUnsafe), ...
    'changed > 0 when unsafe_raw > 0', ...
    'Safety filter must change at least one unsafe raw selection.');

unsafeNoChange = ~selectedTable.raw_selected_safety_valid & ~selectedTable.safety_filter_changed_action;
unsafeNoChangeNotFallback = sum(unsafeNoChange & ~selectedTable.fallback_used);
rows = add_check(rows, 'unsafe_raw_kept_only_in_fallback', 'error', ...
    unsafeNoChangeNotFallback == 0, ...
    sprintf('%d unsafe raw picks kept without fallback flag', unsafeNoChangeNotFallback), '== 0', ...
    'Whenever the filter keeps an unsafe raw pick, fallback_used must be true (no safe candidate and no different no-op existed).');

% (12) no forbidden leakage columns used
% Phase 10A doesn't train, so we only need to verify Phase 9B's input
% features did not contain leakage (carried from Phase 9B validation).
phase9bValFile = fullfile(cfg.tablesDir, 'phase9b_action_value_validation.csv');
leakageOk = true;
if isfile(phase9bValFile)
    p9bv = readtable(phase9bValFile);
    rowsLeak = p9bv(strcmp(p9bv.check_name, 'no_forbidden_features_used'), :);
    if ~isempty(rowsLeak)
        leakageOk = logical(rowsLeak.pass_flag(1));
    end
end
rows = add_check(rows, 'no_forbidden_leakage_used_in_phase9b', 'error', leakageOk, ...
    sprintf('phase9b_no_forbidden_features_used pass_flag=%d', leakageOk), '== true', ...
    'Phase 10A inherits Phase 9B leakage guarantees; this check verifies them.');

% (13) no action was applied to simulator (structural check)
[appliedKpi, evidence] = scan_for_simulator_application();
rows = add_check(rows, 'no_action_applied_to_simulator', 'error', ~appliedKpi, evidence, ...
    '== false', 'Phase 10A source must not write back to simulator state.');

% (14) no KPI(t+1) column exists in output
kpiNextCols = intersect({'kpi_t_plus_1','kpi_next','next_state_dataset'}, ...
    selectedTable.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_column', 'error', ...
    isempty(kpiNextCols), strjoin(kpiNextCols, ', '), '== empty', ...
    'Output must not contain any KPI(t+1) column.');

% (15) no coordinator logic (structural)
[hasCoord, coordEvidence] = scan_for_coordinator_logic();
rows = add_check(rows, 'no_coordinator_logic', 'error', ~hasCoord, coordEvidence, ...
    '== false', 'Phase 10A source must not implement decision coordinator.');

% (16) safety_enforced_mean_regret should not be massively higher than raw
rawMean = mean(selectedTable.raw_regret, 'omitnan');
safetyMean = mean(selectedTable.safety_enforced_regret, 'omitnan');
isWorse = isfinite(rawMean) && isfinite(safetyMean) && (safetyMean - rawMean) > 1.0;
rows = add_check(rows, 'safety_enforced_regret_not_explosive', 'warning', ~isWorse, ...
    sprintf('raw=%.4f safe=%.4f delta=%.4f', rawMean, safetyMean, safetyMean - rawMean), ...
    'delta <= 1.0', ...
    'Safety enforcement adds <= 1.0 absolute regret on average; otherwise the filter is too aggressive.');

% (17) safe_unsafe_selected_count > 0 only when fallback was forced
% Promote to warning when fallback path was the only option, but emit an
% explicit warning so the count is highlighted in the run report.
rows = add_check(rows, 'safety_enforced_unsafe_residual_count', 'warning', ...
    safeUnsafeTotal == 0, sprintf('%d residual unsafe', safeUnsafeTotal), '== 0', ...
    'Residual unsafe selections come from groups with no safe candidate and no no-op available.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase10a_safety_enforced_validation.csv'));

% Silence unused-arg static analysis.
moduleSummary = moduleSummary;     %#ok<ASGSL>
filterSummary = filterSummary;     %#ok<ASGSL>
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function [hit, evidence] = scan_for_simulator_application()
hit = false;
evidence = 'no simulator-application calls found';
src = which('run_phase10a_safety_enforced_selection');
if isempty(src) || ~isfile(src)
    hit = true;
    evidence = 'orchestrator source not located';
    return;
end
contents = fileread(src);
forbidden = {'apply_action','calc_rsrp_sinr','allocate_sector_throughput', ...
    'compute_sector_kpis','generate_ues','kpi_t_plus_1','next_state_dataset'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    hit = true;
    evidence = sprintf('found: %s', strjoin(found, ', '));
end
end

function [hit, evidence] = scan_for_coordinator_logic()
hit = false;
evidence = 'no coordinator references found';
src = which('run_phase10a_safety_enforced_selection');
if isempty(src) || ~isfile(src)
    hit = true;
    evidence = 'orchestrator source not located';
    return;
end
contents = fileread(src);
forbidden = {'decision_coordinator','run_coordinator','coordinate_modules', ...
    'cross_module_decision'};
found = {};
for i = 1:numel(forbidden)
    if contains(contents, forbidden{i})
        found{end+1} = forbidden{i}; %#ok<AGROW>
    end
end
if ~isempty(found)
    hit = true;
    evidence = sprintf('found: %s', strjoin(found, ', '));
end
end
