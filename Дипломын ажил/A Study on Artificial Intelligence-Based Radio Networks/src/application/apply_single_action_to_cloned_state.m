function clonedTopology = apply_single_action_to_cloned_state(topology, actionRow)
%APPLY_SINGLE_ACTION_TO_CLONED_STATE Dry-run application on a cloned topology.
%
% Inputs:
%   topology  - struct with .sites and .sectors tables; must already have
%               Phase 12B columns (run initialize_action_state_columns first).
%   actionRow - one row from Phase 11B final executable actions, or any
%               action-shaped struct/table with fields:
%                 module_name, accepted_action_type (or safe_action_type),
%                 source_sector_id, target_sector_id,
%                 delta_prs_dB, delta_tilt_deg, delta_cio_dB,
%                 delta_hom_dB, delta_ttt_ms, es_action
%
% Output:
%   clonedTopology - deep-cloned topology with the requested parameter
%   changes applied. The original topology is NEVER mutated. No KPI is
%   recomputed.
%
% Mapping policy (consistent with src/application/map_action_to_simulator_state.m):
%   COC/OH compensate_neighbor:
%     target.referencePowerOffset_dB += delta_prs_dB
%     target.electricalTilt_deg      += delta_tilt_deg
%     target.cio_dB                  += delta_cio_dB
%   LB/MLB cio_bias_to_neighbor:
%     target.cio_dB                  += delta_cio_dB
%   HO/MRO handover_parameter_adjustment:
%     source.hom_offset_dB           += delta_hom_dB   (PLACEHOLDER: NOT RF-CONNECTED)
%     source.ttt_offset_ms           += delta_ttt_ms   (PLACEHOLDER: NOT RF-CONNECTED)
%     target.cio_dB                  += delta_cio_dB
%   ES sleep:    source.is_sleeping = true   (PLACEHOLDER: NO RF/KPI IMPACT YET)
%   ES wake_up:  source.is_sleeping = false  (PLACEHOLDER)
%   ES keep_active: no change
%
% No-op or rejected actions should not reach this helper; we silently
% return the cloned topology unchanged if the action is a no-op.

clonedTopology = topology;
% MATLAB copies tables by value, but be explicit:
clonedTopology.sectors = topology.sectors;
if isfield(topology, 'sites')
    clonedTopology.sites = topology.sites;
end

mod = lookup_text(actionRow, 'module_name');
actType = lookup_text(actionRow, 'safe_action_type');
if actType == "", actType = lookup_text(actionRow, 'accepted_action_type'); end
if actType == "", actType = lookup_text(actionRow, 'action_type'); end
esAction = lookup_text(actionRow, 'es_action');

src = lookup_number(actionRow, 'source_sector_id');
tgt = lookup_number(actionRow, 'target_sector_id');
dPrs = lookup_number(actionRow, 'delta_prs_dB');
dTilt = lookup_number(actionRow, 'delta_tilt_deg');
dCio = lookup_number(actionRow, 'delta_cio_dB');
dHom = lookup_number(actionRow, 'delta_hom_dB');
dTtt = lookup_number(actionRow, 'delta_ttt_ms');

sectorIds = clonedTopology.sectors.sectorId;

switch mod
    case "COC/OH"
        if actType ~= "compensate_neighbor", return; end
        ti = find_sector_row(sectorIds, tgt);
        if isnan(ti), return; end
        clonedTopology.sectors.referencePowerOffset_dB(ti) = ...
            clonedTopology.sectors.referencePowerOffset_dB(ti) + dPrs;
        clonedTopology.sectors.electricalTilt_deg(ti) = ...
            clonedTopology.sectors.electricalTilt_deg(ti) + dTilt;
        clonedTopology.sectors.cio_dB(ti) = clonedTopology.sectors.cio_dB(ti) + dCio;
    case "LB/MLB"
        if actType ~= "cio_bias_to_neighbor", return; end
        ti = find_sector_row(sectorIds, tgt);
        if isnan(ti), return; end
        clonedTopology.sectors.cio_dB(ti) = clonedTopology.sectors.cio_dB(ti) + dCio;
    case "HO/MRO"
        if actType ~= "handover_parameter_adjustment", return; end
        si = find_sector_row(sectorIds, src);
        ti = find_sector_row(sectorIds, tgt);
        if ~isnan(si)
            clonedTopology.sectors.hom_offset_dB(si) = ...
                clonedTopology.sectors.hom_offset_dB(si) + dHom;
            clonedTopology.sectors.ttt_offset_ms(si) = ...
                clonedTopology.sectors.ttt_offset_ms(si) + dTtt;
        end
        if ~isnan(ti)
            clonedTopology.sectors.cio_dB(ti) = clonedTopology.sectors.cio_dB(ti) + dCio;
        end
    case "ES"
        si = find_sector_row(sectorIds, src);
        if isnan(si), return; end
        if esAction == "sleep"
            clonedTopology.sectors.is_sleeping(si) = true;
        elseif esAction == "wake_up"
            clonedTopology.sectors.is_sleeping(si) = false;
        end
end
end

function v = lookup_number(actionRow, name)
v = 0;
if isstruct(actionRow) && isfield(actionRow, name)
    v = double(actionRow.(name));
elseif istable(actionRow) && ismember(name, actionRow.Properties.VariableNames)
    raw = actionRow.(name);
    if iscell(raw), raw = raw{1}; end
    v = double(raw);
end
if isempty(v) || ~isfinite(v), v = 0; end
end

function s = lookup_text(actionRow, name)
s = "";
if isstruct(actionRow) && isfield(actionRow, name)
    raw = actionRow.(name);
elseif istable(actionRow) && ismember(name, actionRow.Properties.VariableNames)
    raw = actionRow.(name);
    if iscell(raw), raw = raw{1}; end
else
    return;
end
s = string(raw);
end

function idx = find_sector_row(sectorIds, sectorId)
hit = find(sectorIds == sectorId, 1, 'first');
if isempty(hit), idx = NaN; else, idx = hit; end
end
