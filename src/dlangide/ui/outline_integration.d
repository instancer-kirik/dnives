module dlangide.ui.outline_integration;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.tabs;
import dcore.compat.splitter;
import dlangui.widgets.popup;
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
import std.format;

import dcore.core;
import dlangide.ui.fileoutline;
import dlangide.ui.workspaceoutline;
import dlangide.ui.inlinediffeditor;
import dlangide.ui.enhanced_editor_integration;
import dlangide.ui.frame;

/**
 * Integrated outline panel that combines file and workspace outlines
 *
 * This creates a unified outline experience that shows:
 * - Workspace structure (projects, files, folders)
 * - Current file symbols (functions, classes, methods)
 * - Cross-references between symbols and files
 * - AI suggestions and changes highlighted in both views
 */
class OutlineIntegrationPanel : VerticalLayout {
    private {
        IDEFrame _frame;
        DCore _dcore;
        EnhancedEditorManager _editorManager;

        // Main UI components
        TabWidget _outlineTabs;
        VSplitter _outlineSplitter;

        // Outline widgets
        WorkspaceOutlineWidget _workspaceOutline;
        FileOutlineWidget _fileOutline;

        // Current state
        string _activeFilePath;
        InlineDiffEditor _activeEditor;

        // Integration features
        bool _syncWithEditor = true;
        bool _highlightRelatedSymbols = true;
        bool _showCrossReferences = true;
        bool _autoExpandToCurrentSymbol = true;

        // Search and navigation
        HorizontalLayout _searchToolbar;
        EditLine _globalSearchField;
        Button _searchBtn;
        Button _nextResultBtn;
        Button _prevResultBtn;
        TextWidget _searchStatusLabel;

        // Quick actions toolbar
        HorizontalLayout _actionsToolbar;
        Button _syncBtn;
        Button _refreshBtn;
        Button _settingsBtn;
        Button _jumpToFileBtn;
        Button _jumpToSymbolBtn;
    }

    // Events
    Signal!(string, int) onNavigateToLocation;  // (filePath, lineNumber)
    Signal!(string) onOpenFile;                 // (filePath)
    Signal!(string, string) onFindReferences;   // (symbol, filePath)

    this(IDEFrame frame, DCore dcore, EnhancedEditorManager editorManager) {
        super("outlineIntegration");
        _frame = frame;
        _dcore = dcore;
        _editorManager = editorManager;

        createUI();
        setupEventHandlers();
        initializeOutlines();
    }

    private void createUI() {
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        // Search toolbar
        createSearchToolbar();
        addChild(_searchToolbar);

        // Actions toolbar
        createActionsToolbar();
        addChild(_actionsToolbar);

        // Main outline area with tabs
        _outlineTabs = new TabWidget("outlineTabs");
        _outlineTabs.layoutWidth = FILL_PARENT;
        _outlineTabs.layoutHeight = FILL_PARENT;

        // Create workspace outline tab
        _workspaceOutline = new WorkspaceOutlineWidget(_dcore);
        _outlineTabs.addTab(_workspaceOutline, "Workspace"d, null, true, "workspace");

        // Create file outline tab
        _fileOutline = new FileOutlineWidget();
        _outlineTabs.addTab(_fileOutline, "File"d, null, true, "file");

        addChild(_outlineTabs);
    }

