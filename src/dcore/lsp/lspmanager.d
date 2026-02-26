module dcore.lsp.lspmanager;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.json;
import std.process;
import std.datetime;
import std.exception;
import std.conv;
import std.typecons;

import dlangui.core.logger;

import dcore.core;
import dcore.session;

/**
 * LSPManager - Manages Language Server Protocol (LSP) connections
 *
 * This class provides:
 * - LSP server management (start, stop, communication)
 * - Language detection
 * - Document synchronization
 * - Code intelligence features (completion, navigation, etc.)
 */
class LSPManager {
    private DCore _core;
    private string _configDir;
    private JSONValue _config;
    
    // Server connections by language
    private LSPConnection[string] _connections;
    
    // File mappings
    private string[string] _fileMappings;       // file path -> LSP URI
    private string[string] _languageForFile;    // file path -> language
    
    /**
     * Constructor
     */
    this(DCore core) {
        _core = core;
        _configDir = buildPath(_core.getConfigDir(), "lsp");
        
        // Ensure config directory exists
        if (!exists(_configDir))
            mkdirRecurse(_configDir);
            
        // Initialize empty mappings
        _fileMappings = null;
        _languageForFile = null;
        
        // Load configuration
        loadConfigurations();
        
        Log.i("LSPManager: Initialized");
    }
    
    /**
     * Initialize LSP manager
     */
    void initialize() {
        // Auto-detect available language servers
        detectLanguageServers();
        
        // Initialize servers for common languages
        initializeServer("d");
        initializeServer("javascript");
        initializeServer("typescript");
        initializeServer("python");
        initializeServer("rust");
        initializeServer("c");
        initializeServer("cpp");
        
        Log.i("LSPManager: Initialized servers");
    }
    
    /**
     * Load LSP configurations
     */
    private void loadConfigurations() {
        string configPath = buildPath(_configDir, "config.json");
        
        if (!exists(configPath)) {
            Log.i("LSPManager: Configuration file doesn't exist, creating default");
            _config = parseJSON("{}");
            _config["servers"] = parseJSON("{}");
            saveConfigurations();
            return;
        }
        
        try {
            string content = readText(configPath);
            _config = parseJSON(content);
            
            if ("servers" !in _config)
                _config["servers"] = parseJSON("{}");
                
            Log.i("LSPManager: Configuration loaded");
        }
        catch (Exception e) {
            Log.e("LSPManager: Error loading configuration: ", e.msg);
            _config = parseJSON("{}");
            _config["servers"] = parseJSON("{}");
        }
    }
    
    /**
     * Save LSP configurations
     */
    private void saveConfigurations() {
        string configPath = buildPath(_configDir, "config.json");
        
        try {
            std.file.write(configPath, _config.toPrettyString());
            Log.i("LSPManager: Configuration saved");
        }
        catch (Exception e) {
            Log.e("LSPManager: Error saving configuration: ", e.msg);
        }
    }
    
    /**
     * Auto-detect available language servers
     */
    private void detectLanguageServers() {
        // Check for common language servers in PATH
        
        // D language server
        if (findExecutable("dls")) {
            registerLanguageServer("d", "dls", null);
        }
        
        // JavaScript/TypeScript language server
        if (findExecutable("typescript-language-server")) {
            registerLanguageServer("javascript", "typescript-language-server", ["--stdio"]);
            registerLanguageServer("typescript", "typescript-language-server", ["--stdio"]);
        }
        
        // Python language server
        if (findExecutable("pyls")) {
            registerLanguageServer("python", "pyls", null);
        } else if (findExecutable("python-language-server")) {
            registerLanguageServer("python", "python-language-server", null);
        }
        
        // Rust language server
        if (findExecutable("rust-analyzer")) {
            registerLanguageServer("rust", "rust-analyzer", null);
        } else if (findExecutable("rls")) {
            registerLanguageServer("rust", "rls", null);
        }
        
        // C/C++ language server
        if (findExecutable("clangd")) {
            registerLanguageServer("c", "clangd", null);
            registerLanguageServer("cpp", "clangd", null);
        }
        
        Log.i("LSPManager: Auto-detected language servers");
    }
    
