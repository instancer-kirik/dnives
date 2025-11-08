module dcore.core;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.datetime;
import std.json;
import std.exception;

import dlangui.core.logger;
import dlangui.widgets.widget;

// Core components
import dcore.vault.vault;
import dcore.ui.mainwindow;
import dcore.editor.editormanager;
import dcore.lsp.lspmanager;
import dcore.ui.uimanager;
import dcore.session;

// AI system imports
import dcore.ai.integration;

/**
 * DCore - Main core class for CompyutinatorCode
 *
 * This is the central coordination point for the IDE, managing:
 * - Sessions and workspaces (via vault system)
 * - Editor instances
 * - Language server protocols (LSP)
 * - UI components
 * - Configuration and settings
 */
class DCore
{
    // Core managers
    private VaultManager _vaultManager;
    private EditorManager _editorManager;
    private LSPManager _lspManager;
    private UIManager _uiManager;
    private SessionManager _sessionManager;

    // AI system integration
    private AIIntegration _aiIntegration;

    // Configuration
    private string _configDir;
    private JSONValue _config;

    // State
    private bool _initialized = false;
    private bool _fastMode = false;
    private bool _aiEnabled = true;

    // Main window reference
    private Widget _mainWindow;

    /// Constructor
    this(string configDir)
    {
        _configDir = configDir;
        Log.i("DCore: Initializing with config directory: ", _configDir);

        // Initialize empty configuration
        _config = parseJSON("{}");

        // Create core components
        _sessionManager = new SessionManager();
        _editorManager = new EditorManager(this);
        _lspManager = new LSPManager(this);
        _uiManager = new UIManager(this);

        // Create vault manager
        string vaultConfigPath = buildPath(_configDir, "vaults.json");
        _vaultManager = new VaultManager(vaultConfigPath);
    }

    /// Initialize core components
    bool initialize()
    {
        if (_initialized)
        {
            Log.w("DCore: Already initialized");
            return true;
        }

        try
        {
            Log.i("DCore: Initializing core components");

            // Load configuration
            loadConfig();

            // Initialize vault manager
            _vaultManager.initialize();

            // Ensure default vault exists
            Vault defaultVault = _vaultManager.ensureDefaultVault();
            if (!defaultVault)
            {
                Log.e("DCore: Failed to create default vault");
                return false;
            }

            // Initialize LSP manager
            _lspManager.initialize();

            // Initialize editor manager
            _editorManager.initialize();

            // Initialize AI system if enabled
            if (_aiEnabled && _mainWindow) {
                initializeAISystem();
            }

            // Set initialization flag
            _initialized = true;

            Log.i("DCore: Initialization complete");
            return true;
        }
        catch (Exception e)
        {
            Log.e("DCore: Initialization error: ", e.msg);
            return false;
        }
    }

    /// Load configuration
    private void loadConfig()
    {
        string configPath = buildPath(_configDir, "config.json");

        if (!exists(configPath))
        {
            Log.i("DCore: Configuration file doesn't exist, creating default");
            saveConfig();
            return;
        }

        try
        {
            string content = readText(configPath);
            _config = parseJSON(content);
            Log.i("DCore: Configuration loaded successfully");
        }
        catch (Exception e)
        {
            Log.e("DCore: Error loading configuration: ", e.msg);
            // Use default config
            _config = parseJSON("{}");
        }

        // Check AI enabled setting
        if ("ai_enabled" in _config) {
            _aiEnabled = _config["ai_enabled"].get!bool;
        }
    }

    /// Save configuration
    void saveConfig()
    {
        string configPath = buildPath(_configDir, "config.json");

        try
        {
            // Create directory if it doesn't exist
            string dir = dirName(configPath);
            if (!exists(dir))
                mkdirRecurse(dir);

            // Save to file
            std.file.write(configPath, _config.toPrettyString());
            Log.i("DCore: Configuration saved successfully");
        }
        catch (Exception e)
        {
            Log.e("DCore: Error saving configuration: ", e.msg);
        }
    }

    /// Get configuration value
    T getConfigValue(T)(string key, T defaultValue)
    {
        import std.conv : to;

        try
        {
            string[] parts = key.split(".");
            JSONValue current = _config;

            // Navigate through nested JSON
            foreach (part; parts[0 .. $ - 1])
            {
                if (part !in current)
                    return defaultValue;
                current = current[part];
            }

            string lastPart = parts[$ - 1];
            if (lastPart !in current)
                return defaultValue;

            // Convert value to requested type
            static if (is(T == string))
                return current[lastPart].str;
            else static if (is(T == int))
                return cast(int) current[lastPart].integer;
            else static if (is(T == bool))
                return current[lastPart].boolean;
            else static if (is(T == double))
                return current[lastPart].floating;
            else
                return defaultValue;
        }
        catch (Exception e)
        {
            Log.e("DCore: Error getting config value: ", e.msg);
            return defaultValue;
        }
    }

