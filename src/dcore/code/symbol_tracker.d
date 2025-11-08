module dcore.code.symbol_tracker;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.json;
import std.datetime;
import std.exception;
import std.conv;
import std.typecons;
import std.regex;

import dlangui.core.logger;

import dcore.core;
import dcore.lsp.lspmanager;
import dcore.lsp.lsptypes;

/**
 * CodeSymbol - Represents a symbol in the codebase with metadata
 */
struct CodeSymbol {
    string name;
    string filePath;
    string fullyQualifiedName;
    SymbolKind kind;
    Range location;
    string documentation;
    string signature;
    string containerName;
    bool isPublic;
    bool isDeprecated;
    DateTime lastModified;

    string toString() const {
        return format("%s (%s) in %s:%d:%d",
                     name, kind, filePath, location.start.line, location.start.character);
    }
}

/**
 * SymbolReference - A reference to a symbol with context
 */
struct SymbolReference {
    CodeSymbol symbol;
    Range location;
    string filePath;
    string contextLine;
    bool isDefinition;
    bool isWrite;
    DateTime timestamp;

    string toString() const {
        return format("Ref to %s at %s:%d:%d (%s)",
                     symbol.name, filePath, location.start.line, location.start.character,
                     isDefinition ? "def" : "use");
    }
}

/**
 * CodeContext - Contextual information about code
 */
struct CodeContext {
    string[] relevantFiles;
    CodeSymbol[] symbols;
    SymbolReference[] references;
    string[] imports;
    string projectPath;
    string language;
}

/**
 * SymbolTracker - Tracks symbols and references across the codebase
 *
 * Features:
 * - Integrates with LSP for real-time symbol information
 * - Tracks symbol references and definitions
 * - Provides context for AI operations
 * - Monitors file changes and updates symbol data
 * - Caches symbol information for performance
 */
class SymbolTracker {
    private DCore _core;
    private LSPManager _lspManager;

    // Symbol storage
    private CodeSymbol[string] _symbols;           // fully qualified name -> symbol
    private SymbolReference[][string] _references; // file path -> references
    private string[][string] _fileSymbols;         // file path -> symbol names

    // File monitoring
    private DateTime[string] _fileTimestamps;      // file path -> last modified
    private string[] _watchedFiles;

    // Cache for performance
    private CodeContext[string] _contextCache;     // context key -> cached context
    private Duration _cacheTimeout = 5.minutes;

    /**
     * Constructor
     */
    this(DCore core, LSPManager lspManager) {
        _core = core;
        _lspManager = lspManager;

        Log.i("SymbolTracker: Initialized");
    }

    /**
     * Initialize the symbol tracker
     */
    void initialize() {
        // Start monitoring workspace files
        startFileMonitoring();

        // Initial symbol scan
        scanWorkspaceSymbols();

        Log.i("SymbolTracker: Ready");
    }

    /**
     * Start monitoring files for changes
     */
    private void startFileMonitoring() {
        auto workspace = _core.getCurrentWorkspace();
        if (!workspace)
            return;

        // Get all source files in workspace
        auto sourceFiles = getSourceFiles(workspace.path);
        foreach (file; sourceFiles) {
            addFileToWatch(file);
        }
    }

    /**
     * Add a file to the watch list
     */
    void addFileToWatch(string filePath) {
        if (_watchedFiles.canFind(filePath))
            return;

        _watchedFiles ~= filePath;

        if (exists(filePath)) {
            _fileTimestamps[filePath] = timeLastModified(filePath);
        }

        // Request symbols from LSP
        requestSymbolsForFile(filePath);
    }

    /**
     * Get source files in a directory recursively
     */
    private string[] getSourceFiles(string dirPath) {
        string[] files;

        if (!exists(dirPath) || !isDir(dirPath))
            return files;

        try {
            foreach (DirEntry entry; dirEntries(dirPath, SpanMode.depth)) {
                if (entry.isFile && isSourceFile(entry.name)) {
                    files ~= entry.name;
                }
            }
        } catch (Exception e) {
            Log.w("SymbolTracker: Error scanning directory ", dirPath, ": ", e.msg);
        }

        return files;
    }

