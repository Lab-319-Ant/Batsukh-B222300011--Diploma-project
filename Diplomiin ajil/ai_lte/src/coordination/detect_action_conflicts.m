function conflictLog = detect_action_conflicts(inputTable, cfg)
%DETECT_ACTION_CONFLICTS Offline diagnostic conflict scan over Phase 11A inputs.
%
% Conflict types:
%   unsafe_non_fallback         - action is unsafe AND not a forced fallback
%   duplicate_application_target_parameter
%                               - two actions write same simulator state
%                                 variable on same application sector
%   same_sector_orthogonal_param- two actions touch same application sector
%                                 with disjoint simulator variables (info)
%   es_sleep_overlap            - ES sleep on a sector where any non-noop higher-priority action runs
%   lb_into_risky_target        - LB action targets a sector flagged as overloaded/risky
%   cross_cell_counteracting    - reverse-cell pair with opposite-sign CIO
%   cross_cell_reinforcing      - reverse-cell pair with same-sign CIO (info)
%
% Conflicts that imply rejection have severity 'error'. Informational
% rows have severity 'info'.

conflictLog = build_empty_log();
if isempty(inputTable)
    return;
end

T = inputTable;
T.row_idx = (1:height(T))';
nextId = 1;

% (1) unsafe non-fallback per row
unsafeMask = ~T.safe_selected_safety_valid & ~T.fallback_used;
unsafeIdx = find(unsafeMask);
for k = 1:numel(unsafeIdx)
    a = T(unsafeIdx(k), :);
    conflictLog = append_one(conflictLog, a.coordinator_group_id, nextId, ...
        'unsafe_non_fallback', a, a, a.application_affected_sector_id, ...
        a.application_state_variable{1}, ...
        'Action is unsafe and not a forced fallback; reject.');
    nextId = nextId + 1;
end

% (2) pairwise checks within each (coordinator_group_id)
[uniqueGroups, ~, idx] = unique(T.coordinator_group_id, 'stable');
for g = 1:numel(uniqueGroups)
    rowsG = T(idx == g, :);
    coordId = uniqueGroups(g);

    [nextId, conflictLog] = check_application_target_pairs(rowsG, coordId, conflictLog, nextId);
    [nextId, conflictLog] = check_es_sleep_overlap(rowsG, coordId, conflictLog, nextId);
    [nextId, conflictLog] = check_lb_risky_target(rowsG, T, coordId, cfg, conflictLog, nextId);
    [nextId, conflictLog] = check_cross_cell_pairs(rowsG, coordId, conflictLog, nextId);
end

% Severity tagging
infoMask = strcmp(conflictLog.conflict_type, 'same_sector_orthogonal_param') | ...
    strcmp(conflictLog.conflict_type, 'cross_cell_reinforcing');
severity = repmat({'error'}, height(conflictLog), 1);
severity(infoMask) = {'info'};
conflictLog.severity = severity;

nextId = nextId; %#ok<ASGSL,NASGU>
end

function [nextId, log] = check_application_target_pairs(rowsG, coordId, log, nextId)
rowsG = rowsG(rowsG.application_affected_sector_id > 0, :);
if height(rowsG) < 2
    return;
end
[~, ~, sectorIdx] = unique(rowsG.application_affected_sector_id);
for sg = unique(sectorIdx)'
    sectorRows = rowsG(sectorIdx == sg, :);
    n = height(sectorRows);
    if n < 2, continue; end
    for i = 1:n-1
        for j = i+1:n
            a = sectorRows(i, :);
            b = sectorRows(j, :);
            varsA = split_params(a.application_state_variable{1});
            varsB = split_params(b.application_state_variable{1});
            varsA = varsA(varsA ~= "none");
            varsB = varsB(varsB ~= "none");
            overlap = intersect(varsA, varsB);
            if ~isempty(overlap)
                log = append_one(log, coordId, nextId, 'duplicate_application_target_parameter', a, b, ...
                    a.application_affected_sector_id, char(strjoin(overlap, '|')), ...
                    'Both actions write the same simulator state variable on the same application sector.');
                nextId = nextId + 1;
            elseif ~isempty(varsA) && ~isempty(varsB)
                log = append_one(log, coordId, nextId, 'same_sector_orthogonal_param', a, b, ...
                    a.application_affected_sector_id, char(strjoin(union(varsA, varsB), '|')), ...
                    'Different simulator state variables on same application sector; both can coexist if safe.');
                nextId = nextId + 1;
            end
        end
    end
end
end

function [nextId, log] = check_es_sleep_overlap(rowsG, coordId, log, nextId)
esSleep = strcmp(rowsG.module_name, 'ES') & strcmp(rowsG.es_action, 'sleep');
if ~any(esSleep)
    return;
end
esRows = rowsG(esSleep, :);
others = rowsG(~esSleep & ismember(rowsG.module_name, {'COC/OH','LB/MLB','HO/MRO'}) & ...
    ~rowsG.noop_selected & rowsG.application_affected_sector_id > 0, :);
