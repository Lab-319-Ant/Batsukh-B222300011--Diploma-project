function ensure_folder(folderPath)
%ENSURE_FOLDER Create folder if it does not exist.
if ~exist(folderPath, 'dir')
    mkdir(folderPath);
end
end
