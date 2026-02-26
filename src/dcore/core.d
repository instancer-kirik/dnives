module dcore.core;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.format;
import std.datetime;
import std.json;
import std.exception;

import dlangui;
import dlangui.widgets.widget;
import dlangui.dialogs.dialog;
import dlangui.core.logger;

import dcore.config;
import dcore.vaultmanager;
import dcore.session;
import dcore.lsp.lspmanager;
import dcore.editor.editormanager;
import dcore.db.dbmanager;
import dcore.tools.toolmanager;

// AI system imports
import dcore.ai.integration;

// Notebooks imports
import dcore.notebooks.integration;

// Static imports for components
import dcore.components.cccore;
import dcore.ui.mainwindow;

/**
 * DCore - Main core system for Dnives IDE
 *
 * Works alongside CCCore to provide core IDE functionality.
 * DCore handles low-level systems while CCCore coordinates higher-level components.
 */
class DCore {
    private string _configDir;
    private bool _initialized;

    // Core managers
    private LSPManager _lspManager;
    private EditorManager _editorManager;
    private DBManager _dbManager;
    private ToolManager _toolManager;

    // Optional systems
    private AIIntegration _aiIntegration;
    private NotebookIntegration _notebookIntegration;

    // Reference to CCCore for workspace operations
    private CCCore _cccore;

    // State
    private SysTime _startTime;

    /**
     * Constructor
     */
    this(string configDir) {
        _configDir = configDir;
        _initialized = false;
        _startTime = Clock.currTime();
        _uiManager = new UIManager();

        Log.i("DCore initializing with config directory: ", configDir);

        // Ensure config directory exists
        if (!exists(_configDir)) {
            try {
                mkdirRecurse(_configDir);
                Log.i("Created config directory: ", _configDir);
            } catch (Exception e) {
                Log.e("Failed to create config directory: ", e.msg);
                throw e;
            }
        }
    }

    /**
     * Property getters for core managers
     */
    @property LSPManager lspManager() { return _lspManager; }
    @property EditorManager editorManager() { return _editorManager; }
    @property DBManager dbManager() { return _dbManager; }
    @property ToolManager toolManager() { return _toolManager; }

    // TODO: Implement these managers
    @property UIManager uiManager() { return _uiManager; }
    @property Object sessionManager() { return null; }

    private UIManager _uiManager;

    // Stub UIManager class
    private class UIManager {
        void updateStatusLine(string text) {
            // TODO: Implement status line updates
            Log.d("Status: ", text);
        }
    }

    /**
     * Get configuration value
     */
    T getConfigValue(T)(string key, T defaultValue) {
        // TODO: Implement proper configuration management
        // For now, return default values
        return defaultValue;
    }

    /**
     * Set configuration value
     */
    void setConfigValue(T)(string key, T value) {
        // TODO: Implement proper configuration management
        // For now, just log the operation
        Log.d("DCore: Setting config value ", key, " = ", value);
    }

    /**
     * Initialize core systems
     */
    bool initialize() {
        if (_initialized) {
            Log.w("DCore already initialized");
            return true;
        }

        try {
            Log.i("Initializing DCore systems...");

            // Initialize database
            string dbPath = buildPath(_configDir, "dnives.db");
            _dbManager = new DBManager(this, dbPath);
            _dbManager.initialize();

            // Initialize LSP manager
            _lspManager = new LSPManager(this);
            _lspManager.initialize();

            // Initialize editor manager
            _editorManager = new EditorManager(this);
            _editorManager.initialize();

            // Initialize tool manager
            string toolsConfigPath = buildPath(_configDir, "tools.json");
            _toolManager = new ToolManager(this, toolsConfigPath);
            _toolManager.initialize();

            // Initialize AI system
            _aiIntegration = new AIIntegration(this, null, null); // CCCore and MainWindow set later

            // Initialize notebook system
            _notebookIntegration = new NotebookIntegration();

            _initialized = true;
            Log.i("DCore initialization complete");
            return true;

        } catch (Exception e) {
            Log.e("DCore initialization failed: ", e.msg);
            return false;
        }
    }

    /**
     * Cleanup all systems
     */
    void cleanup() {
        Log.i("DCore cleanup starting...");

        try {
            // Cleanup AI system
            if (_aiIntegration !is null) {
                _aiIntegration.cleanup();
            }

            // Cleanup notebooks
            if (_notebookIntegration !is null) {
                shutdownNotebookSystem();
            }

            // Cleanup tools
            if (_toolManager !is null) {
                _toolManager.cleanup();
            }

            // Cleanup LSP
            if (_lspManager !is null) {
                _lspManager.cleanup();
            }

            // Cleanup database
            if (_dbManager !is null) {
                // TODO: Add cleanup method to DBManager
                // _dbManager.cleanup();
            }

            Log.i("DCore cleanup complete");

        } catch (Exception e) {
            Log.e("Error during DCore cleanup: ", e.msg);
        }
    }

    // Getters for core systems
    @property string configDir() const { return _configDir; }
    @property bool initialized() const { return _initialized; }

    string getConfigDir() { return _configDir; }
    LSPManager getLSPManager() { return _lspManager; }
    EditorManager getEditorManager() { return _editorManager; }
    DBManager getDBManager() { return _dbManager; }
    ToolManager getToolManager() { return _toolManager; }

    AIIntegration getAIIntegration() { return _aiIntegration; }
    NotebookIntegration getNotebookIntegration() { return _notebookIntegration; }

    bool isAIEnabled() { return _aiIntegration !is null; }

    /**
     * Get current workspace from CCCore
     */
    auto getCurrentWorkspace() {
        return _cccore ? _cccore.getCurrentWorkspace() : null;
    }

    /**
     * Set references from CCCore
     */
    void setCCCoreReferences(CCCore cccore, Widget mainWindow) {
        _cccore = cccore;

        if (_aiIntegration !is null) {
            _aiIntegration = new AIIntegration(this, cccore, cast(MainWindow)mainWindow);
        }

        if (_notebookIntegration !is null && mainWindow !is null) {
            // Initialize notebooks when UI is ready
            _notebookIntegration.initialize(cast(dlangui.widgets.docks.DockHost)mainWindow);
        }
    }

    /**
     * Get system health status
     */
    struct SystemHealth {
        bool overall;
        bool database;
        bool lsp;
        bool editor;
        bool notebooks;
        bool ai;
        string[] warnings;
        string[] errors;
    }

    SystemHealth getSystemHealth() {
        SystemHealth health;
        health.overall = true;

        // Check database
        health.database = _dbManager !is null; // TODO: Add isHealthy method to DBManager
        if (!health.database) {
            health.warnings ~= "Database issues detected";
        }

        // Check LSP
        health.lsp = _lspManager !is null;
        if (!health.lsp) {
            health.warnings ~= "LSP manager not available";
        }

        // Check editor
        health.editor = _editorManager !is null;
        if (!health.editor) {
            health.errors ~= "Editor manager not initialized";
            health.overall = false;
        }

        // Check notebooks
        health.notebooks = _notebookIntegration !is null;
        if (!health.notebooks) {
            health.warnings ~= "Notebook system not available";
        }

        // Check AI
        health.ai = _aiIntegration !is null;
        if (!health.ai) {
            health.warnings ~= "AI system not available";
        }

        return health;
    }
}
