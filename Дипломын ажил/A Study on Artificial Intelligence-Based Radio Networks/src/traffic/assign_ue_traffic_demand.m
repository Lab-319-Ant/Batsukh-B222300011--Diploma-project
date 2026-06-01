function ueTraffic = assign_ue_traffic_demand(cfg, ues, rf)
%ASSIGN_UE_TRAFFIC_DEMAND Assign reproducible traffic demand to each UE.
%
% This function does not change RF attachment. It only adds offered traffic
% demand used later for throughput, load, and QoS KPI calculations.

if nargin < 3
    rf = [];
end

numUE = height(ues);
[demandMin, demandMax] = get_demand_range(cfg);

activeRatio = get_active_user_ratio(cfg);
activeCount = min(numUE, max(0, round(activeRatio * numUE)));
isTrafficActive = false(numUE, 1);
if activeCount > 0
    activeIdx = randperm(numUE, activeCount);
    isTrafficActive(activeIdx) = true;
end

demand_Mbps = zeros(numUE, 1);
demand_Mbps(isTrafficActive) = demandMin + ...
    (demandMax - demandMin) * rand(activeCount, 1);

serviceClass = strings(numUE, 1);
serviceClass(~isTrafficActive) = "no_traffic";
if activeCount > 0
    activeDemand = demand_Mbps(isTrafficActive);
    edges = quantile(activeDemand, [1/3, 2/3]);
    serviceClass(isTrafficActive & demand_Mbps <= edges(1)) = string(cfg.serviceClasses{1});
    serviceClass(isTrafficActive & demand_Mbps > edges(1) & demand_Mbps <= edges(2)) = string(cfg.serviceClasses{2});
    serviceClass(isTrafficActive & demand_Mbps > edges(2)) = string(cfg.serviceClasses{3});
end

ue_id = ues.ueId;
x_m = ues.x_m;
y_m = ues.y_m;

ueTraffic = table(ue_id, x_m, y_m, isTrafficActive, demand_Mbps, categorical(serviceClass), ...
    'VariableNames', {'ue_id','x_m','y_m','isTrafficActive','demand_Mbps','service_class'});

if ~isempty(rf)
    ueTraffic.isAttached = rf.isAttached;
    ueTraffic.serving_sector = rf.servingSector;
end
end

function [demandMin, demandMax] = get_demand_range(cfg)
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

if numel(range) ~= 2 || range(1) < 0 || range(2) < range(1)
    error('Invalid traffic demand range for traffic mode %s.', cfg.trafficMode);
end

demandMin = range(1);
demandMax = range(2);
end

function activeRatio = get_active_user_ratio(cfg)
if ~isfield(cfg, 'useActiveUserRatio') || ~cfg.useActiveUserRatio
    activeRatio = 1.0;
    return;
end

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

if ~isfinite(activeRatio) || activeRatio < 0 || activeRatio > 1
    error('Invalid active user ratio %.3f for traffic mode %s.', activeRatio, cfg.trafficMode);
end
end
