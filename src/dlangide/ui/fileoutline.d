module dlangide.ui.fileoutline;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.tree;
import dlangui.widgets.editors;
import dlangui.widgets.menu;
import dlangui.widgets.popup;
import dlangui.core.events;
import dlangui.core.signals;
import dlangui.graphics.drawbuf;
import dlangui.graphics.resources;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.utf;
import std.json;
import std.stdio;
import std.regex;
import std.typecons;
import std.datetime;
import std.format;

import dcore.editor.document;
import dlangide.ui.inlinediffeditor;

/// Represents a symbol in the file outline
struct FileSymbol {
    string name;           // Symbol name (function name, class name, etc.)
    SymbolType type;       // Type of symbol
    int startLine;         // Starting line number (0-based)
    int endLine;           // Ending line number (0-based)
    int startColumn;       // Starting column (0-based)
    int endColumn;         // Ending column (0-based)
    string signature;      // Full signature/declaration
    string returnType;     // Return type for functions
    string[] parameters;   // Parameter list for functions
    string[] modifiers;    // Access modifiers, static, etc.
    string docComment;     // Documentation comment
    FileSymbol[] children; // Nested symbols
    FileSymbol* parent;    // Parent symbol
    bool isExpanded;       // UI state for tree view
    bool hasChanges;       // True if symbol has pending changes
    double aiConfidence;   // AI confidence score for symbol quality
}

/// Types of symbols that can be displayed in outline
enum SymbolType {
    Unknown,
    Module,
    Import,
    Class,
    Interface,
    Struct,
    Enum,
    Function,
    Method,
    Property,
    Field,
    Variable,
    Constant,
    Constructor,
    Destructor,
    Operator,
    Template,
    Mixin,
    Alias,
    Comment,
    Region
}

/// Configuration for file outline parsing
struct OutlineConfig {
    bool showPrivateMembers = false;
    bool showImports = true;
    bool showComments = false;
    bool showVariables = true;
    bool groupByType = false;
    bool sortAlphabetically = false;
    bool showLineNumbers = true;
    bool showParameters = true;
    bool showReturnTypes = true;
    bool highlightChanges = true;
    string[] languageExtensions = [".d", ".di"];
}

/// File outline widget providing hierarchical code structure view
class FileOutlineWidget : VerticalLayout {
    private {
        // UI Components
        HorizontalLayout _toolbar;
        TreeWidget _outlineTree;
        ScrollWidget _scrollArea;

        // Toolbar controls
        Button _refreshBtn;
        Button _expandAllBtn;
        Button _collapseAllBtn;
        Button _settingsBtn;
        ComboBox _sortCombo;
        CheckBox _showPrivateCheck;
        EditLine _searchField;

        // Data
        FileSymbol[] _symbols;
        FileSymbol[] _filteredSymbols;
        OutlineConfig _config;
        string _currentFilePath;
        InlineDiffEditor _currentEditor;

        // Search and filtering
        string _searchQuery;
        bool _caseSensitiveSearch = false;

        // Language parsers
        LanguageParser[string] _parsers;

        // Update tracking
        SysTime _lastUpdateTime;
        bool _needsRefresh = false;
    }

    // Events
    Signal!(FileSymbol) onSymbolSelected;
    Signal!(FileSymbol) onSymbolDoubleClicked;
    Signal!(FileSymbol, string) onSymbolRenamed;
    Signal!(FileSymbol[]) onOutlineUpdated;

    this() {
        super("fileOutline");
        _config = OutlineConfig();
        initializeParsers();
        createUI();
        setupEventHandlers();
    }

    private void createUI() {
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        margins = Rect(4, 4, 4, 4);

        // Create toolbar
        createToolbar();
        addChild(_toolbar);

        // Create tree view
        createOutlineTree();

        // Wrap tree in scroll area
        _scrollArea = new ScrollWidget("outlineScroll");
        _scrollArea.layoutWidth = FILL_PARENT;
        _scrollArea.layoutHeight = FILL_PARENT;
        _scrollArea.contentWidget = _outlineTree;
        addChild(_scrollArea);
    }

