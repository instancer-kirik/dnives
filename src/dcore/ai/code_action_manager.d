module dcore.ai.code_action_manager;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.json;
import std.datetime;
import std.exception;
import std.conv;
import std.typecons;
import std.regex;
import std.uuid;
import core.time;

import dlangui.core.logger;

import dcore.core;
import dcore.ai.ai_manager;
import dcore.lsp.lspmanager;
import dcore.lsp.lsptypes;

/**
 * CodeChange - Represents a single change to code
 */
struct CodeChange {
    string id;
    string filePath;
    int startLine;
    int startColumn;
    int endLine;
    int endColumn;
    string originalText;
    string newText;
    DateTime timestamp;
    string changeType;  // "replace", "insert", "delete"
    string description;

    this(string filePath, int startLine, int startColumn, int endLine, int endColumn,
         string originalText, string newText, string changeType, string description) {
        this.id = randomUUID().toString();
        this.filePath = filePath;
        this.startLine = startLine;
        this.startColumn = startColumn;
        this.endLine = endLine;
        this.endColumn = endColumn;
        this.originalText = originalText;
        this.newText = newText;
        this.changeType = changeType;
        this.description = description;
        this.timestamp = cast(DateTime)Clock.currTime();
    }
}

/**
 * CodeChangeSet - A collection of related changes
 */
struct CodeChangeSet {
    string id;
    string description;
    CodeChange[] changes;
    string[] affectedFiles;
    DateTime created;
    bool isApplied;
    bool canRollback;

    this(string description) {
        this.id = randomUUID().toString();
        this.description = description;
        this.created = cast(DateTime)Clock.currTime();
        this.isApplied = false;
        this.canRollback = false;
    }
}

/**
 * FileSnapshot - Backup of file state before changes
 */
struct FileSnapshot {
    string filePath;
    string content;
    DateTime timestamp;
    string checksum;

    this(string filePath, string content) {
        this.filePath = filePath;
        this.content = content;
        this.timestamp = cast(DateTime)Clock.currTime();
        this.checksum = calculateChecksum(content);
    }

    private string calculateChecksum(string content) {
        import std.digest.md;
        return toHexString(md5Of(content)).idup;
    }
}

/**
 * RollbackPoint - Point in time that can be restored
 */
struct RollbackPoint {
    string id;
    string description;
    FileSnapshot[string] snapshots;  // filepath -> snapshot
    DateTime created;
    string[] tags;

    this(string description) {
        this.id = randomUUID().toString();
        this.description = description;
        this.created = cast(DateTime)Clock.currTime();
    }
}

/**
 * ConflictResolution - How to handle merge conflicts
 */
enum ConflictResolution {
    Abort,          // Abort the operation
    TakeTheirs,     // Use the new changes
    TakeOurs,       // Keep the current state
    Manual,         // Manual resolution required
    Auto            // Try automatic merge
}

/**
 * ValidationResult - Result of code change validation
 */
struct ValidationResult {
    bool isValid;
    string[] errors;
    string[] warnings;
    string[] suggestions;
    DiagnosticSeverity severity;

    this(bool isValid) {
        this.isValid = isValid;
        this.severity = isValid ? DiagnosticSeverity.Information : DiagnosticSeverity.Error;
    }
}

/**
 * CodeActionManager - Manages automated code changes and rollbacks
 *
 * Features:
 * - Apply code changes with validation
 * - Create rollback points and restore them
 * - Handle merge conflicts intelligently
 * - Validate changes using LSP
 * - Track change history
 * - Provide diff visualization
 */
class CodeActionManager {
    private DCore _core;
    private LSPManager _lspManager;

    // Change tracking
    private CodeChangeSet[string] _changeSets;        // id -> changeset
    private RollbackPoint[string] _rollbackPoints;    // id -> rollback point
    private FileSnapshot[string] _currentSnapshots;   // filepath -> latest snapshot