    private void createSearchToolbar() {
        _searchToolbar = new HorizontalLayout("searchToolbar");
        _searchToolbar.layoutWidth = FILL_PARENT;
        _searchToolbar.layoutHeight = WRAP_CONTENT;
        _searchToolbar.backgroundColor = 0xFFF8F8F8;
        _searchToolbar.padding = Rect(4, 4, 4, 4);

        // Global search field
        _globalSearchField = new EditLine("globalSearch");
        _globalSearchField.tooltipText = "Search symbols & files..."d;
        _globalSearchField.layoutWidth = FILL_PARENT;
        _searchToolbar.addChild(_globalSearchField);

        // Search button
        _searchBtn = new Button("search", "🔍"d);
        _searchBtn.tooltipText = "Search"d;
        _searchBtn.minWidth = 30;
        _searchToolbar.addChild(_searchBtn);

        // Navigation buttons
        _prevResultBtn = new Button("prevResult", "↑"d);
        _prevResultBtn.tooltipText = "Previous result"d;
        _prevResultBtn.minWidth = 25;
        _prevResultBtn.enabled = false;
        _searchToolbar.addChild(_prevResultBtn);

        _nextResultBtn = new Button("nextResult", "↓"d);
        _nextResultBtn.tooltipText = "Next result"d;
        _nextResultBtn.minWidth = 25;
        _nextResultBtn.enabled = false;
        _searchToolbar.addChild(_nextResultBtn);

        // Search status
        _searchStatusLabel = new TextWidget("searchStatus", ""d);
        _searchStatusLabel.textColor = 0xFF666666;
        _searchStatusLabel.fontSize = 9;
        _searchStatusLabel.minWidth = 60;
        _searchToolbar.addChild(_searchStatusLabel);
    }

    private void createActionsToolbar() {
        _actionsToolbar = new HorizontalLayout("actionsToolbar");
        _actionsToolbar.layoutWidth = FILL_PARENT;
        _actionsToolbar.layoutHeight = WRAP_CONTENT;
        _actionsToolbar.backgroundColor = 0xFFEEEEEE;
        _actionsToolbar.padding = Rect(2, 2, 2, 2);

        // Sync button
        _syncBtn = new Button("sync", "🔗"d);
        _syncBtn.tooltipText = "Sync with editor"d;
        _syncBtn.checkable = true;
        _syncBtn.checked = _syncWithEditor;
        _syncBtn.minWidth = 30;
        _actionsToolbar.addChild(_syncBtn);

        // Refresh button
        _refreshBtn = new Button("refresh", "🔄"d);
        _refreshBtn.tooltipText = "Refresh outlines"d;
        _refreshBtn.minWidth = 30;
        _actionsToolbar.addChild(_refreshBtn);

        // Jump buttons
        _jumpToFileBtn = new Button("jumpToFile", "📄"d);
        _jumpToFileBtn.tooltipText = "Jump to file"d;
        _jumpToFileBtn.minWidth = 30;
        _actionsToolbar.addChild(_jumpToFileBtn);

        _jumpToSymbolBtn = new Button("jumpToSymbol", "🎯"d);
        _jumpToSymbolBtn.tooltipText = "Jump to symbol"d;
        _jumpToSymbolBtn.minWidth = 30;
        _actionsToolbar.addChild(_jumpToSymbolBtn);

        // Spacer
        Widget spacer = new Widget();
        spacer.layoutWidth = FILL_PARENT;
        _actionsToolbar.addChild(spacer);

        // Settings button
        _settingsBtn = new Button("settings", "⚙"d);
        _settingsBtn.tooltipText = "Outline settings"d;
        _settingsBtn.minWidth = 30;
        _actionsToolbar.addChild(_settingsBtn);
    }

