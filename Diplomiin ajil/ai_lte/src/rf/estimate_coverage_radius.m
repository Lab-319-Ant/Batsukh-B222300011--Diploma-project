function [radius_m, linkBudget] = estimate_coverage_radius(cfg)
%ESTIMATE_COVERAGE_RADIUS Estimate cell-edge radius using MAPL and 3GPP UMa path loss.
%
% RSRP planning equation:
%   RSRP = P_RS + G_TX + G_UE - PL - losses/margins
%
% Therefore:
%   MAPL = P_RS + G_TX + G_UE - RSRP_min - losses/margins

MAPL_dB = cfg.refSignalPower_dBm + cfg.antennaGain_dBi + cfg.ueAntennaGain_dBi ...
    - cfg.minRSRP_dBm ...
    - cfg.cableLoss_dB ...
    - cfg.coverageMargin_dB ...
    - cfg.sectorEdgeLoss_dB ...
    - cfg.bodyLoss_dB;

% Search distance where PL(d) reaches MAPL. Shadowing is not used in planning radius.
dVec = linspace(cfg.minDistance_m, cfg.maxPlanningDistance_m, 20000).';
plVec = calc_3gpp_uma_pathloss(cfg, dVec, false);

if MAPL_dB < plVec(1)
    radius_m = cfg.minDistance_m;
elseif MAPL_dB > plVec(end)
    radius_m = cfg.maxPlanningDistance_m;
else
    radius_m = interp1(plVec, dVec, MAPL_dB, 'linear', 'extrap');
end

linkBudget = struct();
linkBudget.MAPL_dB = MAPL_dB;
linkBudget.P_RS_dBm = cfg.refSignalPower_dBm;
linkBudget.G_TX_dBi = cfg.antennaGain_dBi;
linkBudget.G_UE_dBi = cfg.ueAntennaGain_dBi;
linkBudget.RSRP_min_dBm = cfg.minRSRP_dBm;
linkBudget.coverageMargin_dB = cfg.coverageMargin_dB;
linkBudget.sectorEdgeLoss_dB = cfg.sectorEdgeLoss_dB;
end
