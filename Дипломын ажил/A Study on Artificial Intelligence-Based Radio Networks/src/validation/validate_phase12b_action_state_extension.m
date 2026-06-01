function validationTable = validate_phase12b_action_state_extension(cfg, extendedTopology, supportTable, cioTest, prsTest, tiltTest, cloneTest, newlyImplementable)
%VALIDATE_PHASE12B_ACTION_STATE_EXTENSION Phase 12B integrity checks.

rows = {};

% (1) action-state support audit exists and non-empty
sf = fullfile(cfg.tablesDir, 'phase12b_action_state_support_audit.csv');
rows = add_check(rows, 'support_audit_exists', 'error', ...
    isfile(sf) && ~isempty(supportTable), ...
    sprintf('%d rows', height(supportTable)), '> 0', ...
    'phase12b_action_state_support_audit.csv must be written and non-empty.');

% (2) cio_dB column exists
hasCio = ismember('cio_dB', extendedTopology.sectors.Properties.VariableNames);
rows = add_check(rows, 'cio_column_exists', 'error', hasCio, ...
    logical_to_text(hasCio), '== true', 'sectors.cio_dB must be present after Phase 12B extension.');

% (3) cio_dB default zero
defaultZero = all(extendedTopology.sectors.cio_dB == 0);
rows = add_check(rows, 'cio_default_zero', 'error', defaultZero, ...
    logical_to_text(defaultZero), '== true', 'sectors.cio_dB must default to zero for every sector.');

% (4) baseline association unchanged when all CIO = 0
zeroBiasOk = cioTest.zeroBiasAssocSame;
rows = add_check(rows, 'baseline_assoc_unchanged_with_zero_cio', 'error', zeroBiasOk, ...
    logical_to_text(zeroBiasOk), '== true', ...
    'biased best-server must equal physical best-server when all CIO = 0.');

% (5) CIO bias changes association metric but not physical RSRP
biasOk = (cioTest.numChangedServing >= 1) && cioTest.physicalUnchanged;
rows = add_check(rows, 'cio_changes_assoc_only', 'error', biasOk, ...
    sprintf('changed_serving=%d, physical_unchanged=%d', ...
        cioTest.numChangedServing, double(cioTest.physicalUnchanged)), ...
    'changed_serving>=1 AND physical_unchanged==1', ...
    'CIO bias must change at least one biased best-server while leaving physical RSRP intact.');

% (6) reference power offset changes physical RSRP
prsOk = prsTest.deltaWithinTol && prsTest.otherUnchanged && prsTest.originalUnchanged;
rows = add_check(rows, 'ref_power_offset_changes_rsrp', 'error', prsOk, ...
    sprintf('mean_delta=%.4f dB, expected %d dB', prsTest.meanDelta, prsTest.deltaDb), ...
    sprintf('|delta - %d| < 0.05', prsTest.deltaDb), ...
    'reference power offset must shift physical RSRP by the configured delta for affected UEs.');

% (7) state clone integrity passes
cloneOk = cloneTest.originalStillEqual && cloneTest.clonedHasDelta;
rows = add_check(rows, 'state_clone_integrity', 'error', cloneOk, ...
    sprintf('orig_unchanged=%d, cloned_has_delta=%d', ...
        double(cloneTest.originalStillEqual), double(cloneTest.clonedHasDelta)), ...
    '== both true', 'dry-run apply must mutate the clone but never the original topology.');

% (8) original simulator state not mutated during dry-run
rows = add_check(rows, 'original_state_not_mutated', 'error', ...
    cloneTest.originalStillEqual, logical_to_text(cloneTest.originalStillEqual), ...
    '== true', 'apply_single_action_to_cloned_state must not modify the input topology.');

% (9) tilt support status reported honestly (implementable_now OR partial)
tiltAllowed = any(strcmp(tiltTest.status, {'implementable_now','partially_implementable'}));
rows = add_check(rows, 'tilt_support_status_honest', 'error', tiltAllowed, ...
    tiltTest.status, 'implementable_now or partially_implementable', ...
    'tilt status must be honestly reported based on whether tilt affects RSRP.');