    /// Set configuration value
    void setConfigValue(T)(string key, T value)
    {
        try
        {
            string[] parts = key.split(".");

            // Ensure parent objects exist
            JSONValue* current = &_config;
            foreach (part; parts[0 .. $ - 1])
            {
                if (part !in *current)
                    (*current)[part] = parseJSON("{}");
                current = &((*current)[part]);
            }

            // Set value
            string lastPart = parts[$ - 1];
            static if (is(T == string))
                (*current)[lastPart] = value;
            else static if (is(T == int))
                (*current)[lastPart] = value;
            else static if (is(T == bool))
                (*current)[lastPart] = value;
            else static if (is(T == double))
                (*current)[lastPart] = value;
            else static if (is(T == JSONValue))
                (*current)[lastPart] = value;

            // Save configuration
            saveConfig();
        }
        catch (Exception e)
        {
            Log.e("DCore: Error setting config value: ", e.msg);
        }
    }

    /// Set main window reference
    void setMainWindow(Widget window)
    {
        _mainWindow = window;
        if (auto mainWindow = cast(MainWindow) window)
        {
            _uiManager.setMainWindow(mainWindow);
        }
        else
        {
            Log.e("DCore: setMainWindow called with non-MainWindow widget");
        }
    }

    /// Get main window reference
    Widget getMainWindow()
    {
        return _mainWindow;
    }

    /// Switch to a workspace
    bool switchWorkspace(string workspaceName)
    {
        // Find vault containing workspace
        Vault vault = _vaultManager.getVaultByWorkspace(workspaceName);
        if (!vault)
        {
            Log.w("DCore: No vault found for workspace: ", workspaceName);
            return false;
        }

        // Set current vault
        _vaultManager.setCurrentVault(vault.name);

        // Set current workspace
        bool result = vault.setCurrentWorkspace(workspaceName);
        if (result)
        {
            // Update recent workspaces
            setConfigValue("workspace.last", workspaceName);

            // Notify managers
            _editorManager.onWorkspaceChanged(vault.getCurrentWorkspace());
            // LSP manager handles workspace differently
            _lspManager.onWorkspaceChanged(vault.getCurrentWorkspace());
            _uiManager.onWorkspaceChanged(vault.getCurrentWorkspace());

            Log.i("DCore: Switched to workspace: ", workspaceName);
        }

        return result;
    }

    /// Get current workspace
    Workspace getCurrentWorkspace()
    {
        if (!_vaultManager || !_vaultManager.currentVault)
            return null;

        return _vaultManager.currentVault.getCurrentWorkspace();
    }

    /// Cleanup resources
    void cleanup()
    {
        Log.i("DCore: Cleaning up resources");

        // Save configuration
        saveConfig();

        // Clean up managers
        if (_vaultManager)
            _vaultManager.cleanup();

        if (_editorManager)
            _editorManager.cleanup();

        if (_lspManager)
            _lspManager.cleanup();

        if (_sessionManager)
            _sessionManager.saveSession(buildPath(_configDir, "session.json"));

        Log.i("DCore: Cleanup complete");
    }

    // Getters for managers
    VaultManager vaultManager()
    {
        return _vaultManager;
    }

    EditorManager editorManager()
    {
        return _editorManager;
    }

    LSPManager lspManager()
    {
        return _lspManager;
    }

    UIManager uiManager()
    {
        return _uiManager;
    }

    /// Get session manager
    SessionManager getSessionManager()
    {
        return _sessionManager;
    }

    /// Get AI integration
    AIIntegration getAIIntegration()
    {
        return _aiIntegration;
    }

    /// Check if AI is enabled
    bool isAIEnabled()
    {
        return _aiEnabled;
    }

    /// Enable or disable AI system
    void setAIEnabled(bool enabled)
    {
        if (_aiEnabled == enabled) return;

        _aiEnabled = enabled;

        if (enabled && !_aiIntegration && _initialized) {
            initializeAISystem();
        } else if (!enabled && _aiIntegration) {
            _aiIntegration.cleanup();
            _aiIntegration = null;
        }

        saveConfig();
    }

    /// Initialize AI system
    private void initializeAISystem()
    {
        if (_aiIntegration) return;

        try {
            Log.i("DCore: Initializing AI system...");

            // Create AI integration
            auto ccCore = cast(CCCore)_mainWindow;
            auto mainWindow = cast(MainWindow)_mainWindow;
            _aiIntegration = new AIIntegration(this, ccCore, mainWindow);

            // Initialize with LSP manager
            _aiIntegration.initialize(_lspManager);

            // Create AI chat dock
            _aiIntegration.createAIChatDock();

            Log.i("DCore: AI system initialized successfully");
        } catch (Exception e) {
            Log.e("DCore: Failed to initialize AI system: ", e.msg);
            _aiIntegration = null;
            _aiEnabled = false;
        }
    }

    /// Get configuration directory
    string getConfigDir()
    {
        return _configDir;
    }
}