    // Configuration
    private bool _validateChanges = true;
    private bool _createAutoBackups = true;
    private int _maxRollbackPoints = 50;
    private Duration _snapshotRetention = 7.days;

    // Events
    void delegate(CodeChangeSet changeSet) onChangeSetApplied;
    void delegate(CodeChangeSet changeSet) onChangeSetRolledBack;
    void delegate(string filePath, ValidationResult result) onValidationComplete;
    void delegate(string message) onConflictDetected;

    /**
     * Constructor
     */
    this(DCore core, LSPManager lspManager) {
        _core = core;
        _lspManager = lspManager;

        Log.i("CodeActionManager: Initialized");
    }

    /**
     * Initialize the code action manager
     */
    void initialize() {
        // Load saved rollback points
        loadRollbackPoints();

        // Clean up old snapshots
        cleanupOldSnapshots();

        Log.i("CodeActionManager: Ready");
    }

    /**
     * Create a rollback point for current state
     */
    string createRollbackPoint(string description, string[] filePaths = []) {
        auto rollbackPoint = RollbackPoint(description);

        // If no specific files, snapshot all workspace files
        if (filePaths.empty) {
            auto workspace = _core.getCurrentWorkspace();
            if (workspace) {
                filePaths = getWorkspaceSourceFiles(workspace.path);
            }
        }

        // Create snapshots for each file
        foreach (filePath; filePaths) {
            if (exists(filePath)) {
                try {
                    string content = readText(filePath);
                    auto snapshot = FileSnapshot(filePath, content);
                    rollbackPoint.snapshots[filePath] = snapshot;
                    _currentSnapshots[filePath] = snapshot;
                } catch (Exception e) {
                    Log.w("CodeActionManager: Failed to snapshot ", filePath, ": ", e.msg);
                }
            }
        }

        _rollbackPoints[rollbackPoint.id] = rollbackPoint;

        // Cleanup old rollback points
        cleanupOldRollbackPoints();

        Log.i("CodeActionManager: Created rollback point: ", rollbackPoint.id, " - ", description);
        return rollbackPoint.id;
    }

    /**
     * Apply a set of code changes
     */
    bool applyChangeSet(CodeChangeSet changeSet, ConflictResolution conflictResolution = ConflictResolution.Auto) {
        if (changeSet.isApplied) {
            Log.w("CodeActionManager: ChangeSet already applied: ", changeSet.id);
            return false;
        }

        // Create automatic rollback point before applying changes
        if (_createAutoBackups) {
            string backupDescription = "Before: " ~ changeSet.description;
            createRollbackPoint(backupDescription, changeSet.affectedFiles);
        }

        // Validate changes first
        if (_validateChanges) {
            auto validationResult = validateChangeSet(changeSet);
            if (!validationResult.isValid) {
                Log.e("CodeActionManager: Validation failed for changeset: ", changeSet.id);
                foreach (error; validationResult.errors) {
                    Log.e("  Error: ", error);
                }
                return false;
            }
        }

        // Check for conflicts
        auto conflicts = detectConflicts(changeSet);
        if (!conflicts.empty) {
            if (conflictResolution == ConflictResolution.Abort) {
                Log.w("CodeActionManager: Conflicts detected, aborting");
                return false;
            }

            if (!resolveConflicts(changeSet, conflicts, conflictResolution)) {
                Log.e("CodeActionManager: Failed to resolve conflicts");
                return false;
            }
        }

        // Apply changes
        try {
            foreach (change; changeSet.changes) {
                if (!applyChange(change)) {
                    Log.e("CodeActionManager: Failed to apply change: ", change.id);
                    // Rollback changes applied so far
                    rollbackChangeSet(changeSet);
                    return false;
                }
            }

            changeSet.isApplied = true;
            changeSet.canRollback = true;
            _changeSets[changeSet.id] = changeSet;

            // Trigger event
            if (onChangeSetApplied)
                onChangeSetApplied(changeSet);

            Log.i("CodeActionManager: Applied changeset: ", changeSet.id);
            return true;

        } catch (Exception e) {
            Log.e("CodeActionManager: Exception applying changeset: ", e.msg);
            return false;
        }
    }

