function phase13 = run_phase13_final_result_package(cfg)
%RUN_PHASE13_FINAL_RESULT_PACKAGE Assemble thesis-ready outputs only.
%
% Phase 13 packages completed simulation outputs. It does NOT introduce
% new simulation logic, NOT train models, NOT apply actions, and NOT
% extend closed-loop behaviour. The final claim remains a synthetic
% AI/ML-assisted LTE SON-inspired framework with limited one-step
% KPI(t)->KPI(t+1) evaluation for implementable COC/OH and LB/MLB.
%
% This run archives any stale thesis_package contents to a timestamped
% sub-folder before writing fresh outputs derived from the corrected
% post-fix Phase 12E summaries.

packageDir = fullfile(cfg.resultsDir, 'thesis_package');
ensure_folder(packageDir);
archive_stale_package(packageDir);

bundle = collect_final_result_tables(cfg);
tables = build_final_thesis_summary_tables(bundle);
limitations = build_final_limitations_table();
beforeAfter = build_before_after_kpi_tables(bundle);
manifest = build_final_figure_manifest(cfg);

% Generate the before/after figure inside the thesis package so the
% manifest's "thesis package" path branch can find it.
figurePath = fullfile(packageDir, 'final_before_after_kpi_comparison.png');
try
    plot_phase13_before_after_kpi_comparison(beforeAfter, tables.baselineAiOracle, figurePath);
catch ME
    warning('Phase 13 before/after figure failed: %s', ME.message);
end

% Re-build manifest AFTER the figure write so availability is correct.
manifest = build_final_figure_manifest(cfg);

write_tables_to_package(packageDir, tables, manifest, limitations, beforeAfter);
narrativePaths = build_final_result_narrative(cfg, tables, manifest, limitations, beforeAfter);

validationTable = validate_phase13_final_result_package(cfg, packageDir, ...
    tables, manifest, limitations, narrativePaths, beforeAfter);
writetable(validationTable, fullfile(packageDir, 'final_result_package_validation.csv'));

counts = summarize_phase13_package(packageDir);

phase13 = struct();
phase13.packageDir = packageDir;
phase13.tables = tables;
phase13.manifest = manifest;
phase13.limitations = limitations;
phase13.beforeAfter = beforeAfter;
phase13.narrativePaths = narrativePaths;
phase13.validationTable = validationTable;
phase13.counts = counts;
phase13.numMdFiles = counts.numMdFiles;
phase13.numCsvFiles = counts.numCsvFiles;
phase13.numFigureManifestEntries = counts.numFigureManifestEntries;
phase13.numAvailableFigures = counts.numAvailableFigures;

% Booleans for console / validator reporting.
phase13.usesCorrectedPostFixValues = check_post_fix_values(tables);
if ~isempty(tables.kpiImprovement)
    appliedRow = strcmp(tables.kpiImprovement.metric, 'applied_action_count');
    if any(appliedRow)
        phase13.appliedActionCount = round(tables.kpiImprovement.value(find(appliedRow, 1)));
    else
        phase13.appliedActionCount = 0;
    end
else
    phase13.appliedActionCount = 0;
end
end

function archive_stale_package(packageDir)
%ARCHIVE_STALE_PACKAGE Move any existing thesis-package files into a stale_/ subfolder.
listing = dir(packageDir);
listing = listing(~[listing.isdir]);
if isempty(listing)
    return;
end
stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<DATST>
staleDir = fullfile(packageDir, sprintf('stale_%s', stamp));
ensure_folder(staleDir);
for i = 1:numel(listing)
    src = fullfile(packageDir, listing(i).name);
    dst = fullfile(staleDir, listing(i).name);
    try
        movefile(src, dst, 'f');
    catch ME
        warning('Could not archive stale file %s: %s', listing(i).name, ME.message);
    end
end
end

function tf = check_post_fix_values(tables)
%CHECK_POST_FIX_VALUES Reject if the famous stale 104-action count is present.
tf = true;
if isempty(tables.kpiImprovement), tf = false; return; end
KI = tables.kpiImprovement;
appliedRow = strcmp(KI.metric, 'applied_action_count');
if ~any(appliedRow), tf = false; return; end
applied = KI.value(find(appliedRow, 1, 'first'));
if isnan(applied) || applied <= 0, tf = false; return; end
if applied == 104, tf = false; end  % stale value signature
end

function write_tables_to_package(packageDir, tables, manifest, limitations, beforeAfter)
write(packageDir, 'final_module_status_table.csv',          tables.moduleStatus);
write(packageDir, 'final_baseline_ai_oracle_summary.csv',   tables.baselineAiOracle);
write(packageDir, 'final_kpi_improvement_summary.csv',      tables.kpiImprovement);
write(packageDir, 'final_scenario_summary.csv',             tables.scenarioSummary);
write(packageDir, 'final_module_validation_summary.csv',    tables.moduleValidation);
write(packageDir, 'final_safety_coordination_summary.csv',  tables.safetyCoordination);
write(packageDir, 'final_oracle_regret_summary.csv',        tables.oracleRegret);
write(packageDir, 'final_limitations_table.csv',            limitations);
% Persist manifest WITHOUT the absolute full_path column (Windows backslash
% paths confuse readtable round-trip and file_name is sufficient for
% downstream consumers).
manifestForCsv = manifest;
if ismember('full_path', manifestForCsv.Properties.VariableNames)
    manifestForCsv = removevars(manifestForCsv, 'full_path');
end
write(packageDir, 'final_figure_manifest.csv',              manifestForCsv);
write(packageDir, 'final_before_after_kpi_summary.csv',     beforeAfter.summary);
write(packageDir, 'final_before_after_kpi_by_module.csv',   beforeAfter.byModule);
write(packageDir, 'final_before_after_kpi_by_scenario.csv', beforeAfter.byScenario);
end

function write(packageDir, name, T)
filePath = fullfile(packageDir, name);
if isempty(T)
    fid = fopen(filePath, 'w');
    if fid >= 0
        fprintf(fid, '# empty -- no upstream data available\n');
        fclose(fid);
    end
    return;
end
writetable(T, filePath);
end
