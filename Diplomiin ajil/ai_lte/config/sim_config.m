function cfg = sim_config()
%SIM_CONFIG Configuration for LTE RF, traffic KPI, and calibration phases.
%
% This configuration keeps the project in a simulation-only LTE framing.
% RSRP uses LTE reference signal power P_RS, while SINR/interference uses
% total sector downlink transmit power.

%% Reproducibility
cfg.seed = 42;

%% Active phase
% Phase 8B is counterfactual action evaluation only (deterministic local
% KPI proxy). It is NOT closed-loop SON control: no action selection, no
% oracle, no safety enforcement, no decision coordinator, no action
% application, no KPI(t+1) feedback.
cfg.phase = 'Phase8B_Counterfactual_Action_Evaluation';
cfg.phaseName = 'Phase8B_Counterfactual_Action_Evaluation';
cfg.phaseDescription = 'Counterfactual evaluation only; not closed-loop.';
cfg.rfPhaseName = 'Phase_1B_7site21sector_RF_validation';
cfg.runMode = 'full'; % full, phase4_only, phase8a_only, reuse_phase4_to_phase8a, fast_debug
cfg.enablePhase8B = true;
cfg.enablePhase8C = true;
cfg.enablePhase9A = true;
cfg.enablePhase9B = true;
cfg.enablePhase10A = true;
cfg.enablePhase11A = true;
cfg.enablePhase11B = true;
cfg.enablePhase12A = true;
cfg.enablePhase12B = true;
cfg.enablePhase12C = true;
cfg.enablePhase12D = true;
cfg.enablePhase12E = true;
cfg.enablePhase13 = false; % Disabled until the supervised-only thesis package is regenerated.
cfg.enableUnsupervisedClustering = false; % K-means monitor archived/disabled for supervised-only workflow.
cfg.enableSupervisedActionValueComparison = true;

%% Phase 9B action-value regression hyperparameters
cfg.phase9bNumLearningCycles = 200;
cfg.phase9bLearnRate = 0.05;
cfg.phase9bMaxNumSplits = 32;
cfg.topologyMode = '7site21sector';
cfg.numSites = 7;
cfg.sectorsPerSite = 3;

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
cfg.defaultTilt_deg = cfg.electricalTilt_deg;
cfg.horizontalHPBW_deg = 65;
cfg.verticalHPBW_deg = 10;
cfg.frontBackAtten_dB = 30;
cfg.sideLobeAtten_dB = 20;

% Sector azimuths for tri-sector macro sites
cfg.sectorAzimuths_deg = [30; 150; 270];

%% RF planning thresholds
cfg.minRSRP_dBm = -105;
cfg.minSINR_dB = -3;
cfg.coverageMargin_dB = 8;
cfg.sectorEdgeLoss_dB = 3;
cfg.cableLoss_dB = 0;
cfg.bodyLoss_dB = 0;

%% Propagation
cfg.pathlossModel = '3GPP_UMa_NLOS';
cfg.minDistance_m = 10;
cfg.maxPlanningDistance_m = 5000;
cfg.shadowingEnabled = true;
cfg.shadowingStd_dB = 6;

%% Noise model for SINR
cfg.noiseFigure_dB = 9;
cfg.thermalNoiseDensity_dBmHz = -174;

%% UE generation
cfg.numUE = 500;
cfg.serviceAreaMode = 'planned_coverage_union';
cfg.ueDropMode = 'service_area_uniform';
cfg.outsideFraction = 0.20;

% cfg.area_m is updated in main.m after the link-budget radius and ISD are known.
cfg.area_m = 3000;

%% Phase 2 traffic and KPI model
cfg.trafficMode = 'normal';       % allowed: 'low_load', 'normal', 'overload', 'heavy_overload'
cfg.serviceClasses = {'low_rate','normal_rate','high_rate'};

cfg.useActiveUserRatio = true;
cfg.trafficModesToTest = {'low_load','normal','overload','heavy_overload'};

cfg.lowLoadActiveUserRatio = 0.05;
cfg.normalLoadActiveUserRatio = 0.15;
cfg.overloadActiveUserRatio = 0.30;
cfg.heavyOverloadActiveUserRatio = 1.00;

cfg.lowLoadDemandRange_Mbps = [0.5 3];
cfg.normalLoadDemandRange_Mbps = [1 8];
cfg.overloadDemandRange_Mbps = [3 12];
cfg.heavyOverloadDemandRange_Mbps = [20 80];

% UE is QoS-satisfied if served throughput >= threshold * demand.
cfg.qosDemandSatisfactionThreshold = 0.8;

% Simplified wideband spectral-efficiency model:
% eta = implementationLossFactor * log2(1 + SINR_linear), capped below.
cfg.implementationLossFactor = 0.7;
cfg.maxSpectralEfficiency_bpsHz = 4.5;

% Phase 2 uses a traffic-aware load ratio, not LTE PRB scheduling.
cfg.sectorOverloadThreshold = 0.8;
cfg.minThroughput_Mbps = 1.0;

%% Phase 3 scenario generation
cfg.defaultImpairedSectorId = 11;
cfg.degradedReferencePowerOffset_dB = -10;
cfg.degradedTxPowerOffset_dB = -10;
cfg.outageReferencePowerOffset_dB = -100;
cfg.outageTxPowerOffset_dB = -100;
cfg.energySavingCandidateLoadThreshold = 0.10;
cfg.handoverMarginRisk_dB = 3;
cfg.handoverStressBoundaryFraction = 0.60;
cfg.handoverStressCandidateMultiplier = 10;
cfg.handoverStressMarginRisk_dB = 6;

