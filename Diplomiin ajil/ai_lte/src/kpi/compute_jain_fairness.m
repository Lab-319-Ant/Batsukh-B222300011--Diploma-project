function J = compute_jain_fairness(x)
%COMPUTE_JAIN_FAIRNESS Compute Jain's fairness index.
%
% For Phase 2, this is typically called with all UE served throughputs,
% including zero-throughput unattached UEs.

x = x(:);
x(~isfinite(x)) = 0;
n = numel(x);
den = n * sum(x .^ 2);

if n == 0 || den <= 0
    J = NaN;
else
    J = (sum(x) ^ 2) / den;
end
end