    /**
     * Find executable in PATH
     */
    private bool findExecutable(string executable) {
        version(Windows) {
            executable ~= ".exe";
        }
        
        string[] paths = environment.get("PATH").split(pathSeparator);
        
        foreach (path; paths) {
            string fullPath = buildPath(path, executable);
            if (exists(fullPath) && isFile(fullPath)) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Register a language server
     */
    void registerLanguageServer(string language, string command, string[] args) {
        if ("servers" !in _config)
            _config["servers"] = parseJSON("{}");
            
        JSONValue serverConfig = parseJSON("{}");
        serverConfig["command"] = command;
        
        if (args !is null && args.length > 0) {
            JSONValue[] argsJson;
            foreach (arg; args)
                argsJson ~= JSONValue(arg);
                
            serverConfig["args"] = JSONValue(argsJson);
        } else {
            serverConfig["args"] = parseJSON("[]");
        }
        
        _config["servers"][language] = serverConfig;
        
        Log.i("LSPManager: Registered server for language: ", language);
        saveConfigurations();
    }
    
    /**
     * Initialize server for a language
     */
    void initializeServer(string language) {
        if (language in _connections) {
            Log.i("LSPManager: Server already initialized for language: ", language);
            return;
        }
        
        if ("servers" !in _config || language !in _config["servers"]) {
            Log.w("LSPManager: No server configuration found for language: ", language);
            return;
        }
        
        JSONValue serverConfig = _config["servers"][language];
        
        if ("command" !in serverConfig) {
            Log.e("LSPManager: Invalid server configuration for language: ", language);
            return;
        }
        
        string command = serverConfig["command"].str;
        string[] args;
        
        if ("args" in serverConfig && serverConfig["args"].type == JSONType.array) {
            foreach (arg; serverConfig["args"].array)
                args ~= arg.str;
        }
        
        // Create connection
        LSPConnection connection = new LSPConnection(language, command, args);
        
        // Initialize connection
        if (connection.initialize()) {
            _connections[language] = connection;
            Log.i("LSPManager: Initialized server for language: ", language);
        } else {
            Log.e("LSPManager: Failed to initialize server for language: ", language);
        }
    }
    
    /**
     * Get language for file
     */
    string getLanguageForFile(string filePath) {
        if (filePath in _languageForFile)
            return _languageForFile[filePath];
            
        // Determine language by extension
        string ext = extension(filePath);
        if (ext.length > 0 && ext[0] == '.')
            ext = ext[1..$];
            
        string language;
        
        // Map extension to language
        switch (ext) {
            case "d":
                language = "d";
                break;
            case "js":
                language = "javascript";
                break;
            case "ts":
                language = "typescript";
                break;
            case "py":
                language = "python";
                break;
            case "rs":
                language = "rust";
                break;
            case "c":
            case "h":
                language = "c";
                break;
            case "cpp":
            case "cc":
            case "cxx":
            case "hpp":
            case "hxx":
                language = "cpp";
                break;
            default:
                language = "";
                break;
        }
        
        // Cache the mapping
        if (language.length > 0)
            _languageForFile[filePath] = language;
            
        return language;
    }
    
    /**
     * Get URI for file
     */
    string getURIForFile(string filePath) {
        if (filePath in _fileMappings)
            return _fileMappings[filePath];
            
        // Convert file path to URI
        string uri = "file://" ~ absolutePath(filePath);
        
        // Cache the mapping
        _fileMappings[filePath] = uri;
        
        return uri;
    }
    
    /**
     * Get server connection for language
     */
    LSPConnection getConnectionForLanguage(string language) {
        if (language !in _connections) {
            // Try to initialize server if not already done
            initializeServer(language);
            
            if (language !in _connections)
                return null;
        }
        
        return _connections[language];
    }
    
    /**
     * Get server connection for file
     */
    LSPConnection getConnectionForFile(string filePath) {
        string language = getLanguageForFile(filePath);
        
        if (language.length == 0)
            return null;
            
        return getConnectionForLanguage(language);
    }
    
    /**
     * Notify server about file open
     */
    void notifyFileOpen(string filePath, string text) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return;
            
        string uri = getURIForFile(filePath);
        connection.notifyDocumentOpen(uri, text);
        
        Log.i("LSPManager: Notified server about file open: ", filePath);
    }
    
    /**
     * Notify server about file change
     */
    void notifyFileChange(string filePath, string text) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return;
            
        string uri = getURIForFile(filePath);
        connection.notifyDocumentChange(uri, text);
        
        Log.i("LSPManager: Notified server about file change: ", filePath);
    }
    
    /**
     * Notify server about file close
     */
    void notifyFileClose(string filePath) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return;
            