% (10) HOM/TTT not marked fully implemented
hRow = supportTable(strcmp(supportTable.module_name, 'HO/MRO') & ...
    strcmp(supportTable.parameter_or_action, 'delta_hom_dB'), :);
tRow = supportTable(strcmp(supportTable.module_name, 'HO/MRO') & ...
    strcmp(supportTable.parameter_or_action, 'delta_ttt_ms'), :);
homOk = ~isempty(hRow) && ~strcmp(hRow.implementability_status{1}, 'implementable_now');
tttOk = ~isempty(tRow) && ~strcmp(tRow.implementability_status{1}, 'implementable_now');
rows = add_check(rows, 'hom_not_marked_implemented', 'error', homOk, ...
    extract_status(hRow), '!= implementable_now', 'HOM placeholder must not be marked implemented_now.');
rows = add_check(rows, 'ttt_not_marked_implemented', 'error', tttOk, ...
    extract_status(tRow), '!= implementable_now', 'TTT placeholder must not be marked implemented_now.');

% (11) ES sleep not marked fully implemented unless RF/KPI connected
sRow = supportTable(strcmp(supportTable.module_name, 'ES') & ...
    strcmp(supportTable.parameter_or_action, 'es_action:sleep'), :);
sleepOk = ~isempty(sRow) && ~strcmp(sRow.implementability_status{1}, 'implementable_now');
rows = add_check(rows, 'es_sleep_not_marked_implemented', 'error', sleepOk, ...
    extract_status(sRow), '!= implementable_now', ...
    'ES sleep state flag exists but RF/KPI engines do not yet consume it.');

% (12) no kpi_t_plus_1 columns introduced
forbiddenCols = {'kpi_t_plus_1','kpi_next','next_state_dataset'};
hits = intersect(forbiddenCols, extendedTopology.sectors.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_in_sectors', 'error', isempty(hits), ...
    strjoin(hits, ', '), '== empty', ...
    'No KPI(t+1) column may be added to sectors by Phase 12B.');

hitsSupport = intersect(forbiddenCols, supportTable.Properties.VariableNames);
rows = add_check(rows, 'no_kpi_t_plus_1_in_support', 'error', isempty(hitsSupport), ...
    strjoin(hitsSupport, ', '), '== empty', 'No KPI(t+1) column may exist in support audit.');

% (13) no closed-loop claim
forbiddenCl = {'applied','executed_at_simulator','closed_loop_state_update'};
clHits = intersect(forbiddenCl, extendedTopology.sectors.Properties.VariableNames);
rows = add_check(rows, 'no_closed_loop_columns', 'error', isempty(clHits), ...
    strjoin(clHits, ', '), '== empty', 'No closed-loop columns may be added.');

% (14) Phase 12A can show improvement after Phase 12B
improvement = newlyImplementable.numImplementableNow > 0;
rows = add_check(rows, 'phase12a_rerun_shows_improvement', 'error', improvement, ...
    sprintf('implementable_now=%d after extension', newlyImplementable.numImplementableNow), ...
    '> 0', ...
    'Re-classifying Phase 11B executable rows with the post-extension mapping must produce at least one implementable_now row.');

validationTable = cell2table(rows, 'VariableNames', ...
    {'check_name','severity','pass_flag','actual_value','expected_condition','notes'});
writetable(validationTable, fullfile(cfg.tablesDir, 'phase12b_action_state_validation.csv'));
end

function rows = add_check(rows, checkName, severity, passFlag, actualValue, expectedCondition, notes)
rows(end+1, :) = {checkName, severity, logical(passFlag), actualValue, expectedCondition, notes}; %#ok<AGROW>
end

function s = logical_to_text(v)
if v, s = 'true'; else, s = 'false'; end
end

function s = extract_status(row)
if isempty(row), s = '(missing)'; return; end
s = row.implementability_status{1};
end
