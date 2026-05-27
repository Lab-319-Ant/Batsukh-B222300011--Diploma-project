function scenarioPlan = get_phase4_scenario_plan(cfg)
%GET_PHASE4_SCENARIO_PLAN Build deterministic Phase 4 scenario realization plan.

scenarioTypes = cfg.phase4ScenarioTypes;
numRealizations = cfg.phase4NumRealizationsPerScenario;
numRows = numel(scenarioTypes) * numRealizations;

dataset_id = (1:numRows).';
scenario_id = zeros(numRows, 1);
realization_id = zeros(numRows, 1);
scenario_name = cell(numRows, 1);
traffic_mode = cell(numRows, 1);
impaired_sector_id = zeros(numRows, 1);
impaired_sector_status = cell(numRows, 1);
referencePowerOffset_dB = zeros(numRows, 1);
txPowerOffset_dB = zeros(numRows, 1);
enable_es_candidate_flag = false(numRows, 1);
enable_handover_stress_metrics = false(numRows, 1);
ue_seed = zeros(numRows, 1);
shadowing_seed = zeros(numRows, 1);
traffic_seed = zeros(numRows, 1);

row = 0;
for s = 1:numel(scenarioTypes)
    scenarioName = scenarioTypes{s};
    for r = 1:numRealizations
        row = row + 1;
        scenario = scenario_from_name(cfg, s, scenarioName, r);

        scenario_id(row) = s;
        realization_id(row) = r;
        scenario_name{row} = scenario.scenario_name;
        traffic_mode{row} = scenario.traffic_mode;
        impaired_sector_id(row) = scenario.impaired_sector_id;
        impaired_sector_status{row} = scenario.impaired_sector_status;
        referencePowerOffset_dB(row) = scenario.referencePowerOffset_dB;
        txPowerOffset_dB(row) = scenario.txPowerOffset_dB;
        enable_es_candidate_flag(row) = scenario.enable_es_candidate_flag;
        enable_handover_stress_metrics(row) = scenario.enable_handover_stress_metrics;

        base = cfg.phase4BaseSeed + 10000 * s + r;
        ue_seed(row) = choose_seed(cfg.phase4UseVariableUESamplingSeed, base + 100, cfg.seed + 100);
        shadowing_seed(row) = choose_seed(cfg.phase4UseVariableShadowingSeed, base + 200, cfg.seed + 200);
        traffic_seed(row) = choose_seed(cfg.phase4UseVariableTrafficSeed, base + 300, cfg.seed + 300);
    end
end

scenarioPlan = table(dataset_id, scenario_id, realization_id, scenario_name, traffic_mode, ...
    impaired_sector_id, impaired_sector_status, referencePowerOffset_dB, txPowerOffset_dB, ...
    enable_es_candidate_flag, enable_handover_stress_metrics, ue_seed, shadowing_seed, traffic_seed);
end

function seed = choose_seed(useVariable, variableSeed, fixedSeed)
if useVariable
    seed = variableSeed;
else
    seed = fixedSeed;
end
end

function scenario = scenario_from_name(cfg, scenarioId, scenarioName, realizationId)
scenario = empty_scenario();
scenario.scenario_id = scenarioId;
scenario.scenario_name = scenarioName;

switch scenarioName
    case 'normal'
        scenario.traffic_mode = 'normal';
    case 'low_load'
        scenario.traffic_mode = 'low_load';
    case 'overload'
        scenario.traffic_mode = 'overload';
    case 'degraded_sector'
        scenario.traffic_mode = 'normal';
        scenario.impaired_sector_id = select_impaired_sector(cfg, realizationId);
        scenario.impaired_sector_status = 'degraded';
        scenario.referencePowerOffset_dB = cfg.degradedReferencePowerOffset_dB;
        scenario.txPowerOffset_dB = cfg.degradedTxPowerOffset_dB;
    case 'outage_sector'
        scenario.traffic_mode = 'normal';
        scenario.impaired_sector_id = select_impaired_sector(cfg, realizationId);
        scenario.impaired_sector_status = 'outage';
        scenario.referencePowerOffset_dB = cfg.outageReferencePowerOffset_dB;
        scenario.txPowerOffset_dB = cfg.outageTxPowerOffset_dB;
    case 'low_load_energy_saving_candidate'
        scenario.traffic_mode = 'low_load';
        scenario.enable_es_candidate_flag = true;
    case 'handover_stress'
        scenario.traffic_mode = 'normal';
        scenario.enable_handover_stress_metrics = true;
    case 'mixed_conflict'
        scenario.traffic_mode = 'overload';
        scenario.impaired_sector_id = select_impaired_sector(cfg, realizationId);
        scenario.impaired_sector_status = 'degraded';
        scenario.referencePowerOffset_dB = cfg.degradedReferencePowerOffset_dB;
        scenario.txPowerOffset_dB = cfg.degradedTxPowerOffset_dB;
    otherwise
        error('Unsupported Phase 4 scenario type: %s', scenarioName);
end
end

function sectorId = select_impaired_sector(cfg, realizationId)
ids = cfg.phase4ImpairedSectorIds(:);
sectorId = ids(mod(realizationId - 1, numel(ids)) + 1);
end

function scenario = empty_scenario()
scenario = struct( ...
    'scenario_id', 0, ...
    'scenario_name', '', ...
    'traffic_mode', '', ...
    'impaired_sector_id', 0, ...
    'impaired_sector_status', 'normal', ...
    'referencePowerOffset_dB', 0, ...
    'txPowerOffset_dB', 0, ...
    'enable_es_candidate_flag', false, ...
    'enable_handover_stress_metrics', false);
end
