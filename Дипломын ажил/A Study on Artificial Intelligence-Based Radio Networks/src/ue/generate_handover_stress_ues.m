function stressUes = generate_handover_stress_ues(cfg, topology, baseUes)
%GENERATE_HANDOVER_STRESS_UES Bias UE locations toward sector-boundary regions.
%
% Boundary candidates are selected by the lowest best-vs-second-best RSRP
% gaps over the same planned service area. This creates synthetic handover
% stress only; it does not simulate mobility or HO/MRO control.

targetBoundaryCount = round(cfg.handoverStressBoundaryFraction * cfg.numUE);
candidateCfg = cfg;
candidateCfg.numUE = max(cfg.numUE, cfg.numUE * cfg.handoverStressCandidateMultiplier);
candidateCfg.ueDropMode = 'service_area_uniform';
candidateCfg.shadowingEnabled = false;

if isfield(cfg, 'handoverStressSeed')
    rng(cfg.handoverStressSeed);
else
    rng(cfg.seed + 7000);
end

candidateUes = generate_ues(candidateCfg, topology);
candidateRf = calc_rsrp_sinr(candidateCfg, topology, candidateUes);
candidateGap = candidateRf.bestRSRP_dBm - candidateRf.secondBestRSRP_dBm;
attachedCandidateIdx = find(candidateRf.isAttached);
[~, gapOrder] = sort(candidateGap(attachedCandidateIdx), 'ascend');
candidateBoundaryIdx = attachedCandidateIdx(gapOrder);
candidateNonBoundaryIdx = setdiff((1:height(candidateUes)).', candidateBoundaryIdx);

numBoundary = min(targetBoundaryCount, numel(candidateBoundaryIdx));
selectedBoundary = [];
if numBoundary > 0
    selectedBoundary = candidateBoundaryIdx(randperm(numel(candidateBoundaryIdx), numBoundary));
end

numRemaining = cfg.numUE - numel(selectedBoundary);
selectedRemaining = [];
if numRemaining > 0 && ~isempty(candidateNonBoundaryIdx)
    numFromNonBoundary = min(numRemaining, numel(candidateNonBoundaryIdx));
    selectedRemaining = candidateNonBoundaryIdx(randperm(numel(candidateNonBoundaryIdx), numFromNonBoundary));
end

selectedIdx = [selectedBoundary(:); selectedRemaining(:)];
if numel(selectedIdx) < cfg.numUE
    needed = cfg.numUE - numel(selectedIdx);
    filler = baseUes(1:needed, :);
    selectedUes = candidateUes(selectedIdx, :);
    stressUes = [selectedUes; filler];
else
    stressUes = candidateUes(selectedIdx(1:cfg.numUE), :);
end

stressUes.ueId = (1:height(stressUes)).';
end