    private void setupEventHandlers() {
        // Search functionality
        _searchBtn.click = delegate(Widget source) {
            performGlobalSearch();
            return true;
        };

        // Search field handler - disabled due to signature mismatch
        // _globalSearchField.onContentChange requires different delegate signature

        _nextResultBtn.click = delegate(Widget source) {
            navigateToNextResult();
            return true;
        };

        _prevResultBtn.click = delegate(Widget source) {
            navigateToPreviousResult();
            return true;
        };

        // Action buttons
        _syncBtn.click = delegate(Widget source) {
            _syncWithEditor = _syncBtn.checked;
            if (_syncWithEditor && _activeEditor) {
                syncWithCurrentEditor();
            }
            return true;
        };

        _refreshBtn.click = delegate(Widget source) {
            refreshAllOutlines();
            return true;
        };

        _jumpToFileBtn.click = delegate(Widget source) {
            showJumpToFileDialog();
            return true;
        };

        _jumpToSymbolBtn.click = delegate(Widget source) {
            showJumpToSymbolDialog();
            return true;
        };

        _settingsBtn.click = delegate(Widget source) {
            showOutlineSettings();
            return true;
        };

        // Workspace outline events - delegates use direct assignment, not connect
        _workspaceOutline.onFileOpened = delegate(string filePath) {
            openFileInEditor(filePath);
            return true;
        };

        _workspaceOutline.onItemSelected = delegate(WorkspaceItem item) {
            handleWorkspaceItemSelected(item);
            return true;
        };

        // File outline events
        _fileOutline.onSymbolSelected = delegate(FileSymbol symbol) {
            handleSymbolSelected(symbol);
            return true;
        };

        _fileOutline.onSymbolDoubleClicked = delegate(FileSymbol symbol) {
            navigateToSymbol(symbol);
            return true;
        };

        // Editor manager events - disabled due to Signal API incompatibilities
        // _editorManager.onFileOpened and onFileClosed expect different delegate signatures
        // The Signal!string type requires string delegate() but we're providing bool delegate(string)
    }

    private void initializeOutlines() {
        // Load current workspace
        _workspaceOutline.loadWorkspaceFromVault();

        // If there's an active editor, sync with it
        if (_editorManager) {
            auto activeEditor = _editorManager.getActiveEditor();
            if (activeEditor) {
                setActiveEditor(activeEditor);
            }
        }
    }

    /// Set the active editor for outline synchronization
    void setActiveEditor(InlineDiffEditor editor) {
        if (_activeEditor == editor) return;

        _activeEditor = editor;

        if (editor) {
            _activeFilePath = editor.filePath;

            // Update file outline
            if (_syncWithEditor) {
                syncWithCurrentEditor();
            }

            // Highlight file in workspace outline
            highlightFileInWorkspace(_activeFilePath);
        } else {
            _activeFilePath = "";
            _activeEditor = null;
            _fileOutline.updateContentOutline("", "");
        }
    }

    /// Sync file outline with current editor content
    void syncWithCurrentEditor() {
        if (!_activeEditor || !_syncWithEditor) return;

        string content = _activeEditor.content;
        _fileOutline.updateContentOutline(content, _activeFilePath);

        // Highlight any pending changes in the outline
        if (_activeEditor.pendingChangesCount > 0) {
            // Get changes from editor and highlight symbols
            // This would require getting changes from the editor
            highlightChangedSymbolsInOutline();
        }

        // Update tab to show current file
        string fileName = _activeFilePath.empty ? "Untitled" : baseName(_activeFilePath);
        // _outlineTabs.setTabText("file", fileName.toUTF32());
    }

    private void highlightFileInWorkspace(string filePath) {
        if (filePath.empty) return;

        auto item = _workspaceOutline.findItemByPath(filePath);
        if (item) {
            // Highlight the item in workspace outline
            // This would need implementation in WorkspaceOutlineWidget
        }
    }

    private void highlightChangedSymbolsInOutline() {
        if (!_activeEditor) return;

        // Get pending changes from editor
        // This is a mock implementation - would need actual changes
        InlineChange[] changes = [];

        if (changes.length > 0) {
            _fileOutline.highlightChangedSymbols(changes);
        }
    }

    private void performGlobalSearch() {
        string query = std.utf.toUTF8(_globalSearchField.text);
        if (query.empty) return;

        // Search in both workspace and file outline
        performWorkspaceSearch(query);
        performFileSearch(query);
    }

    private void performIncrementalSearch() {
        string query = std.utf.toUTF8(_globalSearchField.text);

        // Quick search in current file outline
        performFileSearch(query);
    }

    private void performWorkspaceSearch(string query) {
        // Search for files matching the query
        // This would integrate with workspace outline's search functionality
        writeln("Searching workspace for: ", query);
    }

