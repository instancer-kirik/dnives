module dcore.vaultmanager;

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
import std.conv;
import std.uuid;
import std.process;

import dlangui.core.logger;

import dcore.components.cccore;

/**
 * VaultManager - Manages vaults (collections of workspaces)
 *
 * Responsible for:
 * - Loading/saving vault configurations
 * - Managing multiple vaults
 * - Creating/removing vaults
 * - Setting the current vault
 */
class VaultManager {
    // Configuration
    private string configPath;
    private JSONValue config;
    
    // Vaults
    private Vault[string] vaults;
    private string defaultVaultPath;
    
    // Reference to core
    private CCCore ccCore;
    
    // Current vault
    Vault currentVault;
    
    /// Constructor
    this(string configFilePath, CCCore core) {
        this.configPath = configFilePath;
        this.ccCore = core;
        
        // Initialize empty config
        config = parseJSON("{}");
        
        // Default vault path
        string appDataDir = ccCore.configManager.getValue!string("app_data_dir", 
                      buildPath(environment.get("HOME", "~"), ".computinator_code"));
        defaultVaultPath = buildPath(appDataDir, "default_vault");
        
        // Load configuration
        loadConfig();
    }
    
    /// Load vault configuration
    private void loadConfig() {
        // Create config file if it doesn't exist
        if (!exists(configPath)) {
            Log.i("Vault configuration file does not exist, creating:", configPath);
            // Initialize with empty vaults array
            config = parseJSON(`{"vaults": []}`);
            saveConfig();
            return;
        }
        
        try {
            // Load configuration
            string content = readText(configPath);
            config = parseJSON(content);
            
            // Load vaults from config
            loadVaults();
            
            Log.i("VaultManager initialized. Config file: ", configPath);
        } catch (Exception e) {
            Log.e("Error loading vault configuration: ", e.msg);
            // Use empty config
        }
    }
    
    /// Save vault configuration
    private void saveConfig() {
        try {
            // Create directory if it doesn't exist
            string dir = dirName(configPath);
            if (!exists(dir))
                mkdirRecurse(dir);
            
            // Prepare vault config
            JSONValue vaultConfig = parseJSON("{}");
            vaultConfig["vaults"] = parseJSON("[]");
            
            // Add each vault to the config
            JSONValue[] vaultArray;
            foreach (name, vault; vaults) {
                JSONValue vaultJson = parseJSON("{}");
                vaultJson["name"] = name;
                vaultJson["path"] = vault.path;
                vaultJson["description"] = vault.description;
                vaultArray ~= vaultJson;
            }
            
            // Set current vault
            if (currentVault)
                vaultConfig["current_vault"] = currentVault.name;
                
            // Add vaults to config
            vaultConfig["vaults"] = JSONValue(vaultArray);
            config = vaultConfig;
            
            // Save to file
            std.file.write(configPath, config.toPrettyString());
            
            Log.i("Vaults configuration saved successfully");
        } catch (Exception e) {
            Log.e("Error saving vault configuration: ", e.msg);
        }
    }
    
    /// Load vaults from configuration
    private void loadVaults() {
        Log.i("Loading vaults...");
        
        try {
            // Clear existing vaults
            vaults.clear();
            
            // Check if vaults section exists
            if ("vaults" !in config)
                return;
                
            // Load each vault
            auto vaultsArray = config["vaults"];
            if (vaultsArray.type != JSONType.array) {
                Log.w("Vaults configuration is not an array, skipping vault loading");
                return;
            }
            
            foreach (vaultJson; vaultsArray.array) {
                string name = vaultJson["name"].str;
                string path = vaultJson["path"].str;
                string description = "description" in vaultJson ? vaultJson["description"].str : "";
                
                Log.i("Loading vault: ", name, " at ", path);
                
                // Create and initialize vault
                Vault vault = new Vault(name, path, description);
                vault.initialize();
                
                // Add to vaults dictionary
                vaults[name] = vault;
                
                Log.i("Successfully loaded vault: ", name);
            }
            
            // Set current vault
            if ("current_vault" in config) {
                string currentVaultName = config["current_vault"].str;
                if (currentVaultName in vaults) {
                    setCurrentVault(currentVaultName);
                }
            }
        } catch (Exception e) {
            Log.e("Error loading vaults: ", e.msg);
        }
    }
    