    private void createToolbar() {
        _toolbar = new HorizontalLayout("outlineToolbar");
        _toolbar.layoutWidth = FILL_PARENT;
        _toolbar.layoutHeight = WRAP_CONTENT;
        _toolbar.backgroundColor = 0xFFF0F0F0;
        _toolbar.padding = Rect(2, 2, 2, 2);

        // Refresh button
        _refreshBtn = new Button("refresh", "🔄"d);
        _refreshBtn.tooltipText = "Refresh outline"d;
        _refreshBtn.minWidth = 30;
        _toolbar.addChild(_refreshBtn);

        // Expand/Collapse buttons
        _expandAllBtn = new Button("expandAll", "⊞"d);
        _expandAllBtn.tooltipText = "Expand all"d;
        _expandAllBtn.minWidth = 30;
        _toolbar.addChild(_expandAllBtn);

        _collapseAllBtn = new Button("collapseAll", "⊟"d);
        _collapseAllBtn.tooltipText = "Collapse all"d;
        _collapseAllBtn.minWidth = 30;
        _toolbar.addChild(_collapseAllBtn);

        // Sort options
        _sortCombo = new ComboBox("sortCombo",
            ["Source Order"d, "Alphabetical"d, "By Type"d]);
        _sortCombo.minWidth = 100;
        _toolbar.addChild(_sortCombo);

        // Show private checkbox
        _showPrivateCheck = new CheckBox("showPrivate", "Private"d);
        _showPrivateCheck.tooltipText = "Show private members"d;
        _toolbar.addChild(_showPrivateCheck);

        // Search field
        _searchField = new EditLine("search");
        _searchField.hint = "Search symbols..."d;
        _searchField.layoutWidth = FILL_PARENT;
        _toolbar.addChild(_searchField);

        // Settings button
        _settingsBtn = new Button("settings", "⚙"d);
        _settingsBtn.tooltipText = "Outline settings"d;
        _settingsBtn.minWidth = 30;
        _toolbar.addChild(_settingsBtn);
    }

    private void createOutlineTree() {
        _outlineTree = new TreeWidget("outlineTree");
        _outlineTree.layoutWidth = FILL_PARENT;
        _outlineTree.layoutHeight = FILL_PARENT;

        // Configure tree appearance
        _outlineTree.showRoot = false;
        _outlineTree.allowMultipleSelection = false;
    }

    private void setupEventHandlers() {
        // Toolbar button handlers
        _refreshBtn.click = delegate(Widget source) {
            refreshOutline();
            return true;
        };

        _expandAllBtn.click = delegate(Widget source) {
            expandAll();
            return true;
        };

        _collapseAllBtn.click = delegate(Widget source) {
            collapseAll();
            return true;
        };

        _settingsBtn.click = delegate(Widget source) {
            showSettingsDialog();
            return true;
        };

        // Sort combo handler
        _sortCombo.onSelectionChange = delegate(Widget source, int itemIndex) {
            updateSortMode(itemIndex);
            return true;
        };

        // Show private checkbox
        _showPrivateCheck.checkChange = delegate(Widget source, bool checked) {
            _config.showPrivateMembers = checked;
            refreshOutline();
            return true;
        };

        // Search field handler
        _searchField.onContentChange = delegate(EditableContent source) {
            _searchQuery = _searchField.text.toUTF8();
            filterSymbols();
            return true;
        };

        // Tree selection handler
        _outlineTree.onItemSelected = delegate(TreeWidget source, TreeItem item) {
            if (item && item.tag) {
                auto symbol = cast(FileSymbol*)item.tag;
                if (symbol && onSymbolSelected.assigned) {
                    onSymbolSelected(*symbol);
                }
            }
            return true;
        };

        // Tree double-click handler
        _outlineTree.onItemDoubleClicked = delegate(TreeWidget source, TreeItem item) {
            if (item && item.tag) {
                auto symbol = cast(FileSymbol*)item.tag;
                if (symbol && onSymbolDoubleClicked.assigned) {
                    onSymbolDoubleClicked(*symbol);
                }
            }
            return true;
        };
    }

    private void initializeParsers() {
        // Initialize language-specific parsers
        _parsers["d"] = new DLanguageParser();
        _parsers["di"] = new DLanguageParser();
        _parsers["py"] = new PythonParser();
        _parsers["js"] = new JavaScriptParser();
        _parsers["ts"] = new TypeScriptParser();
        _parsers["c"] = new CParser();
        _parsers["cpp"] = new CppParser();
        _parsers["h"] = new CParser();
        _parsers["hpp"] = new CppParser();
    }

    /// Update outline for specific file
    void updateFileOutline(string filePath, InlineDiffEditor editor = null) {
        _currentFilePath = filePath;
        _currentEditor = editor;

        if (!exists(filePath)) {
            clearOutline();
            return;
        }

        try {
            string content = readText(filePath);
            updateContentOutline(content, filePath);
        } catch (Exception e) {
            writeln("Error reading file for outline: ", e.msg);
            clearOutline();
        }
    }

    /// Update outline from editor content
    void updateContentOutline(string content, string filePath = null) {
        if (filePath) _currentFilePath = filePath;

        string fileExt = filePath ? extension(filePath).toLower() : ".d";
        if (fileExt.startsWith(".")) fileExt = fileExt[1..$];

        auto parser = fileExt in _parsers;
        if (!parser) {
            // Use generic parser for unknown file types
            _symbols = parseGeneric(content);
        } else {
            _symbols = parser.parseFile(content, _config);
        }

        // Post-process symbols
        postProcessSymbols(_symbols);

        // Apply current filters
        filterSymbols();

        _lastUpdateTime = Clock.currTime();
        _needsRefresh = false;

        if (onOutlineUpdated.assigned) {
            onOutlineUpdated(_symbols);
        }
    }

