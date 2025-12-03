module dlangide.ui.diffmanager;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.menu;
import dlangui.dialogs.dialog;
import dlangui.core.events;
import dlangui.core.signals;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.utf;
import std.json;
import std.stdio;
import std.datetime;

import dcore.core;
import dcore.editor.document;
import dcore.ai.code_action_manager;
import dlangide.ui.diffmerger;
import dlangide.ui.diffanalyzer;
import dlangide.ui.aimerger;
import dlangide.ui.dsourceedit;
import dlangide.workspace.workspace;

/// Integration point for diff merger functionality in dnives IDE
class DiffMergerManager {
    private {
        DCore _dcore;
        AIAssistedMerger _aiMerger;
        DiffAnalyzer _diffAnalyzer;

        // Active diff sessions
        DiffMergerWidget[string] _activeSessions;

        // Configuration
        bool _autoShowOnConflicts = true;
        bool _enableAIAssistance = true;
        string _defaultStrategy = "balanced";

        // Menu integration
        Action _showDiffMergerAction;
        Action _compareFielsAction;
        Action _resolveConflictsAction;
    }

    // Events
    Signal!(string) onMergeCompleted;    // Emitted when merge is completed
    Signal!(string) onMergeAborted;      // Emitted when merge is aborted
    Signal!(DiffResolvedEventArgs) onConflictsResolved; // Emitted when conflicts resolved

    this(DCore dcore) {
        _dcore = dcore;
        _diffAnalyzer = new DiffAnalyzer();

        if (_dcore.codeActionManager) {
            _aiMerger = new AIAssistedMerger(_dcore.codeActionManager);
            _aiMerger.configureAI(_enableAIAssistance);
        }

        initializeActions();
        setupEventHandlers();
    }

    /// Initialize menu actions and keyboard shortcuts
    private void initializeActions() {
        _showDiffMergerAction = new Action(EditorActions.ShowDiffMerger,
            "Show Diff Merger"d, null, KeyFlag.Ctrl, KeyCode.KEY_D, KeyFlag.Shift);

        _compareFielsAction = new Action(EditorActions.CompareFiles,
            "Compare Files..."d, null, KeyFlag.Ctrl, KeyCode.KEY_D, KeyFlag.Alt);

        _resolveConflictsAction = new Action(EditorActions.ResolveConflicts,
            "Resolve Merge Conflicts"d, null, KeyFlag.Ctrl, KeyCode.KEY_R, KeyFlag.Shift);
    }

    /// Setup event handlers for integration with dnives
    private void setupEventHandlers() {
        // Listen for merge conflicts from version control or AI suggestions
        if (_dcore.codeActionManager) {
            // This would connect to the existing CodeActionManager events
            // _dcore.codeActionManager.onConflictDetected.connect(&handleConflictDetected);
        }

        // Listen for file changes that might need diffing
        if (_dcore.editorManager) {
            // This would connect to editor events for detecting when files change
            // _dcore.editorManager.onFileModified.connect(&handleFileModified);
        }
    }

    /// Show diff merger dialog for two text contents
    DiffMergerWidget showDiffMerger(string originalText, string suggestedText,
                                   string filePath = null, string title = null) {

        string sessionKey = filePath ? filePath : format("session_%s", Clock.currTime().stdTime);

        // Check if already have session for this file
        if (sessionKey in _activeSessions) {
            _activeSessions[sessionKey].show();
            return _activeSessions[sessionKey];
        }

        // Create new diff merger
        auto merger = new DiffMergerWidget(originalText, suggestedText, filePath);

        if (title) {
            merger.windowCaption = title.toUTF32();
        }

        // Setup event handlers for this session
        merger.onDiffResolved.connect((DiffResolvedEventArgs args) {
            handleDiffResolved(sessionKey, args);
        });

        // Store active session
        _activeSessions[sessionKey] = merger;

        // Show the dialog
        merger.show();

        return merger;
    }

    /// Compare two files using diff merger
    void compareFiles(string filePath1, string filePath2) {
        try {
            if (!exists(filePath1) || !exists(filePath2)) {
                showErrorMessage("File not found",
                               format("One or both files do not exist:\n%s\n%s",
                                     filePath1, filePath2));
                return;
            }

            string content1 = readText(filePath1);
            string content2 = readText(filePath2);

            string title = format("Compare: %s ↔ %s",
                                baseName(filePath1), baseName(filePath2));

            showDiffMerger(content1, content2, filePath2, title);

        } catch (Exception e) {
            showErrorMessage("Error comparing files", e.msg);
        }
    }

    /// Show file comparison dialog
    void showFileComparisonDialog() {
        // Create file selection dialog
        auto dialog = new FileDialog(UIString.fromRaw("Select Files to Compare"),
                                   Platform.instance.mainWindow);
        dialog.allowMultipleFiles = true;

        dialog.onDialogResult = delegate(const Object source, const DialogResult result) {
            if (result == DialogResult.OK) {
                auto files = dialog.filenames;
                if (files.length == 2) {
                    compareFiles(files[0], files[1]);
                } else {
                    showErrorMessage("File Selection", "Please select exactly 2 files to compare");
                }
            }
        };

        dialog.show();
    }

