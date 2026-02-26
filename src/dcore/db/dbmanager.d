module dcore.db.dbmanager;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.json;
import std.exception;
import std.conv : to;
import std.datetime;

import d2sqlite3;
import dlangui.core.logger;

import dcore.core;

/**
 * DBManager - Manages SQLite database connections and operations
 *
 * This class provides:
 * - Database connection management
 * - Query execution and result handling
 * - Transaction support
 * - Error handling for database operations
 * - Schema migration support
 */
class DBManager {
    private {
        Database _db;
        string _dbPath;
        bool _initialized = false;
        DCore _core;
    }
    
    /// Constructor
    this(DCore core, string dbPath) {
        _core = core;
        _dbPath = dbPath;
        Log.i("DBManager: Created with database path: ", _dbPath);
    }
    
    /// Initialize the database connection
    bool initialize() {
        if (_initialized) {
            Log.w("DBManager: Already initialized");
            return true;
        }
        
        try {
            // Create directory if it doesn't exist
            string dir = dirName(_dbPath);
            if (!exists(dir))
                mkdirRecurse(dir);
                
            // Open database connection
            _db = Database(_dbPath);
            Log.i("DBManager: Database connection established");
            
            // Enable foreign keys
            _db.execute("PRAGMA foreign_keys = ON");
            
            // Apply migrations if needed
            applyMigrations();
            
            _initialized = true;
            return true;
        }
        catch (Exception e) {
            Log.e("DBManager: Initialization error: ", e.msg);
            return false;
        }
    }
    
    /// Close the database connection
    void close() {
        if (_initialized) {
            _db.close();
            Log.i("DBManager: Database connection closed");
        }
        _initialized = false;
    }
    
    /// Execute a query without results
    void execute(string sql, BindParameter[] params = null) {
        checkConnection();
        
        try {
            Statement stmt = _db.prepare(sql);
            
            // Bind parameters if provided
            if (params !is null && params.length > 0) {
                foreach (i, param; params) {
                    bindParameter(stmt, cast(int)(i + 1), param);
                }
            }
            
            stmt.execute();
            stmt.reset();
        }
        catch (Exception e) {
            Log.e("DBManager: Query execution error: ", e.msg);
            Log.e("DBManager: Query was: ", sql);
            throw e;
        }
    }
    
    /// Execute a query and return the results as Row[]
    Row[] query(string sql, BindParameter[] params = null) {
        checkConnection();
        
        try {
            Statement stmt = _db.prepare(sql);
            
            // Bind parameters if provided
            if (params !is null && params.length > 0) {
                foreach (i, param; params) {
                    bindParameter(stmt, cast(int)(i + 1), param);
                }
            }
            
            ResultRange results = stmt.execute();
            Row[] rows;
            
            foreach (row; results) {
                rows ~= row;
            }
            
            return rows;
        }
        catch (Exception e) {
            Log.e("DBManager: Query error: ", e.msg);
            Log.e("DBManager: Query was: ", sql);
            throw e;
        }
    }
    
    /// Execute a query and return the first row
    Row queryOne(string sql, BindParameter[] params = null) {
        Row[] rows = query(sql, params);
        
        if (rows.length > 0) {
            return rows[0];
        }
        
        return Row.init; // Return empty row
    }
    
    /// Begin a transaction
    void beginTransaction() {
        execute("BEGIN TRANSACTION");
    }
    
    /// Commit a transaction
    void commit() {
        execute("COMMIT");
    }
    
    /// Rollback a transaction
    void rollback() {
        execute("ROLLBACK");
    }
    
    /// Get the last inserted row ID
    long lastInsertRowID() {
        checkConnection();
        return _db.lastInsertRowid();
    }
    
    /// Get the number of rows changed by the last statement
    int changes() {
        checkConnection();
        return _db.changes();
    }
    
    /// Execute statements in a transaction and handle errors
    void transaction(void delegate() operations) {
        checkConnection();
        
        beginTransaction();
        
        try {
            operations();
            commit();
        }
        catch (Exception e) {
            rollback();
            throw e;
        }
    }
    
    /// Check if a table exists
    bool tableExists(string tableName) {
        string sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?";
        BindParameter[] params = [BindParameter(tableName)];
        Row[] rows = query(sql, params);
        return rows.length > 0;
    }
    
    /// Create table if it doesn't exist
    void createTableIfNotExists(string tableName, string schema) {
        string sql = format("CREATE TABLE IF NOT EXISTS %s (%s)", tableName, schema);
        execute(sql);
    }
    