    /// Create a new vault
    public Vault createVault(string name, string path, string description = "") {
        if (name in vaults) {
            Log.w("Vault already exists: ", name);
            return vaults[name];
        }
        
        try {
            // Create vault directory if it doesn't exist
            if (!exists(path))
                mkdirRecurse(path);
                
            // Create vault
            Vault vault = new Vault(name, path, description);
            vault.initialize();
            
            // Add to vaults
            vaults[name] = vault;
            
            // Save configuration
            saveConfig();
            
            Log.i("Created vault: ", name, " at ", path);
            return vault;
        } catch (Exception e) {
            Log.e("Error creating vault: ", e.msg);
            return null;
        }
    }
    
    /// Remove a vault
    public bool removeVault(string name) {
        if (name !in vaults) {
            Log.w("Vault does not exist: ", name);
            return false;
        }
        
        try {
            // Check if it's the current vault
            if (currentVault && currentVault.name == name) {
                // Can't remove current vault
                Log.w("Cannot remove current vault: ", name);
                return false;
            }
            
            // Remove from vaults
            vaults.remove(name);
            
            // Save configuration
            saveConfig();
            
            Log.i("Removed vault: ", name);
            return true;
        } catch (Exception e) {
            Log.e("Error removing vault: ", e.msg);
            return false;
        }
    }
    
    /// Set current vault
    public bool setCurrentVault(string name) {
        if (name !in vaults) {
            Log.w("Vault does not exist: ", name);
            return false;
        }
        
        try {
            // Set current vault
            currentVault = vaults[name];
            
            // Save configuration
            saveConfig();
            
            Log.w("Current vault set to: ", name);
            return true;
        } catch (Exception e) {
            Log.e("Error setting current vault: ", e.msg);
            return false;
        }
    }
    
    /// Get vault by name
    public Vault getVault(string name) {
        if (name !in vaults) {
            Log.w("Vault not found: ", name);
            return null;
        }
        
        return vaults[name];
    }
    
    /// Get vault by workspace
    public Vault getVaultByWorkspace(string workspaceName) {
        foreach (name, vault; vaults) {
            if (vault.hasWorkspace(workspaceName))
                return vault;
        }
        
        Log.w("No vault found for workspace: ", workspaceName);
        return null;
    }
    
    /// Get all vaults
    public Vault[] getAllVaults() {
        Vault[] result;
        foreach (name, vault; vaults)
            result ~= vault;
        return result;
    }
    
    /// Ensure default vault exists
    public Vault ensureDefaultVault() {
        // Check if default vault already exists
        foreach (name, vault; vaults) {
            if (vault.path == defaultVaultPath)
                return vault;
        }
        
        // Create default vault
        Log.i("Creating default vault at ", defaultVaultPath);
        Vault defaultVault = createVault("AppData Vault", defaultVaultPath, "Default vault for application data");
        
        // Set as current if no current vault
        if (!currentVault)
            setCurrentVault(defaultVault.name);
            
        return defaultVault;
    }
    
    /// Clean up resources
    public void cleanup() {
        Log.i("Cleaning up VaultManager resources");
        
        // Save configuration
        saveConfig();
        
        // Clean up temporary vaults
        int tempVaultsCleaned = 0;
        foreach (name, vault; vaults) {
            if (vault.isTemporary) {
                // Remove temporary vault
                vaults.remove(name);
                tempVaultsCleaned++;
            }
        }
        
        Log.i("Cleaned up ", tempVaultsCleaned, " temporary vaults");
    }
}

/**
 * Vault - A collection of workspaces
 */
class Vault {
    string name;
    string path;
    string description;
    bool isTemporary = false;
    
    // Workspaces in this vault
    private Workspace[string] workspaces;
    private Workspace currentWorkspace;
    
    /// Constructor
    this(string name, string path, string description = "") {
        this.name = name;
        this.path = path;
        this.description = description;
    }
    
    /// Initialize vault
    public void initialize() {
        Log.i("Initializing Vault: ", name, " at ", path);
        
        try {
            // Create directory if it doesn't exist
            if (!exists(path))
                mkdirRecurse(path);
                
            // Load workspaces
            loadWorkspaces();
        } catch (Exception e) {
            Log.e("Error initializing vault: ", e.msg);
        }
    }
    
