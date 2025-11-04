module dcore.vault.vault;

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

/**
 * Workspace - Represents a coding workspace with files and settings
 *
 * A workspace is a directory containing source files and configuration
 * for a project or set of related projects.
 */
class Workspace {
    private {
        string _name;           // Workspace name
        string _path;           // Workspace path
        string _description;    // Workspace description
        SysTime _created;       // Creation time
        SysTime _lastAccessed;  // Last accessed time
        JSONValue _settings;    // Workspace settings
    }
    
    /**
     * Constructor
     */
    this(string name, string path, string description = "") {
        _name = name;
        _path = path;
        _description = description;
        _created = Clock.currTime();
        _lastAccessed = _created;
        _settings = parseJSON("{}");
    }
    
    /**
     * Constructor from JSON
     */
    this(JSONValue json) {
        deserialize(json);
    }
    
    // Getters and Setters
    string name() const { return _name; }
    string path() const { return _path; }
    string description() const { return _description; }
    SysTime created() const { return _created; }
    SysTime lastAccessed() const { return _lastAccessed; }
    
    void name(string value) { _name = value; }
    void path(string value) { _path = value; }
    void description(string value) { _description = value; }
    
    /**
     * Update last accessed time
     */
    void updateLastAccessed() {
        _lastAccessed = Clock.currTime();
    }
    
    /**
     * Get a workspace setting
     */
    T getSetting(T)(string key, T defaultValue) {
        try {
            string[] parts = key.split(".");
            JSONValue current = _settings;
            
            // Navigate through nested JSON
            foreach (part; parts[0 .. $-1]) {
                if (part !in current)
                    return defaultValue;
                current = current[part];
            }
            
            string lastPart = parts[$-1];
            if (lastPart !in current)
                return defaultValue;
                
            // Convert value to requested type
            static if (is(T == string))
                return current[lastPart].str;
            else static if (is(T == int))
                return cast(int)current[lastPart].integer;
            else static if (is(T == bool))
                return current[lastPart].boolean;
            else static if (is(T == double))
                return current[lastPart].floating;
            else
                return defaultValue;
        }
        catch (Exception e) {
            Log.e("Workspace: Error getting setting: ", e.msg);
            return defaultValue;
        }
    }
    
    /**
     * Set a workspace setting
     */
    void setSetting(T)(string key, T value) {
        try {
            string[] parts = key.split(".");
            
            // Ensure parent objects exist
            JSONValue* current = &_settings;
            foreach (part; parts[0 .. $-1]) {
                if (part !in *current)
                    (*current)[part] = parseJSON("{}");
                current = &((*current)[part]);
            }
            
            // Set value
            string lastPart = parts[$-1];
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
        }
        catch (Exception e) {
            Log.e("Workspace: Error setting setting: ", e.msg);
        }
    }
    
    /**
     * Check if workspace exists on disk
     */
    bool exists() const {
        return std.file.exists(_path) && std.file.isDir(_path);
    }
    
    /**
     * Create workspace directory if it doesn't exist
     */
    bool create() {
        try {
            if (!exists()) {
                mkdirRecurse(_path);
                Log.i("Workspace: Created workspace directory: ", _path);
            }
            return true;
        }
        catch (Exception e) {
            Log.e("Workspace: Error creating workspace: ", e.msg);
            return false;
        }
    }
    
    /**
     * Serialize workspace to JSON
     */
    JSONValue serialize() const {
        JSONValue json = parseJSON("{}");
        
        json["name"] = _name;
        json["path"] = _path;
        json["description"] = _description;
        json["created"] = _created.toISOExtString();
        json["lastAccessed"] = _lastAccessed.toISOExtString();
        json["settings"] = parseJSON(_settings.toString());
        
        return json;
    }
    
    /**
     * Deserialize workspace from JSON
     */
    void deserialize(JSONValue json) {
        if ("name" in json)
            _name = json["name"].str;
            
        if ("path" in json)
            _path = json["path"].str;
            
        if ("description" in json)
            _description = json["description"].str;
            
        if ("created" in json) {
            try {
                _created = SysTime.fromISOExtString(json["created"].str);
            } catch (Exception e) {
                _created = Clock.currTime();
            }
        } else {
            _created = Clock.currTime();
        }
        
        if ("lastAccessed" in json) {
            try {
                _lastAccessed = SysTime.fromISOExtString(json["lastAccessed"].str);
            } catch (Exception e) {
                _lastAccessed = Clock.currTime();
            }
        } else {
            _lastAccessed = Clock.currTime();
        }
        
        if ("settings" in json)
            _settings = parseJSON(json["settings"].toString());
        else
            _settings = parseJSON("{}");
    }
}