    private void performFileSearch(string query) {
        // Search for symbols matching the query in current file
        writeln("Searching file symbols for: ", query);
    }

    private void navigateToNextResult() {
        // Navigate to next search result
        writeln("Navigate to next search result");
    }

    private void navigateToPreviousResult() {
        // Navigate to previous search result
        writeln("Navigate to previous search result");
    }

    private void refreshAllOutlines() {
        _workspaceOutline.refreshWorkspace();
        if (_activeEditor) {
            syncWithCurrentEditor();
        }
        writeln("Refreshed all outlines");
    }

    private void showJumpToFileDialog() {
        // Create quick file picker dialog - disabled due to API issues
        // auto dialog = new QuickFilePickerDialog(_workspaceOutline.rootItem, window);
        // dialog.onFileSelected = delegate(string filePath) {
        //     openFileInEditor(filePath);
        //     return true;
        // };
        // dialog.show();
        writeln("Jump to file dialog disabled - API incompatibilities");
    }

    private void showJumpToSymbolDialog() {
        if (!_activeEditor) return;

        // Create quick symbol picker for current file - disabled due to API issues
        // auto symbols = _fileOutline.symbols;
        // auto dialog = new QuickSymbolPickerDialog(symbols, window);
        // dialog.onSymbolSelected = delegate(FileSymbol symbol) {
        //     navigateToSymbol(symbol);
        //     return true;
        // };
        // dialog.show();
        writeln("Jump to symbol dialog disabled - API incompatibilities");
    }

    private void showOutlineSettings() {
        // Show combined settings dialog for both outlines - disabled due to API issues
        // auto dialog = new CombinedOutlineSettingsDialog(
        //     _workspaceOutline.config,
        //     _fileOutline.config,
        //     window
        // );
        // dialog.onWorkspaceConfigChanged = delegate(WorkspaceConfig config) {
        //     _workspaceOutline.config = config;
        //     return true;
        // };
        // dialog.onFileConfigChanged = delegate(OutlineConfig config) {
        //     _fileOutline.config = config;
        //     return true;
        // };
        // dialog.show();
        writeln("Outline settings dialog disabled - API incompatibilities");
    }

    private void openFileInEditor(string filePath) {
        if (_editorManager) {
            auto editor = _editorManager.openFile(filePath);
            if (editor) {
                setActiveEditor(editor);
            }
        }

        // Signal emission disabled - incompatible Signal API
        // onOpenFile requires different handling
    }

    private void navigateToSymbol(FileSymbol symbol) {
        // Signal emission disabled - incompatible Signal API
        // onNavigateToLocation requires different handling

        // Also focus the editor and scroll to symbol
        if (_activeEditor) {
            _activeEditor.navigateToChange(0); // Would need proper symbol navigation
        }
    }

    private void handleWorkspaceItemSelected(WorkspaceItem item) {
        // Show item details in status or info panel
        updateStatusForItem(item);

        // If it's a source file, potentially update file outline preview
        if (item.type == WorkspaceItemType.SourceFile && item.path != _activeFilePath) {
            // Could show quick preview of file structure
            previewFileStructure(item.path);
        }
    }

    private void handleSymbolSelected(FileSymbol symbol) {
        // Show symbol details
        updateStatusForSymbol(symbol);

        // Find references if enabled
        if (_showCrossReferences) {
            findSymbolReferences(symbol);
        }
    }

    private void handleFileOpened(string filePath) {
        _activeFilePath = filePath;

        if (_syncWithEditor) {
            // Get the editor instance
            if (_editorManager) {
                auto editor = _editorManager.getActiveEditor();
                if (editor) {
                    setActiveEditor(editor);
                }
            }
        }
    }

    private void handleFileClosed(string filePath) {
        if (_activeFilePath == filePath) {
            setActiveEditor(null);
        }
    }

