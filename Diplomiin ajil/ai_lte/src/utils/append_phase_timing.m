function timingTable = append_phase_timing(timingTable, cfg, phaseName, elapsedSeconds, status, notes)
%APPEND_PHASE_TIMING Append one row to the run timing log and save it.

if nargin < 6
    notes = '';
end
if isempty(timingTable)
    timingTable = table();
end

run_mode = {cfg.runMode};
phase_name = {phaseName};
elapsed_seconds = elapsedSeconds;
status_cell = {status};
notes_cell = {notes};
timestamp = {char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'))};

row = table(run_mode, phase_name, elapsed_seconds, status_cell, notes_cell, timestamp, ...
    'VariableNames', {'run_mode','phase_name','elapsed_seconds','status','notes','timestamp'});
timingTable = [timingTable; row]; %#ok<AGROW>

if isfield(cfg, 'tablesDir')
    writetable(timingTable, fullfile(cfg.tablesDir, 'run_phase_timing_log.csv'));
end
end