    /// Apply migrations to bring the database schema up to date
    private void applyMigrations() {
        // Create migrations table if it doesn't exist
        createTableIfNotExists("migrations", 
            "version INTEGER PRIMARY KEY, name TEXT, applied_at TIMESTAMP");
        
        // Get current migration version
        int currentVersion = 0;
        Row row = queryOne("SELECT MAX(version) as version FROM migrations");
        if (row != Row.init && row["version"].type != SqliteType.NULL) {
            currentVersion = row["version"].as!int;
        }
        
        Log.i("DBManager: Current migration version: ", currentVersion);
        
        // Apply migrations
        applyMigrationIfNeeded(currentVersion, 1, "Create initial schema", () {
            // Create workspaces table
            createTableIfNotExists("workspaces", 
                "id INTEGER PRIMARY KEY, name TEXT UNIQUE, path TEXT, " ~
                "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, " ~
                "last_accessed TIMESTAMP");
                    
            // Create files table
            createTableIfNotExists("files", 
                "id INTEGER PRIMARY KEY, workspace_id INTEGER, " ~
                "path TEXT, name TEXT, size INTEGER, " ~
                "last_modified TIMESTAMP, favorite INTEGER DEFAULT 0, " ~
                "FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE");
                    
            // Create tags table
            createTableIfNotExists("tags", 
                "id INTEGER PRIMARY KEY, name TEXT UNIQUE, color TEXT");
                    
            // Create file_tags table for many-to-many relationship
            createTableIfNotExists("file_tags", 
                "file_id INTEGER, tag_id INTEGER, " ~
                "PRIMARY KEY (file_id, tag_id), " ~
                "FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE, " ~
                "FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE");
        });
        
        // More migrations can be added here as the schema evolves
    }
    
    /// Apply a specific migration if needed
    private void applyMigrationIfNeeded(int currentVersion, int migrationVersion, 
                                         string name, void delegate() migrationFunc) {
        if (currentVersion < migrationVersion) {
            Log.i("DBManager: Applying migration ", migrationVersion, ": ", name);
            
            transaction(() {
                // Apply the migration
                migrationFunc();
                
                // Record the migration
                string sql = "INSERT INTO migrations (version, name, applied_at) VALUES (?, ?, CURRENT_TIMESTAMP)";
                BindParameter[] params = [BindParameter(migrationVersion), BindParameter(name)];
                execute(sql, params);
            });
            
            Log.i("DBManager: Migration applied successfully");
        }
    }
    
    /// Helper to check if database is connected
    private void checkConnection() {
        if (!_initialized) {
            Log.e("DBManager: Database not initialized");
            throw new Exception("Database not initialized");
        }
    }
    
    /// Helper to bind different parameter types
    private void bindParameter(Statement stmt, int index, BindParameter param) {
        if (param.isNull) {
            stmt.bind(index, null);
        } else if (param.type == typeid(int)) {
            stmt.bind(index, param.get!int);
        } else if (param.type == typeid(long)) {
            stmt.bind(index, param.get!long);
        } else if (param.type == typeid(double)) {
            stmt.bind(index, param.get!double);
        } else if (param.type == typeid(string)) {
            stmt.bind(index, param.get!string);
        } else if (param.type == typeid(bool)) {
            stmt.bind(index, param.get!bool ? 1 : 0);
        } else if (param.type == typeid(SysTime)) {
            // Store as ISO-8601 string
            stmt.bind(index, param.get!SysTime.toISOExtString());
        } else {
            // Convert to string for anything else
            stmt.bind(index, param.toString());
        }
    }
}

/**
 * BindParameter - Helper struct for binding parameters to queries
 * 
 * Allows for type-safe binding of parameters in database queries
 */
struct BindParameter {
    private {
        TypeInfo _type;
        union {
            int _intValue;
            long _longValue;
            double _doubleValue;
            bool _boolValue;
        }
        string _stringValue;
        SysTime _timeValue;
        bool _isNull = false;
    }
    
    /// Null parameter
    this(typeof(null)) {
        _isNull = true;
    }
    
    /// Integer parameter
    this(int value) {
        _type = typeid(int);
        _intValue = value;
    }
    
    /// Long parameter
    this(long value) {
        _type = typeid(long);
        _longValue = value;
    }
    
    /// Double parameter
    this(double value) {
        _type = typeid(double);
        _doubleValue = value;
    }
    
    /// String parameter
    this(string value) {
        _type = typeid(string);
        _stringValue = value;
    }
    
    /// Boolean parameter
    this(bool value) {
        _type = typeid(bool);
        _boolValue = value;
    }
    
    /// DateTime parameter
    this(SysTime value) {
        _type = typeid(SysTime);
        _timeValue = value;
    }
    
    /// Check if parameter is null
    bool isNull() const {
        return _isNull;
    }
    
    /// Get parameter type
    TypeInfo type() const {
        return cast(TypeInfo)_type;
    }
    
    /// Get parameter value as T
    T get(T)() const {
        static if (is(T == int)) {
            return _intValue;
        } else static if (is(T == long)) {
            return _longValue;
        } else static if (is(T == double)) {
            return _doubleValue;
        } else static if (is(T == string)) {
            return _stringValue;
        } else static if (is(T == bool)) {
            return _boolValue;
        } else static if (is(T == SysTime)) {
            return _timeValue;
        } else {
            throw new Exception("Unsupported parameter type: " ~ T.stringof);
        }
    }
    
    /// Convert to string
    string toString() const {
        if (_isNull) {
            return "NULL";
        } else if (_type == typeid(int)) {
            return to!string(_intValue);
        } else if (_type == typeid(long)) {
            return to!string(_longValue);
        } else if (_type == typeid(double)) {
            return to!string(_doubleValue);
        } else if (_type == typeid(string)) {
            return _stringValue;
        } else if (_type == typeid(bool)) {
            return _boolValue ? "true" : "false";
        } else if (_type == typeid(SysTime)) {
            return _timeValue.toISOExtString();
        } else {
            return "Unknown type";
        }
    }
}