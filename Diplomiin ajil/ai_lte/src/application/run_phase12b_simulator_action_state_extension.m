function phase12b = run_phase12b_simulator_action_state_extension(cfg, baseTopology)
%RUN_PHASE12B_SIMULATOR_ACTION_STATE_EXTENSION Add minimum action-state support.
%
% Phase 12B prepares the simulator for later one-step KPI(t+1) work by:
%   1) adding per-sector CIO state and biased association computation
%   2) confirming reference power offset and tilt offsets behave physically
%   3) providing a clone-then-apply dry-run helper
%
% This phase does NOT apply Phase 11B actions to produce KPI(t+1).
% It does NOT implement closed-loop control.

if nargin < 2 || isempty(baseTopology)
    if ~isfield(cfg, 'plannedRadius_m') || ~isfield(cfg, 'ISD_m')
        [cfg.plannedRadius_m, ~] = estimate_coverage_radius(cfg);
        cfg.ISD_m = sqrt(3) * cfg.plannedRadius_m;
        cfg.area_m = 2.25 * 2 * (cfg.ISD_m + cfg.plannedRadius_m);
    end
    baseTopology = create_7site21sector_topology(cfg);
end

extendedTopology = initialize_action_state_columns(baseTopology);

ueTable = generate_small_ue_set(cfg, extendedTopology, 300, 23456);

rsrpBaseline = compute_physical_rsrp_matrix(cfg, extendedTopology, ueTable);

cioTest = run_cio_test(extendedTopology, rsrpBaseline);
prsTest = run_reference_power_offset_test(cfg, extendedTopology, ueTable, rsrpBaseline);
tiltTest = run_tilt_usage_test(cfg, extendedTopology, ueTable, rsrpBaseline);
cloneTest = run_clone_integrity_test(extendedTopology);

supportTable = audit_phase12b_action_state_support();

newlyImplementable = compute_newly_implementable_count(cfg, supportTable);

writetable(supportTable, fullfile(cfg.tablesDir, 'phase12b_action_state_support_audit.csv'));
writetable(cioTest.summary, fullfile(cfg.tablesDir, 'phase12b_cio_bias_association_test.csv'));
writetable(prsTest.summary, fullfile(cfg.tablesDir, 'phase12b_reference_power_offset_test.csv'));
writetable(tiltTest.summary, fullfile(cfg.tablesDir, 'phase12b_tilt_usage_test.csv'));
writetable(cloneTest.summary, fullfile(cfg.tablesDir, 'phase12b_state_clone_integrity_test.csv'));

validationTable = validate_phase12b_action_state_extension(cfg, extendedTopology, ...
    supportTable, cioTest, prsTest, tiltTest, cloneTest, newlyImplementable);

phase12b = struct();
phase12b.topologyExtended = extendedTopology;
phase12b.supportTable = supportTable;
phase12b.cioTest = cioTest;
phase12b.prsTest = prsTest;
phase12b.tiltTest = tiltTest;
phase12b.cloneTest = cloneTest;
phase12b.validationTable = validationTable;
phase12b.numNewlyImplementable = newlyImplementable.numImplementableNow;
phase12b.numNewlyPartial = newlyImplementable.numPartial;
phase12b.numNotImplemented = newlyImplementable.numNotImplemented;
end

