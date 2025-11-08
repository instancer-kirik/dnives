module dcore.ai.context_manager;

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
import std.range;

import dlangui.core.logger;

import dcore.core;
import dcore.code.symbol_tracker;
import dcore.lsp.lspmanager;
import dcore.lsp.lsptypes;

/**
 * FileContext - Context information for a file
 */
struct FileContext {
    string filePath;
    string content;
    string language;
    CodeSymbol[] symbols;
    SymbolReference[] references;
    string[] imports;
    int[] relevantLines;  // Line numbers that are contextually important
    string summary;       // AI-generated summary of the file
    DateTime lastUpdated;

    this(string filePath) {
        this.filePath = filePath;
        this.lastUpdated = cast(DateTime)Clock.currTime();
    }
}

/**
 * ConversationContext - Context for an AI conversation
 */
struct ConversationContext {
    string conversationId;
    string workspacePath;
    string[] focusFiles;           // Primary files being discussed
    string[] relatedFiles;         // Files that might be relevant
    string currentSymbol;          // Currently focused symbol
    CodeSymbol[] relevantSymbols;  // Symbols that are contextually important
    string[] keywords;             // Important keywords from conversation
    string intent;                 // What the user is trying to achieve
    string language;               // Primary programming language
    DateTime created;
    DateTime lastUpdated;

    this(string conversationId, string workspacePath) {
        this.conversationId = conversationId;
        this.workspacePath = workspacePath;
        this.created = cast(DateTime)Clock.currTime();
        this.lastUpdated = cast(DateTime)Clock.currTime();
    }
}

/**
 * CodeScope - Represents a scope of code (function, class, etc.)
 */
struct CodeScope {
    string name;
    string filePath;
    SymbolKind kind;
    Range range;
    string content;
    CodeScope[] children;
    CodeScope* parent;

    this(string name, string filePath, SymbolKind kind, Range range) {
        this.name = name;
        this.filePath = filePath;
        this.kind = kind;
        this.range = range;
    }
}

/**
 * ContextPriority - Priority levels for context inclusion
 */
enum ContextPriority {
    Critical,   // Must be included
    High,       // Should be included if space allows
    Medium,     // Include if related to current focus
    Low         // Background context only
}

/**
 * ContextItem - A piece of context with metadata
 */
struct ContextItem {
    string id;
    string content;
    ContextPriority priority;
    string source;      // Where this context came from
    string[] tags;      // Categorization tags
    int relevanceScore; // 0-100 relevance score
    DateTime timestamp;

    this(string id, string content, ContextPriority priority, string source) {
        this.id = id;
        this.content = content;
        this.priority = priority;
        this.source = source;
        this.relevanceScore = 50;
        this.timestamp = cast(DateTime)Clock.currTime();
    }
}

/**
 * ContextManager - Manages context for AI operations
 *
 * Features:
 * - Gathers relevant code context using symbol tracker
 * - Maintains conversation history and context
 * - Prioritizes and filters context based on relevance
 * - Manages context windows and token limits
 * - Provides intelligent context summarization
 */
class ContextManager {
    private DCore _core;
    private SymbolTracker _symbolTracker;
    private LSPManager _lspManager;

    // Context storage
    private FileContext[string] _fileContexts;           // file path -> context
    private ConversationContext[string] _conversations;  // conversation id -> context
    private ContextItem[] _globalContext;                // Global context items

    // Configuration
    private int _maxContextTokens = 8000;      // Maximum context window
    private int _maxFileLines = 100;           // Max lines to include from a file
    private int _maxSymbolReferences = 20;     // Max references per symbol
    private Duration _contextCacheTimeout = 10.minutes;

    // Cache
    private string[string] _contextCache;      // cache key -> rendered context
    private SysTime[string] _cacheTimestamps; // cache key -> timestamp

    /**
     * Constructor
     */
    this(DCore core, SymbolTracker symbolTracker, LSPManager lspManager) {
        _core = core;
        _symbolTracker = symbolTracker;
        _lspManager = lspManager;

        Log.i("ContextManager: Initialized");
    }

    /**
     * Initialize the context manager
     */
    void initialize() {
        // Load any persistent context
        loadPersistentContext();

        // Set up file watching for context updates
        startContextMonitoring();

        Log.i("ContextManager: Ready");
    }

