/**
 * SymbolOutlinePanel — Power symbol navigator for Dnives IDE
 *
 * Four integrated modes in one panel:
 *
 *  ⊏ Outline  — hierarchical symbol tree for the active file, with
 *               live filter, kind toggles, sort options, and ref-count
 *               badges.  Double-click any symbol to pivot into Flow mode.
 *
 *  ⇌ Flow     — persistent call-chain explorer.  Callers above, callees
 *               below, the focused symbol in the centre.  Every pivot
 *               appends to a breadcrumb trail so you can retrace every
 *               step.  Works without LSP via regex-based callee detection.
 *
 *  ⌕ Search   — fuzzy workspace-symbol search backed by LSP or a fast
 *               in-memory regex scan.  Results jump to definition or
 *               directly into Flow mode.
 *
 *  ⊡ Pins     — a personal debug pinboard.  Pin any symbol from Flow or
 *               right-click in the editor; add notes; export as Markdown.
 */
module dcore.code.symbol_outline_panel;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.lists;
import dlangui.core.logger;
import dlangui.core.events;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.json;
import std.math : abs;
import std.path;
import std.range;
import std.regex;
import std.string;
import std.traits;
import std.utf;

import dcore.core;
import dcore.lsp.lspmanager;
import dcore.lsp.lsptypes;

// ═══════════════════════════════════════════════════════════════════════════
// Data types
// ═══════════════════════════════════════════════════════════════════════════

/// A symbol as used throughout the panel (unified source: LSP or regex).
struct OutlineSymbol {
    string   name;
    string   detail;       /// Signature / type hint / container
    SymbolKind kind;
    string   filePath;
    int      line;         /// 0-based source line
    int      col;
    int      endLine = -1; /// -1 = unknown
    int      depth   = 0;  /// nesting depth for tree indentation
    int      refCount = -1;/// -1 = not yet fetched
    bool     isPublic = true;
    OutlineSymbol[] children;

    string id() const {
        return format("%s|%s|%d", filePath, name, line);
    }
    bool isValid() const { return name.length > 0; }
}

/// A breadcrumb entry in Flow mode navigation history.
struct FlowCrumb {
    OutlineSymbol sym;
    string label;          /// displayed in the breadcrumb bar
}

/// A symbol pinned to the debug Pinboard.
struct PinnedEntry {
    OutlineSymbol sym;
    string note;           /// user annotation
    bool   isWatchPoint;   /// visual highlight
}

// ═══════════════════════════════════════════════════════════════════════════
// Kind helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Short prefix badge rendered before the symbol name.
string kindPrefix(SymbolKind k) pure nothrow {
    switch (k) {
        case SymbolKind.Class:         return "cls";
        case SymbolKind.Struct:        return "st ";
        case SymbolKind.Interface:     return "ifc";
        case SymbolKind.Enum:          return "enm";
        case SymbolKind.EnumMember:    return " em";
        case SymbolKind.Function:      return " fn";
        case SymbolKind.Method:        return "mth";
        case SymbolKind.Constructor:   return "new";
        case SymbolKind.Property:      return "prp";
        case SymbolKind.Field:         return "fld";
        case SymbolKind.Variable:      return "var";
        case SymbolKind.Constant:      return "kst";
        case SymbolKind.Module:        return "mod";
        case SymbolKind.Namespace:     return " ns";
        case SymbolKind.Package:       return "pkg";
        case SymbolKind.TypeParameter: return "tpr";
        case SymbolKind.Operator:      return " op";
        default:                        return "   ";
    }
}

bool isCallable(SymbolKind k) pure nothrow {
    return k == SymbolKind.Function  || k == SymbolKind.Method ||
           k == SymbolKind.Constructor || k == SymbolKind.Operator;
}

bool isContainer(SymbolKind k) pure nothrow {
    return k == SymbolKind.Class  || k == SymbolKind.Struct ||
           k == SymbolKind.Interface || k == SymbolKind.Enum ||
           k == SymbolKind.Module || k == SymbolKind.Namespace;
}

// ═══════════════════════════════════════════════════════════════════════════
// Symbol parser (LSP JSON → OutlineSymbol)
// ═══════════════════════════════════════════════════════════════════════════

/// Parse a textDocument/documentSymbol LSP response (both formats).
OutlineSymbol[] parseDocumentSymbols(JSONValue json, string filePath, int depth = 0) {
    if (json.type != JSONType.array) return [];

    OutlineSymbol[] result;
    foreach (ref item; json.array) {
        if (item.type != JSONType.object) continue;
        OutlineSymbol sym;
        sym.filePath = filePath;
        sym.depth    = depth;

        if (auto p = "name" in item)    sym.name   = p.str;
        if (auto p = "detail" in item)  sym.detail = p.str;
        if (auto p = "kind" in item) {
            int v = cast(int)p.integer;
            if (v >= 1 && v <= 26) sym.kind = cast(SymbolKind)v;
        }

        // DocumentSymbol format (range + selectionRange + children)
        if (auto rp = "range" in item) {
            if (auto sp = "start" in *rp) {
                if (auto lp = "line"      in *sp) sym.line = cast(int)lp.integer;
                if (auto cp = "character" in *sp) sym.col  = cast(int)cp.integer;
            }
            if (auto ep = "end" in *rp) {
                if (auto lp = "line" in *ep) sym.endLine = cast(int)lp.integer;
            }
        }
        // SymbolInformation format (location object)
        else if (auto lp = "location" in item) {
            if (auto rp2 = "range" in *lp) {
                if (auto sp = "start" in *rp2) {
                    if (auto lp2 = "line"      in *sp) sym.line = cast(int)lp2.integer;
                    if (auto cp  = "character" in *sp) sym.col  = cast(int)cp.integer;
                }
            }
            if (auto up = "uri" in *lp) sym.filePath = uriToPath(up.str);
        }

        // Recursively parse children (DocumentSymbol)
        if (auto cp = "children" in item)
            sym.children = parseDocumentSymbols(*cp, filePath, depth + 1);

        result ~= sym;
    }
    return result;
}

