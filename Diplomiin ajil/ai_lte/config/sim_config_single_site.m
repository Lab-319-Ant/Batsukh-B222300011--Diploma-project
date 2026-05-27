function cfg = sim_config_single_site()
%SIM_CONFIG_SINGLE_SITE Configuration for Phase 1A single-site LTE RF validation.
%
% Engineering note:
%   - RSRP uses LTE reference signal power P_RS.
%   - SINR uses total sector downlink transmit power as a simplified full-band model.
%   - Main path-loss model is 3GPP UMa NLOS from TR 38.901-style formulation.
%   - COST-231/Hata is intentionally not used as the main 2.6 GHz model.

%% Reproducibility
cfg.seed = 42;

%% Carrier and LTE radio assumptions
cfg.fc_GHz = 2.6;
cfg.bandwidth_MHz = 20;

% LTE power assumptions
cfg.txPower_dBm = 46;             % total sector DL power, used for SINR/interference
cfg.refSignalPower_dBm = 15;      % reference signal power, used for RSRP

% Antenna assumptions
cfg.antennaGain_dBi = 17;
cfg.ueAntennaGain_dBi = 0;
cfg.hBS_m = 25;
cfg.hUE_m = 1.5;
cfg.electricalTilt_deg = 6;
cfg.horizontalHPBW_deg = 65;
cfg.verticalHPBW_deg = 10;
cfg.frontBackAtten_dB = 30;
cfg.sideLobeAtten_dB = 20;

% Sector azimuths for tri-sector macro site
cfg.sectorAzimuths_deg = [30; 150; 270];

%% RF planning thresholds
cfg.minRSRP_dBm = -105;           % attach threshold for RSRP
cfg.minSINR_dB = -3;              % very weak LTE edge threshold for attach validation
cfg.coverageMargin_dB = 8;        % shadow/fading/planning margin used in radius planning
cfg.sectorEdgeLoss_dB = 3;        % additional conservative sector-edge planning loss
cfg.cableLoss_dB = 0;             % set nonzero if feeder/cable loss is modeled
cfg.bodyLoss_dB = 0;              % optional UE/body loss

%% Propagation
cfg.pathlossModel = '3GPP_UMa_NLOS';
cfg.minDistance_m = 10;
cfg.maxPlanningDistance_m = 5000;
cfg.shadowingEnabled = true;
cfg.shadowingStd_dB = 6;

%% Noise model for SINR
cfg.noiseFigure_dB = 7;
cfg.thermalNoiseDensity_dBmHz = -174;

%% UE generation
cfg.numUE = 500;

% Options:
%   'service_area_uniform' : drops all UEs inside planned service radius.
%   'square_uniform'       : drops all UEs in full square study window.
%   'mixed_radius'         : drops most UEs inside radius and some outside for attach testing.
cfg.ueDropMode = 'mixed_radius';
cfg.outsideFraction = 0.25;

% Study window is for plots and stress-test UE drops.
% It is not the same as planned service area.
cfg.area_m = 2500;                % square plot area: [-area/2, area/2]

%% Output folders
projectRoot = fileparts(fileparts(mfilename('fullpath')));
cfg.resultsDir = fullfile(projectRoot, 'results');
cfg.figuresDir = fullfile(cfg.resultsDir, 'figures');
cfg.tablesDir = fullfile(cfg.resultsDir, 'tables');
end