    /**
     * Check if a file is a source file
     */
    private bool isSourceFile(string filePath) {
        string ext = extension(filePath).toLower();
        return [".d", ".di", ".js", ".ts", ".py", ".rs", ".c", ".cpp", ".h", ".hpp"].canFind(ext);
    }

    /**
     * Request symbols for a file from LSP
     */
    private void requestSymbolsForFile(string filePath) {
        if (!_lspManager)
            return;

        string language = detectLanguage(filePath);
        if (language.empty)
            return;

        try {
            // Request document symbols
            auto symbols = _lspManager.getDocumentSymbols(filePath);
            updateFileSymbols(filePath, symbols);

            // Request references for major symbols
            foreach (symbol; symbols) {
                if (isMajorSymbol(symbol)) {
                    requestSymbolReferences(filePath, symbol);
                }
            }
        } catch (Exception e) {
            Log.w("SymbolTracker: Error requesting symbols for ", filePath, ": ", e.msg);
        }
    }

    /**
     * Update symbols for a file
     */
    private void updateFileSymbols(string filePath, DocumentSymbol[] symbols) {
        // Clear existing symbols for this file
        if (filePath in _fileSymbols) {
            foreach (symbolName; _fileSymbols[filePath]) {
                _symbols.remove(symbolName);
            }
        }

        string[] newSymbolNames;

        // Process new symbols
        foreach (symbol; symbols) {
            auto codeSymbol = convertToCodeSymbol(filePath, symbol);
            _symbols[codeSymbol.fullyQualifiedName] = codeSymbol;
            newSymbolNames ~= codeSymbol.fullyQualifiedName;
        }

        _fileSymbols[filePath] = newSymbolNames;
    }

    /**
     * Convert LSP DocumentSymbol to CodeSymbol
     */
    private CodeSymbol convertToCodeSymbol(string filePath, DocumentSymbol symbol) {
        CodeSymbol cs;
        cs.name = symbol.name;
        cs.filePath = filePath;
        cs.fullyQualifiedName = buildFullyQualifiedName(filePath, symbol);
        cs.kind = symbol.kind;
        cs.location = symbol.range;
        cs.documentation = symbol.detail;
        cs.containerName = "";
        cs.isPublic = true; // TODO: Determine from symbol details
        cs.isDeprecated = false; // DocumentSymbol doesn't have deprecated info
        cs.lastModified = cast(DateTime)Clock.currTime();

        return cs;
    }

    /**
     * Build fully qualified name for a symbol
     */
    private string buildFullyQualifiedName(string filePath, DocumentSymbol symbol) {
        string moduleName = getModuleName(filePath);
        if (moduleName.empty)
            return symbol.name;

        return moduleName ~ "." ~ symbol.name;
    }

    /**
     * Get module name from file path
     */
    private string getModuleName(string filePath) {
        // Simple heuristic - use filename without extension
        return baseName(filePath, extension(filePath));
    }

    /**
     * Check if a symbol is major (class, function, etc.)
     */
    private bool isMajorSymbol(DocumentSymbol symbol) {
        return [SymbolKind.Class, SymbolKind.Function, SymbolKind.Method,
                SymbolKind.Interface, SymbolKind.Enum, SymbolKind.Struct].canFind(symbol.kind);
    }

    /**
     * Request references for a symbol
     */
    private void requestSymbolReferences(string filePath, DocumentSymbol symbol) {
        try {
            auto references = _lspManager.getReferences(filePath, symbol.range.start);
            updateSymbolReferences(filePath, symbol, references);
        } catch (Exception e) {
            Log.w("SymbolTracker: Error getting references for ", symbol.name, ": ", e.msg);
        }
    }

    /**
     * Update references for a symbol
     */
    private void updateSymbolReferences(string filePath, DocumentSymbol symbol, LocationInfo[] locations) {
        auto codeSymbol = convertToCodeSymbol(filePath, symbol);

        foreach (location; locations) {
            SymbolReference symbolRef;
            symbolRef.symbol = codeSymbol;
            symbolRef.location = location.range;
            symbolRef.filePath = location.uri;
            symbolRef.contextLine = getContextLine(location.uri, location.range.start.line);
            symbolRef.isDefinition = (location.uri == filePath &&
                              location.range.start.line == symbol.range.start.line);
            symbolRef.timestamp = cast(DateTime)Clock.currTime();

            // Add to references
            if (location.uri !in _references)
                _references[location.uri] = [];
            _references[location.uri] ~= symbolRef;
        }
    }

