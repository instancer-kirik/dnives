module dcore.session;

import dlangui.core.logger;
import std.json;
import std.file;
import std.path;
import std.datetime;

/**
 * SessionManager - Tracks open files and editor state
 */
class SessionManager {
    private string[] recentFiles;
    private string[] openFiles;
    private JSONValue editorState;

    // Save the current session
    void saveSession(string sessionPath) {
        JSONValue session = parseJSON("{}");

        // Add recent files
        JSONValue recentFilesArray = parseJSON("[]");
        foreach (file; recentFiles)
            recentFilesArray.array ~= JSONValue(file);
        session["recentFiles"] = recentFilesArray;

        // Add open files
        JSONValue openFilesArray = parseJSON("[]");
        foreach (file; openFiles)
            openFilesArray.array ~= JSONValue(file);
        session["openFiles"] = openFilesArray;

        // Add editor state
        session["editorState"] = editorState;

        // Save to file
        std.file.write(sessionPath, session.toPrettyString());
    }
}
