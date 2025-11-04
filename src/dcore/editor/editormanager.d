module dcore.editor.editormanager;

import dlangui.core.logger;
import dlangui.widgets.widget;
import dlangui.widgets.tabs;

import std.file;
import std.path;
import std.algorithm;
import std.array;
import std.string;

import dcore.core;
import dcore.editor.editor;
import dcore.editor.document;
import dcore.lsp.lspmanager;
import dcore.vault.vault;

/**
 * EditorManager - Manages editor instances and file operations
 *
 * Responsible for:
 * - Creating and managing editor instances
 * - Opening/closing files in editors
 * - Tracking active/recent files
 * - Coordinating with LSP for diagnostics and code intelligence
 * - Handling editor events (cursor position, text changes, etc.)
 */
class EditorManager {
    private DCore _core;
    private TabWidget _editorTabs;
    private EditorWidget[string] _editors; // File path -> Editor
    private EditorWidget _activeEditor;
    private string[] _recentFiles;
    private const int MAX_RECENT_FILES = 20;
    
    // Editor settings
    private bool _showLineNumbers = true;
    private bool _showWhitespace = false;
    private bool _lineWrapping = false;
    private int _tabSize = 4;
    private bool _autoIndent = true;
    private bool _autoCloseBrackets = true;
    
    /**
     * Constructor
     */
    this(DCore core) {
        _core = core;
        Log.i("EditorManager: Initializing");
    }
    
    /**
     * Initialize the manager
     */
    void initialize() {
        Log.i("EditorManager: Starting initialization");
        
        // Load settings from config
        loadSettings();
        
        // Load recent files
        loadRecentFiles();
        
        Log.i("EditorManager: Initialization complete");
    }
    
    /**
     * Set the editor tabs widget
     */
    void setEditorTabWidget(TabWidget tabWidget) {
        _editorTabs = tabWidget;
        Log.i("EditorManager: Editor tab widget set");
    }
    
    /**
     * Open a file in an editor
     */
    EditorWidget openFile(string filePath) {
        if (!exists(filePath)) {
            Log.e("EditorManager: Cannot open file (not found): ", filePath);
            return null;
        }
        
        // Normalize path
        filePath = buildNormalizedPath(filePath);
        
        // Check if already open
        if (filePath in _editors) {
            // File already open, just activate it
            activateEditor(_editors[filePath]);
            return _editors[filePath];
        }
        
        try {
            // Create a new editor
            string fileName = baseName(filePath);
            string editorId = "EDITOR_" ~ fileName;
            EditorWidget editor = new EditorWidget(editorId);
            
            // Apply settings
            editor.showLineNumbers(_showLineNumbers);
            editor.setTabSize(_tabSize);
            
            // Connect signals - directly assign handlers
            editor.onFileLoaded.connect(&handleFileLoaded);
            editor.onFileSaved.connect(&handleFileSaved);
            editor.onCursorMoved.connect(&handleCursorMoved);
            editor.onTextChanged.connect(&handleTextChanged);
            editor.onLanguageChanged.connect(&handleLanguageChanged);
            editor.onKeyboardShortcut.connect(&handleKeyboardShortcut);
            
            // Open the file
            if (!editor.openFile(filePath)) {
                Log.e("EditorManager: Failed to open file: ", filePath);
                return null;
            }
            
            // Add to editors map
            _editors[filePath] = editor;
            
            // Add to tabs
            if (_editorTabs) {
                _editorTabs.addTab(editor, cast(dstring)fileName);
                _editorTabs.selectTab(_editorTabs.tabCount - 1);
            }
            
            // Activate this editor
            activateEditor(editor);
            
            // Add to recent files
            addToRecentFiles(filePath);
            
            Log.i("EditorManager: File opened: ", filePath);
            return editor;
        }
        catch (Exception e) {
            Log.e("EditorManager: Error opening file: ", e.msg);
            return null;
        }
    }
    
    /**
     * Save the current file
     */
    bool saveCurrentFile() {
        if (!_activeEditor)
            return false;
            
        string filePath = _activeEditor.getFilePath();
        return saveFile(filePath);
    }
    
    /**
     * Save a file
     */
    bool saveFile(string filePath) {
        if (filePath !in _editors)
            return false;
            
        EditorWidget editor = _editors[filePath];
        return editor.saveFile();
    }
    