/**
 * Vault - Represents a collection of workspaces
 *
 * A vault is a logical grouping of workspaces, which can be
 * used to organize projects by client, domain, or other criteria.
 */
class Vault {
    private {
        string _name;              // Vault name
        string _basePath;          // Base path for workspaces
        Workspace[] _workspaces;   // List of workspaces
        Workspace _currentWorkspace; // Currently selected workspace
    }
    
    /**
     * Constructor
     */
    this(string name, string basePath) {
        _name = name;
        _basePath = basePath;
        _workspaces = [];
        _currentWorkspace = null;
    }
    
    /**
     * Constructor from JSON
     */
    this(JSONValue json) {
        deserialize(json);
    }
    
    // Getters
    string name() const { return _name; }
    string basePath() const { return _basePath; }
    Workspace[] workspaces() { return _workspaces; }
    Workspace currentWorkspace() { return _currentWorkspace; }
    
    // Setters
    void name(string value) { _name = value; }
    void basePath(string value) { _basePath = value; }
    
    /**
     * Add a workspace to this vault
     */
    void addWorkspace(Workspace workspace) {
        // Check if workspace already exists
        auto existing = _workspaces.find!(w => w.name == workspace.name);
        if (!existing.empty) {
            Log.w("Vault: Workspace already exists: ", workspace.name);
            return;
        }
        
        _workspaces ~= workspace;
        Log.i("Vault: Added workspace: ", workspace.name);
    }
    
    /**
     * Remove a workspace by name
     */
    bool removeWorkspace(string name) {
        auto index = _workspaces.countUntil!(w => w.name == name);
        if (index >= 0) {
            // If removing current workspace, clear current selection
            if (_currentWorkspace && _currentWorkspace.name == name)
                _currentWorkspace = null;
                
            _workspaces = _workspaces.remove(index);
            Log.i("Vault: Removed workspace: ", name);
            return true;
        }
        
        Log.w("Vault: Workspace not found for removal: ", name);
        return false;
    }
    
    /**
     * Get workspace by name
     */
    Workspace getWorkspace(string name) {
        auto found = _workspaces.find!(w => w.name == name);
        if (!found.empty)
            return found.front;
            
        return null;
    }
    
    /**
     * Create a new workspace
     */
    Workspace createWorkspace(string name, string description = "") {
        // Check if workspace already exists
        if (getWorkspace(name)) {
            Log.w("Vault: Workspace already exists: ", name);
            return null;
        }
        
        // Create workspace path
        string workspacePath = buildPath(_basePath, name);
        
        // Create workspace
        Workspace workspace = new Workspace(name, workspacePath, description);
        
        // Create directory if it doesn't exist
        if (workspace.create()) {
            addWorkspace(workspace);
            return workspace;
        }
        
        return null;
    }
    
    /**
     * Set current workspace by name
     */
    bool setCurrentWorkspace(string name) {
        Workspace workspace = getWorkspace(name);
        if (!workspace) {
            Log.w("Vault: Workspace not found: ", name);
            return false;
        }
        
        _currentWorkspace = workspace;
        _currentWorkspace.updateLastAccessed();
        Log.i("Vault: Set current workspace: ", name);
        return true;
    }
    
    /**
     * Get current workspace
     */
    Workspace getCurrentWorkspace() {
        return _currentWorkspace;
    }
    
    /**
     * Serialize vault to JSON
     */
    JSONValue serialize() const {
        JSONValue json = parseJSON("{}");
        
        json["name"] = _name;
        json["basePath"] = _basePath;
        
        JSONValue[] workspacesJson;
        foreach (workspace; _workspaces) {
            workspacesJson ~= workspace.serialize();
        }
        
        json["workspaces"] = JSONValue(workspacesJson);
        
        if (_currentWorkspace)
            json["currentWorkspace"] = _currentWorkspace.name;
        
        return json;
    }
    
