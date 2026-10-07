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
import std.string;

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
            string dirToUse;

            // A highlighted folder is the selection. The browsed path is only the fallback.
            if (_fileList && _entries.length > 0) {
                int row = _fileList.row;
                if (row >= 0 && row < cast(int) _entries.length && _entries[row].isDir) {
                    string highlighted = _entries[row].name;
                    string leaf = baseName(highlighted);
                    if (leaf != "." && leaf != ".." && exists(highlighted) && isDir(highlighted))
                        dirToUse = highlighted;
                }
            }

            if (dirToUse.length == 0 && _edFilename) {
                string typed = toUTF8(_edFilename.text).strip;
                if (typed.length && typed != "." && typed != "..") {
                    string fullPath = isAbsolute(typed) ? typed : buildNormalizedPath(_path, typed);
                    if (exists(fullPath) && isDir(fullPath))
                        dirToUse = fullPath;
                }
            }

            if (dirToUse.length == 0 && _userSelectedDir.length && exists(_userSelectedDir) && isDir(_userSelectedDir))
                dirToUse = _userSelectedDir;

            if (dirToUse.length == 0)
                dirToUse = _path;

            if (dirToUse.endsWith("/") || dirToUse.endsWith("\\"))
                dirToUse = dirToUse[0 .. $ - 1];

            if (dirToUse.length && exists(dirToUse) && isDir(dirToUse)) {
                Log.i("PROJECTDIRDIALOG: Returning directory: ", dirToUse);
                Action result = _action;
                result.stringParam = dirToUse;
                close(result);
                return true;
            }
        }

        return super.handleAction(action);
    }
}