        string uri = getURIForFile(filePath);
        connection.notifyDocumentClose(uri);
        
        Log.i("LSPManager: Notified server about file close: ", filePath);
    }
    
    /**
     * Get completion items
     */
    JSONValue getCompletions(string filePath, int line, int character) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestCompletion(uri, line, character);
    }
    
    /**
     * Get hover information
     */
    JSONValue getHoverInfo(string filePath, int line, int character) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestHover(uri, line, character);
    }
    
    /**
     * Get definition location
     */
    JSONValue getDefinition(string filePath, int line, int character) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestDefinition(uri, line, character);
    }
    
    /**
     * Get references
     */
    JSONValue getReferences(string filePath, int line, int character) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestReferences(uri, line, character);
    }
    
    /**
     * Get document symbols
     */
    JSONValue getDocumentSymbols(string filePath) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestDocumentSymbols(uri);
    }
    
    /**
     * Get workspace symbols
     */
    JSONValue getWorkspaceSymbols(string query) {
        // Get all connections
        JSONValue result = parseJSON("[]");
        
        foreach (language, connection; _connections) {
            JSONValue symbols = connection.requestWorkspaceSymbols(query);
            
            if (symbols.type == JSONType.array && symbols.array.length > 0) {
                foreach (symbol; symbols.array)
                    result.array ~= symbol;
            }
        }
        
        return result;
    }
    
    /**
     * Get diagnostics for file
     */
    JSONValue getDiagnostics(string filePath) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.getDiagnostics(uri);
    }
    
    /**
     * Format document
     */
    JSONValue formatDocument(string filePath, string text) {
        LSPConnection connection = getConnectionForFile(filePath);
        
        if (connection is null)
            return JSONValue(null);
            
        string uri = getURIForFile(filePath);
        return connection.requestFormatting(uri, text);
    }
    
    /**
     * Update workspace when workspace changes
     */
    import dcore.vault.vault : Workspace;
    void onWorkspaceChanged(Workspace workspace) {
        if (workspace is null) {
            Log.w("LSPManager: Workspace changed to null");
            return;
        }
        
        // Notify all language servers about workspace change
        string rootPath = workspace.path;
        
        foreach (language, connection; _connections) {
            if (connection.isConnected()) {
                connection.notifyWorkspaceChange(rootPath);
            } else {
                // Reinitialize disconnected servers
                initializeServer(language);
            }
        }
        
        // Clear file mappings
        _fileMappings.clear();
        _languageForFile.clear();
        
        Log.i("LSPManager: Cleared all connections due to workspace change");
    }
    
    /**
     * Cleanup resources
     */
    void cleanup() {
        // Save configurations
        saveConfigurations();
        
        // Shutdown all language servers
        foreach (language, connection; _connections) {
            if (connection.isConnected()) {
                Log.i("LSPManager: Shutting down language server for ", language);
                connection.shutdown();
            }
        }
        
        // Clear connections
        _connections.clear();
        
        // Clear file mappings
        _fileMappings.clear();
        _languageForFile.clear();
        
        Log.i("LSPManager: Cleanup complete");
    }
}

/**
 * LSPConnection - Manages a connection to a language server
 */
class LSPConnection {
    private string _language;
    private string _command;
    private string[] _args;
    private ProcessPipes _pipes;
    private bool _connected;
    private int _requestId;
    private JSONValue[string] _diagnostics;
    
    /**
     * Constructor
     */
    this(string language, string command, string[] args) {
        _language = language;
        _command = command;
        _args = args;
        _connected = false;
        _requestId = 0;
        _diagnostics = null;
    }
    