    /**
     * Apply a single code change
     */
    private bool applyChange(CodeChange change) {
        if (!exists(change.filePath)) {
            Log.e("CodeActionManager: File not found: ", change.filePath);
            return false;
        }

        try {
            auto lines = readText(change.filePath).split('\n');

            switch (change.changeType) {
                case "replace":
                    return applyReplaceChange(lines, change);
                case "insert":
                    return applyInsertChange(lines, change);
                case "delete":
                    return applyDeleteChange(lines, change);
                default:
                    Log.e("CodeActionManager: Unknown change type: ", change.changeType);
                    return false;
            }

        } catch (Exception e) {
            Log.e("CodeActionManager: Error applying change: ", e.msg);
            return false;
        }
    }

    /**
     * Apply a replace change
     */
    private bool applyReplaceChange(ref string[] lines, CodeChange change) {
        // Verify the original text matches
        string actualText = extractTextRange(lines, change.startLine, change.startColumn,
                                           change.endLine, change.endColumn);

        if (actualText != change.originalText) {
            Log.w("CodeActionManager: Original text mismatch for change ", change.id);
            Log.w("  Expected: ", change.originalText);
            Log.w("  Actual: ", actualText);
            // Could handle this as a conflict
        }

        // Replace the text
        if (change.startLine == change.endLine) {
            // Single line replacement
            string line = lines[change.startLine];
            lines[change.startLine] = line[0..change.startColumn] ~
                                     change.newText ~
                                     line[change.endColumn..$];
        } else {
            // Multi-line replacement
            string[] newLines = change.newText.split('\n');
            string firstLine = lines[change.startLine][0..change.startColumn] ~ newLines[0];
            string lastLine = newLines[$-1] ~ lines[change.endLine][change.endColumn..$];

            lines = lines[0..change.startLine] ~
                   [firstLine] ~
                   newLines[1..$-1] ~
                   [lastLine] ~
                   lines[change.endLine+1..$];
        }

        // Write back to file
        std.file.write(change.filePath, lines.join('\n'));
        return true;
    }

    /**
     * Apply an insert change
     */
    private bool applyInsertChange(ref string[] lines, CodeChange change) {
        if (change.startLine >= lines.length) {
            // Append to end
            lines ~= change.newText.split('\n');
        } else {
            // Insert at position
            string line = lines[change.startLine];
            string[] newLines = change.newText.split('\n');

            if (newLines.length == 1) {
                // Single line insert
                lines[change.startLine] = line[0..change.startColumn] ~
                                         change.newText ~
                                         line[change.startColumn..$];
            } else {
                // Multi-line insert
                string firstPart = line[0..change.startColumn];
                string secondPart = line[change.startColumn..$];

                lines = lines[0..change.startLine] ~
                       [firstPart ~ newLines[0]] ~
                       newLines[1..$-1] ~
                       [newLines[$-1] ~ secondPart] ~
                       lines[change.startLine+1..$];
            }
        }

        std.file.write(change.filePath, lines.join('\n'));
        return true;
    }

    /**
     * Apply a delete change
     */
    private bool applyDeleteChange(ref string[] lines, CodeChange change) {
        if (change.startLine == change.endLine) {
            // Single line deletion
            string line = lines[change.startLine];
            lines[change.startLine] = line[0..change.startColumn] ~ line[change.endColumn..$];
        } else {
            // Multi-line deletion
            string firstPart = lines[change.startLine][0..change.startColumn];
            string secondPart = lines[change.endLine][change.endColumn..$];

            lines = lines[0..change.startLine] ~
                   [firstPart ~ secondPart] ~
                   lines[change.endLine+1..$];
        }

        std.file.write(change.filePath, lines.join('\n'));
        return true;
    }

