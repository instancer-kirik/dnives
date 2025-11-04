module dcore.components.cccore;

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
import std.variant;

import dlangui;
import dlangui.widgets.widget;
import dlangui.dialogs.dialog;
import dlangui.core.logger;

// Core imports
import dcore.config;
import dcore.vaultmanager;

/**
 * CCCore - Central component of CompyutinatorCode D implementation
 * 
 * Responsible for:
 * - Managing configuration
 * - Coordinating subsystems
 * - Handling events between components
 * - Providing centralized access to services
 */
class CCCore {
    // Core managers
    ConfigManager configManager;
    VaultManager vaultManager;
    
    // UI components
    Widget mainWindow;
    
    // State tracking
    bool initialized = false;
    bool coreInitialized = false;
    bool mainWindowSet = false;
    bool skipAIInitialization = false;
    
    // Optional components (will be implemented as needed)
    // FileManager fileManager;
    // ProjectManager projectManager;
    // BuildManager buildManager;
    // ThemeManager themeManager;
    // WidgetManager widgetManager;
    
    /// Constructor
    this(ConfigManager config) {
        Log.i("Initializing CCCore");
        
        // Store configuration manager
        this.configManager = config;
        
        // Initialize essential components
        initEssentialComponents();
    }
    
    /// Initialize essential components needed at startup
    private void initEssentialComponents() {
        try {
            // Create vault manager (handles workspaces/files)
            string vaultsConfigPath = buildPath(configManager.getConfigDir(), "vaults_config.json");
            vaultManager = new VaultManager(vaultsConfigPath, this);
            Log.i("VaultManager initialized");
            
            initialized = true;
        } catch (Exception e) {
            Log.e("Failed to initialize essential components: ", e.msg);
            throw e;
        }
    }
    
    /// Initialize remaining components after essential startup
    public void initialize() {
        if (coreInitialized)
            return;
            
        Log.i("Loading remaining CCCore components");
        
        try {
            // Initialize core managers
            initManagers();
            
            // Initialize late-binding components
            lateInit();
            
            coreInitialized = true;
            Log.i("CCCore initialization complete");
        } catch (Exception e) {
            Log.e("CCCore initialization failed: ", e.msg);
        }
    }
    
    /// Initialize core managers
    private void initManagers() {
        Log.i("Initializing managers");
        
        // TODO: Initialize other managers as needed
        // fileManager = new FileManager(this);
        // projectManager = new ProjectManager(this);
        // buildManager = new BuildManager(this);
        // themeManager = new ThemeManager(this);
        
        // Ensure default vault exists
        vaultManager.ensureDefaultVault();
    }
    
    /// Late initialization - called after window is set
    private void lateInit() {
        if (!mainWindowSet) {
            Log.w("Late initialization called before window was set");
        }
        
        // TODO: Add late initialization logic
    }
    
    /// Set the main application window
    public void setMainWindow(Widget window) {
        this.mainWindow = window;
        mainWindowSet = true;
        Log.i("Main window set successfully: ", window.toString());
    }
    
    /// Load configuration
    public bool loadConfig() {
        try {
            // Load configuration file
            if (configManager)
                configManager.load();
                
            return true;
        } catch (Exception e) {
            Log.e("Error loading configuration: ", e.msg);
            return false;
        }
    }
    
    /// Save configuration
    public bool saveConfig() {
        try {
            // Save configuration file
            if (configManager)
                configManager.save();
                
            return true;
        } catch (Exception e) {
            Log.e("Error saving configuration: ", e.msg);
            return false;
        }
    }
    
    /// Switch to another workspace
    public bool switchWorkspace(string workspaceName) {
        if (!vaultManager)
            return false;
            
        try {
            Vault vault = vaultManager.getVaultByWorkspace(workspaceName);
            if (vault is null) {
                Log.w("Workspace not found: ", workspaceName);
                return false;
            }
            
            // Set the current vault and workspace
            vaultManager.setCurrentVault(vault.name);
            vault.setCurrentWorkspace(workspaceName);
            
            // Save the last workspace in config
            if (configManager)
                configManager.setValue("last_workspace", workspaceName);
                
            Log.i("Switched to workspace: ", workspaceName);
            return true;
        } catch (Exception e) {
            Log.e("Error switching workspace: ", e.msg);
            return false;
        }
    }
    
    /// Get the current workspace
    public Workspace getCurrentWorkspace() {
        if (!vaultManager || !vaultManager.currentVault)
            return null;
            
        return vaultManager.currentVault.getCurrentWorkspace();
    }
    
    /// Create a new workspace
    public Workspace createWorkspace(string name, string path = null) {
        if (!vaultManager || !vaultManager.currentVault)
            return null;
            
        try {
            return vaultManager.currentVault.createWorkspace(name, path);
        } catch (Exception e) {
            Log.e("Error creating workspace: ", e.msg);
            return null;
        }
    }
    
    /// Open a project in the current workspace
    public bool openProject(string projectPath) {
        auto workspace = getCurrentWorkspace();
        if (!workspace)
            return false;
            
        try {
            return workspace.openProject(projectPath);
        } catch (Exception e) {
            Log.e("Error opening project: ", e.msg);
            return false;
        }
    }
    
    /// Clean up resources
    public void cleanup() {
        Log.i("Cleaning up CCCore resources");
        
        // Save configuration
        saveConfig();
        
        // Clean up managers in reverse initialization order
        // TODO: Clean up other managers
        
        // Clean up vault manager last
        if (vaultManager)
            vaultManager.cleanup();
    }
}

/**
 * Workspace representation
 */
class Workspace {
    string name;
    string path;
    string[] openProjects;
    string currentProject;
    
    this(string name, string path) {
        this.name = name;
        this.path = path;
    }
    
    bool openProject(string projectPath) {
        try {
            // Check if project exists
            if (!exists(projectPath) || !isDir(projectPath)) {
                Log.w("Project path does not exist: ", projectPath);
                return false;
            }
            
            // Add to open projects if not already there
            if (!openProjects.canFind(projectPath))
                openProjects ~= projectPath;
                
            // Set as current project
            currentProject = projectPath;
            
            Log.i("Opened project: ", projectPath);
            return true;
        } catch (Exception e) {
            Log.e("Error opening project: ", e.msg);
            return false;
        }
    }
    
    string getProjectName(string projectPath) {
        return baseName(projectPath);
    }
}