    /// Compare current editor content with a file
    void compareWithFile(string filePath) {
        auto editor = getCurrentEditor();
        if (!editor) {
            showErrorMessage("No Editor", "No active editor to compare with");
            return;
        }

        try {
            string currentContent = editor.text.toUTF8();
            string fileContent = readText(filePath);

            string title = format("Compare: Current Editor ↔ %s", baseName(filePath));
            showDiffMerger(currentContent, fileContent, filePath, title);

        } catch (Exception e) {
            showErrorMessage("Error comparing with file", e.msg);
        }
    }

    /// Handle AI-suggested code changes by showing diff merger
    void handleAISuggestedChanges(string originalCode, string suggestedCode,
                                 string filePath, string context = null) {

        // Create merge context for AI assistance
        MergeContext mergeContext;
        mergeContext.filePath = filePath;
        mergeContext.language = detectLanguage(filePath);
        mergeContext.surroundingCode = context;

        auto merger = showDiffMerger(originalCode, suggestedCode, filePath,
                                   "AI Suggested Changes - " ~ baseName(filePath));

        // Enable AI assistance for this session
        if (_aiMerger && _enableAIAssistance) {
            // The merger would use AI assistance for conflict resolution
            // This integration would happen within the merger itself
        }
    }

    /// Handle merge conflicts from version control
    void handleMergeConflicts(string filePath, string[] conflictMarkers) {
        try {
            string content = readText(filePath);

            // Parse conflict markers to extract original and suggested content
            auto conflictData = parseConflictMarkers(content, conflictMarkers);

            if (conflictData.empty) {
                showErrorMessage("No Conflicts", "No merge conflicts found in " ~ baseName(filePath));
                return;
            }

            // For multiple conflicts, show them one by one or in batch
            if (conflictData.length == 1) {
                auto conflict = conflictData[0];
                showDiffMerger(conflict.originalContent, conflict.suggestedContent,
                             filePath, "Resolve Merge Conflict");
            } else {
                showBatchConflictResolver(filePath, conflictData);
            }

        } catch (Exception e) {
            showErrorMessage("Error handling merge conflicts", e.msg);
        }
    }

    /// Show batch conflict resolver for multiple conflicts
    private void showBatchConflictResolver(string filePath, ConflictData[] conflicts) {
        // Create a specialized dialog for handling multiple conflicts
        // This would be a more advanced version of the diff merger
        // For now, handle them one by one

        foreach (i, conflict; conflicts) {
            string title = format("Resolve Conflict %d/%d in %s",
                                i + 1, conflicts.length, baseName(filePath));
            showDiffMerger(conflict.originalContent, conflict.suggestedContent,
                         filePath, title);
        }
    }

    /// Get the currently active editor
    private SourceEdit getCurrentEditor() {
        if (_dcore.editorManager) {
            // This would get the current editor from the editor manager
            // For now, return null - real implementation would integrate with EditorManager
            return null;
        }
        return null;
    }

    /// Detect programming language from file extension
    private string detectLanguage(string filePath) {
        string ext = extension(filePath).toLower();

        switch (ext) {
            case ".d":
                return "d";
            case ".py":
                return "python";
            case ".js":
                return "javascript";
            case ".ts":
                return "typescript";
            case ".cpp", ".cc", ".cxx":
                return "cpp";
            case ".c":
                return "c";
            case ".java":
                return "java";
            case ".cs":
                return "csharp";
            case ".rs":
                return "rust";
            case ".go":
                return "go";
            default:
                return "text";
        }
    }

    /// Parse conflict markers in text
    private ConflictData[] parseConflictMarkers(string content, string[] markers) {
        ConflictData[] conflicts;

        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i].strip();

