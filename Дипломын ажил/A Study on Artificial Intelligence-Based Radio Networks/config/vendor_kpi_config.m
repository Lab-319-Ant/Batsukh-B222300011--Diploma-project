function vcfg = vendor_kpi_config()
%VENDOR_KPI_CONFIG Configuration for real vendor KPI suggestion-only mode.
%
% This mode maps real LTE KPI files onto the simulated 7-site/21-sector
% topology for diagnosis and recommendation display only. It does not
% apply RF actions, mutate live network state, or claim before/after
% healing.

projectRoot = fileparts(fileparts(mfilename('fullpath')));

vcfg.rawKpiDir = fullfile(fileparts(projectRoot), 'KPI');
vcfg.processedDir = fullfile(projectRoot, 'data', 'processed', 'vendor_kpi');
vcfg.resultsDir = fullfile(projectRoot, 'results', 'vendor');
vcfg.tablesDir = fullfile(vcfg.resultsDir, 'tables');
vcfg.figuresDir = fullfile(vcfg.resultsDir, 'figures');
vcfg.vendorCocModelFile = fullfile(projectRoot, 'models', 'phase9b_coc_action_value_model.mat');

vcfg.expectedIntervalsPerCell = 7 * 24 * 4; % 7 days at 15-minute granularity.
vcfg.expectedGranularityMinutes = 15;

% Site mapping supplied by the user. Sector/cell orientation is provisional
% and will be updated after the user maps real sectors.
vcfg.siteMap = table( ...
    [1; 2; 3; 4; 5; 6; 7], ...
    {'CENTER'; 'NORTH'; 'NORTHEAST'; 'SOUTHEAST'; 'SOUTH'; 'SOUTHWEST'; 'NORTHWEST'}, ...
    {'gemtel'; 'uulzwar'; 'denver'; 'rivercastle'; 'mkm'; 'shutis'; 'hiid'}, ...
    {'gemtel.xlsx'; 'uulzwar.xlsx'; 'denver.xlsx'; 'rivercastle.xlsx'; 'mkm.xlsx'; 'shutis.xlsx'; 'hiid.xlsx'}, ...
    'VariableNames', {'sim_site_id','sim_position','vendor_site_key','vendor_file'});

% User-confirmed vendor-cell to simulated-sector mapping.
% Extra fourth/fifth cells are kept in the raw inventory report but ignored
% in the cleaned 21-cell table until explicitly mapped later.
vcfg.cellMap = table( ...
    [1;1;1; 2;2;2; 3;3;3; 4;4;4; 5;5;5; 6;6;6; 7;7;7], ...
    [1;3;2; 5;4;6; 8;9;7; 10;11;12; 14;15;13; 16;17;18; 20;21;19], ...
    [1;2;3; 2;1;3; 1;2;3; 1;2;3; 1;2;3; 4;5;6; 4;5;6], ...
    [30;270;150; 150;30;270; 150;270;30; 30;150;270; 150;270;30; 30;150;270; 150;270;30], ...
    'VariableNames', {'sim_site_id','sim_sector_id','vendor_cell_id','sim_azimuth_deg'});

% COD thresholds. Vendor percentages are standardized to ratios [0, 1].
vcfg.codAvailabilityOutageThreshold = 0.01;
vcfg.codRrcDegradedThreshold = 0.95;
vcfg.codErabSetupDegradedThreshold = 0.95;
vcfg.codRrcDropHighThreshold = 0.05;
vcfg.codErabDropHighThreshold = 0.03;
vcfg.codRssiVeryLow_dBm = -115;
vcfg.codTrafficCollapseRatio = 0.10;
vcfg.codLowEvidenceMinRows = 12;

% COC suggestion/safety thresholds.
vcfg.cocNeighborLoadSafeThreshold = 0.75;
vcfg.cocNeighborLoadHardRejectThreshold = 0.90;
vcfg.cocCompensationLoadCaptureFactor = 0.20;
vcfg.cocCompensationUserCaptureFactor = 0.20;
vcfg.cocRssiWeak_dBm = -105;
vcfg.cocMinAvailabilityForTarget = 0.95;
vcfg.cocMaxDropRateForTarget = 0.03;

% Assumed planning configuration for KPI-only advisory mode. These values
% are not vendor-verified unless replaced by a real configuration export.
vcfg.vendorConfigSource = 'assumed_not_vendor_verified';
vcfg.defaultRsPowerDbm = 15;
vcfg.defaultElectricalTiltDeg = 4;
vcfg.minRsPowerDbm = 12;
vcfg.maxRsPowerDbm = 21;
vcfg.minElectricalTiltDeg = 0;
vcfg.maxElectricalTiltDeg = 10;
vcfg.cocDefaultRsPowerDeltaDb = 1;
vcfg.cocSevereRsPowerDeltaDb = 2;
vcfg.cocTiltDeltaDeg = -1; % Lower electrical tilt to review coverage extension.

