function counts = summarize_phase13_package(packageDir)
%SUMMARIZE_PHASE13_PACKAGE Return counts for the thesis-package contents.

counts = struct();
counts.packageDir = packageDir;
counts.numMdFiles = 0;
counts.numCsvFiles = 0;
counts.numFigureManifestEntries = 0;
counts.numAvailableFigures = 0;

if ~isfolder(packageDir)
    return;
end

mdFiles = dir(fullfile(packageDir, '*.md'));
csvFiles = dir(fullfile(packageDir, '*.csv'));
counts.numMdFiles = numel(mdFiles);
counts.numCsvFiles = numel(csvFiles);

manifestFile = fullfile(packageDir, 'final_figure_manifest.csv');
if isfile(manifestFile)
    try
        T = readtable(manifestFile);
        counts.numFigureManifestEntries = height(T);
        v = T.available_flag;
        if iscell(v), v = str2double(v); end
        if isstring(v), v = double(v); end
        counts.numAvailableFigures = sum(double(v) > 0);
    catch
        % ignore parse errors
    end
end
end