    /**
     * Create a new conversation context
     */
    ConversationContext createConversation(string workspacePath, string[] initialFiles = []) {
        string conversationId = generateConversationId();
        auto context = ConversationContext(conversationId, workspacePath);
        context.focusFiles = initialFiles;

        // Analyze initial files for context
        foreach (file; initialFiles) {
            analyzeFileForContext(file);
        }

        _conversations[conversationId] = context;

        Log.i("ContextManager: Created conversation ", conversationId);
        return context;
    }

    /**
     * Update conversation with new focus
     */
    void updateConversationFocus(string conversationId, string[] files, string symbol = null) {
        if (conversationId !in _conversations)
            return;

        auto context = &_conversations[conversationId];
        context.focusFiles = files;
        context.currentSymbol = symbol;
        context.lastUpdated = cast(DateTime)Clock.currTime();

        // Re-analyze context
        foreach (file; files) {
            analyzeFileForContext(file);
        }

        // Update related files based on new focus
        updateRelatedFiles(context);

        // Clear cache for this conversation
        invalidateContextCache(conversationId);
    }

    /**
     * Get context for a conversation
     */
    string getConversationContext(string conversationId, string[] additionalFiles = []) {
        if (conversationId !in _conversations)
            return "";

        string cacheKey = conversationId ~ "|" ~ additionalFiles.join(",");

        // Check cache
        if (cacheKey in _contextCache) {
            auto cachedTime = _cacheTimestamps.get(cacheKey, SysTime.min);
            if (Clock.currTime() - cachedTime < _contextCacheTimeout) {
                return _contextCache[cacheKey];
            }
        }

        auto context = _conversations[conversationId];
        auto contextItems = gatherContextItems(context, additionalFiles);
        string renderedContext = renderContext(contextItems);

        // Cache the result
        _contextCache[cacheKey] = renderedContext;
        _cacheTimestamps[cacheKey] = Clock.currTime();

        return renderedContext;
    }

    /**
     * Get context for specific files and symbols
     */
    string getCodeContext(string[] files, string[] symbols = [], int maxTokens = 0) {
        if (maxTokens == 0)
            maxTokens = _maxContextTokens;

        ContextItem[] contextItems;

        // Add file contexts
        foreach (file; files) {
            auto fileContext = getFileContext(file);
            if (fileContext.content.length > 0) {
                auto item = ContextItem(
                    "file:" ~ file,
                    formatFileContext(fileContext),
                    ContextPriority.High,
                    "file_content"
                );
                contextItems ~= item;
            }
        }

        // Add symbol contexts
        foreach (symbol; symbols) {
            auto symbolContext = getSymbolContext(symbol);
            if (!symbolContext.empty) {
                auto item = ContextItem(
                    "symbol:" ~ symbol,
                    symbolContext,
                    ContextPriority.Critical,
                    "symbol_definition"
                );
                contextItems ~= item;
            }
        }

        // Sort by priority and relevance
        contextItems.sort!((a, b) =>
            a.priority < b.priority ||
            (a.priority == b.priority && a.relevanceScore > b.relevanceScore));

        return renderContext(contextItems, maxTokens);
    }

    /**
     * Analyze a file for context information
     */
    private void analyzeFileForContext(string filePath) {
        if (!exists(filePath))
            return;

        try {
            FileContext context = FileContext(filePath);
            context.content = readText(filePath);
            context.language = detectLanguage(filePath);

            // Get symbols from symbol tracker
            context.symbols = _symbolTracker.getFileSymbols(filePath);

            // Get references if file is in references
            // TODO: Add public method to get references from symbol tracker
            // if (_symbolTracker._references && filePath in _symbolTracker._references) {
            //     context.references = _symbolTracker._references[filePath];
            // }

            // Extract imports/includes
            context.imports = extractImports(context.content, context.language);

            // Find relevant lines (function definitions, class declarations, etc.)
            context.relevantLines = findRelevantLines(context.content, context.language);

            // Generate summary if file is large
            if (context.content.split('\n').length > _maxFileLines) {
                context.summary = generateFileSummary(context);
            }

            _fileContexts[filePath] = context;

        } catch (Exception e) {
            Log.w("ContextManager: Failed to analyze file ", filePath, ": ", e.msg);
        }
    }

