function feasibility = audit_action_implementability(executableActions, mapping)
%AUDIT_ACTION_IMPLEMENTABILITY Per-row implementability of executable actions.
%
% Whole-action status is the worst case across its non-zero parameters:
%   not_implemented_in_simulator  >  partially_implementable  >  implementable_now
% No-op rows (which should not appear in executable set) collapse to
% no_parameter_change_required.

n = height(executableActions);
status = strings(n, 1);
stateVar = strings(n, 1);
helperFn = strings(n, 1);
gapReason = strings(n, 1);
canApply = false(n, 1);
dryRunOnly = true(n, 1);

modules = string(executableActions.module_name);
actionTypes = string(executableActions.accepted_action_type);
esActions = string(executableActions.es_action);

% Severity rank used to combine multi-parameter rows.
sevRank = containers.Map( ...
    {'no_parameter_change_required','implementable_now','partially_implementable','not_implemented_in_simulator'}, ...
    {0, 1, 2, 3});

for i = 1:n
    m = modules(i);
    at = actionTypes(i);
    esa = esActions(i);

    paramRows = build_param_rows(m, at, esa, executableActions(i, :), mapping);

    if isempty(paramRows)
        status(i) = "no_parameter_change_required";
        stateVar(i) = "";
        helperFn(i) = "";
        gapReason(i) = "Action carries no non-zero parameter changes.";
        canApply(i) = false;
        continue;
    end

    worstSev = -1;
    worstIdx = 1;
    for r = 1:height(paramRows)
        s = sevRank(char(paramRows.implementability_status(r)));
        if s > worstSev
            worstSev = s;
            worstIdx = r;
        end
    end
    status(i) = paramRows.implementability_status(worstIdx);
    stateVarStrs = unique(paramRows.simulator_state_variable);
    stateVarStrs = stateVarStrs(stateVarStrs ~= "");
    stateVar(i) = strjoin(stateVarStrs, '; ');
    helperStrs = unique(paramRows.required_simulator_function);
    helperStrs = helperStrs(helperStrs ~= "");
    helperFn(i) = strjoin(helperStrs, '; ');
    gapReason(i) = paramRows.implementation_gap_reason(worstIdx);
    canApply(i) = strcmp(status(i), "implementable_now");
end

feasibility = executableActions;
feasibility.implementability_status = cellstr(status);
feasibility.simulator_state_variable = cellstr(stateVar);
feasibility.required_simulator_function = cellstr(helperFn);
feasibility.implementation_gap_reason = cellstr(gapReason);
feasibility.can_apply_in_phase12b = canApply;
feasibility.dry_run_only_flag = dryRunOnly;
end

function rows = build_param_rows(module, actionType, esAction, row, mapping)
keys = strings(0, 1);
switch module
    case "COC/OH"
        if actionType ~= "compensate_neighbor"
            rows = mapping([], :);
            return;
        end
        if row.delta_prs_dB  ~= 0, keys(end+1) = "delta_prs_dB"; end
        if row.delta_tilt_deg ~= 0, keys(end+1) = "delta_tilt_deg"; end
        if row.delta_cio_dB  ~= 0, keys(end+1) = "delta_cio_dB"; end
    case "LB/MLB"
        if actionType ~= "cio_bias_to_neighbor"
            rows = mapping([], :);
            return;
        end
        if row.delta_cio_dB  ~= 0, keys(end+1) = "delta_cio_dB"; end
    case "HO/MRO"
        if actionType ~= "handover_parameter_adjustment"
            rows = mapping([], :);
            return;
        end
        if row.delta_hom_dB ~= 0, keys(end+1) = "delta_hom_dB"; end
        if row.delta_ttt_ms ~= 0, keys(end+1) = "delta_ttt_ms"; end
        if row.delta_cio_dB ~= 0, keys(end+1) = "delta_cio_dB"; end
    case "ES"
        if esAction == "sleep"
            keys(end+1) = "es_action:sleep";
        elseif esAction == "wake_up"
            keys(end+1) = "es_action:wake_up";
        elseif esAction == "keep_active"
            keys(end+1) = "es_action:keep_active";
        end
end

rows = mapping(ismember(string(mapping.module_name), module) & ...
    ismember(string(mapping.parameter_or_action), keys), :);
end