    /**
     * Save file as
     */
    bool saveFileAs(string oldPath, string newPath) {
        if (oldPath !in _editors)
            return false;
            
        EditorWidget editor = _editors[oldPath];
        
        // Save to new path
        if (!editor.saveFile(newPath))
            return false;
            
        // Update editors map
        _editors.remove(oldPath);
        _editors[newPath] = editor;
        
        // Update tab name
        if (_editorTabs) {
            for (int i = 0; i < _editorTabs.tabCount; i++) {
                if (_editorTabs.tabBody(i) is editor) {
                    // Update tab label - remove and add again
                    string id = editor.id;
                    Widget body = _editorTabs.tabBody(i);
                    _editorTabs.removeTab(editor.id);
                    _editorTabs.addTab(body, cast(dstring)baseName(newPath));
                    break;
                }
            }
        }
        
        // Add to recent files
        addToRecentFiles(newPath);
        
        return true;
    }
    
    /**
     * Close a file
     */
    bool closeFile(string filePath) {
        if (filePath !in _editors)
            return false;
            
        EditorWidget editor = _editors[filePath];
        
        // Remove from tabs
        if (_editorTabs) {
            for (int i = 0; i < _editorTabs.tabCount; i++) {
                if (_editorTabs.tabBody(i) is editor) {
                    _editorTabs.removeTab(editor.id);
                    break;
                }
            }
        }
        
        // Remove from editors map
        _editors.remove(filePath);
        
        // Set new active editor if needed
        if (_activeEditor is editor) {
            if (_editors.length > 0) {
                auto keys = _editors.keys;
                activateEditor(_editors[keys[0]]);
            } else {
                _activeEditor = null;
            }
        }
        
        Log.i("EditorManager: File closed: ", filePath);
        return true;
    }
    
    /**
     * Close all files
     */
    void closeAllFiles() {
        if (_editorTabs) {
            // Remove all tabs one by one
            while (_editorTabs.tabCount > 0) {
                _editorTabs.removeTab(_editorTabs.tab(0).id);
            }
        }
        
        _editors.clear();
        _activeEditor = null;
        
        Log.i("EditorManager: All files closed");
    }
    
    /**
     * Activate an editor
     */
    void activateEditor(EditorWidget editor) {
        if (!editor)
            return;
            
        _activeEditor = editor;
        
        // Activate tab
        if (_editorTabs) {
            for (int i = 0; i < _editorTabs.tabCount; i++) {
                if (_editorTabs.tabBody(i) is editor) {
                    _editorTabs.selectTab(i);
                    break;
                }
            }
        }
        
        // Give focus to editor
        if (editor)
            editor.setFocus();
            
        // Get file path
        string filePath = editor.getFilePath();
        string language = editor.getLanguage();
        
        // Notify LSP manager
        if (_core && _core.lspManager) {
            if (_core.lspManager)
                if (_core.lspManager)
                    _core.lspManager.notifyFileOpen(filePath, "");
        }
    }
    
    /**
     * Get the active editor
     */
    EditorWidget getActiveEditor() {
        return _activeEditor;
    }
    
    /**
     * Get editor for file
     */
    EditorWidget getEditorForFile(string filePath) {
        if (filePath in _editors)
            return _editors[filePath];
        return null;
    }
    
    /**
     * Get all open editors
     */
    EditorWidget[] getAllEditors() {
        EditorWidget[] result;
        foreach (editor; _editors.values)
            result ~= editor;
        return result;
    }
    
    /**
     * Get all open file paths
     */
    string[] getOpenFilePaths() {
        return _editors.keys;
    }
    
    /**
     * Get recent files
     */
    string[] getRecentFiles() {
        return _recentFiles.dup;
    }
    
    /**
     * Add to recent files
     */
    private void addToRecentFiles(string filePath) {
        // Remove if already exists
        _recentFiles = _recentFiles.filter!(a => a != filePath).array;
        
        // Add to front
        _recentFiles = [filePath] ~ _recentFiles;
        
        // Limit size
        if (_recentFiles.length > MAX_RECENT_FILES)
            _recentFiles = _recentFiles[0..MAX_RECENT_FILES];
            
        // Save recent files
        saveRecentFiles();
    }
    
    /**
     * Load settings
     */
    private void loadSettings() {
        if (!_core)
            return;
            
        _showLineNumbers = _core.getConfigValue("editor.showLineNumbers", true);
        _showWhitespace = _core.getConfigValue("editor.showWhitespace", false);
        _lineWrapping = _core.getConfigValue("editor.lineWrapping", false);
        _tabSize = _core.getConfigValue("editor.tabSize", 4);
        _autoIndent = _core.getConfigValue("editor.autoIndent", true);
        _autoCloseBrackets = _core.getConfigValue("editor.autoCloseBrackets", true);
        
        Log.i("EditorManager: Settings loaded");
    }
    