%% Phase 4 multi-scenario dataset generation
cfg.phase4NumRealizationsPerScenario = 21;
cfg.phase4ScenarioTypes = { ...
    'normal', ...
    'low_load', ...
    'overload', ...
    'degraded_sector', ...
    'outage_sector', ...
    'low_load_energy_saving_candidate', ...
    'handover_stress', ...
    'mixed_conflict' ...
};
cfg.phase4ImpairedSectorIds = 1:21;
cfg.phase4BaseSeed = 1000;
cfg.phase4UseVariableShadowingSeed = true;
cfg.phase4UseVariableTrafficSeed = true;
cfg.phase4UseVariableUESamplingSeed = true;

%% Phase 6A COD dataset preparation
cfg.phase6NumCODRealizationsPerClass = 150;
cfg.phase6CODImpairedSectorIds = 1:21;
cfg.phase6CODBaseSeed = 6000;

%% Phase 6B COD classifier training
cfg.phase6bNumTrees = 200;

%% Phase 7A temporal TP/QP dataset generation
cfg.phase7TimeStepMinutes = 15;
cfg.phase7TimeStepsPerDay = 96;
cfg.phase7NumDays = 5;
cfg.phase7ScenarioTypes = {'normal','low_load','overload','handover_stress','mixed_conflict'};
cfg.phase7BaseSeed = 7000;
cfg.phase7UseStaticRFPerScenario = true;
cfg.phase7UseTimeVaryingTraffic = true;
cfg.phase7TrafficDailyProfile = 'diurnal';
cfg.phase7TrafficNoiseStd = 0.10;
cfg.phase7LagSteps = [1 2 4];
cfg.phase7PredictionHorizonSteps = 1;

%% Phase 7B TP/QP regression training
cfg.phase7bNumLearningCycles = 150;

%% Phase 8A candidate action generation
cfg.phase8TopNNeighbors = 3;
cfg.phase8MaxSameSiteTargetRatio = 0.50;
cfg.phase8MinSecondBestSupportRatio = 0.20;

%% Phase 8B deterministic counterfactual action evaluation
% Reward = sum_i(w_i * KPI_gain_i) - w_penalty * sum(safety/cost terms).
% Safety/cost penalty weight is intentionally larger than any single gain
% weight so that unsafe candidates cannot win on optimization alone.
cfg.phase8bMaxActions = Inf;
cfg.phase8bRewardCoverageWeight = 1.00;
cfg.phase8bRewardQosWeight = 1.20;
cfg.phase8bRewardLoadWeight = 1.00;
cfg.phase8bRewardHandoverWeight = 1.00;
cfg.phase8bRewardEnergyWeight = 0.50;
cfg.phase8bPenaltyWeight = 3.00;
cfg.phase8bOverloadPenaltyThreshold = 0.80;

% Phase 8B KPI sanitization defaults. Some sectors in some scenarios have
% no UEs or no signal, producing NaN/Inf KPI fields. The Phase 8B
% counterfactual evaluator replaces missing/non-finite values with these
% physically conservative defaults so the reward stays finite.
cfg.noSignalRSRP_dBm = -140;
cfg.noSignalSINR_dB = -20;
cfg.defaultMissingQoS = 0;
cfg.defaultMissingAttachRate = 0;
cfg.defaultMissingLoad = 0;
cfg.defaultMissingHandoverRisk = 0;

% Phase 8B safety-check stub thresholds. These are used by
% safety_check_action.m to flag invalid candidates. They are deliberately
% conservative so that destructive candidates are rejected.
cfg.safetyAttachLossThreshold = 0.05;       % >5% drop in source attach rate
cfg.safetyQosLossThreshold = 0.05;          % >5% drop in source QoS satisfaction
cfg.safetySinrLossThreshold_dB = 1.0;       % >1 dB drop in source SINR
cfg.safetyRsrpLossThreshold_dB = 2.0;       % >2 dB drop in source RSRP
cfg.safetyNeighborOverloadThreshold = 0.90; % target load post-action above 90%
cfg.safetyHandoverRiskIncrease = 0.05;      % +5% increase in handover-risk score
cfg.safetyEsSleepBlockOnImpaired = true;    % block ES sleep on impaired/degraded
cfg.cocDeltaPRS_dB = [0 1 2 3];
cfg.cocDeltaTilt_deg = [-2 -1 0 1];
cfg.cocDeltaCIO_dB = [0 1 2];
cfg.enableCocCioCandidates = true;
cfg.lbDeltaCIO_dB = [-6 -3 0 3 6];
cfg.esActions = {'keep_active','sleep','wake_up'};
cfg.esCandidateLoadThreshold = 0.10;
cfg.mroDeltaHOM_dB = [-2 -1 0 1 2];
cfg.mroDeltaTTT_ms = [-160 0 160 320];
cfg.mroDeltaCIO_dB = [-3 0 3];
% COC trigger thresholds. cocLowAttachThreshold is consulted only after the
% cluster monitor has flagged the sector as a COC candidate, so it can be
% strict. Standalone low-attach triggers are no longer supported.
cfg.cocLowAttachThreshold = 0.50;
cfg.cocLowRsrpThreshold_dBm = -105;
cfg.lbOverloadThreshold = 0.80;
cfg.mroHandoverRiskThreshold = 0.30;
cfg.esLowLoadThreshold = 0.10;

%% Output folders
projectRoot = fileparts(fileparts(mfilename('fullpath')));
cfg.resultsDir = fullfile(projectRoot, 'results');
cfg.figuresDir = fullfile(cfg.resultsDir, 'figures');
cfg.tablesDir = fullfile(cfg.resultsDir, 'tables');
cfg.logsDir = fullfile(cfg.resultsDir, 'logs');
cfg.modelsDir = fullfile(projectRoot, 'models');
end