    /**
     * Get context line for a reference
     */
    private string getContextLine(string filePath, int lineNumber) {
        try {
            if (!exists(filePath))
                return "";

            auto lines = readText(filePath).splitLines();
            if (lineNumber >= 0 && lineNumber < lines.length)
                return lines[lineNumber].strip();
        } catch (Exception e) {
            Log.w("SymbolTracker: Error reading context line: ", e.msg);
        }

        return "";
    }

    /**
     * Scan all symbols in workspace
     */
    void scanWorkspaceSymbols() {
        Log.i("SymbolTracker: Scanning workspace symbols...");

        foreach (filePath; _watchedFiles) {
            if (hasFileChanged(filePath)) {
                requestSymbolsForFile(filePath);
            }
        }

        Log.i("SymbolTracker: Workspace scan complete");
    }

    /**
     * Check if a file has changed since last scan
     */
    private bool hasFileChanged(string filePath) {
        if (!exists(filePath))
            return false;

        auto currentTime = timeLastModified(filePath);
        auto lastTime = _fileTimestamps.get(filePath, SysTime.min);

        if (currentTime > lastTime) {
            _fileTimestamps[filePath] = currentTime;
            return true;
        }

        return false;
    }

    /**
     * Get symbols by name pattern
     */
    CodeSymbol[] findSymbols(string pattern) {
        CodeSymbol[] results;
        auto regex = regex(pattern, "i");

        foreach (symbol; _symbols.values) {
            if (symbol.name.matchFirst(regex) ||
                symbol.fullyQualifiedName.matchFirst(regex)) {
                results ~= symbol;
            }
        }

        return results;
    }

    /**
     * Get references to a symbol
     */
    SymbolReference[] getReferences(string symbolName) {
        SymbolReference[] results;

        foreach (refs; _references.values) {
            foreach (symbolRef; refs) {
                if (symbolRef.symbol.name == symbolName ||
                    symbolRef.symbol.fullyQualifiedName == symbolName) {
                    results ~= symbolRef;
                }
            }
        }

        return results;
    }

    /**
     * Get symbols in a file
     */
    CodeSymbol[] getFileSymbols(string filePath) {
        CodeSymbol[] results;

        if (filePath in _fileSymbols) {
            foreach (symbolName; _fileSymbols[filePath]) {
                if (symbolName in _symbols) {
                    results ~= _symbols[symbolName];
                }
            }
        }

        return results;
    }

    /**
     * Get code context for AI operations
     */
    CodeContext getCodeContext(string[] files, string focusSymbol = null) {
        string contextKey = files.join("|") ~ "|" ~ focusSymbol;

        // Check cache
        if (contextKey in _contextCache) {
            auto cached = _contextCache[contextKey];
            // TODO: Check if cache is still valid
            return cached;
        }

        CodeContext context;
        context.relevantFiles = files;
        context.projectPath = _core.getCurrentWorkspace().path;

        // Gather symbols and references
        foreach (filePath; files) {
            context.symbols ~= getFileSymbols(filePath);
            if (filePath in _references) {
                context.references ~= _references[filePath];
            }
        }

        // If focus symbol specified, add its references
        if (!focusSymbol.empty) {
            context.references ~= getReferences(focusSymbol);
        }

        // Cache the result
        _contextCache[contextKey] = context;

        return context;
    }

    /**
     * Detect programming language from file extension
     */
    private string detectLanguage(string filePath) {
        string ext = extension(filePath).toLower();

        switch (ext) {
            case ".d", ".di": return "d";
            case ".js": return "javascript";
            case ".ts": return "typescript";
            case ".py": return "python";
            case ".rs": return "rust";
            case ".c": return "c";
            case ".cpp", ".cxx", ".cc": return "cpp";
            case ".h": return "c";
            case ".hpp", ".hxx": return "cpp";
            default: return "";
        }
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        _symbols.clear();
        _references.clear();
        _fileSymbols.clear();
        _contextCache.clear();

        Log.i("SymbolTracker: Cleaned up");
    }
}