    /// Load workspaces
    private void loadWorkspaces() {
        try {
            // Clear existing workspaces
            workspaces.clear();
            
            // Check workspaces directory
            string workspacesDir = buildPath(path, "workspaces");
            if (!exists(workspacesDir)) {
                // Create workspaces directory
                mkdirRecurse(workspacesDir);
                return;
            }
            
            // Load each workspace
            foreach (DirEntry entry; dirEntries(workspacesDir, SpanMode.shallow)) {
                if (entry.isDir) {
                    string workspaceName = baseName(entry.name);
                    string workspacePath = entry.name;
                    
                    // Create workspace
                    Workspace workspace = new Workspace(workspaceName, workspacePath);
                    
                    // Add to workspaces
                    workspaces[workspaceName] = workspace;
                }
            }
            
            // Load current workspace from config
            string configPath = buildPath(path, "vault_config.json");
            if (exists(configPath)) {
                string content = readText(configPath);
                JSONValue config = parseJSON(content);
                
                if ("current_workspace" in config) {
                    string currentWorkspaceName = config["current_workspace"].str;
                    if (currentWorkspaceName in workspaces) {
                        currentWorkspace = workspaces[currentWorkspaceName];
                    }
                }
            }
        } catch (Exception e) {
            Log.e("Error loading workspaces: ", e.msg);
        }
    }
    
    /// Save vault configuration
    private void saveConfig() {
        try {
            // Create config
            JSONValue config = parseJSON("{}");
            
            // Add current workspace
            if (currentWorkspace)
                config["current_workspace"] = currentWorkspace.name;
                
            // Save to file
            string configPath = buildPath(path, "vault_config.json");
            std.file.write(configPath, config.toPrettyString());
        } catch (Exception e) {
            Log.e("Error saving vault configuration: ", e.msg);
        }
    }
    
    /// Create a new workspace
    public Workspace createWorkspace(string name, string customPath = null) {
        if (name in workspaces) {
            Log.w("Workspace already exists: ", name);
            return workspaces[name];
        }
        
        try {
            // Determine workspace path
            string workspacePath;
            if (customPath && customPath.length > 0) {
                workspacePath = customPath;
            } else {
                workspacePath = buildPath(path, "workspaces", name);
            }
            
            // Create workspace directory
            if (!exists(workspacePath))
                mkdirRecurse(workspacePath);
                
            // Create workspace
            Workspace workspace = new Workspace(name, workspacePath);
            
            // Add to workspaces
            workspaces[name] = workspace;
            
            // Set as current if no current workspace
            if (!currentWorkspace)
                setCurrentWorkspace(name);
                
            // Save configuration
            saveConfig();
            
            Log.i("Created workspace: ", name, " at ", workspacePath);
            return workspace;
        } catch (Exception e) {
            Log.e("Error creating workspace: ", e.msg);
            return null;
        }
    }
    
    /// Remove a workspace
    public bool removeWorkspace(string name) {
        if (name !in workspaces) {
            Log.w("Workspace does not exist: ", name);
            return false;
        }
        
        try {
            // Check if it's the current workspace
            if (currentWorkspace && currentWorkspace.name == name) {
                // Unset current workspace
                currentWorkspace = null;
            }
            
            // Remove from workspaces
            workspaces.remove(name);
            
            // Save configuration
            saveConfig();
            
            Log.i("Removed workspace: ", name);
            return true;
        } catch (Exception e) {
            Log.e("Error removing workspace: ", e.msg);
            return false;
        }
    }
    
    /// Set current workspace
    public bool setCurrentWorkspace(string name) {
        if (name !in workspaces) {
            Log.w("Workspace does not exist: ", name);
            return false;
        }
        
        try {
            // Set current workspace
            currentWorkspace = workspaces[name];
            
            // Save configuration
            saveConfig();
            
            Log.i("Set current workspace to: ", name);
            return true;
        } catch (Exception e) {
            Log.e("Error setting current workspace: ", e.msg);
            return false;
        }
    }
    
    /// Get current workspace
    public Workspace getCurrentWorkspace() {
        return currentWorkspace;
    }
    
    /// Get workspace by name
    public Workspace getWorkspace(string name) {
        if (name !in workspaces) {
            Log.w("Workspace not found: ", name);
            return null;
        }
        
        return workspaces[name];
    }
    
    /// Check if workspace exists
    public bool hasWorkspace(string name) {
        return (name in workspaces) !is null;
    }
    
    /// Get all workspaces
    public Workspace[] getAllWorkspaces() {
        Workspace[] result;
        foreach (name, workspace; workspaces)
            result ~= workspace;
        return result;
    }
}