    /**
     * Save settings
     */
    private void saveSettings() {
        if (!_core)
            return;
            
        _core.setConfigValue("editor.showLineNumbers", _showLineNumbers);
        _core.setConfigValue("editor.showWhitespace", _showWhitespace);
        _core.setConfigValue("editor.lineWrapping", _lineWrapping);
        _core.setConfigValue("editor.tabSize", _tabSize);
        _core.setConfigValue("editor.autoIndent", _autoIndent);
        _core.setConfigValue("editor.autoCloseBrackets", _autoCloseBrackets);
        
        Log.i("EditorManager: Settings saved");
    }
    
    /**
     * Load recent files
     */
    private void loadRecentFiles() {
        if (!_core)
            return;
            
        import std.json;
        
        try {
            JSONValue recentFilesJson = _core.getConfigValue("editor.recentFiles", parseJSON("[]"));
            
            _recentFiles.length = 0;
            foreach (jsonValue; recentFilesJson.array) {
                string filePath = jsonValue.str;
                if (exists(filePath))
                    _recentFiles ~= filePath;
            }
            
            Log.i("EditorManager: Recent files loaded");
        }
        catch (Exception e) {
            Log.e("EditorManager: Error loading recent files: ", e.msg);
            _recentFiles.length = 0;
        }
    }
    
    /**
     * Save recent files
     */
    private void saveRecentFiles() {
        if (!_core)
            return;
            
        import std.json;
        
        try {
            JSONValue[] jsonArray;
            foreach (filePath; _recentFiles) {
                jsonArray ~= JSONValue(filePath);
            }
            
            JSONValue recentFilesJson = JSONValue(jsonArray);
            _core.setConfigValue("editor.recentFiles", recentFilesJson);
            
            Log.i("EditorManager: Recent files saved");
        }
        catch (Exception e) {
            Log.e("EditorManager: Error saving recent files: ", e.msg);
        }
    }
    
    /**
     * Apply settings to all editors
     */
    void applySettingsToAll() {
        foreach (editor; _editors.values) {
            editor.showLineNumbers(_showLineNumbers);
            editor.setTabSize(_tabSize);
            // Apply other settings as needed
        }
    }
    
    /**
     * Handle file loaded event
     */
    private void handleFileLoaded(string filePath) {
        // Signal to LSP manager
        if (_core && _core.lspManager) {
            EditorWidget editor = getEditorForFile(filePath);
            if (editor) {
                string language = editor.getLanguage();
                _core.lspManager.notifyFileOpen(filePath, "");
            }
        }
    }
    
    /**
     * Handle file saved event
     */
    private void handleFileSaved(string filePath) {
        // Signal to LSP manager
        if (_core && _core.lspManager) {
            if (_core.lspManager)
                _core.lspManager.notifyFileChange(filePath, "");
        }
    }
    
    /**
     * Handle cursor moved event
     */
    private void handleCursorMoved(int line, int column) {
        // Update status bar or other UI elements
        if (_core && _core.uiManager) {
            _core.uiManager.updateStatusLine(format("Ln %d, Col %d", line+1, column+1));
        }
    }
    
    /**
     * Handle text changed event
     */
    private void handleTextChanged() {
        if (!_activeEditor)
            return;
            
        // Signal to LSP manager
        if (_core && _core.lspManager) {
            string filePath = _activeEditor.getFilePath();
            dstring text = _activeEditor.text;
            if (_core.lspManager)
                _core.lspManager.notifyFileChange(filePath, cast(string)text);
        }
    }
    
    /**
     * Handle language changed event
     */
    private void handleLanguageChanged(string language) {
        if (!_activeEditor)
            return;
            
        // Signal to LSP manager
        if (_core && _core.lspManager) {
            string filePath = _activeEditor.getFilePath();
            _core.lspManager.notifyFileOpen(filePath, "");
        }
    }
    
    /**
     * Handle keyboard shortcut event
     */
    private void handleKeyboardShortcut(KeyEvent event) {
        // Process global keyboard shortcuts
    }
    
    /**
     * Handle workspace changed event
     */
    void onWorkspaceChanged(Workspace workspace) {
        // Clear editors for previous workspace
        closeAllFiles();
        
        // Load session for new workspace
        if (workspace && _core && _core.sessionManager) {
            // TODO: Load workspace session
        }
    }
    
    /**
     * Cleanup resources
     */
    void cleanup() {
        // Save recent files
        saveRecentFiles();
        
        // Save settings
        saveSettings();
        
        // Close all files
        closeAllFiles();
        
        Log.i("EditorManager: Cleanup complete");
    }
}