    /**
     * Extract text from a range in lines
     */
    private string extractTextRange(string[] lines, int startLine, int startColumn, int endLine, int endColumn) {
        if (startLine == endLine) {
            return lines[startLine][startColumn..endColumn];
        } else {
            string result = lines[startLine][startColumn..$];
            for (int i = startLine + 1; i < endLine; i++) {
                result ~= "\n" ~ lines[i];
            }
            result ~= "\n" ~ lines[endLine][0..endColumn];
            return result;
        }
    }

    /**
     * Rollback to a specific rollback point
     */
    bool rollbackToPoint(string rollbackPointId) {
        if (rollbackPointId !in _rollbackPoints) {
            Log.e("CodeActionManager: Rollback point not found: ", rollbackPointId);
            return false;
        }

        auto rollbackPoint = _rollbackPoints[rollbackPointId];

        try {
            foreach (filePath, snapshot; rollbackPoint.snapshots) {
                // Check if file has been modified since snapshot
                if (exists(filePath)) {
                    string currentContent = readText(filePath);
                    if (snapshot.checksum != snapshot.calculateChecksum(currentContent)) {
                        Log.i("CodeActionManager: Restoring modified file: ", filePath);
                    }
                }

                // Restore the file
                std.file.write(filePath, snapshot.content);
            }

            Log.i("CodeActionManager: Rolled back to point: ", rollbackPointId, " - ", rollbackPoint.description);
            return true;

        } catch (Exception e) {
            Log.e("CodeActionManager: Error during rollback: ", e.msg);
            return false;
        }
    }

    /**
     * Rollback a specific changeset
     */
    bool rollbackChangeSet(CodeChangeSet changeSet) {
        if (!changeSet.isApplied || !changeSet.canRollback) {
            return false;
        }

        try {
            // Apply changes in reverse order
            foreach_reverse (change; changeSet.changes) {
                if (!rollbackChange(change)) {
                    Log.e("CodeActionManager: Failed to rollback change: ", change.id);
                    return false;
                }
            }

            changeSet.isApplied = false;

            // Trigger event
            if (onChangeSetRolledBack)
                onChangeSetRolledBack(changeSet);

            Log.i("CodeActionManager: Rolled back changeset: ", changeSet.id);
            return true;

        } catch (Exception e) {
            Log.e("CodeActionManager: Error rolling back changeset: ", e.msg);
            return false;
        }
    }

    /**
     * Rollback a single change
     */
    private bool rollbackChange(CodeChange change) {
        try {
            auto lines = readText(change.filePath).split('\n');

            // Create reverse change
            CodeChange reverseChange = change;
            reverseChange.originalText = change.newText;
            reverseChange.newText = change.originalText;

            switch (change.changeType) {
                case "replace":
                    return applyReplaceChange(lines, reverseChange);
                case "insert":
                    // Insert becomes delete
                    reverseChange.changeType = "delete";
                    return applyDeleteChange(lines, reverseChange);
                case "delete":
                    // Delete becomes insert
                    reverseChange.changeType = "insert";
                    return applyInsertChange(lines, reverseChange);
                default:
                    return false;
            }

        } catch (Exception e) {
            Log.e("CodeActionManager: Error rolling back change: ", e.msg);
            return false;
        }
    }

    /**
     * Validate a changeset using LSP
     */
    ValidationResult validateChangeSet(CodeChangeSet changeSet) {
        auto result = ValidationResult(true);

        if (!_lspManager) {
            result.warnings ~= "LSP not available for validation";
            return result;
        }

        foreach (change; changeSet.changes) {
            auto changeResult = validateChange(change);

            result.errors ~= changeResult.errors;
            result.warnings ~= changeResult.warnings;
            result.suggestions ~= changeResult.suggestions;

            if (!changeResult.isValid) {
                result.isValid = false;
                if (changeResult.severity > result.severity) {
                    result.severity = changeResult.severity;
                }
            }
        }

        return result;
    }