/// Parse workspace/symbol LSP response.
OutlineSymbol[] parseWorkspaceSymbols(JSONValue json) {
    if (json.type != JSONType.array) return [];
    OutlineSymbol[] result;
    foreach (ref item; json.array) {
        if (item.type != JSONType.object) continue;
        OutlineSymbol sym;
        if (auto p = "name"          in item) sym.name   = p.str;
        if (auto p = "kind"          in item) {
            int v = cast(int)p.integer;
            if (v >= 1 && v <= 26) sym.kind = cast(SymbolKind)v;
        }
        if (auto p = "containerName" in item) sym.detail = p.str;
        if (auto lp = "location"     in item) {
            if (auto up = "uri" in *lp)       sym.filePath = uriToPath(up.str);
            if (auto rp = "range" in *lp) {
                if (auto sp = "start" in *rp) {
                    if (auto ll = "line"      in *sp) sym.line = cast(int)ll.integer;
                    if (auto cc = "character" in *sp) sym.col  = cast(int)cc.integer;
                }
            }
        }
        result ~= sym;
    }
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Regex-based fallback parser (works without LSP)
// ═══════════════════════════════════════════════════════════════════════════

OutlineSymbol[] parseFileRegex(string filePath) {
    if (!exists(filePath)) return [];
    string content;
    try { content = readText(filePath); } catch (Exception) { return []; }

    string ext = extension(filePath).toLower;
    if (ext.length && ext[0] == '.') ext = ext[1 .. $];

    auto lines = content.splitLines();

    switch (ext) {
        case "d":                          return parseDSymbols(filePath, lines);
        case "py":                         return parsePySymbols(filePath, lines);
        case "js","ts","jsx","tsx","mjs":  return parseJsSymbols(filePath, lines);
        case "rs":                         return parseRsSymbols(filePath, lines);
        case "c","cc","cpp","cxx","h","hpp": return parseCSymbols(filePath, lines);
        default:                           return [];
    }
}

private OutlineSymbol sym(string name, SymbolKind kind, string file, int line, int depth = 0) {
    OutlineSymbol s;
    s.name = name; s.kind = kind; s.filePath = file; s.line = line; s.depth = depth;
    return s;
}

private OutlineSymbol[] parseDSymbols(string file, string[] lines) {
    OutlineSymbol[] res;
    // class/struct/interface/enum
    auto reCls = regex(`^\s*(?:(?:private|public|protected|package|static|final|abstract)\s+)*`
                       ~ `(class|struct|interface|enum|union)\s+(\w+)`);
    // function/method (simplified: type name(
    auto reFn  = regex(`^\s*(?:(?:private|public|protected|package|static|final|`
                       ~ `override|abstract|pure|nothrow|@\w+)\s+)*`
                       ~ `(?:\w[\w\s*\[\]]*)\s+(\w+)\s*\(`);
    // module
    auto reMod = regex(`^\s*module\s+([\w.]+)\s*;`);

    foreach (i, line; lines) {
        int li = cast(int)i;
        if (auto m = line.matchFirst(reMod)) {
            res ~= sym(m[1], SymbolKind.Module, file, li, 0);
        } else if (auto m = line.matchFirst(reCls)) {
            res ~= sym(m[2], m[1] == "class"     ? SymbolKind.Class :
                              m[1] == "struct"    ? SymbolKind.Struct :
                              m[1] == "interface" ? SymbolKind.Interface :
                                                    SymbolKind.Enum,
                       file, li, 0);
        } else if (auto m = line.matchFirst(reFn)) {
            string name = m[1];
            if (name == "if" || name == "for" || name == "while" ||
                name == "switch" || name == "catch") continue;
            res ~= sym(name, SymbolKind.Function, file, li, 1);
        }
    }
    return res;
}

private OutlineSymbol[] parsePySymbols(string file, string[] lines) {
    OutlineSymbol[] res;
    auto reCls = regex(`^(\s*)class\s+(\w+)`);
    auto reFn  = regex(`^(\s*)(?:async\s+)?def\s+(\w+)`);
    foreach (i, line; lines) {
        int li = cast(int)i;
        if (auto m = line.matchFirst(reCls)) {
            int d = cast(int)(m[1].length / 4);
            res ~= sym(m[2], SymbolKind.Class, file, li, d);
        } else if (auto m = line.matchFirst(reFn)) {
            int d = cast(int)(m[1].length / 4);
            bool priv = m[2].startsWith("_") && !m[2].startsWith("__");
            auto s = sym(m[2], SymbolKind.Function, file, li, d);
            s.isPublic = !priv;
            res ~= s;
        }
    }
    return res;
}

private OutlineSymbol[] parseJsSymbols(string file, string[] lines) {
    OutlineSymbol[] res;
    auto reCls  = regex(`^(?:export\s+)?class\s+(\w+)`);
    auto reFn   = regex(`^(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(`);
    auto reConst= regex(`^(?:export\s+)?const\s+(\w+)\s*=\s*(?:async\s+)?\(`);
    auto reMeth = regex(`^\s+(?:async\s+)?(\w+)\s*\(`);
    foreach (i, line; lines) {
        int li = cast(int)i;
        if (auto m = line.matchFirst(reCls))   res ~= sym(m[1], SymbolKind.Class,    file, li, 0);
        else if (auto m = line.matchFirst(reFn)) res ~= sym(m[1], SymbolKind.Function, file, li, 0);
        else if (auto m = line.matchFirst(reConst)) res ~= sym(m[1], SymbolKind.Function, file, li, 0);
        else if (auto m = line.matchFirst(reMeth)) {
            string name = m[1];
            if (name == "if" || name == "for" || name == "while" ||
                name == "return" || name == "switch") continue;
            res ~= sym(name, SymbolKind.Method, file, li, 1);
        }
    }
    return res;
}

private OutlineSymbol[] parseRsSymbols(string file, string[] lines) {
    OutlineSymbol[] res;
    auto reFn   = regex(`^\s*(?:pub\s+)?(?:async\s+)?fn\s+(\w+)`);
    auto reImpl = regex(`^\s*impl(?:<[^>]*>)?\s+(\w+)`);
    auto reStr  = regex(`^\s*(?:pub\s+)?struct\s+(\w+)`);
    auto reEn   = regex(`^\s*(?:pub\s+)?enum\s+(\w+)`);
    auto reTr   = regex(`^\s*(?:pub\s+)?trait\s+(\w+)`);
    foreach (i, line; lines) {
        int li = cast(int)i;
        if (auto m = line.matchFirst(reStr))  res ~= sym(m[1], SymbolKind.Struct,    file, li, 0);
        else if (auto m = line.matchFirst(reEn))  res ~= sym(m[1], SymbolKind.Enum,      file, li, 0);
        else if (auto m = line.matchFirst(reTr))  res ~= sym(m[1], SymbolKind.Interface,  file, li, 0);
        else if (auto m = line.matchFirst(reImpl)) res ~= sym(m[1], SymbolKind.Class,     file, li, 0);
        else if (auto m = line.matchFirst(reFn)) {
            string name = m[1];
            bool priv = !line.stripLeft.startsWith("pub");
            auto s = sym(name, SymbolKind.Function, file, li, 1);
            s.isPublic = !priv;
            res ~= s;
        }
    }
    return res;
}

private OutlineSymbol[] parseCSymbols(string file, string[] lines) {
    OutlineSymbol[] res;
    auto reCls = regex(`^\s*(?:class|struct)\s+(\w+)`);
    // function: return-type name(  at column 0, not indented
    auto reFn  = regex(`^[\w][\w\s*&]*\s+(\w+)\s*\(`);
    foreach (i, line; lines) {
        int li = cast(int)i;
        if (auto m = line.matchFirst(reCls)) {
            SymbolKind k = line.indexOf("struct") >= 0 ? SymbolKind.Struct : SymbolKind.Class;
            res ~= sym(m[1], k, file, li, 0);
        } else if (auto m = line.matchFirst(reFn)) {
            string name = m[1];
            if (name == "if" || name == "for" || name == "while" ||
                name == "switch" || name == "return") continue;
            res ~= sym(name, SymbolKind.Function, file, li, 0);
        }
    }
    return res;
}

// ═══════════════════════════════════════════════════════════════════════════
// Callee detector (best-effort, no LSP required)
// ═══════════════════════════════════════════════════════════════════════════

/// Scan the body of `focused` (from its start line to endLine) and return
/// symbols from `pool` that appear to be called within it.
OutlineSymbol[] detectCallees(OutlineSymbol focused,
                              OutlineSymbol[] pool,
                              string filePath) {
    if (!exists(filePath)) return [];
    string content;
    try { content = readText(filePath); } catch (Exception) { return []; }

    auto lines  = content.splitLines();
    int  start  = focused.line + 1;           // skip the definition line itself
    int  end    = focused.endLine >= 0 ? focused.endLine : min(start + 150, cast(int)lines.length);
    if (start >= lines.length) return [];
    end = min(end, cast(int)lines.length);

    // Collect all identifiers in the body
    auto bodyText = lines[start .. end].join(" ");
    auto reIdent  = regex(`\b([a-zA-Z_]\w*)\s*\(`, "g");   // name followed by (

    bool[string] called;
    foreach (m; bodyText.matchAll(reIdent))
        called[m[1]] = true;

    // Cross-reference with known symbols
    OutlineSymbol[] result;
    foreach (ref s; pool) {
        if (s.name in called && s.name != focused.name)
            result ~= s;
    }
    return result;
}

/// Find symbols in `pool` whose body mentions `target.name` as a call.
/// (Lightweight "find callers" without LSP.)
OutlineSymbol[] detectCallers(OutlineSymbol target,
                              OutlineSymbol[] pool,
                              string filePath) {
    if (!exists(filePath)) return [];
    string content;
    try { content = readText(filePath); } catch (Exception) { return []; }

    auto lines   = content.splitLines();
    auto reCall  = regex(`\b` ~ escaper(target.name).to!string ~ `\s*\(`, "g");

    OutlineSymbol[] result;
    foreach (ref caller; pool) {
        if (!isCallable(caller.kind)) continue;
        if (caller.name == target.name) continue;
        int start = caller.line + 1;
        int end   = caller.endLine >= 0 ? caller.endLine
                                        : min(start + 150, cast(int)lines.length);
        end = min(end, cast(int)lines.length);
        if (start >= lines.length) continue;
        auto body = lines[start .. end].join(" ");
        if (!body.matchFirst(reCall).empty)
            result ~= caller;
    }
    return result;
}

// Helper: escape a string for safe regex insertion
private string escaper(string s) {
    return s.replace(".", r"\.")
            .replace("(", r"\(")
            .replace(")", r"\)")
            .replace("[", r"\[")
            .replace("]", r"\]");
}

// ═══════════════════════════════════════════════════════════════════════════
// Flatten helper (tree → depth-annotated flat array)
// ═══════════════════════════════════════════════════════════════════════════

OutlineSymbol[] flatten(OutlineSymbol[] tree, int depth = 0) {
    OutlineSymbol[] result;
    foreach (ref s; tree) {
        auto copy = s;
        copy.depth = depth;
        result ~= copy;
        result ~= flatten(s.children, depth + 1);
    }
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Panel mode enum
// ═══════════════════════════════════════════════════════════════════════════

enum PanelMode { Outline = 0, Flow = 1, Search = 2, Pinned = 3 }

// ═══════════════════════════════════════════════════════════════════════════
// SymbolOutlinePanel
// ═══════════════════════════════════════════════════════════════════════════

class SymbolOutlinePanel : VerticalLayout {

    // ── Output signals ──────────────────────────────────────────────
    /// Emitted whenever the panel wants the editor to navigate somewhere.
    alias NavHandler = void delegate(string filePath, int line, int col);
    NavHandler onNavigate;

    // ── Dependencies ────────────────────────────────────────────────
    private DCore _core;

    // ── Mode state ──────────────────────────────────────────────────
    private PanelMode _mode = PanelMode.Outline;

    // ── Outline state ───────────────────────────────────────────────
    private string         _activeFilePath;
    private OutlineSymbol[] _fileSymbols;      /// flat, from active file
    private OutlineSymbol[] _dispSymbols;      /// filtered / sorted for display
    private bool[SymbolKind] _kindFilter;      /// empty = show all
    private bool           _publicOnly = false;
    private string         _outlineFilter;

    // ── Flow state ──────────────────────────────────────────────────
    private OutlineSymbol   _focusSym;
    private OutlineSymbol[] _callers;
    private OutlineSymbol[] _callees;
    private FlowCrumb[]     _breadcrumbs;
    private int             _crumbIndex = -1;  /// current position in history
    private int             _flowCrumbLimit = 12; /// configurable max trail length

    /// Maximum breadcrumb hops kept in the Flow trail (editor.flowCrumbLimit).
    @property int flowCrumbLimit() const { return _flowCrumbLimit; }
    @property void flowCrumbLimit(int v) {
        _flowCrumbLimit = v < 1 ? 1 : v;
        // Trim existing trail if the new limit is smaller
        if (cast(int)_breadcrumbs.length > _flowCrumbLimit) {
            _breadcrumbs = _breadcrumbs[$ - _flowCrumbLimit .. $];
            _crumbIndex  = cast(int)_breadcrumbs.length - 1;
            if (_mode == PanelMode.Flow) _renderFlowView();
        }
    }

    // ── Search state ────────────────────────────────────────────────
    private OutlineSymbol[] _searchSyms;

    // ── Pin state ───────────────────────────────────────────────────
    private PinnedEntry[]   _pins;

    // ── UI references ───────────────────────────────────────────────
    // Mode bar
    private Button _btnOutline, _btnFlow, _btnSearch, _btnPins;
    // Outline
    private EditLine   _filterInput;
    private Button     _btnFnOnly, _btnClsOnly, _btnPubOnly;
    private ListWidget _outlineList;
    // Flow
    private VerticalLayout  _flowPanel;
    private HorizontalLayout _crumbBar;
    private ListWidget      _callerList;
    private TextWidget      _focusKindLabel;
    private TextWidget      _focusNameLabel;
    private TextWidget      _focusDetailLabel;
    private TextWidget      _focusLocLabel;
    private TextWidget      _focusRefLabel;
    private ListWidget      _calleeList;
    // Search
    private VerticalLayout  _searchPanel;
    private EditLine        _searchInput;
    private ListWidget      _searchList;
    // Pins
    private ListWidget      _pinList;
    // Content pages
    private VerticalLayout  _outlinePanel;
    private VerticalLayout  _pinPanel;
    // Status
    private TextWidget      _statusBar;

    // ── Constructor ─────────────────────────────────────────────────

    this(string id, DCore core) {
        super(id);
        _core = core;
        layoutWidth  = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        _buildUI();
        _switchMode(PanelMode.Outline);
    }

    // ── Public API ──────────────────────────────────────────────────

    /// Called by EditorManager when the user opens or switches to a file.
    void setActiveFile(string filePath) {
        if (filePath == _activeFilePath) return;
        _activeFilePath = filePath;
        _refreshSymbols();
        if (_mode == PanelMode.Outline) _rebuildOutlineList();
    }

    /// Called from editor right-click "Show in Flow" or via F12 variants.
    void focusSymbolAt(string filePath, int line, int col) {
        // Find the deepest symbol that contains (line, col)
        if (filePath != _activeFilePath) setActiveFile(filePath);

        OutlineSymbol best;
        foreach (ref s; _fileSymbols) {
            if (s.line <= line && (s.endLine < 0 || s.endLine >= line)) {
                if (!best.isValid || s.depth > best.depth)
                    best = s;
            }
        }
        if (!best.isValid && _fileSymbols.length > 0) {
            // Fall back to nearest by line
            best = _fileSymbols[0];
            foreach (ref s; _fileSymbols)
                if (abs(s.line - line) < abs(best.line - line)) best = s;
        }
        if (best.isValid) _pivotFlow(best, /*addCrumb=*/true);
    }

    /// Pin a symbol externally (e.g., from an editor context menu).
    void pinSymbol(OutlineSymbol sym, string note = "") {
        foreach (ref p; _pins) {
            if (p.sym.id == sym.id) { p.note = note; _rebuildPinList(); return; }
        }
        PinnedEntry entry;
        entry.sym  = sym;
        entry.note = note;
        _pins ~= entry;
        _rebuildPinList();
        _setStatus(format("Pinned: %s", sym.name));
    }

    /// Export the current pinboard to Markdown.
    string exportPinsMarkdown() {
        auto sb = appender!string;
        sb.put("# Symbol Pinboard\n\n");
        foreach (ref p; _pins) {
            sb.put(format("## `%s` (%s)\n", p.sym.name, kindPrefix(p.sym.kind)));
            sb.put(format("- **File**: `%s:%d`\n", p.sym.filePath, p.sym.line + 1));
            if (p.sym.detail.length)
                sb.put(format("- **Signature**: `%s`\n", p.sym.detail));
            if (p.note.length)
                sb.put(format("- **Note**: %s\n", p.note));
            sb.put("\n");
        }
        return sb.data;
    }

    // ── UI construction ─────────────────────────────────────────────

    private void _buildUI() {
        // ── Mode tab bar ────────────────────────────────────────────
        auto modeBar = new HorizontalLayout("MODE_BAR");
        modeBar.layoutWidth = FILL_PARENT;
        modeBar.margins = Rect(0, 2, 0, 2);

        _btnOutline = _modeButton("BTN_OUTLINE", "\u22CF Outline"d);
        _btnFlow    = _modeButton("BTN_FLOW",    "\u21CC Flow"d);
        _btnSearch  = _modeButton("BTN_SEARCH",  "\u2315 Search"d);
        _btnPins    = _modeButton("BTN_PINS",    "\u229E Pins"d);

        _btnOutline.click = delegate(Widget w) { _switchMode(PanelMode.Outline); return true; };
        _btnFlow   .click = delegate(Widget w) { _switchMode(PanelMode.Flow);    return true; };
        _btnSearch .click = delegate(Widget w) { _switchMode(PanelMode.Search);  return true; };
        _btnPins   .click = delegate(Widget w) { _switchMode(PanelMode.Pinned);  return true; };

        modeBar.addChild(_btnOutline);
        modeBar.addChild(_btnFlow);
        modeBar.addChild(_btnSearch);
        modeBar.addChild(_btnPins);
        addChild(modeBar);

        // ── Outline panel ───────────────────────────────────────────
        _outlinePanel = new VerticalLayout("OUTLINE_PANEL");
        _outlinePanel.layoutWidth  = FILL_PARENT;
        _outlinePanel.layoutHeight = FILL_PARENT;

        // Filter bar
        auto filterBar = new HorizontalLayout("FILTER_BAR");
        filterBar.layoutWidth = FILL_PARENT;
        filterBar.margins = Rect(2, 2, 2, 2);

        _filterInput = new EditLine("OUTLINE_FILTER");
        _filterInput.layoutWidth = FILL_PARENT;
        _filterInput.minWidth = 60;
        _filterInput.contentChange = delegate(EditableContent c) {
            _outlineFilter = _filterInput.text.to!string;
            _applyFilter();
            _rebuildOutlineList();
        };

        _btnFnOnly  = _toggleButton("BTN_FN",  "fn"d);
        _btnClsOnly = _toggleButton("BTN_CLS", "cls"d);
        _btnPubOnly = _toggleButton("BTN_PUB", "pub"d);

        _btnFnOnly .click = delegate(Widget w) { _toggleKindFilter(SymbolKind.Function); return true; };
        _btnClsOnly.click = delegate(Widget w) { _toggleKindFilter(SymbolKind.Class);    return true; };
        _btnPubOnly.click = delegate(Widget w) {
            _publicOnly = !_publicOnly;
            _btnPubOnly.backgroundColor = _publicOnly ? 0x2060A0 : 0x3C3C3C;
            _applyFilter(); _rebuildOutlineList(); return true;
        };

        filterBar.addChild(_filterInput);
        filterBar.addChild(_btnFnOnly);
        filterBar.addChild(_btnClsOnly);
        filterBar.addChild(_btnPubOnly);
        _outlinePanel.addChild(filterBar);

        // Outline list
        _outlineList = new ListWidget("OUTLINE_LIST");
        _outlineList.layoutWidth  = FILL_PARENT;
        _outlineList.layoutHeight = FILL_PARENT;
        _outlineList.itemSelected = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_dispSymbols.length) return false;
            _navigateTo(_dispSymbols[idx]);
            return true;
        };
        // Single click on callable/container symbols also pivots Flow view.
        _outlineList.itemClick = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_dispSymbols.length) return true;
            auto s = _dispSymbols[idx];
            if (isCallable(s.kind) || isContainer(s.kind))
                _pivotFlow(s, true);
            return true;
        };
        _outlinePanel.addChild(_outlineList);
        addChild(_outlinePanel);

        // ── Flow panel ──────────────────────────────────────────────
        _flowPanel = new VerticalLayout("FLOW_PANEL");
        _flowPanel.layoutWidth  = FILL_PARENT;
        _flowPanel.layoutHeight = FILL_PARENT;

        // Breadcrumb bar
        _crumbBar = new HorizontalLayout("CRUMB_BAR");
        _crumbBar.layoutWidth = FILL_PARENT;
        _crumbBar.margins = Rect(2, 2, 2, 2);
        _flowPanel.addChild(_crumbBar);

        // Callers
        auto callersLabel = new TextWidget("LBL_CALLERS");
        callersLabel.text = "\u2191 Called by:"d;
        callersLabel.textColor = 0x888888;
        callersLabel.margins = Rect(4, 4, 0, 0);
        _flowPanel.addChild(callersLabel);

        _callerList = new ListWidget("CALLER_LIST");
        _callerList.layoutWidth  = FILL_PARENT;
        _callerList.layoutHeight = 120;
        _callerList.itemClick = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_callers.length) return true;
            _pivotFlow(_callers[idx], true);
            return true;
        };
        _flowPanel.addChild(_callerList);

        // Focused symbol display
        auto focusBox = new VerticalLayout("FOCUS_BOX");
        focusBox.layoutWidth = FILL_PARENT;
        focusBox.margins = Rect(4, 8, 4, 8);
        focusBox.padding = Rect(6, 6, 6, 6);
        focusBox.backgroundColor = 0x1E3050;

        _focusKindLabel = new TextWidget("FOCUS_KIND");
        _focusKindLabel.textColor = 0x7090C0;
        _focusKindLabel.fontSize = 9;
        focusBox.addChild(_focusKindLabel);

        _focusNameLabel = new TextWidget("FOCUS_NAME");
        _focusNameLabel.fontSize = 15;
        _focusNameLabel.textColor = 0xE8E8D0;
        focusBox.addChild(_focusNameLabel);

        _focusDetailLabel = new TextWidget("FOCUS_DETAIL");
        _focusDetailLabel.textColor = 0x8898AA;
        _focusDetailLabel.fontSize = 10;
        focusBox.addChild(_focusDetailLabel);

        _focusLocLabel = new TextWidget("FOCUS_LOC");
        _focusLocLabel.textColor = 0x5599CC;
        _focusLocLabel.fontSize = 9;
        focusBox.addChild(_focusLocLabel);

        _focusRefLabel = new TextWidget("FOCUS_REF");
        _focusRefLabel.textColor = 0x669966;
        _focusRefLabel.fontSize = 9;
        focusBox.addChild(_focusRefLabel);

        // Action buttons on the focused symbol
        auto focusActions = new HorizontalLayout("FOCUS_ACTIONS");
        focusActions.margins = Rect(0, 4, 0, 0);

        auto btnJump = new Button("BTN_JUMP", "Go to \u21D2"d);
        btnJump.fontSize = 9;
        btnJump.click = delegate(Widget w) {
            if (_focusSym.isValid) _navigateTo(_focusSym); return true;
        };

        auto btnPin = new Button("BTN_PIN_FLOW", "\u229E Pin"d);
        btnPin.fontSize = 9;
        btnPin.click = delegate(Widget w) {
            if (_focusSym.isValid) pinSymbol(_focusSym); return true;
        };

        auto btnBack = new Button("BTN_BACK", "\u2190"d);
        btnBack.fontSize = 9;
        btnBack.click = delegate(Widget w) { _flowBack(); return true; };

        auto btnFwd = new Button("BTN_FWD", "\u2192"d);
        btnFwd.fontSize = 9;
        btnFwd.click = delegate(Widget w) { _flowForward(); return true; };

        focusActions.addChild(btnBack);
        focusActions.addChild(btnFwd);
        focusActions.addChild(btnJump);
        focusActions.addChild(btnPin);
        focusBox.addChild(focusActions);

        _flowPanel.addChild(focusBox);

        // Callees
        auto calleesLabel = new TextWidget("LBL_CALLEES");
        calleesLabel.text = "\u2193 Calls:"d;
        calleesLabel.textColor = 0x888888;
        calleesLabel.margins = Rect(4, 4, 0, 0);
        _flowPanel.addChild(calleesLabel);

        _calleeList = new ListWidget("CALLEE_LIST");
        _calleeList.layoutWidth  = FILL_PARENT;
        _calleeList.layoutHeight = 120;
        _calleeList.itemClick = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_callees.length) return true;
            _pivotFlow(_callees[idx], true);
            return true;
        };
        _flowPanel.addChild(_calleeList);

        _flowPanel.visibility = Visibility.Gone;
        addChild(_flowPanel);

        // ── Search panel ─────────────────────────────────────────────
        _searchPanel = new VerticalLayout("SEARCH_PANEL");
        _searchPanel.layoutWidth  = FILL_PARENT;
        _searchPanel.layoutHeight = FILL_PARENT;

        _searchInput = new EditLine("SEARCH_INPUT");
        _searchInput.layoutWidth = FILL_PARENT;
        _searchInput.margins = Rect(4, 4, 4, 4);
        _searchInput.contentChange = delegate(EditableContent c) {
            _doSearch(_searchInput.text.to!string);
        };
        _searchPanel.addChild(_searchInput);

        _searchList = new ListWidget("SEARCH_LIST");
        _searchList.layoutWidth  = FILL_PARENT;
        _searchList.layoutHeight = FILL_PARENT;
        _searchList.itemClick = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_searchSyms.length) return true;
            _navigateTo(_searchSyms[idx]);
            return true;
        };
        _searchPanel.addChild(_searchList);

        _searchPanel.visibility = Visibility.Gone;
        addChild(_searchPanel);

        // ── Pin panel ────────────────────────────────────────────────
        _pinPanel = new VerticalLayout("PIN_PANEL");
        _pinPanel.layoutWidth  = FILL_PARENT;
        _pinPanel.layoutHeight = FILL_PARENT;

        auto pinHeader = new HorizontalLayout("PIN_HEADER");
        pinHeader.layoutWidth = FILL_PARENT;
        auto pinTitle = new TextWidget("PIN_TITLE");
        pinTitle.text = "Debug Pinboard"d;
        pinTitle.margins = Rect(4, 4, 0, 4);
        auto btnExportPins = new Button("BTN_EXPORT_PINS", "Export \u2913"d);
        btnExportPins.fontSize = 9;
        btnExportPins.click = delegate(Widget w) {
            string md = exportPinsMarkdown();
            Log.i("SymbolOutlinePanel: Pinboard export:\n", md);
            _setStatus("Pinboard copied to log (hook exportPinsMarkdown() to save)");
            return true;
        };
        pinHeader.addChild(pinTitle);
        pinHeader.addChild(btnExportPins);
        _pinPanel.addChild(pinHeader);

        _pinList = new ListWidget("PIN_LIST");
        _pinList.layoutWidth  = FILL_PARENT;
        _pinList.layoutHeight = FILL_PARENT;
        _pinList.itemClick = delegate(Widget src, int idx) {
            if (idx < 0 || idx >= cast(int)_pins.length) return true;
            _navigateTo(_pins[idx].sym);
            return true;
        };
        _pinPanel.addChild(_pinList);

        _pinPanel.visibility = Visibility.Gone;
        addChild(_pinPanel);

        // ── Status bar ───────────────────────────────────────────────
        _statusBar = new TextWidget("STATUS_BAR");
        _statusBar.text = ""d;
        _statusBar.textColor = 0x606060;
        _statusBar.fontSize = 9;
        _statusBar.margins = Rect(4, 2, 4, 2);
        _statusBar.layoutWidth = FILL_PARENT;
        addChild(_statusBar);
    }

    private Button _modeButton(string id, dstring label) {
        auto b = new Button(id, label);
        b.layoutWidth = FILL_PARENT;
        b.fontSize = 10;
        b.margins = Rect(1, 1, 1, 1);
        return b;
    }

    private Button _toggleButton(string id, dstring label) {
        auto b = new Button(id, label);
        b.fontSize = 9;
        b.minWidth = 28;
        b.margins = Rect(1, 0, 1, 0);
        b.backgroundColor = 0x3C3C3C;
        return b;
    }

    // ── Mode switching ───────────────────────────────────────────────

    private void _switchMode(PanelMode mode) {
        _mode = mode;

        // Update tab button backgrounds
        uint active   = 0x2060A0;
        uint inactive = 0x2D2D2D;
        _btnOutline.backgroundColor = mode == PanelMode.Outline ? active : inactive;
        _btnFlow   .backgroundColor = mode == PanelMode.Flow    ? active : inactive;
        _btnSearch .backgroundColor = mode == PanelMode.Search  ? active : inactive;
        _btnPins   .backgroundColor = mode == PanelMode.Pinned  ? active : inactive;

        // Show/hide panels
        _outlinePanel.visibility = mode == PanelMode.Outline ? Visibility.Visible : Visibility.Gone;
        _flowPanel   .visibility = mode == PanelMode.Flow    ? Visibility.Visible : Visibility.Gone;
        _searchPanel .visibility = mode == PanelMode.Search  ? Visibility.Visible : Visibility.Gone;
        _pinPanel    .visibility = mode == PanelMode.Pinned  ? Visibility.Visible : Visibility.Gone;

        // Mode-specific refresh
        final switch (mode) {
            case PanelMode.Outline:
                if (_activeFilePath.length) _rebuildOutlineList();
                break;
            case PanelMode.Flow:
                if (_focusSym.isValid) _renderFlowView();
                else _setStatus("Double-click any symbol in Outline to start tracing flow");
                break;
            case PanelMode.Search:
                // focus search box
                break;
            case PanelMode.Pinned:
                _rebuildPinList();
                break;
        }
    }

    // ── Symbol loading ───────────────────────────────────────────────

    private void _refreshSymbols() {
        if (!_activeFilePath.length) return;

        // Try LSP first
        if (_core && _core.lspManager) {
            try {
                auto json = _core.lspManager.getDocumentSymbols(_activeFilePath);
                if (json.type == JSONType.array && json.array.length > 0) {
                    _fileSymbols = flatten(parseDocumentSymbols(json, _activeFilePath));
                    _applyFilter();
                    _setStatus(format("%d symbols  (LSP)", _fileSymbols.length));
                    return;
                }
            } catch (Exception e) {
                Log.w("SymbolOutlinePanel: LSP getDocumentSymbols failed: ", e.msg);
            }
        }

        // Regex fallback
        _fileSymbols = parseFileRegex(_activeFilePath);
        _applyFilter();
        _setStatus(format("%d symbols  (regex)", _fileSymbols.length));
    }

    // ── Filter / sort ────────────────────────────────────────────────

    private void _toggleKindFilter(SymbolKind k) {
        if (k in _kindFilter) _kindFilter.remove(k);
        else                  _kindFilter[k] = true;

        // Highlight active kind filters
        _btnFnOnly .backgroundColor = (SymbolKind.Function in _kindFilter) ? 0x2060A0 : 0x3C3C3C;
        _btnClsOnly.backgroundColor = (SymbolKind.Class    in _kindFilter) ? 0x2060A0 : 0x3C3C3C;

        _applyFilter();
        _rebuildOutlineList();
    }

    private void _applyFilter() {
        _dispSymbols = _fileSymbols.filter!((ref s) {
            // Public-only filter
            if (_publicOnly && !s.isPublic) return false;
            // Kind filter: if any kind is selected, only show those kinds
            if (_kindFilter.length > 0) {
                bool show = false;
                // Functions/methods share the fn toggle
                if (SymbolKind.Function in _kindFilter &&
                    (s.kind == SymbolKind.Function || s.kind == SymbolKind.Method ||
                     s.kind == SymbolKind.Constructor)) show = true;
                if (SymbolKind.Class in _kindFilter &&
                    isContainer(s.kind)) show = true;
                if (!show) return false;
            }
            // Name filter
            if (_outlineFilter.length > 0 &&
                !s.name.toLower.canFind(_outlineFilter.toLower)) return false;
            return true;
        }).array;
    }

    // ── Outline list rendering ───────────────────────────────────────

    private void _rebuildOutlineList() {
        dstring[] rows;
        foreach (ref s; _dispSymbols) {
            rows ~= _formatOutlineRow(s);
        }
        _outlineList.ownAdapter = new StringListAdapter(rows);
        _setStatus(format("%d / %d symbols  —  %s",
                   _dispSymbols.length, _fileSymbols.length,
                   baseName(_activeFilePath)));
    }

    private dstring _formatOutlineRow(ref OutlineSymbol s) {
        // indentation (2 spaces per depth level)
        dstring indent = ""d;
        foreach (_; 0 .. s.depth) indent ~= "  "d;

        dstring kp = kindPrefix(s.kind).to!dstring;
        dstring name = s.name.to!dstring;
        dstring detail = s.detail.length ? ("  " ~ s.detail[0 .. min(s.detail.length, 40)]).to!dstring : ""d;
        dstring lineNum = format("  ln %d", s.line + 1).to!dstring;
        dstring refs = s.refCount >= 0 ? format(" (%d ref)", s.refCount).to!dstring : ""d;

        return indent ~ "[" ~ kp ~ "] " ~ name ~ detail ~ refs ~ lineNum;
    }

    // ── Flow mode ────────────────────────────────────────────────────

    private void _pivotFlow(OutlineSymbol sym, bool addToBreadcrumb) {
        _focusSym = sym;

        if (addToBreadcrumb) {
            // Truncate forward history if we're in the middle
            if (_crumbIndex >= 0 && _crumbIndex < cast(int)_breadcrumbs.length - 1)
                _breadcrumbs = _breadcrumbs[0 .. _crumbIndex + 1];

            FlowCrumb crumb;
            crumb.sym   = sym;
            crumb.label = sym.name;
            _breadcrumbs ~= crumb;
            _crumbIndex  = cast(int)_breadcrumbs.length - 1;

            // Keep trail within the configured limit — drop oldest
            if (cast(int)_breadcrumbs.length > _flowCrumbLimit) {
                _breadcrumbs = _breadcrumbs[$ - _flowCrumbLimit .. $];
                _crumbIndex  = cast(int)_breadcrumbs.length - 1;
            }
        }

        _resolveCallersCallees();
        _switchMode(PanelMode.Flow);
        // Also jump editor to definition
        _navigateTo(sym);
    }

    private void _flowBack() {
        if (_crumbIndex <= 0) return;
        _crumbIndex--;
        _focusSym = _breadcrumbs[_crumbIndex].sym;
        _resolveCallersCallees();
        _renderFlowView();
        _navigateTo(_focusSym);
    }

    private void _flowForward() {
        if (_crumbIndex >= cast(int)_breadcrumbs.length - 1) return;
        _crumbIndex++;
        _focusSym = _breadcrumbs[_crumbIndex].sym;
        _resolveCallersCallees();
        _renderFlowView();
        _navigateTo(_focusSym);
    }

    private void _resolveCallersCallees() {
        string fp = _focusSym.filePath.length ? _focusSym.filePath : _activeFilePath;

        // Try LSP for callers (references)
        _callers = [];
        if (_core && _core.lspManager && _focusSym.line >= 0) {
            try {
                auto json = _core.lspManager.getReferences(fp, _focusSym.line, _focusSym.col);
                if (json.type == JSONType.array) {
                    foreach (ref ref_; json.array) {
                        if (ref_.type != JSONType.object) continue;
                        OutlineSymbol caller;
                        if (auto up = "uri" in ref_)
                            caller.filePath = uriToPath(up.str);
                        if (auto rp = "range" in ref_) {
                            if (auto sp = "start" in *rp) {
                                if (auto lp = "line"      in *sp) caller.line = cast(int)lp.integer;
                                if (auto cp = "character" in *sp) caller.col  = cast(int)cp.integer;
                            }
                        }
                        caller.name = format("ref @%s:%d", baseName(caller.filePath), caller.line + 1);
                        caller.kind = SymbolKind.Function;
                        _callers ~= caller;
                    }
                }
            } catch (Exception e) {
                Log.w("SymbolOutlinePanel: LSP getReferences failed: ", e.msg);
            }
        }

        // Regex fallback for callers
        if (_callers.length == 0)
            _callers = detectCallers(_focusSym, _fileSymbols, fp);

        // Callees: try LSP call-hierarchy if available, otherwise regex
        _callees = detectCallees(_focusSym, _fileSymbols, fp);

        _renderFlowView();
    }

    private void _renderFlowView() {
        // Breadcrumb bar
        _crumbBar.removeAllChildren();
        foreach (size_t i, ref crumb; _breadcrumbs) {
            bool isCurrent = (i == _crumbIndex);
            auto btn = new Button(format("CRUMB_%d", i), crumb.label.to!dstring);
            btn.fontSize = 9;
            btn.margins = Rect(1, 0, 1, 0);
            btn.backgroundColor = isCurrent ? 0x2060A0 : 0x303030;
            int ci = cast(int)i; // capture
            btn.click = delegate(Widget w) {
                _crumbIndex = ci;
                _focusSym   = _breadcrumbs[ci].sym;
                _resolveCallersCallees();
                _navigateTo(_focusSym);
                return true;
            };
            if (i > 0) {
                auto sep = new TextWidget(format("SEP_%d", i));
                sep.text = " \u203A "d;
                sep.textColor = 0x555555;
                sep.fontSize = 9;
                _crumbBar.addChild(sep);
            }
            _crumbBar.addChild(btn);
        }
        if (_breadcrumbs.length == 0) {
            auto hint = new TextWidget("CRUMB_HINT");
            hint.text = "navigation trail"d;
            hint.textColor = 0x444444;
            hint.fontSize = 9;
            _crumbBar.addChild(hint);
        }

        // Focused symbol
        if (_focusSym.isValid) {
            string fp = _focusSym.filePath.length ? _focusSym.filePath : _activeFilePath;
            _focusKindLabel .text = ("[" ~ kindPrefix(_focusSym.kind) ~ "]").to!dstring;
            _focusNameLabel .text = _focusSym.name.to!dstring;
            _focusDetailLabel.text = _focusSym.detail.to!dstring;
            _focusLocLabel  .text = format("%s : %d", baseName(fp), _focusSym.line + 1).to!dstring;
            _focusRefLabel  .text = _focusSym.refCount >= 0
                                        ? format("%d reference(s)", _focusSym.refCount).to!dstring
                                        : ""d;
        }

        // Callers list
        dstring[] callerRows;
        foreach (ref c; _callers)
            callerRows ~= format("[%s] %s  —  %s:%d",
                kindPrefix(c.kind), c.name, baseName(c.filePath), c.line + 1).to!dstring;
        if (callerRows.length == 0) callerRows ~= "(no callers found)"d;
        _callerList.ownAdapter = new StringListAdapter(callerRows);

        // Callees list
        dstring[] calleeRows;
        foreach (ref c; _callees)
            calleeRows ~= format("[%s] %s  —  %s:%d",
                kindPrefix(c.kind), c.name, baseName(c.filePath), c.line + 1).to!dstring;
        if (calleeRows.length == 0) calleeRows ~= "(no callees found)"d;
        _calleeList.ownAdapter = new StringListAdapter(calleeRows);

        _setStatus(format("Flow: %s  |  %d caller(s)  |  %d callee(s)",
                          _focusSym.name, _callers.length, _callees.length));
    }

    // ── Search ───────────────────────────────────────────────────────

    private void _doSearch(string query) {
        if (query.length < 2) {
            _searchSyms = [];
            _searchList.ownAdapter = new StringListAdapter(["type 2+ chars to search"d]);
            return;
        }

        // Try LSP workspace symbols
        if (_core && _core.lspManager) {
            try {
                auto json = _core.lspManager.getWorkspaceSymbols(query);
                if (json.type == JSONType.array && json.array.length > 0) {
                    _searchSyms = parseWorkspaceSymbols(json);
                    _rebuildSearchList();
                    return;
                }
            } catch (Exception e) {
                Log.w("SymbolOutlinePanel: LSP getWorkspaceSymbols failed: ", e.msg);
            }
        }

        // Regex fallback: filter current file symbols
        _searchSyms = _fileSymbols.filter!(s => s.name.toLower.canFind(query.toLower)).array;
        _rebuildSearchList();
    }

    private void _rebuildSearchList() {
        dstring[] rows;
        foreach (ref s; _searchSyms) {
            rows ~= format("[%s] %-32s  %s:%d",
                kindPrefix(s.kind), s.name, baseName(s.filePath), s.line + 1).to!dstring;
        }
        if (rows.length == 0) rows ~= "(no results)"d;
        _searchList.ownAdapter = new StringListAdapter(rows);
        _setStatus(format("%d result(s)", _searchSyms.length));
    }

    // ── Pin list ─────────────────────────────────────────────────────

    private void _rebuildPinList() {
        dstring[] rows;
        foreach (ref p; _pins) {
            dstring note = p.note.length ? ("  — " ~ p.note).to!dstring : ""d;
            dstring watch = p.isWatchPoint ? " \u25CF"d : ""d;
            rows ~= format("[%s] %s  %s:%d%s%s",
                kindPrefix(p.sym.kind), p.sym.name,
                baseName(p.sym.filePath), p.sym.line + 1,
                note.to!string, watch.to!string).to!dstring;
        }
        if (rows.length == 0) rows ~= "(no pins — double-click in Flow to pin a symbol)"d;
        _pinList.ownAdapter = new StringListAdapter(rows);
    }

    // ── Navigation helper ─────────────────────────────────────────────

    private void _navigateTo(ref OutlineSymbol sym) {
        string fp = sym.filePath.length ? sym.filePath : _activeFilePath;
        if (fp.length && onNavigate)
            onNavigate(fp, sym.line, sym.col);
    }

    // ── Status bar ───────────────────────────────────────────────────

    private void _setStatus(string msg) {
        _statusBar.text = msg.to!dstring;
    }
}
