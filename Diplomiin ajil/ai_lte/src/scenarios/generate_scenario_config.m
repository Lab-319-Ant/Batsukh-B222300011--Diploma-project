function scenarios = generate_scenario_config(cfg)
%GENERATE_SCENARIO_CONFIG Define deterministic Phase 3 LTE scenarios.
%
% Scenario labels are output labels only. They are not ML features here.

impairedSectorId = cfg.defaultImpairedSectorId;

scenarios = repmat(empty_scenario(), 8, 1);

scenarios(1) = make_scenario(1, 'normal', 'normal', 0, 'normal', 0, 0, false, false);
scenarios(2) = make_scenario(2, 'low_load', 'low_load', 0, 'normal', 0, 0, false, false);
scenarios(3) = make_scenario(3, 'overload', 'overload', 0, 'normal', 0, 0, false, false);
scenarios(4) = make_scenario(4, 'degraded_sector', 'normal', impairedSectorId, 'degraded', ...
    cfg.degradedReferencePowerOffset_dB, cfg.degradedTxPowerOffset_dB, false, false);
scenarios(5) = make_scenario(5, 'outage_sector', 'normal', impairedSectorId, 'outage', ...
    cfg.outageReferencePowerOffset_dB, cfg.outageTxPowerOffset_dB, false, false);
scenarios(6) = make_scenario(6, 'low_load_energy_saving_candidate', 'low_load', 0, 'normal', ...
    0, 0, true, false);
scenarios(7) = make_scenario(7, 'handover_stress', 'normal', 0, 'normal', ...
    0, 0, false, true);
scenarios(8) = make_scenario(8, 'mixed_conflict', 'overload', impairedSectorId, 'degraded', ...
    cfg.degradedReferencePowerOffset_dB, cfg.degradedTxPowerOffset_dB, false, false);
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

function scenario = make_scenario(id, name, trafficMode, impairedSectorId, status, refOffset, txOffset, esFlag, hoFlag)
scenario = empty_scenario();
scenario.scenario_id = id;
scenario.scenario_name = name;
scenario.traffic_mode = trafficMode;
scenario.impaired_sector_id = impairedSectorId;
scenario.impaired_sector_status = status;
scenario.referencePowerOffset_dB = refOffset;
scenario.txPowerOffset_dB = txOffset;
scenario.enable_es_candidate_flag = esFlag;
scenario.enable_handover_stress_metrics = hoFlag;
end