    /// Refresh outline from current editor
    void refreshOutline() {
        if (_currentEditor) {
            string content = _currentEditor.content;
            updateContentOutline(content, _currentFilePath);
        } else if (_currentFilePath && exists(_currentFilePath)) {
            updateFileOutline(_currentFilePath);
        }
    }

    /// Navigate to specific symbol in editor
    void navigateToSymbol(FileSymbol symbol) {
        if (_currentEditor) {
            // Navigate to symbol location in editor
            // _currentEditor.scrollToLine(symbol.startLine);
            // _currentEditor.setCursorPosition(symbol.startLine, symbol.startColumn);
        }
    }

    /// Find symbol at specific line
    FileSymbol* findSymbolAtLine(int lineNumber) {
        return findSymbolAtLineRecursive(_symbols, lineNumber);
    }

    private FileSymbol* findSymbolAtLineRecursive(FileSymbol[] symbols, int lineNumber) {
        foreach (ref symbol; symbols) {
            if (lineNumber >= symbol.startLine && lineNumber <= symbol.endLine) {
                // Check children first (more specific matches)
                auto childMatch = findSymbolAtLineRecursive(symbol.children, lineNumber);
                if (childMatch) return childMatch;
                return &symbol;
            }
        }
        return null;
    }

    /// Highlight symbols with pending changes
    void highlightChangedSymbols(InlineChange[] changes) {
        if (!_config.highlightChanges) return;

        // Clear previous highlights
        clearHighlights(_symbols);

        // Apply new highlights
        foreach (change; changes) {
            auto symbol = findSymbolAtLine(change.startLine);
            if (symbol) {
                symbol.hasChanges = true;
            }
        }

        // Update tree display
        updateTreeDisplay();
    }

    private void clearHighlights(FileSymbol[] symbols) {
        foreach (ref symbol; symbols) {
            symbol.hasChanges = false;
            clearHighlights(symbol.children);
        }
    }

    private void postProcessSymbols(FileSymbol[] symbols) {
        foreach (ref symbol; symbols) {
            // Set parent references
            foreach (ref child; symbol.children) {
                child.parent = &symbol;
            }

            // Calculate AI confidence scores
            symbol.aiConfidence = calculateSymbolQuality(symbol);

            // Recursively process children
            postProcessSymbols(symbol.children);
        }
    }

    private double calculateSymbolQuality(FileSymbol symbol) {
        double score = 0.5; // Base score

        // Bonus for documentation
        if (symbol.docComment.length > 0) score += 0.2;

        // Bonus for descriptive names
        if (symbol.name.length > 3) score += 0.1;
        if (symbol.name.canFind("_")) score += 0.05; // Snake case

        // Penalty for very short names (except common ones)
        if (symbol.name.length <= 2 && !["i", "j", "k", "x", "y", "z"].canFind(symbol.name)) {
            score -= 0.2;
        }

        // Type-specific adjustments
        final switch (symbol.type) {
            case SymbolType.Class:
            case SymbolType.Interface:
                if (symbol.children.length == 0) score -= 0.1; // Empty class
                break;
            case SymbolType.Function:
            case SymbolType.Method:
                if (symbol.parameters.length == 0 && symbol.returnType.empty) score -= 0.1;
                if (symbol.returnType == "void" && symbol.parameters.length == 0) score -= 0.05;
                break;
            case SymbolType.Variable:
                if (symbol.name.startsWith("temp") || symbol.name.startsWith("tmp")) score -= 0.1;
                break;
            case SymbolType.Unknown:
                score -= 0.3;
                break;
            default:
                break;
        }

        return clamp(score, 0.0, 1.0);
    }

    private void filterSymbols() {
        if (_searchQuery.empty && _config.showPrivateMembers) {
            _filteredSymbols = _symbols;
        } else {
            _filteredSymbols = filterSymbolsRecursive(_symbols);
        }

        // Apply sorting
        applySorting(_filteredSymbols);

        // Update tree display
        updateTreeDisplay();
    }

    private FileSymbol[] filterSymbolsRecursive(FileSymbol[] symbols) {
        FileSymbol[] filtered;

        foreach (symbol; symbols) {
            bool include = true;

            // Filter by visibility
            if (!_config.showPrivateMembers && isPrivateSymbol(symbol)) {
                include = false;
            }

            // Filter by search query
            if (!_searchQuery.empty) {
                string searchLower = _caseSensitiveSearch ? _searchQuery : _searchQuery.toLower();
                string symbolName = _caseSensitiveSearch ? symbol.name : symbol.name.toLower();

                if (!symbolName.canFind(searchLower)) {
                    // Check if any children match
                    auto filteredChildren = filterSymbolsRecursive(symbol.children);
                    if (filteredChildren.empty) {
                        include = false;
                    }
                }
            }

            if (include) {
                FileSymbol filteredSymbol = symbol;
                filteredSymbol.children = filterSymbolsRecursive(symbol.children);
                filtered ~= filteredSymbol;
            }
        }

        return filtered;
    }