for i = 1:height(esRows)
    a = esRows(i, :);
    src = a.source_sector_id;
    if src <= 0, continue; end
    matches = others(others.source_sector_id == src | ...
        others.target_sector_id == src | ...
        others.application_affected_sector_id == src, :);
    for j = 1:height(matches)
        b = matches(j, :);
        log = append_one(log, coordId, nextId, 'es_sleep_overlap', a, b, src, 'ES_state', ...
            'ES sleep on a sector also touched by COC/LB/HO-MRO action.');
        nextId = nextId + 1;
    end
end
end

function [nextId, log] = check_lb_risky_target(rowsG, T, coordId, cfg, log, nextId)
lbRows = rowsG(strcmp(rowsG.module_name, 'LB/MLB') & ...
    strcmp(rowsG.safe_action_type, 'cio_bias_to_neighbor'), :);
for i = 1:height(lbRows)
    a = lbRows(i, :);
    tgt = a.target_sector_id;
    if tgt <= 0, continue; end
    other = T(T.coordinator_group_id == coordId & T.application_affected_sector_id == tgt & ...
        T.module_priority < a.module_priority, :);
    unsafeFlagged = T(T.coordinator_group_id == coordId & T.application_affected_sector_id == tgt & ...
        ~T.safe_selected_safety_valid, :);
    if height(other) > 0
        b = other(1, :);
        log = append_one(log, coordId, nextId, 'lb_into_risky_target', a, b, tgt, 'CIO_bias', ...
            'LB action targets a sector already addressed by a higher-priority module.');
        nextId = nextId + 1;
    elseif height(unsafeFlagged) > 0
        b = unsafeFlagged(1, :);
        log = append_one(log, coordId, nextId, 'lb_into_risky_target', a, b, tgt, 'CIO_bias', ...
            'LB action targets a sector with an unsafe-flagged action.');
        nextId = nextId + 1;
    end
end
% silence unused cfg lint
cfg = cfg; %#ok<ASGSL,NASGU>
end

function [nextId, log] = check_cross_cell_pairs(rowsG, coordId, log, nextId)
n = height(rowsG);
for i = 1:n-1
    for j = i+1:n
        a = rowsG(i, :);
        b = rowsG(j, :);
        if a.source_sector_id <= 0 || a.target_sector_id <= 0, continue; end
        if b.source_sector_id <= 0 || b.target_sector_id <= 0, continue; end
        if ~(a.source_sector_id == b.target_sector_id && a.target_sector_id == b.source_sector_id)
            continue;
        end
        if a.delta_cio_dB == 0 && b.delta_cio_dB == 0
            continue;
        end
        if sign(a.delta_cio_dB) == -sign(b.delta_cio_dB) && a.delta_cio_dB ~= 0
            log = append_one(log, coordId, nextId, 'cross_cell_counteracting', a, b, ...
                a.source_sector_id, 'CIO', ...
                'Reverse-cell pair has opposite-sign CIO; lower-priority module rejected.');
            nextId = nextId + 1;
        elseif sign(a.delta_cio_dB) == sign(b.delta_cio_dB) && a.delta_cio_dB ~= 0
            log = append_one(log, coordId, nextId, 'cross_cell_reinforcing', a, b, ...
                a.source_sector_id, 'CIO', ...
                'Reverse-cell pair has same-sign CIO; both retained if safe.');
            nextId = nextId + 1;
        end
    end
end
end

function log = append_one(log, coordId, conflictId, conflictType, a, b, sectorId, paramStr, reason)
row = {coordId, char(extract_text(a, 'scenario_name')), extract_double(a, 'realization_id'), ...
    conflictId, conflictType, ...
    char(extract_text(a, 'module_name')), char(extract_text(b, 'module_name')), ...
    extract_double(a, 'selected_action_id_safe'), extract_double(b, 'selected_action_id_safe'), ...
    sectorId, paramStr, sectorId, paramStr, reason, 'error'};
log = [log; cell2table(row, 'VariableNames', log.Properties.VariableNames)];
end

function s = extract_text(rowTable, colName)
v = rowTable.(colName);
if iscell(v), s = string(v{1}); else, s = string(v); end
end

function v = extract_double(rowTable, colName)
x = rowTable.(colName);
if iscell(x), x = cell2mat(x); end
v = double(x);
end

function ps = split_params(s)
if ischar(s), s = string(s); end
parts = split(s, '|');
ps = strtrim(string(parts));
ps = ps(ps ~= "");
end

function T = build_empty_log()
T = table('Size', [0 15], ...
    'VariableTypes', {'double','cell','double','double','cell','cell','cell', ...
    'double','double','double','cell','double','cell','cell','cell'}, ...
    'VariableNames', {'coordinator_group_id','scenario_name','realization_id', ...
    'conflict_id','conflict_type','module_a','module_b','action_id_a','action_id_b', ...
    'affected_sector_id','affected_parameter','application_affected_sector_id', ...
    'application_state_variable','conflict_reason','severity'});
end
