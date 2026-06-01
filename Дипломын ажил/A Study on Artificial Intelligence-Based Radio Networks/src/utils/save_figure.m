function save_figure(fig, filePath)
%SAVE_FIGURE Save figure robustly across MATLAB versions.
[folderPath, ~, ~] = fileparts(filePath);
ensure_folder(folderPath);

try
    exportgraphics(fig, filePath, 'Resolution', 200);
catch
    saveas(fig, filePath);
end
end