% Vendor COC ML advisory settings. These generate candidate action rows for
% a simulation-trained action-value model; they do not apply live actions.
vcfg.vendorCocMlEnabled = true;
vcfg.vendorCocMlTopTargets = 3;
vcfg.vendorCocMlDeltaRsPowerDb = [1 3 6];
vcfg.vendorCocMlDeltaTiltDeg = [0 -1];
vcfg.vendorCocMlDeltaCioDb = 0;
vcfg.vendorCocMlMaxSelectedRsPowerDeltaDb = 6;
vcfg.vendorRsrpProxyMethod = 'RSSI_minus_20dB_planning_proxy';
vcfg.vendorSinrProxyMethod = 'KPI_quality_proxy_from_RSSI_setup_drop_BLER';

% TP / ES vendor advisory settings.
vcfg.tpForecastHorizonSteps = 4; % one hour at 15-minute granularity.
vcfg.tpRollingWindowSteps = 4;
vcfg.tpOverloadPrbThreshold = 0.80;
vcfg.qpCongestionPrbStartThreshold = 0.65;
vcfg.qpHighPrbThreshold = 0.85;
vcfg.qpThroughputDropWarningRatio = 0.15;
vcfg.qpThroughputDropCriticalRatio = 0.35;
vcfg.qpMinThroughputForDropMbps = 1.0;
vcfg.qpDlBlerWarningThreshold = 0.15;
vcfg.qpDlBlerCriticalThreshold = 0.30;
vcfg.qpModerateRiskThreshold = 0.45;
vcfg.qpHighRiskThreshold = 0.70;
vcfg.esLowPredictedDlPrbThreshold = 0.10;
vcfg.esLowActiveUsersThreshold = 1.0;
vcfg.esLowTrafficDlKbyteThreshold = 1024;
vcfg.esMinConsecutiveLowLoadSteps = 4;
vcfg.esNeighborLoadSafeThreshold = 0.60;

% Сайтын идэвхтэй хэрэглэгчдийн урьдчилсан таамаглал.
% Сайт тус бүр дээр шугаман регресс загвар сургаж, 1 цагийн дараах
% идэвхтэй хэрэглэгчдийн тоог таамаглана. Сүүлийн өдрийн өгөгдлийг
% тестийн зориулалтаар хадгална.
vcfg.tpUserForecastTestDays = 1;
vcfg.tpUserForecastHorizonSteps = 4;   % 15 минут × 4 = 1 цаг.
% Цөөн, дахин давтагдашгүй feature: одоо, 1 цагийн өмнө, өчигдрийн
% таамаглах цаг дээрх утга, цагийн циклик кодчилол.
vcfg.tpUserForecastLagSteps = [0 4 92];
vcfg.tpUserForecastMinTrainRows = 96;
% Ridge регуляризацийн λ-г train өгөгдөл дотроос walk-forward аргаар
% сонгоно.
% Overfit-ыг дарахын тулд floor-ыг 10 болгож, өндөр regularization
% сонгох талд хазайлгана. CV-ийн "хамгийн муу нь best-ээс 5%-аас илүүгүй"
% дүрмээр хамгийн томоохон λ-г сонгоно (1-σ rule-тэй адил санаа).
vcfg.tpUserForecastRidgeLambdaGrid = [50 200 1000 5000];
vcfg.tpUserForecastCvHoldoutSteps = 192;   % CV-д хэрэглэх сүүлийн 2 өдөр.
vcfg.tpUserForecastCvToleranceRatio = 0.05;  % хамгийн их 5% хүртэлх MAE-ийн алдагдлыг зөвшөөрнө.
% Сөрөг бус жин (NNLS) — таамаглал бодит масштабаар хязгаарлагдсан байна.
vcfg.tpUserForecastNonNegativeWeights = true;
vcfg.tpUserForecastPredictionClampMultiplier = 1.05;
% Causal adaptive bias correction: тестийн үед "өчигдрийн өмнөх
% таамаглал хэр зөрсөн" гэдгийг exponential smoothing-аар хянаж
% үлдсэн таамаглалд нэмнэ. Энэ нь distribution shift (баасан → бямба)
% үед бодит трафик руу автоматаар буулгана.
vcfg.tpUserForecastBiasCorrectionEnabled = true;
vcfg.tpUserForecastBiasCorrectionAlpha = 0.30;   % шинэ residual-ын жин.
vcfg.tpUserForecastBiasCorrectionShrink = 0.85;  % бүрэн биш хазайлт сэргэнэ (overshoot-аас сэргийлнэ).
end
