function success = saveEditedDetections(fileFullPath)

% saveEditedDetections: saves all existing and new detections to a file
%
% This script saves all of the existing and new detections to a .txt file,
% in the format of a tab-delimited table. For newly created labels, this
% will save to whatever file name the user specified in the popup window.
%
% For loaded detections, this will be stored in a file with
% the same name as the original detections, except that 'raw' will be replaced
% with 'verified'. If this word is not found within the original name, then
% the file will be saved as [original name]_verified.txt
%
% Overwrite protection: an existing verified file is only overwritten if it
% is the file these labels were loaded from, or the file this WMV session
% has already saved to. Otherwise the edits are saved to a new file with a
% date/time stamp ([name]_verified_yyyyMMdd_HHmmss.txt), the user is warned,
% and later saves in the same session go to that stamped file.
%
% Failed saves: if the save folder cannot be found or the file cannot be
% written, the user is told with a dialog (not just the command window) and
% offered the chance to save somewhere else.
%
% Returns true if the edits were written to disk.
% Created by Michaela Alksne and Shane Andres

    global REMORA

    success = false;

    % Forget the last verified file until this save succeeds, so a failed
    % save never leaves makeNewExamples pointing at an older file.
    if isfield(REMORA.lt.lVis_det, 'verifiedFilePath')
        REMORA.lt.lVis_det = rmfield(REMORA.lt.lVis_det, 'verifiedFilePath');
    end

    % Format here just in case
    REMORA.lt.lVis_det.dataTable.start_time.Format = 'yyyy-MM-dd HH:mm:ss.SSS';
    REMORA.lt.lVis_det.dataTable.end_time.Format = 'yyyy-MM-dd HH:mm:ss.SSS';

    % access the main data table
    data = REMORA.lt.lVis_det.dataTable;

    % naming the new label file
    [folder, name, ext] = fileparts(fileFullPath);

    % set file name for newly created detections
    if isfield(REMORA.lt.lVis_det, 'newFile') && REMORA.lt.lVis_det.newFile == true
        saveFileName = name;

    % set file name for loaded detections
    else
        % if original file name contains "raw", replace with "verified"
        if contains(name, 'raw')
            saveFileName = strrep(name, 'raw', 'verified');
        % if file name already contains "verified", overwrite
        elseif contains(name, 'verified')
            saveFileName = name;
        % if file name does not contain either, append "_verified" to end
        else
            saveFileName = strcat(name, '_verified');
        end
    end
    saveFilePath = fullfile(folder, [saveFileName, ext]);


    % --- overwrite protection ---
    % The file this session has already saved to (cleared whenever a label
    % file is loaded or created, in wmvControl)
    sessionSavePath = '';
    if isfield(REMORA.lt.lVis_det, 'saveFilePath')
        sessionSavePath = REMORA.lt.lVis_det.saveFilePath;
    end

    overwriteWarning = '';
    if ~isempty(sessionSavePath)
        % keep saving to the file this session already wrote, so repeated
        % saves don't create a new date-stamped file every time
        saveFilePath = sessionSavePath;
    elseif isfile(saveFilePath) && ~isSameFile(saveFilePath, fileFullPath)
        % a verified file already exists here and it is not the file these
        % labels were loaded from: save to a date-stamped file instead
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        stampedFileName = [saveFileName, '_', stamp, ext];
        saveFilePath = fullfile(folder, stampedFileName);
        overwriteWarning = sprintf(['Warning: this save would have overwritten the current ', ...
            'verified .txt file in this path:\n%s\n\n', ...
            'A verified .txt file named %s was saved instead.'], ...
            fullfile(folder, [saveFileName, ext]), stampedFileName);
    end


    % --- write the file, and never fail silently ---
    errMsg = writeLabels(data, saveFilePath);

    while ~isempty(errMsg)
        disp('Error saving edits to file:');
        disp(errMsg);
        choice = questdlg(sprintf(['Edits were NOT saved.\n\n%s\n\n', ...
            'Your edits are still open in WMV. Choose another location to save them?'], errMsg), ...
            'Save failed', 'Save elsewhere...', 'Cancel', 'Save elsewhere...');

        if ~strcmp(choice, 'Save elsewhere...')
            disp('Edits were NOT saved.');
            return
        end

        % default to the intended folder if it still exists
        if isfolder(folder)
            defaultPath = fullfile(folder, [saveFileName, ext]);
        else
            defaultPath = [saveFileName, ext];
        end
        [newName, newFolder] = uiputfile('*.txt', 'Save edits as', defaultPath);
        if isequal(newName, 0) || isequal(newFolder, 0)
            disp('Edits were NOT saved.');
            return
        end

        % uiputfile asks before replacing an existing file, so the user has
        % already chosen this location knowingly
        saveFilePath = fullfile(newFolder, newName);
        overwriteWarning = '';
        errMsg = writeLabels(data, saveFilePath);
    end


    % --- save succeeded ---
    % saved table in memory matches table in file
    REMORA.lt.lVis_det.dataTableSaved = REMORA.lt.lVis_det.dataTable;
    REMORA.lt.lVis_det.saveFilePath = saveFilePath;      % later saves this session go here
    REMORA.lt.lVis_det.verifiedFilePath = saveFilePath;  % used by makeNewExamples
    success = true;

    disp(['Edits successfully saved to ', saveFilePath]);
    if isempty(overwriteWarning)
        msgbox(sprintf('Edits successfully saved to:\n%s', saveFilePath), ...
            'Edits saved', 'help', 'replace');
    else
        disp(overwriteWarning);
        warndlg(overwriteWarning, 'Edits saved to a new file', 'replace');
    end

end


function errMsg = writeLabels(data, filePath)
% writes the table and returns '' on success, or a description of the problem

    errMsg = '';
    folder = fileparts(filePath);

    if ~isempty(folder) && ~isfolder(folder)
        errMsg = sprintf('The save folder could not be found:\n%s', folder);
        return
    end

    try
        writetable(data, filePath, 'Delimiter', '\t');  % save as tab-delimited file
    catch ME
        errMsg = sprintf('Could not write to:\n%s\n\n%s', filePath, ME.message);
        return
    end

    if ~isfile(filePath)
        errMsg = sprintf('The file was not found after saving:\n%s', filePath);
    end
end


function tf = isSameFile(a, b)
% true if two paths point to the same file (handles / vs \ and, on Windows,
% letter case)

    a = char(java.io.File(a).getCanonicalPath());
    b = char(java.io.File(b).getCanonicalPath());
    if ispc
        tf = strcmpi(a, b);
    else
        tf = strcmp(a, b);
    end
end