    private bool isPrivateSymbol(FileSymbol symbol) {
        return symbol.modifiers.canFind("private") || symbol.name.startsWith("_");
    }

    private void applySorting(FileSymbol[] symbols) {
        int sortMode = _sortCombo.selectedItemIndex;

        final switch (sortMode) {
            case 0: // Source order - no sorting needed
                break;
            case 1: // Alphabetical
                symbols.sort!((a, b) => a.name < b.name);
                break;
            case 2: // By type
                symbols.sort!((a, b) => a.type < b.type || (a.type == b.type && a.name < b.name));
                break;
        }

        // Recursively sort children
        foreach (ref symbol; symbols) {
            applySorting(symbol.children);
        }
    }

    private void updateTreeDisplay() {
        _outlineTree.clearAllItems();

        foreach (ref symbol; _filteredSymbols) {
            auto item = createTreeItem(symbol);
            _outlineTree.addChild(item);
        }
    }

    private TreeItem createTreeItem(ref FileSymbol symbol) {
        auto item = new TreeItem(generateItemText(symbol).toUTF32());
        item.tag = &symbol;

        // Set icon based on symbol type
        item.iconId = getSymbolIcon(symbol.type);

        // Set text color based on symbol properties
        if (symbol.hasChanges) {
            item.textColor = 0xFFFF6600; // Orange for changes
        } else if (symbol.aiConfidence < 0.5) {
            item.textColor = 0xFFFF0000; // Red for low quality
        } else if (symbol.aiConfidence > 0.8) {
            item.textColor = 0xFF008000; // Green for high quality
        }

        // Add children
        foreach (ref child; symbol.children) {
            auto childItem = createTreeItem(child);
            item.addChild(childItem);
        }

        // Set expansion state
        item.expanded = symbol.isExpanded;

        return item;
    }

    private string generateItemText(FileSymbol symbol) {
        string text = symbol.name;

        // Add type information
        if (_config.showReturnTypes && !symbol.returnType.empty) {
            text = symbol.returnType ~ " " ~ text;
        }

        // Add parameters for functions
        if (_config.showParameters && !symbol.parameters.empty) {
            text ~= "(" ~ symbol.parameters.join(", ") ~ ")";
        }

        // Add line number
        if (_config.showLineNumbers) {
            text ~= format(" : %d", symbol.startLine + 1);
        }

        return text;
    }

    private string getSymbolIcon(SymbolType type) {
        final switch (type) {
            case SymbolType.Module: return "module";
            case SymbolType.Import: return "import";
            case SymbolType.Class: return "class";
            case SymbolType.Interface: return "interface";
            case SymbolType.Struct: return "struct";
            case SymbolType.Enum: return "enum";
            case SymbolType.Function: return "function";
            case SymbolType.Method: return "method";
            case SymbolType.Property: return "property";
            case SymbolType.Field: return "field";
            case SymbolType.Variable: return "variable";
            case SymbolType.Constant: return "constant";
            case SymbolType.Constructor: return "constructor";
            case SymbolType.Destructor: return "destructor";
            case SymbolType.Operator: return "operator";
            case SymbolType.Template: return "template";
            case SymbolType.Mixin: return "mixin";
            case SymbolType.Alias: return "alias";
            case SymbolType.Comment: return "comment";
            case SymbolType.Region: return "region";
            case SymbolType.Unknown: return "unknown";
        }
    }

    private void updateSortMode(int mode) {
        applySorting(_filteredSymbols);
        updateTreeDisplay();
    }

    private void expandAll() {
        expandAllRecursive(_symbols, true);
        updateTreeDisplay();
    }

    private void collapseAll() {
        expandAllRecursive(_symbols, false);
        updateTreeDisplay();
    }

    private void expandAllRecursive(FileSymbol[] symbols, bool expand) {
        foreach (ref symbol; symbols) {
            symbol.isExpanded = expand;
            expandAllRecursive(symbol.children, expand);
        }
    }

    private void clearOutline() {
        _symbols.length = 0;
        _filteredSymbols.length = 0;
        _outlineTree.clearAllItems();
    }

    private void showSettingsDialog() {
        // Create settings dialog
        auto dialog = new OutlineSettingsDialog(_config, window);
        dialog.onConfigChanged.connect((OutlineConfig newConfig) {
            _config = newConfig;
            refreshOutline();
        });
        dialog.show();
    }

