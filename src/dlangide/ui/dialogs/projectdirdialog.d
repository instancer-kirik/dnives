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
    // A folder the user clicked in the list, and has not since navigated into.
    private string _clickedDir;
    private bool _navigating;

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
        return _clickedDir.length > 0 ? _clickedDir : path;
    }

    override protected bool openDirectory(string dir, string selectedItemPath) {
        _navigating = true;
        _clickedDir = null;
        scope (exit)
            _navigating = false;
        return super.openDirectory(dir, selectedItemPath);
    }

    override protected void onItemSelected(int index) {
        super.onItemSelected(index);
        if (_navigating || index < 0 || index >= cast(int) _entries.length)
            return;
        if (_entries[index].isDir) {
            string leaf = baseName(_entries[index].name);
            if (leaf != "." && leaf != "..") {
                _clickedDir = _entries[index].name;
                return;
            }
        }
        _clickedDir = null;
    }

    /**
     * Override to use the user-selected directory when returning results
     */
    override bool handleAction(const Action action) {
        if (action.id == StandardAction.Open || action.id == StandardAction.OpenDirectory || action.id == StandardAction.Save) {
            string dirToUse;

            // A single click on a folder selects it. Entering a folder clears that
            // click, so Open then confirms the folder you are looking at.
            // The filename box is filled by the list's automatic selection after
            // you enter a folder. That must not become the project.
            if (_clickedDir.length && exists(_clickedDir) && isDir(_clickedDir))
                dirToUse = _clickedDir;
            else
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