    /**
     * Get file context, analyzing if not cached
     */
    private FileContext getFileContext(string filePath) {
        if (filePath in _fileContexts) {
            auto context = _fileContexts[filePath];

            // Check if file has been modified
            if (exists(filePath)) {
                auto lastModified = timeLastModified(filePath);
                if (lastModified > cast(SysTime)context.lastUpdated) {
                    analyzeFileForContext(filePath);
                    return _fileContexts[filePath];
                }
            }

            return context;
        }

        // Analyze and cache
        analyzeFileForContext(filePath);
        return _fileContexts.get(filePath, FileContext(filePath));
    }

    /**
     * Get context for a specific symbol
     */
    private string getSymbolContext(string symbolName) {
        auto references = _symbolTracker.getReferences(symbolName);
        if (references.empty)
            return "";

        string context = "Symbol: " ~ symbolName ~ "\n";

        // Find the definition
        auto definitions = references.filter!(r => r.isDefinition).array;
        if (!definitions.empty) {
            auto def = definitions[0];
            context ~= "Definition in " ~ def.filePath ~ ":\n";
            context ~= getCodeAroundLocation(def.filePath, def.location) ~ "\n\n";
        }

        // Add key references (limit to avoid overwhelming)
        auto keyRefs = references.filter!(r => !r.isDefinition)
                                .take(_maxSymbolReferences)
                                .array;

        if (!keyRefs.empty) {
            context ~= "Key references:\n";
            foreach (ref_; keyRefs) {
                context ~= format("  %s:%d - %s\n",
                                baseName(ref_.filePath),
                                ref_.location.start.line + 1,
                                ref_.contextLine);
            }
        }

        return context;
    }

    /**
     * Get code around a specific location
     */
    private string getCodeAroundLocation(string filePath, Range location, int contextLines = 3) {
        if (!exists(filePath))
            return "";

        try {
            auto lines = readText(filePath).split('\n');
            int startLine = max(0, location.start.line - contextLines);
            int endLine = min(cast(int)lines.length - 1, location.end.line + contextLines);

            string[] contextLinesArray;
            for (int i = startLine; i <= endLine; i++) {
                string prefix = (i == location.start.line) ? ">>> " : "    ";
                contextLinesArray ~= format("%s%d: %s", prefix, i + 1, lines[i]);
            }

            return contextLinesArray.join("\n");
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * Extract imports/includes from file content
     */
    private string[] extractImports(string content, string language) {
        string[] imports;

        auto lines = content.split('\n');
        foreach (line; lines) {
            line = line.strip();

            switch (language) {
                case "d":
                    if (line.startsWith("import ") && line.endsWith(";")) {
                        imports ~= line;
                    }
                    break;
                case "python":
                    if (line.startsWith("import ") || line.startsWith("from ")) {
                        imports ~= line;
                    }
                    break;
                case "javascript":
                case "typescript":
                    if (line.startsWith("import ") || line.canFind("require(")) {
                        imports ~= line;
                    }
                    break;
                case "c":
                case "cpp":
                    if (line.startsWith("#include")) {
                        imports ~= line;
                    }
                    break;
                default:
                    break;
            }
        }

        return imports;
    }

    /**
     * Find relevant lines in code (function definitions, class declarations, etc.)
     */
    private int[] findRelevantLines(string content, string language) {
        int[] relevantLines;
        auto lines = content.split('\n');

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i].strip();

            switch (language) {
                case "d":
                    if (line.canFind("class ") || line.canFind("struct ") ||
                        line.canFind("interface ") || line.canFind("enum ") ||
                        (line.canFind("(") && (line.canFind("public") || line.canFind("private")))) {
                        relevantLines ~= i;
                    }
                    break;
                case "python":
                    if (line.startsWith("def ") || line.startsWith("class ") ||
                        line.startsWith("async def ")) {
                        relevantLines ~= i;
                    }
                    break;
                case "javascript":
                case "typescript":
                    if (line.canFind("function ") || line.canFind("class ") ||
                        line.canFind("interface ") || line.canFind("=> ")) {
                        relevantLines ~= i;
                    }
                    break;
                default:
                    break;
            }
        }

        return relevantLines;
    }