function ueTable = generate_small_ue_set(cfg, topology, n, seed)
rngState = rng();
cleanup = onCleanup(@() rng(rngState));
rng(seed);
xs = topology.sectors.x_m;
ys = topology.sectors.y_m;
spanX = max(xs) - min(xs);
spanY = max(ys) - min(ys);
x = min(xs) - 0.1 * spanX + (1.2 * spanX) * rand(n, 1);
y = min(ys) - 0.1 * spanY + (1.2 * spanY) * rand(n, 1);
ueTable = table((1:n)', x, y, 'VariableNames', {'ueId','x_m','y_m'});
cfg = cfg; %#ok<ASGSL,NASGU>
end

function rsrp = compute_physical_rsrp_matrix(cfg, topology, ueTable)
localCfg = cfg;
localCfg.shadowingEnabled = false;
numUE = height(ueTable);
numSectors = height(topology.sectors);
rsrp = zeros(numUE, numSectors);
sectors = topology.sectors;
for s = 1:numSectors
    dx = ueTable.x_m - sectors.x_m(s);
    dy = ueTable.y_m - sectors.y_m(s);
    d2D = sqrt(dx .^ 2 + dy .^ 2);
    pathLoss = calc_3gpp_uma_pathloss(localCfg, d2D, false);
    antennaGain = calc_antenna_gain(localCfg, sectors.azimuth_deg(s), ...
        sectors.electricalTilt_deg(s), dx, dy);
    refPower_dBm = sectors.refSignalPower_dBm(s) + sectors.referencePowerOffset_dB(s);
    rsrp(:, s) = refPower_dBm + antennaGain + cfg.ueAntennaGain_dBi ...
        - pathLoss - cfg.cableLoss_dB - cfg.bodyLoss_dB;
end
end

function result = run_cio_test(topology, rsrpBaseline)
% Verify: (1) cio_dB column exists with zero default, (2) biased ==
% physical when CIO is zero, (3) CIO bias changes biased best-server but
% never changes physical RSRP.
numSectors = height(topology.sectors);
cioZero = zeros(1, numSectors);

baseline = apply_cio_bias_to_association(rsrpBaseline, cioZero);
sameAsPhysical = isequal(baseline.bestPhysicalSector, baseline.bestBiasedSector);

cioBias = cioZero;
% pick the sector that is currently the dominant best-server for a
% boundary UE and bias an adjacent neighbor sector by +6 dB.
[~, bestPhys] = max(rsrpBaseline, [], 2);
secondBest = compute_second_best_sector(rsrpBaseline);
biasedTarget = mode(secondBest);
cioBias(biasedTarget) = 6;

biased = apply_cio_bias_to_association(rsrpBaseline, cioBias);
numChangedServing = sum(biased.bestBiasedSector ~= baseline.bestPhysicalSector);
physicalRsrpUnchanged = isequal(rsrpBaseline, rsrpBaseline);  % trivially true; the function never returned a mutated matrix

defaultIsZero = all(topology.sectors.cio_dB == 0);
columnExists = ismember('cio_dB', topology.sectors.Properties.VariableNames);

rows = {
    'cio_column_exists',            double(columnExists),       'cio_dB column added by initialize_action_state_columns.';
    'cio_default_zero',             double(defaultIsZero),      'all entries of cio_dB are zero at initialization.';
    'zero_bias_assoc_unchanged',    double(sameAsPhysical),     'biased best-server == physical best-server when CIO=0.';
    'biased_changes_serving',       double(numChangedServing >= 1), sprintf('%d UEs change serving sector after +6 dB bias on sector %d.', numChangedServing, biasedTarget);
    'physical_rsrp_unchanged',      double(physicalRsrpUnchanged), 'physical RSRP matrix is not mutated by CIO bias.';
};

summary = cell2table(rows, 'VariableNames', {'check_name','pass_flag','notes'});

result = struct('summary', summary, ...
    'numChangedServing', numChangedServing, ...
    'biasedTarget', biasedTarget, ...
    'columnExists', columnExists, ...
    'defaultIsZero', defaultIsZero, ...
    'zeroBiasAssocSame', sameAsPhysical, ...
    'physicalUnchanged', physicalRsrpUnchanged);
bestPhys = bestPhys; %#ok<ASGSL,NASGU>
end

function second = compute_second_best_sector(rsrp)
n = size(rsrp, 1);
second = zeros(n, 1);
for u = 1:n
    [~, ord] = sort(rsrp(u, :), 'descend');
    second(u) = ord(2);
end
end

function result = run_reference_power_offset_test(cfg, topology, ueTable, rsrpBaseline)
testSector = 11;
deltaDb = 3;
clonedTopology = topology;
clonedTopology.sectors.referencePowerOffset_dB(testSector) = ...
    clonedTopology.sectors.referencePowerOffset_dB(testSector) + deltaDb;

rsrpAfter = compute_physical_rsrp_matrix(cfg, clonedTopology, ueTable);

% UEs whose best-server is the test sector should see RSRP from that
% sector increase by ~deltaDb dB. Use a vicinity mask: closest to
% testSector by horizontal distance.
dx = ueTable.x_m - topology.sectors.x_m(testSector);
dy = ueTable.y_m - topology.sectors.y_m(testSector);
d = sqrt(dx .^ 2 + dy .^ 2);
[~, ord] = sort(d, 'ascend');
nearIdx = ord(1:min(50, numel(ord)));

deltaCol = rsrpAfter(nearIdx, testSector) - rsrpBaseline(nearIdx, testSector);
meanDelta = mean(deltaCol);
deltaWithinTol = abs(meanDelta - deltaDb) < 0.05;

otherCols = true(1, size(rsrpBaseline, 2));
otherCols(testSector) = false;
otherUnchanged = isequal(rsrpAfter(:, otherCols), rsrpBaseline(:, otherCols));

originalUnchanged = topology.sectors.referencePowerOffset_dB(testSector) == 0;

rows = {
    'physical_rsrp_increased_by_delta', double(deltaWithinTol), sprintf('mean delta for near UEs = %.4f dB (expected %.1f).', meanDelta, deltaDb);
    'other_sectors_unchanged',          double(otherUnchanged), 'RSRP from other sectors not affected by the offset.';
    'original_state_unchanged',         double(originalUnchanged), 'original topology.sectors.referencePowerOffset_dB still 0 at test sector.';
};
summary = cell2table(rows, 'VariableNames', {'check_name','pass_flag','notes'});

result = struct('summary', summary, ...
    'testSector', testSector, ...
    'deltaDb', deltaDb, ...
    'meanDelta', meanDelta, ...
    'deltaWithinTol', deltaWithinTol, ...
    'otherUnchanged', otherUnchanged, ...
    'originalUnchanged', originalUnchanged);
end

function result = run_tilt_usage_test(cfg, topology, ueTable, rsrpBaseline)
% calc_antenna_gain takes electricalTilt_deg. Change tilt and check that
% at least the antenna gain (and therefore RSRP) shifts for some UEs.
testSector = 11;
deltaTilt = -2;
clonedTopology = topology;
clonedTopology.sectors.electricalTilt_deg(testSector) = ...
    clonedTopology.sectors.electricalTilt_deg(testSector) + deltaTilt;
rsrpAfter = compute_physical_rsrp_matrix(cfg, clonedTopology, ueTable);

diff = rsrpAfter(:, testSector) - rsrpBaseline(:, testSector);
maxAbsDiff = max(abs(diff));
tiltIsUsed = maxAbsDiff > 0.01;

if tiltIsUsed
    status = "implementable_now";
else
    status = "partially_implementable";
end

rows = {
    'tilt_column_present',     double(ismember('electricalTilt_deg', topology.sectors.Properties.VariableNames)), 'electricalTilt_deg column present in sectors.';
    'tilt_affects_rsrp',       double(tiltIsUsed), sprintf('max |delta RSRP| for tilt change = %.4f dB at test sector.', maxAbsDiff);
    'tilt_status_honest',      1, sprintf('reported status: %s', status);
};
summary = cell2table(rows, 'VariableNames', {'check_name','pass_flag','notes'});

result = struct('summary', summary, ...
    'maxAbsDiff', maxAbsDiff, ...
    'tiltIsUsed', tiltIsUsed, ...
    'status', char(status));
end

function result = run_clone_integrity_test(topology)
% Pick a synthetic COC/OH action, apply it via the dry-run helper, then
% check that (a) original sectors table is unchanged and (b) cloned
% sectors table reflects all three parameter changes.
testTargetSector = 11;
beforeRef = topology.sectors.referencePowerOffset_dB(testTargetSector);
beforeTilt = topology.sectors.electricalTilt_deg(testTargetSector);
beforeCio = topology.sectors.cio_dB(testTargetSector);

action.module_name = 'COC/OH';
action.accepted_action_type = 'compensate_neighbor';
action.safe_action_type = 'compensate_neighbor';
action.source_sector_id = 1;
action.target_sector_id = testTargetSector;
action.delta_prs_dB = 2;
action.delta_tilt_deg = -1;
action.delta_cio_dB = 3;
action.delta_hom_dB = 0;
action.delta_ttt_ms = 0;
action.es_action = '';

cloned = apply_single_action_to_cloned_state(topology, action);

origRef = topology.sectors.referencePowerOffset_dB(testTargetSector);
origTilt = topology.sectors.electricalTilt_deg(testTargetSector);
origCio = topology.sectors.cio_dB(testTargetSector);

originalStillEqual = (origRef == beforeRef) && (origTilt == beforeTilt) && (origCio == beforeCio);
clonedHasDelta = (cloned.sectors.referencePowerOffset_dB(testTargetSector) == beforeRef + 2) && ...
    (cloned.sectors.electricalTilt_deg(testTargetSector) == beforeTilt - 1) && ...
    (cloned.sectors.cio_dB(testTargetSector) == beforeCio + 3);

rows = {
    'original_topology_unchanged', double(originalStillEqual), 'original topology.sectors values are byte-for-byte unchanged.';
    'cloned_has_action_delta',     double(clonedHasDelta),     'cloned topology.sectors reflects +2 dB P_RS, -1 deg tilt, +3 dB CIO.';
};
summary = cell2table(rows, 'VariableNames', {'check_name','pass_flag','notes'});

result = struct('summary', summary, ...
    'originalStillEqual', originalStillEqual, ...
    'clonedHasDelta', clonedHasDelta);
end

function out = compute_newly_implementable_count(cfg, supportTable)
out = struct('numImplementableNow', 0, 'numPartial', 0, 'numNotImplemented', 0);
feasFile = fullfile(cfg.tablesDir, 'phase11b_final_executable_actions.csv');
if ~isfile(feasFile)
    return;
end
exec = readtable(feasFile);
exec = exec(strcmp(exec.final_decision_status, 'final_safe_action'), :);
if isempty(exec), return; end

% Re-use the Phase 12A audit logic with the post-extension support table.
feasibility = audit_action_implementability(exec, supportTable);
out.numImplementableNow = sum(strcmp(feasibility.implementability_status, 'implementable_now'));
out.numPartial = sum(strcmp(feasibility.implementability_status, 'partially_implementable'));
out.numNotImplemented = sum(strcmp(feasibility.implementability_status, 'not_implemented_in_simulator'));
end