    /**
     * Validate a single change
     */
    private ValidationResult validateChange(CodeChange change) {
        auto result = ValidationResult(true);

        try {
            // Basic syntax validation could be added here
            // For now, just check file exists and is writable

            if (!exists(change.filePath)) {
                result.isValid = false;
                result.errors ~= "File does not exist: " ~ change.filePath;
                result.severity = DiagnosticSeverity.Error;
                return result;
            }

            if (!isFile(change.filePath)) {
                result.isValid = false;
                result.errors ~= "Path is not a file: " ~ change.filePath;
                result.severity = DiagnosticSeverity.Error;
                return result;
            }

            // TODO: Add LSP-based validation
            // - Apply change temporarily
            // - Get diagnostics from LSP
            // - Check for syntax errors
            // - Revert temporary change

        } catch (Exception e) {
            result.isValid = false;
            result.errors ~= "Validation error: " ~ e.msg;
            result.severity = DiagnosticSeverity.Error;
        }

        return result;
    }

    /**
     * Detect conflicts in a changeset
     */
    private string[] detectConflicts(CodeChangeSet changeSet) {
        string[] conflicts;

        foreach (change; changeSet.changes) {
            // Check if file has been modified since our snapshot
            if (change.filePath in _currentSnapshots) {
                auto snapshot = _currentSnapshots[change.filePath];

                if (exists(change.filePath)) {
                    string currentContent = readText(change.filePath);
                    if (snapshot.checksum != snapshot.calculateChecksum(currentContent)) {
                        conflicts ~= "File modified externally: " ~ change.filePath;
                    }
                }
            }
        }

        return conflicts;
    }

    /**
     * Resolve conflicts in a changeset
     */
    private bool resolveConflicts(CodeChangeSet changeSet, string[] conflicts, ConflictResolution resolution) {
        switch (resolution) {
            case ConflictResolution.TakeTheirs:
                // Apply changes anyway
                return true;

            case ConflictResolution.TakeOurs:
                // Skip conflicting changes
                auto filteredChanges = changeSet.changes.filter!(
                    change => !conflicts.any!(c => c.canFind(change.filePath))).array;
                changeSet.changes = filteredChanges;
                return true;

            case ConflictResolution.Auto:
                // Try to automatically merge
                return attemptAutoMerge(changeSet, conflicts);

            case ConflictResolution.Manual:
                // Require manual intervention
                if (onConflictDetected) {
                    onConflictDetected("Manual conflict resolution required");
                }
                return false;

            default:
                return false;
        }
    }

    /**
     * Attempt automatic merge resolution
     */
    private bool attemptAutoMerge(CodeChangeSet changeSet, string[] conflicts) {
        // Simple auto-merge strategy - could be made more sophisticated
        Log.i("CodeActionManager: Attempting auto-merge for ", conflicts.length, " conflicts");

        // For now, just take the new changes
        return true;
    }

    /**
     * Get workspace source files
     */
    private string[] getWorkspaceSourceFiles(string workspacePath) {
        string[] files;

        if (!exists(workspacePath) || !isDir(workspacePath))
            return files;

        try {
            foreach (DirEntry entry; dirEntries(workspacePath, SpanMode.depth)) {
                if (entry.isFile && isSourceFile(entry.name)) {
                    files ~= entry.name;
                }
            }
        } catch (Exception e) {
            Log.w("CodeActionManager: Error scanning workspace: ", e.msg);
        }

        return files;
    }

    /**
     * Check if file is a source file
     */
    private bool isSourceFile(string filePath) {
        string ext = extension(filePath).toLower();
        return [".d", ".di", ".js", ".ts", ".py", ".rs", ".c", ".cpp", ".h", ".hpp"].canFind(ext);
    }