    /**
     * Generate a summary of a large file
     */
    private string generateFileSummary(FileContext context) {
        // Simple heuristic-based summary for now
        // In practice, you might use AI to generate better summaries

        string summary = "File: " ~ baseName(context.filePath) ~ " (" ~ context.language ~ ")\n";

        if (!context.symbols.empty) {
            auto classes = context.symbols.filter!(s => s.kind == SymbolKind.Class).array;
            auto functions = context.symbols.filter!(s =>
                s.kind == SymbolKind.Function || s.kind == SymbolKind.Method).array;

            if (!classes.empty) {
                summary ~= "Classes: " ~ classes.map!(c => c.name).join(", ") ~ "\n";
            }

            if (!functions.empty && functions.length <= 10) {
                summary ~= "Functions: " ~ functions.map!(f => f.name).join(", ") ~ "\n";
            } else if (!functions.empty) {
                summary ~= format("Functions: %d total\n", functions.length);
            }
        }

        if (!context.imports.empty) {
            summary ~= format("Dependencies: %d imports\n", context.imports.length);
        }

        return summary;
    }

    /**
     * Update related files for a conversation context
     */
    private void updateRelatedFiles(ConversationContext* context) {
        string[] relatedFiles;

        // Find files that import/are imported by focus files
        foreach (focusFile; context.focusFiles) {
            auto fileContext = getFileContext(focusFile);

            // Add imported files
            foreach (importLine; fileContext.imports) {
                string importedFile = resolveImportPath(importLine, focusFile);
                if (!importedFile.empty && !relatedFiles.canFind(importedFile)) {
                    relatedFiles ~= importedFile;
                }
            }

            // Add files that reference symbols from this file
            foreach (symbol; fileContext.symbols) {
                auto references = _symbolTracker.getReferences(symbol.fullyQualifiedName);
                foreach (ref_; references) {
                    if (!context.focusFiles.canFind(ref_.filePath) &&
                        !relatedFiles.canFind(ref_.filePath)) {
                        relatedFiles ~= ref_.filePath;
                    }
                }
            }
        }

        context.relatedFiles = relatedFiles.take(20).array; // Limit to prevent overwhelming
    }

    /**
     * Gather context items for rendering
     */
    private ContextItem[] gatherContextItems(ConversationContext context, string[] additionalFiles) {
        ContextItem[] items;

        // Add focus files with critical priority
        foreach (file; context.focusFiles) {
            auto fileContext = getFileContext(file);
            auto item = ContextItem(
                "focus_file:" ~ file,
                formatFileContext(fileContext),
                ContextPriority.Critical,
                "focus_file"
            );
            item.relevanceScore = 95;
            items ~= item;
        }

        // Add current symbol with critical priority
        if (!context.currentSymbol.empty) {
            auto symbolContext = getSymbolContext(context.currentSymbol);
            if (!symbolContext.empty) {
                auto item = ContextItem(
                    "current_symbol:" ~ context.currentSymbol,
                    symbolContext,
                    ContextPriority.Critical,
                    "current_symbol"
                );
                item.relevanceScore = 100;
                items ~= item;
            }
        }

        // Add additional files with high priority
        foreach (file; additionalFiles) {
            auto fileContext = getFileContext(file);
            auto item = ContextItem(
                "additional_file:" ~ file,
                formatFileContext(fileContext),
                ContextPriority.High,
                "additional_file"
            );
            item.relevanceScore = 85;
            items ~= item;
        }

        // Add related files with medium priority
        foreach (file; context.relatedFiles.take(5)) { // Limit related files
            auto fileContext = getFileContext(file);
            auto item = ContextItem(
                "related_file:" ~ file,
                formatFileContext(fileContext, true), // Abbreviated format
                ContextPriority.Medium,
                "related_file"
            );
            item.relevanceScore = 60;
            items ~= item;
        }

        return items;
    }

