function out = classify_phase12e_kpi_outcomes(baselineAi)
%CLASSIFY_PHASE12E_KPI_OUTCOMES Per-row outcome class + tradeoff flag.
%
% outcome_class values:
%   improved          - any positive headline gain (QoS up OR served traffic up
%                       OR load down) AND no severe attach-rate drop > 5pp
%   worsened          - QoS down OR served traffic down significantly OR
%                       attach drops more than 5pp without any compensating gain
%   unchanged         - all deltas within +/- 1e-3 of zero
%   improved_with_tradeoff - clear KPI gain but attach rate drops > 5pp
%
% tradeoff_flag is true when there is at least one positive direction
% AND at least one negative direction in the same row.

n = height(baselineAi);
outcomeClass = strings(n, 1);
tradeoffFlag = false(n, 1);

dq = baselineAi.delta_qos_satisfaction_ratio;
dst = baselineAi.delta_served_traffic_Mbps;
dl = baselineAi.delta_mean_sector_load;
ds = baselineAi.delta_mean_sinr_dB;
dr = baselineAi.delta_mean_rsrp_dB;
da = baselineAi.delta_attach_rate;

threshold = 1e-3;
attachDropTol = 0.05;

posDir = (dq > threshold) | (dst > threshold) | (dl < -threshold) | ...
    (ds > threshold) | (dr > threshold);
negDir = (dq < -threshold) | (dst < -threshold) | (dl > threshold) | ...
    (da < -threshold) | (ds < -threshold) | (dr < -threshold);

bigAttachDrop = da < -attachDropTol;

for i = 1:n
    if posDir(i) && negDir(i)
        tradeoffFlag(i) = true;
    end

    if abs(dq(i)) < threshold && abs(da(i)) < threshold && ...
            abs(dl(i)) < threshold && abs(dst(i)) < threshold
        outcomeClass(i) = "unchanged";
    elseif posDir(i) && bigAttachDrop(i)
        outcomeClass(i) = "improved_with_tradeoff";
    elseif posDir(i) && ~negDir(i)
        outcomeClass(i) = "improved";
    elseif posDir(i) && negDir(i) && dq(i) > 0
        outcomeClass(i) = "improved_with_tradeoff";
    elseif negDir(i) && ~posDir(i)
        outcomeClass(i) = "worsened";
    else
        outcomeClass(i) = "mixed";
    end
end

% NOTE: struct('field', cellArray) would create a STRUCT ARRAY (one
% element per cell). Build the struct field-by-field so outcome_class
% stays a single Nx1 cell array inside one scalar struct.
out = struct();
out.outcome_class = cellstr(outcomeClass);
out.tradeoff_flag = tradeoffFlag;
end