    /**
     * Cleanup old rollback points
     */
    private void cleanupOldRollbackPoints() {
        if (_rollbackPoints.length <= _maxRollbackPoints)
            return;

        // Sort by creation time and remove oldest
        auto sortedPoints = _rollbackPoints.values.sort!((a, b) => a.created > b.created).array;

        while (sortedPoints.length > _maxRollbackPoints) {
            auto oldest = sortedPoints[$-1];
            _rollbackPoints.remove(oldest.id);
            sortedPoints = sortedPoints[0..$-1];
        }

        Log.i("CodeActionManager: Cleaned up old rollback points");
    }

    /**
     * Cleanup old snapshots
     */
    private void cleanupOldSnapshots() {
        auto cutoffTime = Clock.currTime() - _snapshotRetention;

        string[] toRemove;
        foreach (filePath, snapshot; _currentSnapshots) {
            if (cast(SysTime)snapshot.timestamp < cutoffTime) {
                toRemove ~= filePath;
            }
        }

        foreach (filePath; toRemove) {
            _currentSnapshots.remove(filePath);
        }

        if (!toRemove.empty) {
            Log.i("CodeActionManager: Cleaned up ", toRemove.length, " old snapshots");
        }
    }

    /**
     * Load saved rollback points
     */
    private void loadRollbackPoints() {
        string rollbackDir = buildPath(_core.getConfigDir(), "rollback_points");

        if (!exists(rollbackDir))
            return;

        try {
            import std.file : SpanMode;
            foreach (DirEntry entry; dirEntries(rollbackDir, SpanMode.shallow)) {
                if (entry.isFile && entry.name.endsWith(".json")) {
                    loadRollbackPoint(entry.name);
                }
            }
        } catch (Exception e) {
            Log.w("CodeActionManager: Error loading rollback points: ", e.msg);
        }
    }

    /**
     * Load a single rollback point
     */
    private void loadRollbackPoint(string filePath) {
        try {
            string content = readText(filePath);
            JSONValue json = parseJSON(content);

            // TODO: Deserialize rollback point from JSON

        } catch (Exception e) {
            Log.w("CodeActionManager: Error loading rollback point ", filePath, ": ", e.msg);
        }
    }

    /**
     * Get all rollback points
     */
    RollbackPoint[] getRollbackPoints() {
        return _rollbackPoints.values;
    }

    /**
     * Get applied changesets
     */
    CodeChangeSet[] getAppliedChangeSets() {
        return _changeSets.values.filter!(cs => cs.isApplied).array;
    }

    /**
     * Get changeset by ID
     */
    CodeChangeSet* getChangeSet(string id) {
        if (id in _changeSets) {
            return &_changeSets[id];
        }
        return null;
    }

    /**
     * Create a changeset from code changes
     */
    CodeChangeSet createChangeSet(string description, CodeChange[] changes) {
        auto changeSet = CodeChangeSet(description);
        changeSet.changes = changes;

        // Collect affected files
        string[] files;
        foreach (change; changes) {
            if (!files.canFind(change.filePath)) {
                files ~= change.filePath;
            }
        }
        changeSet.affectedFiles = files;

        return changeSet;
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        // Save rollback points
        saveRollbackPoints();

        _changeSets.clear();
        _rollbackPoints.clear();
        _currentSnapshots.clear();

        Log.i("CodeActionManager: Cleaned up");
    }

    /**
     * Save rollback points to disk
     */
    private void saveRollbackPoints() {
        string rollbackDir = buildPath(_core.getConfigDir(), "rollback_points");

        if (!exists(rollbackDir)) {
            mkdirRecurse(rollbackDir);
        }

        foreach (id, point; _rollbackPoints) {
            try {
                string filePath = buildPath(rollbackDir, id ~ ".json");

                // TODO: Serialize rollback point to JSON
                JSONValue json = JSONValue.emptyObject;
                json["id"] = point.id;
                json["description"] = point.description;
                json["created"] = point.created.toISOExtString();

                std.file.write(filePath, json.toPrettyString());

            } catch (Exception e) {
                Log.w("CodeActionManager: Error saving rollback point ", id, ": ", e.msg);
            }
        }
    }
}