    /**
     * Deserialize vault from JSON
     */
    void deserialize(JSONValue json) {
        if ("name" in json)
            _name = json["name"].str;
            
        if ("basePath" in json)
            _basePath = json["basePath"].str;
        
        _workspaces = [];
        if ("workspaces" in json && json["workspaces"].type == JSONType.array) {
            foreach (workspaceJson; json["workspaces"].array) {
                Workspace workspace = new Workspace(workspaceJson);
                _workspaces ~= workspace;
            }
        }
        
        _currentWorkspace = null;
        if ("currentWorkspace" in json && json["currentWorkspace"].type == JSONType.string) {
            string currentWorkspaceName = json["currentWorkspace"].str;
            auto found = _workspaces.find!(w => w.name == currentWorkspaceName);
            if (!found.empty) {
                _currentWorkspace = found.front;
            }
        }
    }
}

/**
 * VaultManager - Manages all vaults
 */
class VaultManager {
    private {
        string _configPath;     // Path to vault configuration file
        Vault[] _vaults;        // List of vaults
        Vault _currentVault;    // Currently selected vault
        string _defaultVaultPath; // Default vault path
        Workspace _defaultWorkspace; // Default workspace
    }
    
    /**
     * Constructor
     */
    this(string configPath) {
        _configPath = configPath;
        _vaults = [];
        _currentVault = null;
        
        // Set default vault path
        string homeDir = environment["HOME"];
        _defaultVaultPath = buildPath(homeDir, ".compyutinatorcode", "workspaces");
        
        Log.i("VaultManager: Initialized with config path: ", _configPath);
    }
    
    /**
     * Initialize the vault manager
     */
    bool initialize() {
        // Load vaults from configuration
        if (!loadVaults()) {
            Log.e("VaultManager: Failed to load vaults");
            return false;
        }
        
        return true;
    }
    
    /**
     * Load vaults from configuration file
     */
    private bool loadVaults() {
        if (!exists(_configPath)) {
            Log.i("VaultManager: Configuration file doesn't exist, creating default");
            return true; // No vaults to load
        }
        
        try {
            string content = readText(_configPath);
            JSONValue config = parseJSON(content);
            
            _vaults = [];
            
            if ("vaults" in config && config["vaults"].type == JSONType.array) {
                foreach (vaultJson; config["vaults"].array) {
                    Vault vault = new Vault(vaultJson);
                    _vaults ~= vault;
                }
            }
            
            _currentVault = null;
            if ("currentVault" in config && config["currentVault"].type == JSONType.string) {
                string currentVaultName = config["currentVault"].str;
                auto found = _vaults.find!(v => v.name == currentVaultName);
                if (!found.empty) {
                    _currentVault = found.front;
                }
            }
            
            Log.i("VaultManager: Loaded ", _vaults.length, " vaults");
            return true;
        }
        catch (Exception e) {
            Log.e("VaultManager: Error loading vaults: ", e.msg);
            return false;
        }
    }
    
    /**
     * Save vaults to configuration file
     */
    bool saveVaults() {
        try {
            JSONValue config = parseJSON("{}");
            
            JSONValue[] vaultsJson;
            foreach (vault; _vaults) {
                vaultsJson ~= vault.serialize();
            }
            
            config["vaults"] = JSONValue(vaultsJson);
            
            if (_currentVault)
                config["currentVault"] = _currentVault.name;
            
            // Create directory if it doesn't exist
            string dir = dirName(_configPath);
            if (!exists(dir))
                mkdirRecurse(dir);
                
            std.file.write(_configPath, config.toPrettyString());
            
            Log.i("VaultManager: Saved vaults configuration");
            return true;
        }
        catch (Exception e) {
            Log.e("VaultManager: Error saving vaults: ", e.msg);
            return false;
        }
    }
    
    /**
     * Add a vault
     */
    void addVault(Vault vault) {
        // Check if vault already exists
        auto existing = _vaults.find!(v => v.name == vault.name);
        if (!existing.empty) {
            Log.w("VaultManager: Vault already exists: ", vault.name);
            return;
        }
        
        _vaults ~= vault;
        Log.i("VaultManager: Added vault: ", vault.name);
        
        // Save configuration
        saveVaults();
    }
    