    /**
     * Initialize connection to language server
     */
    bool initialize() {
        try {
            // Start process
            _pipes = pipeProcess([_command] ~ _args, Redirect.all);
            _connected = true;
            
            // Send initialize request
            JSONValue initRequest = createRequest("initialize", JSONValue([
                "processId": JSONValue(thisProcessID()),
                "rootUri": JSONValue(null),
                "capabilities": JSONValue([
                    "textDocument": JSONValue([
                        "synchronization": JSONValue([
                            "didSave": JSONValue(true),
                            "dynamicRegistration": JSONValue(true)
                        ]),
                        "completion": JSONValue([
                            "dynamicRegistration": JSONValue(true),
                            "contextSupport": JSONValue(true),
                            "completionItem": JSONValue([
                                "snippetSupport": JSONValue(true),
                                "commitCharactersSupport": JSONValue(true),
                                "documentationFormat": JSONValue(["plaintext", "markdown"]),
                                "deprecatedSupport": JSONValue(true)
                            ])
                        ]),
                        "hover": JSONValue([
                            "dynamicRegistration": JSONValue(true),
                            "contentFormat": JSONValue(["plaintext", "markdown"])
                        ]),
                        "signatureHelp": JSONValue([
                            "dynamicRegistration": JSONValue(true),
                            "signatureInformation": JSONValue([
                                "documentationFormat": JSONValue(["plaintext", "markdown"])
                            ])
                        ]),
                        "references": JSONValue([
                            "dynamicRegistration": JSONValue(true)
                        ]),
                        "documentHighlight": JSONValue([
                            "dynamicRegistration": JSONValue(true)
                        ]),
                        "documentSymbol": JSONValue([
                            "dynamicRegistration": JSONValue(true),
                            "symbolKind": JSONValue([
                                "valueSet": JSONValue([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26])
                            ])
                        ]),
                        "formatting": JSONValue([
                            "dynamicRegistration": JSONValue(true)
                        ])
                    ]),
                    "workspace": JSONValue([
                        "applyEdit": JSONValue(true),
                        "didChangeConfiguration": JSONValue([
                            "dynamicRegistration": JSONValue(true)
                        ]),
                        "didChangeWatchedFiles": JSONValue([
                            "dynamicRegistration": JSONValue(true)
                        ]),
                        "symbol": JSONValue([
                            "dynamicRegistration": JSONValue(true),
                            "symbolKind": JSONValue([
                                "valueSet": JSONValue([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26])
                            ])
                        ])
                    ])
                ])
            ]));
            
            // Send request
            sendRequest(initRequest);
            
            // Read response
            JSONValue response = readResponse();
            
            if (response.type == JSONType.null_)
                return false;
                
            // Send initialized notification
            JSONValue initializedNotification = createNotification("initialized", JSONValue(null));
            sendNotification(initializedNotification);
            
            return true;
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error initializing: ", e.msg);
            _connected = false;
            return false;
        }
    }
    
    /**
     * Shutdown connection
     */
    void shutdown() {
        if (!_connected)
            return;
            
        try {
            // Send shutdown request
            JSONValue shutdownRequest = createRequest("shutdown", JSONValue(null));
            sendRequest(shutdownRequest);
            
            // Read response
            JSONValue response = readResponse();
            
            // Send exit notification
            JSONValue exitNotification = createNotification("exit", JSONValue(null));
            sendNotification(exitNotification);
            
            // Close pipes
            _pipes.stdin.close();
            _pipes.stdout.close();
            _pipes.stderr.close();
            
            // Mark as disconnected
            _connected = false;
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error shutting down: ", e.msg);
        }
    }
    
    /**
     * Check if connection is active
     */
    bool isConnected() {
        return _connected;
    }
    
    /**
     * Create JSON-RPC request
     */
    private JSONValue createRequest(string method, JSONValue params) {
        JSONValue request = parseJSON("{}");
        request["jsonrpc"] = "2.0";
        request["id"] = ++_requestId;
        request["method"] = method;
        request["params"] = params;
        
        return request;
    }
    
    /**
     * Create JSON-RPC notification
     */
    private JSONValue createNotification(string method, JSONValue params) {
        JSONValue notification = parseJSON("{}");
        notification["jsonrpc"] = "2.0";
        notification["method"] = method;
        notification["params"] = params;
        
        return notification;
    }
    
    /**
     * Send JSON-RPC request
     */
    private void sendRequest(JSONValue request) {
        if (!_connected)
            return;
            
        try {
            string content = request.toString();
            string message = format("Content-Length: %d\r\n\r\n%s", content.length, content);
            _pipes.stdin.write(message);
            _pipes.stdin.flush();
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error sending request: ", e.msg);
            _connected = false;
        }
    }
    
    /**
     * Send JSON-RPC notification
     */
    private void sendNotification(JSONValue notification) {
        if (!_connected)
            return;
            
        try {
            string content = notification.toString();
            string message = format("Content-Length: %d\r\n\r\n%s", content.length, content);
            _pipes.stdin.write(message);
            _pipes.stdin.flush();
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error sending notification: ", e.msg);
            _connected = false;
        }
    }
    
