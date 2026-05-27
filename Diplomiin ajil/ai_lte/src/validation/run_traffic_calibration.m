function [calibrationSummary, calibrationSectorKpis, calibrationUeResults] = run_traffic_calibration(cfg, topology, ues, rf, rfMap)
%RUN_TRAFFIC_CALIBRATION Evaluate calibrated Phase 2 traffic modes.
%
% This is sensitivity validation, not ML. It reuses the same RF topology,
% UE locations, RSRP/SINR, and RF attachment state, then changes only the
% active-user ratio and traffic demand range.

modes = cfg.trafficModesToTest;
calibrationSummary = table();
calibrationSectorKpis = table();
calibrationUeResults = table();

for m = 1:numel(modes)
    modeName = modes{m};
    cfgMode = cfg;
    cfgMode.trafficMode = modeName;

    % Reset only the traffic random draw for reproducible sensitivity runs.
    % The active cfg.trafficMode reuses the same seed as the single Phase 2
    % run so its row matches the command-window Phase 2 summary.
    if strcmpi(modeName, cfg.trafficMode)
        rng(cfg.seed + 2000);
    else
        rng(cfg.seed + 2000 + m);
    end

    ueTraffic = assign_ue_traffic_demand(cfgMode, ues, rf);
    [ueTrafficResult, sectorCapacity_Mbps] = allocate_sector_throughput(cfgMode, ueTraffic, rf, topology);
    sectorKpiTable = compute_sector_kpis(cfgMode, topology, ueTrafficResult, sectorCapacity_Mbps);
    networkKpiTable = compute_network_kpis(cfgMode, topology, ueTrafficResult, sectorKpiTable, rfMap);

    activeRatio = get_active_user_ratio(cfgMode);
    demandRange = get_demand_range(cfgMode);

    modeCol = {modeName};
    activeUserRatio = activeRatio;
    demandMin_Mbps = demandRange(1);
    demandMax_Mbps = demandRange(2);
    summaryRow = [table(modeCol, activeUserRatio, demandMin_Mbps, demandMax_Mbps, ...
        'VariableNames', {'traffic_mode','active_user_ratio','demand_min_Mbps','demand_max_Mbps'}), ...
        networkKpiTable];
    calibrationSummary = [calibrationSummary; summaryRow]; %#ok<AGROW>

    sectorMode = repmat({modeName}, height(sectorKpiTable), 1);
    sectorKpiTable = addvars(sectorKpiTable, sectorMode, ...
        'Before', 1, 'NewVariableNames', 'traffic_mode');
    calibrationSectorKpis = [calibrationSectorKpis; sectorKpiTable]; %#ok<AGROW>

    ueMode = repmat({modeName}, height(ueTrafficResult), 1);
    ueTrafficResult = addvars(ueTrafficResult, ueMode, ...
        'Before', 1, 'NewVariableNames', 'traffic_mode');
    calibrationUeResults = [calibrationUeResults; ueTrafficResult]; %#ok<AGROW>
end
end

function activeRatio = get_active_user_ratio(cfg)
switch lower(cfg.trafficMode)
    case 'low_load'
        activeRatio = cfg.lowLoadActiveUserRatio;
    case 'normal'
        activeRatio = cfg.normalLoadActiveUserRatio;
    case 'overload'
        activeRatio = cfg.overloadActiveUserRatio;
    case 'heavy_overload'
        activeRatio = cfg.heavyOverloadActiveUserRatio;
    otherwise
        error('Unsupported cfg.trafficMode: %s', cfg.trafficMode);
end
end

function range = get_demand_range(cfg)
switch lower(cfg.trafficMode)
    case 'low_load'
        range = cfg.lowLoadDemandRange_Mbps;
    case 'normal'
        range = cfg.normalLoadDemandRange_Mbps;
    case 'overload'
        range = cfg.overloadDemandRange_Mbps;
    case 'heavy_overload'
        range = cfg.heavyOverloadDemandRange_Mbps;
    otherwise
        error('Unsupported cfg.trafficMode: %s', cfg.trafficMode);
end
end
