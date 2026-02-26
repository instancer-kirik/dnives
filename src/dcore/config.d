module dcore.config;

import std.stdio;
import std.string;
import std.file;
import std.path;
import std.json;
import std.variant;
import std.conv;
import std.exception;
import dlangui.core.logger;

/**
 * ConfigManager - Handles application configuration
 *
 * Responsible for:
 * - Loading/saving configuration from/to JSON files
 * - Providing access to configuration values
 * - Managing default values
 */
class ConfigManager {
    private JSONValue config;
    private string configPath;
    private bool modified = false;
    
    /// Constructor
    this(string configFilePath) {
        configPath = configFilePath;
        config = parseJSON("{}");
        
        // Try to load config if file exists
        if (exists(configPath)) {
            try {
                load();
            } catch (Exception e) {
                Log.e("Failed to load config from ", configPath, ": ", e.msg);
                // Use empty config
            }
        } else {
            Log.i("Config file does not exist, using default configuration");
            // Save default configuration
            save();
        }
    }
    
    /// Load configuration from file
    public void load() {
        if (!exists(configPath)) {
            Log.w("Cannot load config, file does not exist: ", configPath);
            return;
        }
        
        try {
            string content = readText(configPath);
            config = parseJSON(content);
            Log.i("Configuration loaded from ", configPath);
        } catch (Exception e) {
            Log.e("Error loading configuration: ", e.msg);
            throw e;
        }
    }
    
    /// Save configuration to file
    public void save() {
        try {
            // Ensure directory exists
            string dir = dirName(configPath);
            if (!exists(dir))
                mkdirRecurse(dir);
                
            // Pretty-print JSON with indentation
            auto prettyConfig = config.toPrettyString();
            std.file.write(configPath, prettyConfig);
            
            modified = false;
            Log.i("Configuration saved to ", configPath);
        } catch (Exception e) {
            Log.e("Error saving configuration: ", e.msg);
            throw e;
        }
    }
    
    /// Get configuration value as a specific type with optional default
    public T getValue(T)(string key, T defaultValue = T.init) {
        try {
            // Check if key exists in config
            if (hasValue(key)) {
                auto value = config[key];
                
                // Handle JSON conversion to requested type
                static if (is(T == string)) {
                    return value.str;
                } else static if (is(T == bool)) {
                    return value.type == JSON_TYPE.TRUE;
                } else static if (is(T == int)) {
                    return cast(int)value.integer;
                } else static if (is(T == long)) {
                    return value.integer;
                } else static if (is(T == double)) {
                    return value.floating;
                } else static if (is(T == string[])) {
                    string[] result;
                    foreach (item; value.array)
                        result ~= item.str;
                    return result;
                } else {
                    // For other types, use std.conv
                    return to!T(value.toString());
                }
            }
        } catch (Exception e) {
            Log.w("Error getting configuration value for key '", key, "': ", e.msg);
        }
        
        return defaultValue;
    }
    
    /// Set configuration value
    public void setValue(T)(string key, T value) {
        try {
            // Convert value to JSONValue based on type
            static if (is(T == string)) {
                config[key] = JSONValue(value);
            } else static if (is(T == bool)) {
                config[key] = JSONValue(value);
            } else static if (is(T == int) || is(T == long)) {
                config[key] = JSONValue(cast(long)value);
            } else static if (is(T == float) || is(T == double)) {
                config[key] = JSONValue(cast(double)value);
            } else static if (is(T == string[])) {
                JSONValue[] array;
                foreach (item; value)
                    array ~= JSONValue(item);
                config[key] = JSONValue(array);
            } else {
                // For other types, convert to string
                config[key] = JSONValue(to!string(value));
            }
            
            modified = true;
        } catch (Exception e) {
            Log.e("Error setting configuration value for key '", key, "': ", e.msg);
            throw e;
        }
    }
    
    /// Check if a key exists in the configuration
    public bool hasValue(string key) {
        if (key in config)
            return true;
            
        return false;
    }
    
    /// Remove a key from the configuration
    public void removeValue(string key) {
        if (hasValue(key)) {
            config.object.remove(key);
            modified = true;
        }
    }
    
    /// Get the configuration directory
    public string getConfigDir() {
        return dirName(configPath);
    }
    
    /// Get all configuration keys
    public string[] getKeys() {
        string[] keys;
        foreach (key, value; config.object)
            keys ~= key;
        return keys;
    }
    
    /// Load configuration from JSON string
    public void loadFromJSON(string jsonString) {
        try {
            config = parseJSON(jsonString);
            modified = true;
        } catch (Exception e) {
            Log.e("Error loading configuration from JSON string: ", e.msg);
            throw e;
        }
    }
    
    /// Export configuration as JSON string
    public string exportToJSON(bool pretty = false) {
        if (pretty)
            return config.toPrettyString();
        else
            return config.toString();
    }
    
    /// Get if configuration has been modified since last save
    public bool isModified() {
        return modified;
    }
    
    /// Reset configuration to empty state
    public void reset() {
        config = parseJSON("{}");
        modified = true;
    }
}