    /**
     * Read JSON-RPC response
     */
    private JSONValue readResponse() {
        if (!_connected)
            return JSONValue(null);
            
        try {
            // Read header
            string line;
            int contentLength = -1;
            
            while ((line = _pipes.stdout.readln().chomp()) != "") {
                if (line.startsWith("Content-Length: ")) {
                    contentLength = to!int(line[16..$]);
                }
            }
            
            if (contentLength == -1)
                return JSONValue(null);
                
            // Read content
            char[] buffer = new char[contentLength];
            _pipes.stdout.rawRead(buffer);
            string content = buffer.idup;
            
            // Parse JSON
            return parseJSON(content);
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error reading response: ", e.msg);
            _connected = false;
            return JSONValue(null);
        }
    }
    
    /**
     * Notify document open
     */
    void notifyDocumentOpen(string uri, string text) {
        if (!_connected)
            return;
            
        JSONValue notification = createNotification("textDocument/didOpen", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri),
                "languageId": JSONValue(_language),
                "version": JSONValue(1),
                "text": JSONValue(text)
            ])
        ]));
        
        sendNotification(notification);
    }
    
    /**
     * Notify document change
     */
    void notifyDocumentChange(string uri, string text) {
        if (!_connected)
            return;
            
        JSONValue notification = createNotification("textDocument/didChange", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri),
                "version": JSONValue(2)
            ]),
            "contentChanges": JSONValue([
                JSONValue([
                    "text": JSONValue(text)
                ])
            ])
        ]));
        
        sendNotification(notification);
    }
    
    /**
     * Notify document close
     */
    void notifyDocumentClose(string uri) {
        if (!_connected)
            return;
            
        JSONValue notification = createNotification("textDocument/didClose", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ])
        ]));
        
        sendNotification(notification);
    }
    
    /**
     * Notify workspace change
     */
    void notifyWorkspaceChange(string rootPath) {
        if (!_connected)
            return;
            
        // Convert path to URI
        string rootUri = "file://" ~ absolutePath(rootPath);
        
        // Change workspace folders
        JSONValue notification = createNotification("workspace/didChangeWorkspaceFolders", JSONValue([
            "event": JSONValue([
                "added": JSONValue([
                    JSONValue([
                        "uri": JSONValue(rootUri),
                        "name": JSONValue(baseName(rootPath))
                    ])
                ]),
                "removed": JSONValue(cast(JSONValue[])[])
            ])
        ]));
        
        sendNotification(notification);
    }
    
    /**
     * Request completion
     */
    JSONValue requestCompletion(string uri, int line, int character) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/completion", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ]),
            "position": JSONValue([
                "line": JSONValue(line),
                "character": JSONValue(character)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request hover information
     */
    JSONValue requestHover(string uri, int line, int character) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/hover", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ]),
            "position": JSONValue([
                "line": JSONValue(line),
                "character": JSONValue(character)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request definition
     */
    JSONValue requestDefinition(string uri, int line, int character) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/definition", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ]),
            "position": JSONValue([
                "line": JSONValue(line),
                "character": JSONValue(character)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request references
     */
    JSONValue requestReferences(string uri, int line, int character) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/references", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ]),
            "position": JSONValue([
                "line": JSONValue(line),
                "character": JSONValue(character)
            ]),
            "context": JSONValue([
                "includeDeclaration": JSONValue(true)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request document symbols
     */
    JSONValue requestDocumentSymbols(string uri) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/documentSymbol", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request workspace symbols
     */
    JSONValue requestWorkspaceSymbols(string query) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("workspace/symbol", JSONValue([
            "query": JSONValue(query)
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Request formatting
     */
    JSONValue requestFormatting(string uri, string text) {
        if (!_connected)
            return JSONValue(null);
            
        JSONValue request = createRequest("textDocument/formatting", JSONValue([
            "textDocument": JSONValue([
                "uri": JSONValue(uri)
            ]),
            "options": JSONValue([
                "tabSize": JSONValue(4),
                "insertSpaces": JSONValue(true)
            ])
        ]));
        
        sendRequest(request);
        return readResponse();
    }
    
    /**
     * Get diagnostics for document
     */
    JSONValue getDiagnostics(string uri) {
        if (uri in _diagnostics)
            return _diagnostics[uri];
            
        return JSONValue(null);
    }
    
    /**
     * Process diagnostics notification
     */
    void processDiagnostics(JSONValue params) {
        if ("uri" in params && "diagnostics" in params) {
            string uri = params["uri"].str;
            _diagnostics[uri] = params["diagnostics"];
        }
    }
}