            if (line.startsWith("<<<<<<<")) {
                // Start of conflict
                ConflictData conflict;
                conflict.startLine = i;

                // Find middle marker
                int middleIndex = -1;
                for (int j = i + 1; j < lines.length; j++) {
                    if (lines[j].strip().startsWith("=======")) {
                        middleIndex = j;
                        break;
                    }
                }

                // Find end marker
                int endIndex = -1;
                for (int j = middleIndex + 1; j < lines.length; j++) {
                    if (lines[j].strip().startsWith(">>>>>>>")) {
                        endIndex = j;
                        break;
                    }
                }

                if (middleIndex != -1 && endIndex != -1) {
                    // Extract original content (between start and middle)
                    conflict.originalContent = lines[(i+1)..middleIndex].join("\n");

                    // Extract suggested content (between middle and end)
                    conflict.suggestedContent = lines[(middleIndex+1)..endIndex].join("\n");

                    conflict.endLine = endIndex;
                    conflicts ~= conflict;

                    i = endIndex; // Skip to end of this conflict
                }
            }
        }

        return conflicts;
    }

    /// Handle when diff is resolved
    private void handleDiffResolved(string sessionKey, DiffResolvedEventArgs args) {
        // Apply the merged content if needed
        if (sessionKey in _activeSessions) {
            auto session = _activeSessions[sessionKey];

            // If this was for a specific file, offer to save the result
            if (session._filePath && session._filePath.length > 0) {
                auto result = askUserToSaveResult(session._filePath, args.mergedContent);
                if (result) {
                    applyMergedContent(session._filePath, args.mergedContent);
                }
            }

            // Clean up session
            _activeSessions.remove(sessionKey);
        }

        // Emit event
        if (onConflictsResolved.assigned) {
            onConflictsResolved(args);
        }

        if (onMergeCompleted.assigned) {
            onMergeCompleted(sessionKey);
        }
    }

    /// Ask user if they want to save the merge result
    private bool askUserToSaveResult(string filePath, string mergedContent) {
        auto dialog = new MessageBoxDialog("Save Merge Result"d,
                                         format("Apply merged changes to %s?", baseName(filePath)).toUTF32(),
                                         Platform.instance.mainWindow,
                                         MessageBoxButtons.OK | MessageBoxButtons.Cancel,
                                         MessageBoxIcon.Question);

        return dialog.show() == DialogResult.OK;
    }

    /// Apply merged content to file or editor
    private void applyMergedContent(string filePath, string mergedContent) {
        try {
            // Check if file is currently open in editor
            auto editor = findEditorForFile(filePath);

            if (editor) {
                // Update editor content
                editor.text = mergedContent.toUTF32();
                editor.save(); // Save the file
            } else {
                // Write directly to file
                std.file.write(filePath, mergedContent);
            }

            writeln("Merge result applied to: ", filePath);

        } catch (Exception e) {
            showErrorMessage("Error applying merge", e.msg);
        }
    }

    /// Find editor widget for a specific file
    private SourceEdit findEditorForFile(string filePath) {
        // This would integrate with the editor manager to find the editor
        // For now, return null - real implementation would search open editors
        return null;
    }

    /// Show error message dialog
    private void showErrorMessage(string title, string message) {
        auto dialog = new MessageBoxDialog(title.toUTF32(), message.toUTF32(),
                                         Platform.instance.mainWindow,
                                         MessageBoxButtons.OK,
                                         MessageBoxIcon.Error);
        dialog.show();
    }

    /// Get configuration settings
    JSONValue getConfiguration() {
        JSONValue config = JSONValue.emptyObject;

        config["autoShowOnConflicts"] = JSONValue(_autoShowOnConflicts);
        config["enableAIAssistance"] = JSONValue(_enableAIAssistance);
        config["defaultStrategy"] = JSONValue(_defaultStrategy);

        if (_aiMerger) {
            config["aiStatistics"] = _aiMerger.exportSession();
        }

        return config;
    }

    /// Apply configuration settings
    void applyConfiguration(JSONValue config) {
        if ("autoShowOnConflicts" in config) {
            _autoShowOnConflicts = config["autoShowOnConflicts"].boolean;
        }

        if ("enableAIAssistance" in config) {
            _enableAIAssistance = config["enableAIAssistance"].boolean;
            if (_aiMerger) {
                _aiMerger.configureAI(_enableAIAssistance);
            }
        }

        if ("defaultStrategy" in config) {
            _defaultStrategy = config["defaultStrategy"].str;
        }
    }

    /// Get statistics about diff operations
    auto getStatistics() {
        struct DiffManagerStats {
            int activeSessions;
            int totalSessionsCreated;
            int mergesCompleted;
            int mergesAborted;
        }

        DiffManagerStats stats;
        stats.activeSessions = cast(int)_activeSessions.length;
        // Other stats would be tracked over time

        return stats;
    }

    /// Cleanup resources
    void cleanup() {
        // Close all active sessions
        foreach (key, session; _activeSessions) {
            session.close();
        }
        _activeSessions.clear();

        // Clear AI merger cache
        if (_aiMerger) {
            _aiMerger.clearCache();
        }
    }
}

/// Structure for conflict data parsing
private struct ConflictData {
    string originalContent;
    string suggestedContent;
    int startLine;
    int endLine;
}

/// Additional editor actions for diff merger
class EditorActions {
    static immutable int ShowDiffMerger = 5001;
    static immutable int CompareFiles = 5002;
    static immutable int ResolveConflicts = 5003;
    static immutable int CompareWithFile = 5004;
    static immutable int ShowAIChanges = 5005;
}

/// Factory function to create diff merger manager
DiffMergerManager createDiffMergerManager(DCore dcore) {
    return new DiffMergerManager(dcore);
}