    /**
     * Format file context for inclusion
     */
    private string formatFileContext(FileContext context, bool abbreviated = false) {
        string formatted = "=== " ~ baseName(context.filePath) ~ " ===\n";

        if (abbreviated) {
            if (!context.summary.empty) {
                formatted ~= context.summary ~ "\n";
            } else {
                // Show just key lines
                auto lines = context.content.split('\n');
                foreach (lineNum; context.relevantLines.take(10)) {
                    if (lineNum < lines.length) {
                        formatted ~= format("%d: %s\n", lineNum + 1, lines[lineNum]);
                    }
                }
            }
        } else {
            if (context.content.split('\n').length > _maxFileLines && !context.summary.empty) {
                formatted ~= context.summary ~ "\n\n";

                // Include key sections
                auto lines = context.content.split('\n');
                foreach (lineNum; context.relevantLines) {
                    formatted ~= getCodeAroundLocation(context.filePath,
                                                    Range(Position(lineNum, 0), Position(lineNum, 0)), 2) ~ "\n";
                }
            } else {
                formatted ~= context.content;
            }
        }

        return formatted ~ "\n";
    }

    /**
     * Render context items into final context string
     */
    private string renderContext(ContextItem[] items, int maxTokens = 0) {
        if (maxTokens == 0)
            maxTokens = _maxContextTokens;

        // Sort by priority and relevance
        items.sort!((a, b) =>
            a.priority < b.priority ||
            (a.priority == b.priority && a.relevanceScore > b.relevanceScore));

        string context = "=== CODE CONTEXT ===\n\n";
        int tokenCount = cast(int)context.length; // Rough token estimation

        foreach (item; items) {
            int itemTokens = cast(int)(item.content.length * 0.75); // Rough estimation

            if (tokenCount + itemTokens > maxTokens) {
                if (item.priority == ContextPriority.Critical) {
                    // Try to truncate rather than skip critical items
                    int availableTokens = maxTokens - tokenCount;
                    if (availableTokens > 100) {
                        string truncated = item.content[0 .. min(cast(int)(availableTokens * 1.33), item.content.length)];
                        context ~= truncated ~ "\n[... truncated ...]\n\n";
                        break;
                    }
                }
                break; // Skip remaining items
            }

            context ~= item.content ~ "\n";
            tokenCount += itemTokens;
        }

        context ~= "=== END CONTEXT ===\n";

        return context;
    }

    /**
     * Resolve import path to actual file path
     */
    private string resolveImportPath(string importLine, string currentFile) {
        // Simplified resolution - would need full import resolution logic
        // This is a placeholder implementation
        return "";
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
            default: return "text";
        }
    }

    /**
     * Generate unique conversation ID
     */
    private string generateConversationId() {
        import std.uuid;
        return randomUUID().toString();
    }

    /**
     * Start monitoring for context changes
     */
    private void startContextMonitoring() {
        // Would implement file watching for context updates
        Log.i("ContextManager: Started context monitoring");
    }

    /**
     * Load persistent context data
     */
    private void loadPersistentContext() {
        // Would load saved context data
        Log.i("ContextManager: Loaded persistent context");
    }

    /**
     * Invalidate cached context
     */
    private void invalidateContextCache(string pattern = "") {
        if (pattern.empty) {
            _contextCache.clear();
            _cacheTimestamps.clear();
        } else {
            string[] keysToRemove;
            foreach (key; _contextCache.keys) {
                if (key.canFind(pattern)) {
                    keysToRemove ~= key;
                }
            }
            foreach (key; keysToRemove) {
                _contextCache.remove(key);
                _cacheTimestamps.remove(key);
            }
        }
    }

    /**
     * Add global context item
     */
    void addGlobalContext(string id, string content, ContextPriority priority, string source) {
        auto item = ContextItem(id, content, priority, source);
        _globalContext ~= item;
    }

    /**
     * Remove global context item
     */
    void removeGlobalContext(string id) {
        _globalContext = _globalContext.filter!(item => item.id != id).array;
    }

    /**
     * Get conversation by ID
     */
    ConversationContext* getConversation(string conversationId) {
        if (conversationId in _conversations) {
            return &_conversations[conversationId];
        }
        return null;
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        _fileContexts.clear();
        _conversations.clear();
        _globalContext.length = 0;
        _contextCache.clear();
        _cacheTimestamps.clear();

        Log.i("ContextManager: Cleaned up");
    }
}
