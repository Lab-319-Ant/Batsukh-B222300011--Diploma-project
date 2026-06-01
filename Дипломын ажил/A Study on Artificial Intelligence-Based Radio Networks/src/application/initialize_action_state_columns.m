function topology = initialize_action_state_columns(topology)
%INITIALIZE_ACTION_STATE_COLUMNS Add Phase 12B action-state columns.
%
% Ensures the following columns exist on topology.sectors with default
% zero/false values. Existing columns are preserved.
%
%   referencePowerOffset_dB  - additive offset to refSignalPower_dBm (RSRP)
%   txPowerOffset_dB         - additive offset to txPower_dBm (SINR/interference)
%   cio_dB                   - per-sector association bias; affects best-server
%                              metric only, NOT physical RSRP/SINR
%   hom_offset_dB            - placeholder, NOT YET RF-CONNECTED
%   ttt_offset_ms            - placeholder, NOT YET RF-CONNECTED
%   is_sleeping              - placeholder; presence does NOT yet alter RF/KPI
%
% This is a state-extension only. No KPI(t+1) is generated.

sectors = topology.sectors;
n = height(sectors);

sectors = ensure_numeric_column(sectors, 'referencePowerOffset_dB', n);
sectors = ensure_numeric_column(sectors, 'txPowerOffset_dB', n);
sectors = ensure_numeric_column(sectors, 'cio_dB', n);
sectors = ensure_numeric_column(sectors, 'hom_offset_dB', n);
sectors = ensure_numeric_column(sectors, 'ttt_offset_ms', n);
sectors = ensure_logical_column(sectors, 'is_sleeping', n);

topology.sectors = sectors;
end

function T = ensure_numeric_column(T, name, n)
if ~ismember(name, T.Properties.VariableNames)
    T.(name) = zeros(n, 1);
end
end

function T = ensure_logical_column(T, name, n)
if ~ismember(name, T.Properties.VariableNames)
    T.(name) = false(n, 1);
end
end