    /**
     * Remove a vault by name
     */
    bool removeVault(string name) {
        auto index = _vaults.countUntil!(v => v.name == name);
        if (index >= 0) {
            // If removing current vault, clear current selection
            if (_currentVault && _currentVault.name == name)
                _currentVault = null;
                
            _vaults = _vaults.remove(index);
            Log.i("VaultManager: Removed vault: ", name);
            
            // Save configuration
            saveVaults();
            return true;
        }
        
        Log.w("VaultManager: Vault not found for removal: ", name);
        return false;
    }
    
    /**
     * Get vault by name
     */
    Vault getVault(string name) {
        auto found = _vaults.find!(v => v.name == name);
        if (!found.empty)
            return found.front;
            
        return null;
    }
    
    /**
     * Create a new vault
     */
    Vault createVault(string name, string basePath) {
        // Check if vault already exists
        if (getVault(name)) {
            Log.w("VaultManager: Vault already exists: ", name);
            return null;
        }
        
        // Create vault
        Vault vault = new Vault(name, basePath);
        
        // Create directory if it doesn't exist
        if (!exists(basePath)) {
            try {
                mkdirRecurse(basePath);
            }
            catch (Exception e) {
                Log.e("VaultManager: Error creating vault directory: ", e.msg);
                return null;
            }
        }
        
        addVault(vault);
        return vault;
    }
    
    /**
     * Set current vault by name
     */
    bool setCurrentVault(string name) {
        Vault vault = getVault(name);
        if (!vault) {
            Log.w("VaultManager: Vault not found: ", name);
            return false;
        }
        
        _currentVault = vault;
        Log.i("VaultManager: Set current vault: ", name);
        
        // Save configuration
        saveVaults();
        return true;
    }
    
    /**
     * Get current vault
     */
    Vault currentVault() {
        return _currentVault;
    }
    
    /**
     * Ensure default vault exists
     */
    Vault ensureDefaultVault() {
        // Check if default vault exists
        Vault defaultVault = getVault("Default");
        if (defaultVault)
            return defaultVault;
            
        // Create default vault
        defaultVault = createVault("Default", _defaultVaultPath);
        if (!defaultVault) {
            Log.e("VaultManager: Failed to create default vault");
            return null;
        }
        
        // Create default workspace
        Workspace defaultWorkspace = defaultVault.createWorkspace("Default", "Default workspace");
        if (!defaultWorkspace) {
            Log.e("VaultManager: Failed to create default workspace");
            return defaultVault;
        }
        
        // Set current vault and workspace
        setCurrentVault("Default");
        defaultVault.setCurrentWorkspace("Default");
        
        return defaultVault;
    }
    
    /**
     * Get vault containing a workspace
     */
    Vault getVaultByWorkspace(string workspaceName) {
        foreach (vault; _vaults) {
            if (vault.getWorkspace(workspaceName))
                return vault;
        }
        
        return null;
    }
    
    /**
     * Cleanup resources
     */
    void cleanup() {
        // Save vaults configuration
        saveVaults();
    }
}

/**
 * Import environment variables
 */
private string[string] environment() {
    string[string] env;
    
    version(Windows) {
        import core.sys.windows.winbase;
        import core.sys.windows.windef;
        import core.sys.windows.winnt;
        
        LPWSTR envStrings = GetEnvironmentStringsW();
        if (envStrings == null)
            return env;
            
        size_t i = 0;
        while (true) {
            if (envStrings[i] == 0) {
                if (envStrings[i + 1] == 0)
                    break;
            }
            
            auto envString = envStrings[i .. i + wcslen(&envStrings[i])];
            i += envString.length + 1;
            
            import std.utf;
            string envStr = toUTF8(envString);
            
            auto eqIndex = indexOf(envStr, '=');
            if (eqIndex > 0) {
                string name = envStr[0 .. eqIndex];
                string value = envStr[eqIndex + 1 .. $];
                env[name] = value;
            }
        }
        
        FreeEnvironmentStringsW(envStrings);
    } else {
        import std.process : environment;
        
        foreach (string name, string value; environment.toAA()) {
            env[name] = value;
        }
    }
    
    return env;
}