    private FileSymbol[] parseGeneric(string content) {
        // Generic parser for unknown file types
        FileSymbol[] symbols;
        auto lines = content.splitLines();

        foreach (i, line; lines) {
            string trimmed = line.strip();

            // Look for function-like patterns
            if (auto match = matchFirst(trimmed, ctRegex!(`(\w+)\s*\(`))) {
                FileSymbol symbol;
                symbol.name = match[1];
                symbol.type = SymbolType.Function;
                symbol.startLine = cast(int)i;
                symbol.endLine = cast(int)i;
                symbol.signature = trimmed;
                symbols ~= symbol;
            }
        }

        return symbols;
    }

    /// Get current outline symbols
    @property FileSymbol[] symbols() {
        return _symbols.dup;
    }

    /// Get filtered symbols (after search/filtering)
    @property FileSymbol[] filteredSymbols() {
        return _filteredSymbols.dup;
    }

    /// Get current configuration
    @property OutlineConfig config() {
        return _config;
    }

    /// Set configuration
    @property void config(OutlineConfig cfg) {
        _config = cfg;
        refreshOutline();
    }

    /// Export outline data as JSON
    JSONValue exportOutline() {
        JSONValue result = JSONValue.emptyObject;
        result["filePath"] = JSONValue(_currentFilePath);
        result["timestamp"] = JSONValue(_lastUpdateTime.toISOExtString());
        result["symbols"] = serializeSymbols(_symbols);
        result["config"] = serializeConfig(_config);
        return result;
    }

    private JSONValue serializeSymbols(FileSymbol[] symbols) {
        JSONValue[] symbolsArray;

        foreach (symbol; symbols) {
            JSONValue symbolJson = JSONValue.emptyObject;
            symbolJson["name"] = JSONValue(symbol.name);
            symbolJson["type"] = JSONValue(to!string(symbol.type));
            symbolJson["startLine"] = JSONValue(symbol.startLine);
            symbolJson["endLine"] = JSONValue(symbol.endLine);
            symbolJson["signature"] = JSONValue(symbol.signature);
            symbolJson["returnType"] = JSONValue(symbol.returnType);
            symbolJson["parameters"] = JSONValue(symbol.parameters);
            symbolJson["modifiers"] = JSONValue(symbol.modifiers);
            symbolJson["docComment"] = JSONValue(symbol.docComment);
            symbolJson["aiConfidence"] = JSONValue(symbol.aiConfidence);
            symbolJson["children"] = serializeSymbols(symbol.children);

            symbolsArray ~= symbolJson;
        }

        return JSONValue(symbolsArray);
    }

    private JSONValue serializeConfig(OutlineConfig config) {
        JSONValue configJson = JSONValue.emptyObject;
        configJson["showPrivateMembers"] = JSONValue(config.showPrivateMembers);
        configJson["showImports"] = JSONValue(config.showImports);
        configJson["showComments"] = JSONValue(config.showComments);
        configJson["showVariables"] = JSONValue(config.showVariables);
        configJson["groupByType"] = JSONValue(config.groupByType);
        configJson["sortAlphabetically"] = JSONValue(config.sortAlphabetically);
        configJson["showLineNumbers"] = JSONValue(config.showLineNumbers);
        configJson["showParameters"] = JSONValue(config.showParameters);
        configJson["showReturnTypes"] = JSONValue(config.showReturnTypes);
        configJson["highlightChanges"] = JSONValue(config.highlightChanges);
        return configJson;
    }
}

/// Base class for language-specific parsers
abstract class LanguageParser {
    abstract FileSymbol[] parseFile(string content, OutlineConfig config);

    protected FileSymbol createSymbol(string name, SymbolType type, int line, string signature = "") {
        FileSymbol symbol;
        symbol.name = name;
        symbol.type = type;
        symbol.startLine = line;
        symbol.endLine = line;
        symbol.signature = signature;
        return symbol;
    }
}

