function [statusCol, executableCol, unresolvedFlag] = classify_final_action_status(...
    acceptedFlag, rejectedFlag, noopSelected, fallbackUsed, safeSelectedSafetyValid, ...
    rejectionType, safetyRelatedRej)
%CLASSIFY_FINAL_ACTION_STATUS Map Phase 11A flags to Phase 11B status.
%
% Precedence (top wins):
%   1) fallback_used && ~safety_valid                -> unresolved_unsafe_fallback (NOT executable)
%   2) rejected_flag && safety_related rejection     -> rejected_safety_conflict
%   3) rejected_flag (other rejection type)          -> rejected_priority_conflict
%   4) accepted_flag && noop_selected                -> final_noop (NOT executable)
%   5) accepted_flag && safety_valid && !noop        -> final_safe_action (executable)
%   6) anything else                                 -> diagnostic_only
%
% Inputs are column vectors with one entry per Phase 11A candidate row.

n = numel(acceptedFlag);
statusCol = strings(n, 1);
executableCol = false(n, 1);
unresolvedFlag = false(n, 1);

acceptedFlag = logical(acceptedFlag);
rejectedFlag = logical(rejectedFlag);
noopSelected = logical(noopSelected);
fallbackUsed = logical(fallbackUsed);
safeOk = logical(safeSelectedSafetyValid);
safetyRelatedRej = logical(safetyRelatedRej);

for i = 1:n
    if fallbackUsed(i) && ~safeOk(i)
        statusCol(i) = "unresolved_unsafe_fallback";
        unresolvedFlag(i) = true;
        executableCol(i) = false;
        continue;
    end
    if rejectedFlag(i)
        if safetyRelatedRej(i) || is_safety_rejection_type(rejectionType(i))
            statusCol(i) = "rejected_safety_conflict";
        else
            statusCol(i) = "rejected_priority_conflict";
        end
        executableCol(i) = false;
        continue;
    end
    if acceptedFlag(i) && noopSelected(i)
        statusCol(i) = "final_noop";
        executableCol(i) = false;
        continue;
    end
    if acceptedFlag(i) && safeOk(i) && ~noopSelected(i)
        statusCol(i) = "final_safe_action";
        executableCol(i) = true;
        continue;
    end
    statusCol(i) = "diagnostic_only";
    executableCol(i) = false;
end
end

function tf = is_safety_rejection_type(rt)
if ismissing(rt) || rt == ""
    tf = false;
    return;
end
tf = any(rt == ["unsafe_non_fallback","es_sleep_overlap","lb_into_risky_target"]);
end