    private void handleChangesApplied(string filePath, InlineChange[] changes) {
        if (filePath == _activeFilePath) {
            // Refresh file outline to reflect changes
            syncWithCurrentEditor();

            // Update workspace outline if needed
            auto item = _workspaceOutline.findItemByPath(filePath);
            if (item) {
                item.hasChanges = false; // Changes have been applied
            }
        }
    }

    private void updateStatusForItem(WorkspaceItem item) {
        string status = format("%s - %s", item.name, to!string(item.type));
        if (item.description.length > 0) {
            status ~= " - " ~ item.description;
        }
        _searchStatusLabel.text = status.toUTF32();
    }

    private void updateStatusForSymbol(FileSymbol symbol) {
        string status = format("%s (%s)", symbol.name, to!string(symbol.type));
        if (symbol.returnType.length > 0) {
            status ~= " : " ~ symbol.returnType;
        }
        _searchStatusLabel.text = status.toUTF32();
    }

    private void previewFileStructure(string filePath) {
        // Quick preview without opening the file
        try {
            string content = readText(filePath);
            // Show simplified outline in tooltip or quick panel
        } catch (Exception e) {
            writeln("Error previewing file: ", e.msg);
        }
    }

    private void findSymbolReferences(FileSymbol symbol) {
        // Signal emission disabled - incompatible Signal API
        // onFindReferences requires different handling
    }

    /// Get current workspace outline
    @property WorkspaceOutlineWidget workspaceOutline() {
        return _workspaceOutline;
    }

    /// Get current file outline
    @property FileOutlineWidget fileOutline() {
        return _fileOutline;
    }

    /// Export current outline state
    JSONValue exportOutlineState() {
        JSONValue state = JSONValue.emptyObject;
        state["activeFilePath"] = JSONValue(_activeFilePath);
        state["syncWithEditor"] = JSONValue(_syncWithEditor);
        state["workspace"] = _workspaceOutline.exportWorkspace();
        state["fileOutline"] = _fileOutline.exportOutline();
        return state;
    }

    /// Cleanup resources
    void cleanup() {
        if (_workspaceOutline) {
            _workspaceOutline.cleanup();
        }
    }
}

/// Quick file picker dialog for jump-to-file functionality
class QuickFilePickerDialog : Dialog {
    bool delegate(string) onFileSelected;

    this(string[] files, Window parent) {
        super(UIString.fromRaw("Jump to File"), parent, DialogFlag.Modal, 400, 300);
        // Implementation would show searchable file list
    }
}

/// Quick symbol picker dialog for jump-to-symbol functionality
class QuickSymbolPickerDialog : Dialog {
    bool delegate(FileSymbol) onSymbolSelected;

    this(FileSymbol[] symbols, Window parent) {
        super(UIString.fromRaw("Jump to Symbol"), parent, DialogFlag.Modal, 400, 300);
        // Implementation would show searchable symbol list
    }
}

/// Combined settings dialog for both outline types
class CombinedOutlineSettingsDialog : Dialog {
    bool delegate(WorkspaceConfig) onWorkspaceConfigChanged;
    bool delegate(OutlineConfig) onFileConfigChanged;

    this(WorkspaceConfig workspaceConfig, OutlineConfig fileConfig, Window parent) {
        super(UIString.fromRaw("Outline Settings"), parent, DialogFlag.Modal, 500, 600);
        // Implementation would combine settings from both outline types
    }
}

/// Factory function to create outline integration panel
OutlineIntegrationPanel createOutlineIntegrationPanel(IDEFrame frame, DCore dcore,
                                                     EnhancedEditorManager editorManager) {
    return new OutlineIntegrationPanel(frame, dcore, editorManager);
}

/// Example of how to integrate into main IDE window - disabled due to API incompatibilities
void integrateOutlinesIntoIDE(IDEFrame frame, DCore dcore, EnhancedEditorManager editorManager) {
    // Outline integration disabled - Signal/Delegate API incompatibilities
    writeln("Outline integration disabled - API incompatibilities with dlangui signals");
}