/// D language parser
class DLanguageParser : LanguageParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        FileSymbol[] symbols;
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i];
            string trimmed = line.strip();

            if (trimmed.empty || trimmed.startsWith("//")) continue;

            // Parse imports
            if (config.showImports && trimmed.startsWith("import ")) {
                auto symbol = parseImport(trimmed, i);
                if (symbol.name.length > 0) symbols ~= symbol;
            }

            // Parse classes
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:(public|private|protected)\s+)?class\s+(\w+)`))) {
                auto symbol = parseClass(lines, i, match);
                symbols ~= symbol;
                i = symbol.endLine; // Skip processed lines
            }

            // Parse structs
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:(public|private|protected)\s+)?struct\s+(\w+)`))) {
                auto symbol = parseStruct(lines, i, match);
                symbols ~= symbol;
                i = symbol.endLine;
            }

            // Parse functions
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:(public|private|protected|static)\s+)?(?:(\w+)\s+)?(\w+)\s*\(`))) {
                auto symbol = parseFunction(lines, i, match);
                if (symbol.name.length > 0) {
                    symbols ~= symbol;
                }
            }

            // Parse enums
            else if (auto match = matchFirst(trimmed, ctRegex!(`^enum\s+(\w+)`))) {
                auto symbol = parseEnum(lines, i, match);
                symbols ~= symbol;
                i = symbol.endLine;
            }
        }

        return symbols;
    }

    private FileSymbol parseImport(string line, int lineNum) {
        auto match = matchFirst(line, ctRegex!(`import\s+([\w\.]+)`));
        if (!match) return FileSymbol.init;

        FileSymbol symbol;
        symbol.name = match[1];
        symbol.type = SymbolType.Import;
        symbol.startLine = lineNum;
        symbol.endLine = lineNum;
        symbol.signature = line.strip();
        return symbol;
    }

    private FileSymbol parseClass(string[] lines, int startLine, Captures!string match) {
        FileSymbol symbol;
        symbol.name = match[2];
        symbol.type = SymbolType.Class;
        symbol.startLine = startLine;
        symbol.signature = lines[startLine].strip();

        if (match[1].length > 0) {
            symbol.modifiers ~= match[1];
        }

        // Find class body and parse members
        int braceCount = 0;
        bool foundOpenBrace = false;

        for (int i = startLine; i < lines.length; i++) {
            string line = lines[i];

            foreach (ch; line) {
                if (ch == '{') {
                    braceCount++;
                    foundOpenBrace = true;
                } else if (ch == '}') {
                    braceCount--;
                }
            }

            if (foundOpenBrace && braceCount == 0) {
                symbol.endLine = i;
                break;
            }
        }

        // Parse class members
        symbol.children = parseClassMembers(lines, startLine + 1, symbol.endLine - 1);

        return symbol;
    }

    private FileSymbol parseStruct(string[] lines, int startLine, Captures!string match) {
        FileSymbol symbol;
        symbol.name = match[2];
        symbol.type = SymbolType.Struct;
        symbol.startLine = startLine;
        symbol.signature = lines[startLine].strip();

        // Similar logic to parseClass but for struct
        // ... implementation similar to parseClass

        return symbol;
    }

    private FileSymbol parseFunction(string[] lines, int startLine, Captures!string match) {
        FileSymbol symbol;
        symbol.name = match[3];
        symbol.type = SymbolType.Function;
        symbol.startLine = startLine;
        symbol.signature = lines[startLine].strip();

        if (match[1].length > 0) {
            symbol.modifiers ~= match[1];
        }
        if (match[2].length > 0) {
            symbol.returnType = match[2];
        }

        // Parse parameters
        string line = lines[startLine];
        auto paramMatch = matchFirst(line, ctRegex!(`\((.*?)\)`));
        if (paramMatch && paramMatch[1].length > 0) {
            symbol.parameters = paramMatch[1].split(",").map!(
                s => s.strip()).array;
        }

        // Find function end
        int braceCount = 0;
        bool foundOpenBrace = false;

        for (int i = startLine; i < lines.length; i++) {
            string funcLine = lines[i];

            foreach (ch; funcLine) {
                if (ch == '{') {
                    braceCount++;
                    foundOpenBrace = true;
                } else if (ch == '}') {
                    braceCount--;
                }
            }

            if (foundOpenBrace && braceCount == 0) {
                symbol.endLine = i;
                break;
            }
        }

        return symbol;
    }

    private FileSymbol parseEnum(string[] lines, int startLine, Captures!string match) {
        FileSymbol symbol;
        symbol.name = match[1];
        symbol.type = SymbolType.Enum;
        symbol.startLine = startLine;
        symbol.signature = lines[startLine].strip();

        // Find enum end
        int braceCount = 0;
        bool foundOpenBrace = false;

        for (int i = startLine; i < lines.length; i++) {
            string line = lines[i];

            foreach (ch; line) {
                if (ch == '{') {
                    braceCount++;
                    foundOpenBrace = true;
                } else if (ch == '}') {
                    braceCount--;
                }
            }

            if (foundOpenBrace && braceCount == 0) {
                symbol.endLine = i;
                break;
            }
        }

        return symbol;
    }

    private FileSymbol[] parseClassMembers(string[] lines, int startLine, int endLine) {
        FileSymbol[] members;

        for (int i = startLine; i <= endLine; i++) {
            string line = lines[i];
            string trimmed = line.strip();

            if (trimmed.empty || trimmed.startsWith("//")) continue;

            // Parse methods
            if (auto match = matchFirst(trimmed, ctRegex!(`^(?:(public|private|protected|static)\s+)?(?:(\w+)\s+)?(\w+)\s*\(`))) {
                auto symbol = parseFunction(lines, i, match);
                if (symbol.name.length > 0) {
                    symbol.type = SymbolType.Method;
                    members ~= symbol;
                    i = symbol.endLine;
                }
            }

            // Parse fields
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:(public|private|protected|static)\s+)?(\w+)\s+(\w+)\s*[;=]`))) {
                FileSymbol symbol;
                symbol.name = match[3];
                symbol.type = SymbolType.Field;
                symbol.startLine = i;
                symbol.endLine = i;
                symbol.signature = trimmed;
                symbol.returnType = match[2];
                if (match[1].length > 0) {
                    symbol.modifiers ~= match[1];
                }
                members ~= symbol;
            }
        }

        return members;
    }
}

