module dlangide.ui.dialogs.projectdirdialog;

import dlangui.dialogs.filedlg;
import dlangui.dialogs.dialog;
import dlangui.widgets.widget;
import dlangui.widgets.controls;
import dlangui.core.stdaction;
import dlangui.core.files;
import dlangui.core.logger;
import std.path;
import std.file;

/**
 * A specialized file dialog for selecting project directories.
 * This extends the standard FileDialog to properly track and honor
 * the directory specifically selected by the user.
 */
class ProjectDirectoryDialog : FileDialog {
    // Track the directory specifically selected by the user
    private string _userSelectedDir;

    /**
     * Create a dialog for selecting project directories
     */
    this(UIString caption, Window parent, Action action = null, uint fileDialogFlags = DialogFlag.Modal | DialogFlag.Resizable | FileDialogFlag.SelectDirectory | FileDialogFlag.FileMustExist) {
        // Ensure proper flags for directory selection
        fileDialogFlags |= FileDialogFlag.SelectDirectory;
        super(caption, parent, action, fileDialogFlags);
    }

    /**
     * Get the directory explicitly selected by the user
     */
    @property string userSelectedDir() {
        return _userSelectedDir.length > 0 ? _userSelectedDir : path;
    }

    /**
     * Override to track directory changes initiated by the user
     */
    override protected bool openDirectory(string dir, string selectedItemPath) {
        // If the call is from user action (not internal navigation),
        // track it as explicit user selection
        if (selectedItemPath is null) {
            // This is direct user navigation - preserve the exact path
            _userSelectedDir = dir;
            Log.i("PROJECTDIRDIALOG: User explicitly selected directory: ", _userSelectedDir);
        }
        
        // Call parent but capture result
        bool result = super.openDirectory(dir, selectedItemPath);
        return result;
    }

    /**
     * Override to track when user selects a directory from the list
     */
    override protected void onItemActivated(int index) {
        if (index >= 0 && index < _entries.length) {
            DirEntry e = _entries[index];
            if (e.isDir) {
                // Track as explicit user selection
                _userSelectedDir = e.name;
                Log.i("PROJECTDIRDIALOG: User activated directory: ", _userSelectedDir);
            }
        }
        super.onItemActivated(index);
    }

    /**
     * Override to use the user-selected directory when returning results
     */
    override bool handleAction(const Action action) {
        if (action.id == StandardAction.Open || action.id == StandardAction.OpenDirectory || action.id == StandardAction.Save) {
            // Check if user manually typed a path in the filename field
            string baseFilename = "";
            if (_edFilename) {
                baseFilename = toUTF8(_edFilename.text);
            }
            
            string dirToUse = "";
            
            // Try to use manual filename entry if it's a directory
            if (baseFilename.length > 0) {
                string fullPath;
                // Check if it's an absolute path
                if (isAbsolute(baseFilename)) {
                    fullPath = baseFilename;
                } else {
                    // Combine with current directory
                    fullPath = buildNormalizedPath(_path, baseFilename);
                }
                
                // If it exists and is a directory, use that
                if (exists(fullPath) && isDir(fullPath)) {
                    dirToUse = fullPath;
                    Log.i("PROJECTDIRDIALOG: Using manually entered directory: ", dirToUse);
                }
            }
            
            // Use explicitly selected directory from navigation or list
            if (dirToUse.length == 0 && _userSelectedDir.length > 0) {
                // Verify it's a valid directory
                if (exists(_userSelectedDir) && isDir(_userSelectedDir)) {
                    dirToUse = _userSelectedDir;
                    Log.i("PROJECTDIRDIALOG: Using explicitly selected directory: ", dirToUse);
                }
            }
            
            // Fall back to current directory if nothing else selected
            if (dirToUse.length == 0) {
                dirToUse = _path;
                Log.i("PROJECTDIRDIALOG: Using current directory as fallback: ", dirToUse);
            }
            
            // If we have a directory to return, do so
            if (action.id == StandardAction.OpenDirectory && dirToUse.length > 0) {
                if (exists(dirToUse) && isDir(dirToUse)) {
                    Log.i("PROJECTDIRDIALOG: Returning directory: ", dirToUse);
                    Action result = _action;
                    result.stringParam = dirToUse;
                    close(result);
                    return true;
                }
            }
        }
        
        // For all other actions, use standard behavior
        return super.handleAction(action);
    }
}