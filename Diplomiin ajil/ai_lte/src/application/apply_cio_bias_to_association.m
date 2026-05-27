function out = apply_cio_bias_to_association(rsrpMatrix, cioPerSector)
%APPLY_CIO_BIAS_TO_ASSOCIATION Compute physical + biased best-server.
%
% Inputs:
%   rsrpMatrix    - [numUE x numSectors] physical RSRP in dBm
%   cioPerSector  - [1 x numSectors] or [numSectors x 1] per-sector CIO bias in dB
%
% Outputs (struct):
%   bestPhysicalRSRP_dBm    - column vector, max(rsrpMatrix, [], 2)
%   bestPhysicalSector      - column vector, argmax of physical RSRP
%   biasedMetric_dB         - [numUE x numSectors] = RSRP + cio (broadcast)
%   bestBiasedMetric_dB     - column vector, max of biasedMetric
%   bestBiasedSector        - column vector, argmax of biasedMetric
%
% CRITICAL: this function never modifies the physical RSRP matrix. SINR /
% interference computations must continue to use the physical RSRP, not
% the biased metric.

if isempty(rsrpMatrix)
    out = struct('bestPhysicalRSRP_dBm', [], 'bestPhysicalSector', [], ...
        'biasedMetric_dB', [], 'bestBiasedMetric_dB', [], 'bestBiasedSector', []);
    return;
end

cioRow = reshape(double(cioPerSector), 1, []);
if numel(cioRow) ~= size(rsrpMatrix, 2)
    error('apply_cio_bias_to_association: cio length (%d) must equal numSectors (%d).', ...
        numel(cioRow), size(rsrpMatrix, 2));
end

[bestPhysRsrp, bestPhysSec] = max(rsrpMatrix, [], 2);
biasedMetric = rsrpMatrix + cioRow;
[bestBiasedMet, bestBiasedSec] = max(biasedMetric, [], 2);

out = struct();
out.bestPhysicalRSRP_dBm = bestPhysRsrp;
out.bestPhysicalSector = bestPhysSec;
out.biasedMetric_dB = biasedMetric;
out.bestBiasedMetric_dB = bestBiasedMet;
out.bestBiasedSector = bestBiasedSec;
end