/// Python language parser
class PythonParser : LanguageParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        FileSymbol[] symbols;
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i];
            string trimmed = line.strip();

            if (trimmed.empty || trimmed.startsWith("#")) continue;

            // Parse imports
            if (config.showImports && (trimmed.startsWith("import ") || trimmed.startsWith("from "))) {
                auto symbol = createSymbol(trimmed, SymbolType.Import, i, trimmed);
                symbols ~= symbol;
            }

            // Parse classes
            else if (auto match = matchFirst(trimmed, ctRegex!(`^class\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Class, i, trimmed);
                symbols ~= symbol;
            }

            // Parse functions
            else if (auto match = matchFirst(trimmed, ctRegex!(`^def\s+(\w+)\s*\(`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Function, i, trimmed);
                symbols ~= symbol;
            }
        }

        return symbols;
    }
}

/// JavaScript/TypeScript parser
class JavaScriptParser : LanguageParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        FileSymbol[] symbols;
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i];
            string trimmed = line.strip();

            if (trimmed.empty || trimmed.startsWith("//")) continue;

            // Parse functions
            if (auto match = matchFirst(trimmed, ctRegex!(`^function\s+(\w+)\s*\(`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Function, i, trimmed);
                symbols ~= symbol;
            }

            // Parse arrow functions
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:const|let|var)\s+(\w+)\s*=\s*\(`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Function, i, trimmed);
                symbols ~= symbol;
            }

            // Parse classes
            else if (auto match = matchFirst(trimmed, ctRegex!(`^class\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Class, i, trimmed);
                symbols ~= symbol;
            }
        }

        return symbols;
    }
}

/// TypeScript parser (inherits from JavaScript)
class TypeScriptParser : JavaScriptParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        auto symbols = super.parseFile(content, config);

        // Add TypeScript-specific parsing
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();

            // Parse interfaces
            if (auto match = matchFirst(trimmed, ctRegex!(`^interface\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Interface, i, trimmed);
                symbols ~= symbol;
            }

            // Parse enums
            else if (auto match = matchFirst(trimmed, ctRegex!(`^enum\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Enum, i, trimmed);
                symbols ~= symbol;
            }
        }

        return symbols;
    }
}

/// C language parser
class CParser : LanguageParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        FileSymbol[] symbols;
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string line = lines[i];
            string trimmed = line.strip();

            if (trimmed.empty || trimmed.startsWith("//") || trimmed.startsWith("/*")) continue;

            // Parse structs
            if (auto match = matchFirst(trimmed, ctRegex!(`^struct\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Struct, i, trimmed);
                symbols ~= symbol;
            }

            // Parse functions
            else if (auto match = matchFirst(trimmed, ctRegex!(`^(?:\w+\s+)*(\w+)\s*\(`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Function, i, trimmed);
                symbols ~= symbol;
            }
        }

        return symbols;
    }
}

/// C++ language parser (inherits from C)
class CppParser : CParser {
    override FileSymbol[] parseFile(string content, OutlineConfig config) {
        auto symbols = super.parseFile(content, config);

        // Add C++-specific parsing
        auto lines = content.splitLines();

        for (int i = 0; i < lines.length; i++) {
            string trimmed = lines[i].strip();

            // Parse classes
            if (auto match = matchFirst(trimmed, ctRegex!(`^class\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Class, i, trimmed);
                symbols ~= symbol;
            }

            // Parse namespaces
            else if (auto match = matchFirst(trimmed, ctRegex!(`^namespace\s+(\w+)`))) {
                FileSymbol symbol = createSymbol(match[1], SymbolType.Module, i, trimmed);
                symbols ~= symbol;
            }
        }

        return symbols;
    }
}

/// Settings dialog for outline configuration
class OutlineSettingsDialog : Dialog {
    private {
        OutlineConfig _config;
        CheckBox _showPrivateCheck;
        CheckBox _showImportsCheck;
        CheckBox _showCommentsCheck;
        CheckBox _showVariablesCheck;
        CheckBox _groupByTypeCheck;
        CheckBox _sortAlphabeticallyCheck;
        CheckBox _showLineNumbersCheck;
        CheckBox _showParametersCheck;
        CheckBox _showReturnTypesCheck;
        CheckBox _highlightChangesCheck;
    }

    Signal!(OutlineConfig) onConfigChanged;

    this(OutlineConfig config, Window parent) {
        super(UIString.fromRaw("Outline Settings"), parent, DialogFlag.Modal, 400, 500);
        _config = config;
        createUI();
    }

    private void createUI() {
        VerticalLayout content = new VerticalLayout();
        content.layoutWidth = FILL_PARENT;
        content.layoutHeight = FILL_PARENT;
        content.margins = Rect(10, 10, 10, 10);

        // Visibility options
        auto visibilityGroup = new GroupBox("visibility", "Visibility"d);
        VerticalLayout visibilityLayout = new VerticalLayout();

        _showPrivateCheck = new CheckBox("showPrivate", "Show private members"d);
        _showPrivateCheck.checked = _config.showPrivateMembers;
        visibilityLayout.addChild(_showPrivateCheck);

        _showImportsCheck = new CheckBox("showImports", "Show imports"d);
        _showImportsCheck.checked = _config.showImports;
        visibilityLayout.addChild(_showImportsCheck);

        _showCommentsCheck = new CheckBox("showComments", "Show comments"d);
        _showCommentsCheck.checked = _config.showComments;
        visibilityLayout.addChild(_showCommentsCheck);

        _showVariablesCheck = new CheckBox("showVariables", "Show variables"d);
        _showVariablesCheck.checked = _config.showVariables;
        visibilityLayout.addChild(_showVariablesCheck);

        visibilityGroup.addChild(visibilityLayout);
        content.addChild(visibilityGroup);

        // Display options
        auto displayGroup = new GroupBox("display", "Display"d);
        VerticalLayout displayLayout = new VerticalLayout();

        _showLineNumbersCheck = new CheckBox("showLineNumbers", "Show line numbers"d);
        _showLineNumbersCheck.checked = _config.showLineNumbers;
        displayLayout.addChild(_showLineNumbersCheck);

        _showParametersCheck = new CheckBox("showParameters", "Show parameters"d);
        _showParametersCheck.checked = _config.showParameters;
        displayLayout.addChild(_showParametersCheck);

        _showReturnTypesCheck = new CheckBox("showReturnTypes", "Show return types"d);
        _showReturnTypesCheck.checked = _config.showReturnTypes;
        displayLayout.addChild(_showReturnTypesCheck);

        _highlightChangesCheck = new CheckBox("highlightChanges", "Highlight changes"d);
        _highlightChangesCheck.checked = _config.highlightChanges;
        displayLayout.addChild(_highlightChangesCheck);

        displayGroup.addChild(displayLayout);
        content.addChild(displayGroup);

        // Organization options
        auto orgGroup = new GroupBox("organization", "Organization"d);
        VerticalLayout orgLayout = new VerticalLayout();

        _groupByTypeCheck = new CheckBox("groupByType", "Group by type"d);
        _groupByTypeCheck.checked = _config.groupByType;
        orgLayout.addChild(_groupByTypeCheck);

        _sortAlphabeticallyCheck = new CheckBox("sortAlphabetically", "Sort alphabetically"d);
        _sortAlphabeticallyCheck.checked = _config.sortAlphabetically;
        orgLayout.addChild(_sortAlphabeticallyCheck);

        orgGroup.addChild(orgLayout);
        content.addChild(orgGroup);

        // Buttons
        HorizontalLayout buttonLayout = new HorizontalLayout();
        buttonLayout.layoutWidth = FILL_PARENT;
        buttonLayout.layoutHeight = WRAP_CONTENT;

        Widget spacer = new Widget();
        spacer.layoutWidth = FILL_PARENT;
        buttonLayout.addChild(spacer);

        Button cancelBtn = new Button("cancel", "Cancel"d);
        cancelBtn.click = delegate(Widget source) {
            close(StandardAction.Cancel);
            return true;
        };
        buttonLayout.addChild(cancelBtn);

        Button okBtn = new Button("ok", "OK"d);
        okBtn.click = delegate(Widget source) {
            applySettings();
            close(StandardAction.Ok);
            return true;
        };
        buttonLayout.addChild(okBtn);

        content.addChild(buttonLayout);
        addChild(content);
    }

    private void applySettings() {
        _config.showPrivateMembers = _showPrivateCheck.checked;
        _config.showImports = _showImportsCheck.checked;
        _config.showComments = _showCommentsCheck.checked;
        _config.showVariables = _showVariablesCheck.checked;
        _config.groupByType = _groupByTypeCheck.checked;
        _config.sortAlphabetically = _sortAlphabeticallyCheck.checked;
        _config.showLineNumbers = _showLineNumbersCheck.checked;
        _config.showParameters = _showParametersCheck.checked;
        _config.showReturnTypes = _showReturnTypesCheck.checked;
        _config.highlightChanges = _highlightChangesCheck.checked;

        if (onConfigChanged.assigned) {
            onConfigChanged(_config);
        }
    }
}

/// Factory function to create file outline widget
FileOutlineWidget createFileOutlineWidget() {
    return new FileOutlineWidget();
}
