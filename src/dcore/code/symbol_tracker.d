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
import std.range;

import dlangui.core.logger;

import dcore.core;
import dcore.code.knowledge_graph;
import dcore.lang.language_profile;
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
    string referenceType; /// call, import, inheritance, assignment, wiki
    string fromName;      /// enclosing symbol, when the reference sits inside one
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
    private CodeSymbol[][string] _byName;          // bare name -> symbols
    private SymbolReference[][string] _references; // file path -> outgoing references
    private string[][string] _fileSymbols;         // file path -> symbol names
    private string[string] _fileModule;            // file path -> module name
    private string[][string] _pendingBases;        // symbol fqn -> base names
    private KnowledgeGraph _knowledge;

    // File monitoring
    private DateTime[string] _fileTimestamps;      // file path -> last modified
    private string[] _watchedFiles;
    private string[] _indexedRoots;

    // Cache for performance
    private CodeContext[string] _contextCache;     // context key -> cached context
    private Duration _cacheTimeout = 5.minutes;

    /**
     * Constructor
     */
    this(DCore core, LSPManager lspManager) {
        _core = core;
        _lspManager = lspManager;
        _knowledge = new KnowledgeGraph();

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
        if (filePath.length == 0)
            return;
        filePath = buildNormalizedPath(filePath);
        if (_watchedFiles.canFind(filePath))
            return;

        _watchedFiles ~= filePath;

        if (exists(filePath))
            _fileTimestamps[filePath] = cast(DateTime)timeLastModified(filePath);
    }

    /**
     * Reindex one file and the references that originate in it.
     */
    void reindexFile(string filePath) {
        if (filePath.length == 0 || !exists(filePath) || !isFile(filePath))
            return;
        addFileToWatch(filePath);
        dropFile(filePath);
        collectSymbols(filePath);
        resolveReferences(filePath);
        _contextCache.clear();
    }

    /**
     * Index source roots that have not been scanned yet.
     * Returns true when a scan actually ran.
     */
    bool ensureRoots(string[] roots) {
        string[] fresh;
        foreach (root; roots) {
            if (root.length == 0 || !exists(root) || !isDir(root))
                continue;
            string normal = buildNormalizedPath(root);
            if (_indexedRoots.canFind(normal))
                continue;
            _indexedRoots ~= normal;
            fresh ~= normal;
        }
        if (fresh.length == 0 && _symbols.length > 0)
            return false;

        foreach (root; fresh.length ? fresh : roots) {
            if (root.length == 0 || !exists(root))
                continue;
            foreach (file; getSourceFiles(root))
                addFileToWatch(file);
        }
        scanWorkspaceSymbols();
        return true;
    }

    /**
     * Rebuild the symbol index and knowledge graph for the whole workspace.
     */
    void rescan() {
        scanWorkspaceSymbols();
    }

    @property KnowledgeGraph knowledge() {
        return _knowledge;
    }

    string[] knowledgeLinks(string filePath) const {
        return _knowledge ? _knowledge.linksFrom(filePath) : [];
    }

    SymbolReference[] outgoingReferences(string filePath) {
        auto existing = filePath in _references;
        if (existing is null)
            existing = buildNormalizedPath(filePath) in _references;
        return existing ? (*existing).dup : [];
    }

    /// Every recorded reference, so callers and callees can be queried.
    SymbolReference[] allReferences() {
        SymbolReference[] all;
        foreach (refs; _references.byValue)
            all ~= refs;
        return all;
    }

    /**
     * Case-insensitive name search. Exact names come first.
     */
    CodeSymbol[] searchSymbols(string query, int limit = 20) {
        CodeSymbol[] exact;
        CodeSymbol[] partial;
        if (query.length == 0)
            return exact;
        string q = query.toLower();
        foreach (name, symbols; _byName) {
            string lowered = name.toLower();
            bool isExact = lowered == q;
            bool isPartial = !isExact && lowered.indexOf(q) >= 0;
            if (!isExact && !isPartial)
                continue;
            foreach (symbol; symbols) {
                if (isExact)
                    exact ~= symbol;
                else
                    partial ~= symbol;
            }
        }
        CodeSymbol[] results = exact ~ partial;
        if (results.length > limit)
            results = results[0 .. limit];
        return results;
    }

    string[] symbolNames() {
        return _byName.keys.dup;
    }

    CodeSymbol[] symbolsNamed(string name) {
        auto existing = name in _byName;
        return existing ? (*existing).dup : [];
    }

    /**
     * Get source files in a directory recursively
     */
    private string[] getSourceFiles(string dirPath) {
        string[] files;
        if (!exists(dirPath) || !isDir(dirPath))
            return files;

        try {
            walkSources(dirPath, files);
        } catch (Exception e) {
            Log.w("SymbolTracker: Error scanning directory ", dirPath, ": ", e.msg);
        }
        return files;
    }

    private void walkSources(string dirPath, ref string[] files) {
        if (files.length >= 4000)
            return;
        DirEntry[] dirs;
        foreach (DirEntry entry; dirEntries(dirPath, SpanMode.shallow)) {
            string name = baseName(entry.name);
            if (entry.isDir) {
                if (!skipIndexDir(name))
                    dirs ~= entry;
            } else if (entry.isFile && shouldIndex(entry.name)) {
                files ~= buildNormalizedPath(entry.name);
                if (files.length >= 4000)
                    return;
            }
        }
        dirs.sort!((a, b) => dirRank(baseName(a.name)) < dirRank(baseName(b.name)));
        foreach (dir; dirs)
            walkSources(dir.name, files);
    }

    private static int dirRank(string name) {
        switch (name) {
            case "lib":
            case "src":
            case "source":
            case "app":
            case "test":
            case "tests":
                return 0;
            default:
                return 1;
        }
    }

    private static bool skipIndexDir(string name) {
        if (name.startsWith("."))
            return true;
        switch (name) {
            case "node_modules":
            case "stash":
            case "__pycache__":
            case "_build":
            case "deps":
            case "ebin":
            case "_checkouts":
            case "target":
            case "vendor":
            case "bower_components":
            case "dist":
            case "coverage":
                return true;
            default:
                return false;
        }
    }

    private bool shouldIndex(string filePath) {
        if (!isSourceFile(filePath))
            return false;
        string lang = detectLanguage(filePath);
        return lang != "json" && lang != "toml";
    }

    /**
     * Check if a file is a source file
     */
    private bool isSourceFile(string filePath) {
        return dcore.lang.language_profile.isSourceFile(filePath);
    }

    /**
     * Request symbols for a file from LSP
     */
    private void requestSymbolsForFile(string filePath) {
        collectSymbols(filePath);
        resolveReferences(filePath);
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
            auto references = _lspManager.getReferences(filePath, symbol.range.start.line, symbol.range.start.character);
            // TODO: Fix updateSymbolReferences signature - expects DocumentSymbol but gets JSONValue
            // updateSymbolReferences(filePath, symbol, references);
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
            // TODO: Fix LocationInfo structure - it doesn't have range property
            // symbolRef.location = location.range;
            symbolRef.filePath = location.uri;
            // TODO: Fix LocationInfo structure access
            // symbolRef.contextLine = getContextLine(location.uri, location.range.start.line);
            symbolRef.isDefinition = (location.uri == filePath &&
                              // TODO: Fix LocationInfo.range access
                              false); // location.range.start.line == symbol.range.start.line);
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

        _symbols.clear();
        _byName.clear();
        _references.clear();
        _fileSymbols.clear();
        _fileModule.clear();
        _pendingBases.clear();
        _contextCache.clear();
        if (_knowledge)
            _knowledge.clear();

        foreach (filePath; _watchedFiles)
            collectSymbols(filePath);
        foreach (filePath; _watchedFiles)
            resolveReferences(filePath);

        foreach (filePath; _watchedFiles) {
            if (exists(filePath))
                _fileTimestamps[filePath] = cast(DateTime)timeLastModified(filePath);
        }

        Log.i("SymbolTracker: Workspace scan complete — ",
              _symbols.length, " symbols, ",
              _watchedFiles.length, " files");
    }

    /**
     * Check if a file has changed since last scan
     */
    private bool hasFileChanged(string filePath) {
        if (!exists(filePath))
            return false;

        auto currentTime = cast(DateTime)timeLastModified(filePath);
        auto lastTime = _fileTimestamps.get(filePath, DateTime.min);

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
        if (filePath.length == 0)
            return results;

        auto listed = filePath in _fileSymbols;
        if (listed is null)
            listed = buildNormalizedPath(filePath) in _fileSymbols;
        if (listed is null)
            return results;

        foreach (symbolName; *listed) {
            if (symbolName in _symbols)
                results ~= _symbols[symbolName];
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
        return dcore.lang.language_profile.detectLanguage(filePath);
    }

    /**
     * Symbols named in a prompt, plus their parents, children, and callees.
     * Mirrors the Python SymbolManager.get_relevant_symbols neighbourhood.
     */
    CodeSymbol[] getRelevantSymbols(string prompt, int limit = 12) {
        if (prompt.length == 0 || _byName.length == 0)
            return [];

        bool[string] seen;
        CodeSymbol[] results;

        void consider(CodeSymbol symbol) {
            if (symbol.fullyQualifiedName.length == 0)
                return;
            if (symbol.fullyQualifiedName in seen)
                return;
            if (results.length >= limit)
                return;
            seen[symbol.fullyQualifiedName] = true;
            results ~= symbol;
        }

        string lowered = prompt.toLower();
        foreach (name, symbols; _byName) {
            if (name.length < 3)
                continue;
            if (lowered.indexOf(name.toLower()) < 0)
                continue;
            foreach (symbol; symbols) {
                consider(symbol);
                if (symbol.containerName.length && symbol.containerName in _symbols)
                    consider(_symbols[symbol.containerName]);
                foreach (child; childrenOf(symbol.fullyQualifiedName))
                    consider(child);
                foreach (ref r; getReferences(symbol.name)) {
                    if (r.referenceType == "call" || r.referenceType == "inheritance"
                            || r.referenceType == "import")
                        consider(r.symbol);
                }
            }
        }
        return results;
    }

    /**
     * Short text the assistant can read: definitions, edges, and note links.
     */
    string formatNeighborhood(string prompt, string[] files) {
        string[] lines;
        auto relevant = getRelevantSymbols(prompt, 10);
        if (relevant.length) {
            lines ~= "Symbols mentioned:";
            foreach (symbol; relevant) {
                string sig = symbol.signature.length ? symbol.signature : symbol.name;
                lines ~= format("  %s %s — %s:%d",
                    kindLabel(symbol.kind), sig,
                    baseName(symbol.filePath), symbol.location.start.line + 1);
                int shown = 0;
                foreach (ref r; outgoingReferences(symbol.filePath)) {
                    if (r.fromName != symbol.fullyQualifiedName && r.fromName != symbol.name)
                        continue;
                    if (r.symbol.name.length == 0)
                        continue;
                    lines ~= format("    %s %s (%s)",
                        r.referenceType.length ? r.referenceType : "uses",
                        r.symbol.name,
                        baseName(r.filePath));
                    if (++shown >= 4)
                        break;
                }
            }
        }

        foreach (filePath; files) {
            auto links = knowledgeLinks(filePath);
            auto backs = _knowledge ? _knowledge.backlinks(filePath) : [];
            auto tags = _knowledge ? _knowledge.tags(filePath) : [];
            if (links.length == 0 && backs.length == 0 && tags.length == 0)
                continue;
            lines ~= "Notes for " ~ baseName(filePath) ~ ":";
            if (tags.length)
                lines ~= "  tags: " ~ tags.join(", ");
            foreach (link; links.take(8))
                lines ~= "  links to " ~ baseName(link);
            foreach (back; backs.take(8))
                lines ~= "  linked from " ~ baseName(back);
        }

        return lines.join("\n");
    }

    CodeSymbol[] childrenOf(string fqn) {
        CodeSymbol[] children;
        foreach (symbol; _symbols.byValue) {
            if (symbol.containerName == fqn)
                children ~= symbol;
        }
        return children;
    }

    private void dropFile(string filePath) {
        if (filePath in _fileSymbols) {
            foreach (fqn; _fileSymbols[filePath]) {
                if (fqn in _symbols) {
                    string name = _symbols[fqn].name;
                    _symbols.remove(fqn);
                    if (name in _byName) {
                        _byName[name] = _byName[name].filter!(s => s.fullyQualifiedName != fqn).array;
                        if (_byName[name].length == 0)
                            _byName.remove(name);
                    }
                }
            }
        }
        _fileSymbols.remove(filePath);
        _references.remove(filePath);
        _fileModule.remove(filePath);
    }

    private void collectSymbols(string filePath) {
        if (!exists(filePath) || !isFile(filePath))
            return;
        try {
            if (getSize(filePath) > 1_048_576)
                return;
            string content = readText(filePath);
            string language = detectLanguage(filePath);
            if (language == "markdown")
                indexNote(filePath, content);
            else
                indexSource(filePath, content, language);
        } catch (Exception e) {
            Log.w("SymbolTracker: parse failed for ", filePath, ": ", e.msg);
        }
    }

    private void indexNote(string filePath, string content) {
        auto note = makeSymbol(baseName(filePath), filePath, SymbolKind.File, 0, 0, "", "");
        remember(note);

        auto wikiRe = regex(`\[\[([^\]|#]+)(?:[#|][^\]]*)?\]\]`);
        foreach (match; content.matchAll(wikiRe)) {
            string target = match[1].strip();
            if (target.length == 0)
                continue;
            _knowledge.addLink(filePath, target);
            addOutgoing(filePath, note, target, "wiki", 0, match.hit);
        }
        auto tagRe = regex(`(?:^|\s)#([A-Za-z_][\w-]*)`);
        foreach (match; content.matchAll(tagRe))
            _knowledge.addTag(filePath, match[1]);
        auto atRe = regex(`(?:^|\s)@([A-Za-z_][\w-]*)`);
        foreach (match; content.matchAll(atRe))
            _knowledge.addReference(filePath, match[1]);
    }

    private void indexSource(string filePath, string content, string language) {
        string moduleName = baseName(stripExtension(filePath));
        auto lines = content.splitLines();
        bool pythonLike = language == "python" || language == "ruby"
            || language == "elixir" || language == "lua" || language == "shellscript";

        static struct Frame {
            int depth;
            string fqn;
        }
        Frame[] stack;
        string container;
        bool pending;
        string pendingFqn;
        int depth;

        void applyBraces(string text) {
            foreach (ch; text) {
                if (ch == '{') {
                    depth++;
                    if (pending) {
                        stack ~= Frame(depth, pendingFqn);
                        container = pendingFqn;
                        pending = false;
                    }
                } else if (ch == '}') {
                    if (depth > 0)
                        depth--;
                    while (stack.length && stack[$ - 1].depth > depth)
                        stack = stack[0 .. $ - 1];
                    container = stack.length ? stack[$ - 1].fqn : "";
                }
            }
        }

        foreach (i, line; lines) {
            string stripped = stripCodeComment(line, language).strip();
            if (stripped.length == 0)
                continue;

            if (!pythonLike && stripped.startsWith("module ") && stripped.endsWith(";")) {
                moduleName = stripped[7 .. $ - 1].strip();
                continue;
            }

            int indent = 0;
            while (indent < cast(int)line.length && line[indent] == ' ')
                indent++;

            if (pythonLike) {
                while (stack.length && indent <= stack[$ - 1].depth)
                    stack = stack[0 .. $ - 1];
                container = stack.length ? stack[$ - 1].fqn : "";
            }

            string kindWord, name, bases;
            bool isFunc;
            if (!matchDeclaration(language, stripped, kindWord, name, bases, isFunc)) {
                if (!pythonLike)
                    applyBraces(stripped);
                continue;
            }

            string fqn = container.length ? container ~ "." ~ name : moduleName ~ "." ~ name;
            SymbolKind kind = kindFromWord(kindWord, isFunc);
            auto symbol = makeSymbol(name, filePath, kind, cast(int)i, indent, container, stripped);
            symbol.fullyQualifiedName = fqn;
            remember(symbol);

            if (bases.length) {
                foreach (part; bases.split(",")) {
                    string base = firstToken(part);
                    auto bang = base.indexOf("!");
                    if (bang > 0)
                        base = base[0 .. bang];
                    if (base.length >= 2)
                        _pendingBases[fqn] ~= base;
                }
            }

            if (pythonLike) {
                stack ~= Frame(indent, isFunc ? container : fqn);
                if (!isFunc)
                    container = fqn;
            } else {
                if (!stripped.endsWith(";")) {
                    pending = true;
                    pendingFqn = isFunc ? container : fqn;
                }
                applyBraces(stripped);
            }
        }

        _fileModule[filePath] = moduleName;
    }

    private void resolveReferences(string filePath) {
        if (!exists(filePath) || detectLanguage(filePath) == "markdown")
            return;
        try {
            if (getSize(filePath) > 1_048_576)
                return;
            auto lines = readText(filePath).splitLines();
            string language = detectLanguage(filePath);
            auto callRe = regex(`\b([A-Za-z_]\w{1,})\s*\(`);
            int budget = 160;

            if (auto bases = filePath in _fileSymbols) {
                foreach (fqn; *bases) {
                    auto listed = fqn in _pendingBases;
                    if (listed is null || fqn !in _symbols)
                        continue;
                    foreach (base; *listed) {
                        if (base !in _byName)
                            continue;
                        auto target = pickSymbol(_byName[base], filePath);
                        addRef(filePath, _symbols[fqn], target, "inheritance",
                            _symbols[fqn].location.start.line, _symbols[fqn].signature, false);
                        _knowledge.addLink(filePath, target.filePath);
                    }
                }
            }

            foreach (i, line; lines) {
                string stripped = stripCodeComment(line, language).strip();
                if (stripped.length == 0)
                    continue;

                if (language == "d" && stripped.startsWith("import ") && stripped.endsWith(";")) {
                    string spec = stripped[7 .. $ - 1].strip();
                    auto colon = spec.indexOf(":");
                    if (colon >= 0)
                        spec = spec[0 .. colon].strip();
                    noteImport(filePath, spec, cast(int)i, stripped);
                } else if (language == "python" && (stripped.startsWith("import ") || stripped.startsWith("from "))) {
                    notePythonImport(filePath, stripped, cast(int)i);
                }

                if (budget <= 0)
                    continue;
                foreach (match; stripped.matchAll(callRe)) {
                    string callee = match[1];
                    if (isKeyword(callee) || callee !in _byName)
                        continue;
                    auto target = pickSymbol(_byName[callee], filePath);
                    auto from = enclosingSymbol(filePath, cast(int)i);
                    addRef(filePath, from, target, "call", cast(int)i, stripped, false);
                    if (--budget <= 0)
                        break;
                }
            }
        } catch (Exception e) {
            Log.w("SymbolTracker: references failed for ", filePath, ": ", e.msg);
        }
    }

    private void noteImport(string filePath, string spec, int line, string context) {
        string leaf = spec;
        auto dot = spec.lastIndexOf(".");
        if (dot >= 0)
            leaf = spec[dot + 1 .. $];
        string targetFile;
        foreach (path, moduleName; _fileModule) {
            if (moduleName == spec || moduleName == leaf || baseName(stripExtension(path)) == leaf) {
                targetFile = path;
                break;
            }
        }
        if (targetFile.length)
            _knowledge.addLink(filePath, targetFile);
        if (leaf in _byName) {
            auto target = pickSymbol(_byName[leaf], filePath);
            auto from = makeSymbol(baseName(filePath), filePath, SymbolKind.File, line, 0, "", "");
            addRef(filePath, from, target, "import", line, context, false);
        } else if (targetFile.length) {
            auto from = makeSymbol(baseName(filePath), filePath, SymbolKind.File, line, 0, "", "");
            auto target = makeSymbol(leaf, targetFile, SymbolKind.Module, 0, 0, "", spec);
            addRef(filePath, from, target, "import", line, context, false);
        }
    }

    private void notePythonImport(string filePath, string stripped, int line) {
        auto fromRe = regex(`^from\s+([\w.]+)\s+import\s+(.+)$`);
        auto m = stripped.matchFirst(fromRe);
        if (!m.empty) {
            foreach (part; m[2].split(",")) {
                string name = firstToken(part);
                if (name.length && name != "*" && name != "(")
                    noteImport(filePath, name, line, stripped);
            }
            return;
        }
        if (stripped.startsWith("import ")) {
            string spec = firstToken(stripped[7 .. $]);
            if (spec.length)
                noteImport(filePath, spec, line, stripped);
        }
    }

    private void addOutgoing(string filePath, CodeSymbol from, string targetName,
            string referenceType, int line, string context) {
        CodeSymbol target;
        target.name = targetName;
        target.fullyQualifiedName = targetName;
        target.filePath = targetName;
        target.kind = SymbolKind.File;
        addRef(filePath, from, target, referenceType, line, context, false);
    }

    private void addRef(string filePath, CodeSymbol from, CodeSymbol target,
            string referenceType, int line, string context, bool isDefinition) {
        SymbolReference symbolRef;
        symbolRef.symbol = target;
        symbolRef.filePath = filePath;
        symbolRef.location = Range(Position(line, 0), Position(line, 0));
        symbolRef.contextLine = context.length > 180 ? context[0 .. 180] : context;
        symbolRef.isDefinition = isDefinition;
        symbolRef.referenceType = referenceType;
        symbolRef.fromName = from.fullyQualifiedName.length ? from.fullyQualifiedName : from.name;
        symbolRef.timestamp = cast(DateTime)Clock.currTime();
        _references[filePath] ~= symbolRef;
    }

    private CodeSymbol enclosingSymbol(string filePath, int line) {
        CodeSymbol best;
        int bestLine = -1;
        if (filePath !in _fileSymbols)
            return best;
        foreach (fqn; _fileSymbols[filePath]) {
            if (fqn !in _symbols)
                continue;
            auto symbol = _symbols[fqn];
            int start = symbol.location.start.line;
            if (start <= line && start >= bestLine && symbol.kind != SymbolKind.File) {
                best = symbol;
                bestLine = start;
            }
        }
        return best;
    }

    private static CodeSymbol pickSymbol(CodeSymbol[] options, string preferFile) {
        foreach (symbol; options)
            if (symbol.filePath == preferFile)
                return symbol;
        return options[0];
    }

    private void remember(CodeSymbol symbol) {
        _symbols[symbol.fullyQualifiedName] = symbol;
        _fileSymbols[symbol.filePath] ~= symbol.fullyQualifiedName;
        _byName[symbol.name] ~= symbol;
    }

    private static CodeSymbol makeSymbol(string name, string filePath, SymbolKind kind,
            int line, int column, string container, string signature) {
        CodeSymbol symbol;
        symbol.name = name;
        symbol.filePath = filePath;
        symbol.fullyQualifiedName = name;
        symbol.kind = kind;
        symbol.location = Range(Position(line, column), Position(line, column));
        symbol.containerName = container;
        symbol.signature = signature.length > 160 ? signature[0 .. 160] : signature;
        symbol.isPublic = true;
        symbol.lastModified = cast(DateTime)Clock.currTime();
        return symbol;
    }

    private static string firstToken(string text) {
        text = text.strip();
        if (text.length == 0)
            return "";
        auto space = text.indexOf(' ');
        return space < 0 ? text : text[0 .. space];
    }

    private static bool matchDeclaration(string language, string stripped,
            ref string kindWord, ref string name, ref string bases, ref bool isFunc) {
        kindWord = "";
        name = "";
        bases = "";
        isFunc = false;

        if (language == "python") {
            auto classMatch = stripped.matchFirst(regex(`^class\s+(\w+)\s*(?:\(([^)]*)\))?`));
            if (!classMatch.empty) {
                kindWord = "class";
                name = classMatch[1];
                bases = classMatch[2];
                return true;
            }
            auto defMatch = stripped.matchFirst(regex(`^def\s+(\w+)`));
            if (!defMatch.empty) {
                kindWord = "def";
                name = defMatch[1];
                isFunc = true;
                return true;
            }
            return false;
        }

        if (language == "ruby") {
            auto classMatch = stripped.matchFirst(regex(`^class\s+(\w+)`));
            if (!classMatch.empty) {
                kindWord = "class";
                name = classMatch[1];
                return true;
            }
            auto defMatch = stripped.matchFirst(regex(`^def\s+(?:self\.)?(\w+)`));
            if (!defMatch.empty) {
                kindWord = "def";
                name = defMatch[1];
                isFunc = true;
                return true;
            }
            return false;
        }

        if (language == "elixir") {
            auto modMatch = stripped.matchFirst(regex(`^defmodule\s+([A-Za-z_][\w.]*)`));
            if (!modMatch.empty) {
                kindWord = "defmodule";
                name = modMatch[1];
                return true;
            }
            auto defMatch = stripped.matchFirst(regex(
                `^(?:def|defp|defmacro|defmacrop|defguard|defguardp)\s+([A-Za-z_][\w!?]*|[\+\-\*\/=!<>]+)`));
            if (!defMatch.empty) {
                kindWord = "def";
                name = defMatch[1];
                isFunc = true;
                return true;
            }
            return false;
        }

        auto typeMatch = stripped.matchFirst(regex(
            `^(?:[\w@]+\s+)*(class|struct|interface|enum|union|trait|impl|type|object)\s+(\w+)\s*(?:\([^)]*\))?\s*(?::\s*([^{]+))?`));
        if (!typeMatch.empty && !stripped.endsWith(";")) {
            kindWord = typeMatch[1];
            name = typeMatch[2];
            bases = typeMatch[3].strip();
            if (bases.endsWith("{"))
                bases = bases[0 .. $ - 1].strip();
            return name.length > 0;
        }

        if (language == "go") {
            auto goFn = stripped.matchFirst(regex(`^func\s+(?:\([^)]*\)\s+)?(\w+)\s*\(`));
            if (!goFn.empty) {
                kindWord = "func";
                name = goFn[1];
                isFunc = true;
                return true;
            }
        }
        if (language == "rust") {
            auto rustFn = stripped.matchFirst(regex(`^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?fn\s+(\w+)\s*[<(]`));
            if (!rustFn.empty) {
                kindWord = "fn";
                name = rustFn[1];
                isFunc = true;
                return true;
            }
        }

        auto fnMatch = stripped.matchFirst(regex(
            `^(?:(?:public|private|protected|package|export|extern|static|final|abstract|override|nothrow|pure|const|immutable|shared|inout|scope|deprecated|async|unsafe|pub|virtual|internal|inline|constexpr|friend|explicit|def|fun|function|fn|func|sub|local|@\w+)\s+)*([A-Za-z_][\w!:.<>,\[\]*]*\s+)+([A-Za-z_]\w*)\s*\(`));
        if (fnMatch.empty)
            return false;
        name = fnMatch[2];
        if (isKeyword(name) || stripped.endsWith(";"))
            return false;
        kindWord = "function";
        isFunc = true;
        return true;
    }

    private static SymbolKind kindFromWord(string word, bool isFunc) {
        if (isFunc)
            return SymbolKind.Function;
        switch (word) {
            case "class": return SymbolKind.Class;
            case "struct": return SymbolKind.Struct;
            case "interface":
            case "trait": return SymbolKind.Interface;
            case "enum": return SymbolKind.Enum;
            case "impl":
            case "object": return SymbolKind.Class;
            case "defmodule": return SymbolKind.Module;
            default: return SymbolKind.Class;
        }
    }

    private static string kindLabel(SymbolKind kind) {
        final switch (kind) {
            case SymbolKind.File: return "file";
            case SymbolKind.Module: return "module";
            case SymbolKind.Namespace: return "namespace";
            case SymbolKind.Package: return "package";
            case SymbolKind.Class: return "class";
            case SymbolKind.Method: return "method";
            case SymbolKind.Property: return "property";
            case SymbolKind.Field: return "field";
            case SymbolKind.Constructor: return "constructor";
            case SymbolKind.Enum: return "enum";
            case SymbolKind.Interface: return "interface";
            case SymbolKind.Function: return "function";
            case SymbolKind.Variable: return "variable";
            case SymbolKind.Constant: return "constant";
            case SymbolKind.String: return "string";
            case SymbolKind.Number: return "number";
            case SymbolKind.Boolean: return "boolean";
            case SymbolKind.Array: return "array";
            case SymbolKind.Object: return "object";
            case SymbolKind.Key: return "key";
            case SymbolKind.Null: return "null";
            case SymbolKind.EnumMember: return "enum member";
            case SymbolKind.Struct: return "struct";
            case SymbolKind.Event: return "event";
            case SymbolKind.Operator: return "operator";
            case SymbolKind.TypeParameter: return "type";
        }
    }

    private static bool isKeyword(string name) {
        switch (name) {
            case "if":
            case "while":
            case "for":
            case "foreach":
            case "foreach_reverse":
            case "switch":
            case "catch":
            case "scope":
            case "with":
            case "version":
            case "debug":
            case "mixin":
            case "assert":
            case "static":
            case "return":
            case "new":
            case "delete":
            case "cast":
            case "pragma":
            case "unittest":
            case "invariant":
            case "else":
            case "do":
            case "synchronized":
            case "try":
            case "finally":
            case "import":
            case "module":
            case "function":
            case "delegate":
                return true;
            default:
                return false;
        }
    }

    private static string stripCodeComment(string line, string language) {
        string mark = language == "python" || language == "ruby" || language == "shellscript"
            || language == "elixir" || language == "toml" ? "#" : "//";
        if (language == "lua")
            mark = "--";
        auto at = line.indexOf(mark);
        if (at < 0)
            return line;
        return line[0 .. at];
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
