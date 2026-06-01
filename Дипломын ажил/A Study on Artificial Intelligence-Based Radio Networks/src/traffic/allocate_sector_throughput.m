function [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfg, ueTraffic, rf, topology)
%ALLOCATE_SECTOR_THROUGHPUT Allocate simplified sector throughput to RF-attached UEs.
%
% The throughput model is intentionally simplified:
%   eta = loss_factor * log2(1 + SINR_linear)
%   peak UE throughput = bandwidth_MHz * eta
%
% A sector capacity is approximated as bandwidth_MHz * mean(eta) for the
% UEs attached to that sector. If offered demand exceeds this capacity, UEs
% receive proportional demand sharing, capped by each UE's peak throughput.
% This is not a PRB-level LTE scheduler.

numUE = height(ueTraffic);
numSectors = height(topology.sectors);

SINR_linear = 10 .^ (rf.bestSINR_dB ./ 10);
spectralEfficiency_bpsHz = cfg.implementationLossFactor .* log2(1 + SINR_linear);
spectralEfficiency_bpsHz = min(spectralEfficiency_bpsHz, cfg.maxSpectralEfficiency_bpsHz);
spectralEfficiency_bpsHz = max(spectralEfficiency_bpsHz, 0);

peakThroughput_Mbps = cfg.bandwidth_MHz .* spectralEfficiency_bpsHz;
servedThroughput_Mbps = zeros(numUE, 1);
sectorCapacity_Mbps = zeros(numSectors, 1);

for s = 1:numSectors
    idx = rf.isAttached & rf.servingSector == s;
    if ~any(idx)
        sectorCapacity_Mbps(s) = 0;
        continue;
    end

    etaMean = mean(spectralEfficiency_bpsHz(idx), 'omitnan');
    sectorCapacity_Mbps(s) = cfg.bandwidth_MHz * etaMean;
    offeredTraffic = sum(ueTraffic.demand_Mbps(idx), 'omitnan');

    if offeredTraffic <= sectorCapacity_Mbps(s)
        allocation = ueTraffic.demand_Mbps(idx);
    else
        allocation = ueTraffic.demand_Mbps(idx) .* sectorCapacity_Mbps(s) ./ max(offeredTraffic, eps);
    end

    allocation = min(allocation, peakThroughput_Mbps(idx));
    servedThroughput_Mbps(idx) = allocation;
end

unservedDemand_Mbps = max(ueTraffic.demand_Mbps - servedThroughput_Mbps, 0);
isTrafficActive = ueTraffic.isTrafficActive;
meetsMinThroughput = isTrafficActive & rf.isAttached & ...
    servedThroughput_Mbps >= cfg.minThroughput_Mbps;
qosSatisfied = isTrafficActive & rf.isAttached & ...
    servedThroughput_Mbps >= cfg.qosDemandSatisfactionThreshold .* ueTraffic.demand_Mbps;

ue_id = ueTraffic.ue_id;
x_m = ueTraffic.x_m;
y_m = ueTraffic.y_m;
serving_sector = rf.servingSector;
isAttached = rf.isAttached;
isTrafficActive = ueTraffic.isTrafficActive;
demand_Mbps = ueTraffic.demand_Mbps;
service_class = ueTraffic.service_class;
bestRSRP_dBm = rf.bestRSRP_dBm;
bestSINR_dB = rf.bestSINR_dB;

ueTrafficResult = table(ue_id, x_m, y_m, serving_sector, isAttached, ...
    isTrafficActive, demand_Mbps, service_class, spectralEfficiency_bpsHz, peakThroughput_Mbps, ...
    servedThroughput_Mbps, unservedDemand_Mbps, meetsMinThroughput, qosSatisfied, bestRSRP_dBm, bestSINR_dB, ...
    'VariableNames', {'ue_id','x_m','y_m','serving_sector','isAttached', ...
    'isTrafficActive','demand_Mbps','service_class','spectralEfficiency_bpsHz','peakThroughput_Mbps', ...
    'servedThroughput_Mbps','unservedDemand_Mbps','meetsMinThroughput','qosSatisfied','bestRSRP_dBm','bestSINR_dB'});
end
