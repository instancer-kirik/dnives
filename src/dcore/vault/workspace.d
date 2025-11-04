module dcore.vault.workspace;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.datetime;
import std.json;
import std.exception;
import std.conv;

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
        
        // Filesets - Collections of files for different contexts
        string[][string] _filesets;     // Map of fileset name to array of file paths
        string _activeFileset;          // Currently active fileset
        
        // Layout information
        JSONValue _layout;              // Layout configuration
        string[] _visibleDocks;         // List of visible dock panels
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
        
        // Initialize empty filesets
        _filesets = null;
        _activeFileset = null;
        
        // Initialize empty layout
        _layout = parseJSON("{}");
        _visibleDocks = [];
        
        // Load configuration if exists
        loadConfig();
    }
    
    // Getters
    string name() const { return _name; }
    string path() const { return _path; }
    string description() const { return _description; }
    SysTime created() const { return _created; }
    SysTime lastAccessed() const { return _lastAccessed; }
    string activeFileset() const { return _activeFileset; }
    
    // Setters
    void name(string value) { _name = value; }
    void path(string value) { _path = value; }
    void description(string value) { _description = value; }
    
    /**
     * Load workspace configuration
     */
    void loadConfig() {
        string configFile = buildPath(_path, ".workspace_" ~ _name ~ ".json");
        
        if (!exists(configFile)) {
            Log.i("Workspace config does not exist, creating:", configFile);
            saveConfig();
            return;
        }
        
        try {
            // Load configuration
            string content = readText(configFile);
            JSONValue config = parseJSON(content);
            
            // Load filesets
            if ("filesets" in config && config["filesets"].type == JSONType.object) {
                foreach (string name, filesetJson; config["filesets"].object) {
                    string[] files;
                    if (filesetJson.type == JSONType.array) {
                        foreach (fileJson; filesetJson.array) {
                            files ~= fileJson.str;
                        }
                    }
                    _filesets[name] = files;
                }
            }
            
            // Load active fileset
            if ("active_fileset" in config && config["active_fileset"].type == JSONType.string) {
                _activeFileset = config["active_fileset"].str;
            }
            
            // Load layout
            if ("layout" in config && config["layout"].type == JSONType.object) {
                _layout = config["layout"];
            }
            
            // Load visible docks
            if ("visible_docks" in config && config["visible_docks"].type == JSONType.array) {
                _visibleDocks = [];
                foreach (dockJson; config["visible_docks"].array) {
                    _visibleDocks ~= dockJson.str;
                }
            }
            
            // Load settings
            if ("settings" in config && config["settings"].type == JSONType.object) {
                _settings = config["settings"];
            }
            
            Log.i("Workspace configuration loaded: ", _name);
        } catch (Exception e) {
            Log.e("Error loading workspace configuration: ", e.msg);
        }
    }
    
    /**
     * Save workspace configuration
     */
    void saveConfig() {
        string configFile = buildPath(_path, ".workspace_" ~ _name ~ ".json");
        
        try {
            // Create directory if it doesn't exist
            string dir = dirName(configFile);
            if (!exists(dir))
                mkdirRecurse(dir);
                
            // Prepare configuration
            JSONValue config = parseJSON("{}");
            
            // Add basic info
            config["name"] = _name;
            config["description"] = _description;
            config["created"] = _created.toISOExtString();
            config["last_accessed"] = _lastAccessed.toISOExtString();
            
            // Add filesets
            JSONValue filesets = parseJSON("{}");
            foreach (string name, files; _filesets) {
                JSONValue filesJson = parseJSON("[]");
                foreach (file; files) {
                    filesJson.array ~= JSONValue(file);
                }
                filesets[name] = filesJson;
            }
            config["filesets"] = filesets;
            
            // Add active fileset
            if (_activeFileset && _activeFileset.length > 0)
                config["active_fileset"] = _activeFileset;
                
            // Add layout
            config["layout"] = _layout;
            
            // Add visible docks
            JSONValue docksJson = parseJSON("[]");
            foreach (dock; _visibleDocks) {
                docksJson.array ~= JSONValue(dock);
            }
            config["visible_docks"] = docksJson;
            
            // Add settings
            config["settings"] = _settings;
            
            // Save to file
            std.file.write(configFile, config.toPrettyString());
            
            Log.i("Workspace configuration saved: ", _name);
        } catch (Exception e) {
            Log.e("Error saving workspace configuration: ", e.msg);
        }
    }
    
    /**
     * Update last accessed time
     */
    void updateLastAccessed() {
        _lastAccessed = Clock.currTime();
        saveConfig();
    }
    
    /**
     * Add a fileset
     */
    void addFileset(string name, string[] files = []) {
        _filesets[name] = files;
        
        // Set as active if no active fileset
        if (_activeFileset is null || _activeFileset.length == 0)
            _activeFileset = name;
            
        saveConfig();
        Log.i("Added fileset: ", name, " with ", files.length, " files");
    }
    
    /**
     * Remove a fileset
     */
    bool removeFileset(string name) {
        if (name !in _filesets) {
            Log.w("Fileset not found: ", name);
            return false;
        }
        
        _filesets.remove(name);
        
        // Clear active fileset if it was the removed one
        if (_activeFileset == name)
            _activeFileset = null;
            
        saveConfig();
        Log.i("Removed fileset: ", name);
        return true;
    }
    
    /**
     * Set active fileset
     */
    bool setActiveFileset(string name) {
        if (name !in _filesets) {
            Log.w("Fileset not found: ", name);
            return false;
        }
        
        _activeFileset = name;
        saveConfig();
        Log.i("Set active fileset: ", name);
        return true;
    }
    
    /**
     * Get active files
     */
    string[] getActiveFiles() {
        if (_activeFileset is null || _activeFileset !in _filesets)
            return [];
            
        return _filesets[_activeFileset];
    }
    
    /**
     * Add file to active fileset
     */
    bool addFileToActiveFileset(string filePath) {
        if (_activeFileset is null || _activeFileset !in _filesets) {
            Log.w("No active fileset");
            return false;
        }
        
        // Check if file is already in the fileset
        if (_filesets[_activeFileset].canFind(filePath))
            return true;
            
        // Add file to fileset
        _filesets[_activeFileset] ~= filePath;
        saveConfig();
        
        Log.i("Added file to fileset: ", filePath);
        return true;
    }
    
    /**
     * Remove file from active fileset
     */
    bool removeFileFromActiveFileset(string filePath) {
        if (_activeFileset is null || _activeFileset !in _filesets) {
            Log.w("No active fileset");
            return false;
        }
        
        // Check if file is in the fileset
        auto index = _filesets[_activeFileset].countUntil(filePath);
        if (index < 0)
            return false;
            
        // Remove file from fileset
        _filesets[_activeFileset] = _filesets[_activeFileset].remove(index);
        saveConfig();
        
        Log.i("Removed file from fileset: ", filePath);
        return true;
    }
    
    /**
     * Set layout
     */
    void setLayout(JSONValue layout, string[] visibleDocks) {
        _layout = layout;
        _visibleDocks = visibleDocks;
        saveConfig();
        Log.i("Set workspace layout");
    }
    
    /**
     * Get layout
     */
    JSONValue getLayout() {
        return _layout;
    }
    
    /**
     * Get visible docks
     */
    string[] getVisibleDocks() {
        return _visibleDocks;
    }
    
    /**
     * Get a setting value
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
     * Set a setting value
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
                
            saveConfig();
        }
        catch (Exception e) {
            Log.e("Workspace: Error setting setting: ", e.msg);
        }
    }
}