/**
 * symbolgraph.d — Symbol Graph View Widget for DlangIDE
 *
 * Renders a force-directed, interactive graph of CodeSymbol nodes and their
 * reference edges, sourced from a SymbolTracker.  Hosted inside a DockWindow
 * panel with a small toolbar.
 *
 * Authors: dnives contributors
 */
module dlangide.ui.symbolgraph;

import std.string, std.conv, std.format, std.algorithm, std.array,
       std.math, std.typecons, std.path;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.docks;
import dlangui.widgets.tabs;
import dlangui.graphics.drawbuf;
import dlangui.core.logger;

import dcore.code.symbol_tracker;
import dcore.lsp.lsptypes;
import dcore.lang.language_profile;

// ─────────────────────────────────────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────────────────────────────────────

/// A single node in the symbol graph.
struct GraphNode {
    string     id;          /// fullyQualifiedName or filePath — unique key
    string     label;       /// short display name shown on the node
    string     filePath;    /// source file this symbol lives in
    int        line;        /// 0-based line number (for navigation)
    SymbolKind kind;        /// drives colour / badge
    float      x = 0.5f;   /// normalised canvas position  [0.0 … 1.0]
    float      y = 0.5f;
    bool       isSelected;
    bool       isPinned;
}

/// A directed edge between two nodes.
struct GraphEdge {
    string fromId;
    string toId;
    bool   isDefinition; /// true = definition edge, false = usage / reference edge
}

/// Container for all graph data.
struct SymbolGraphData {
    GraphNode[] nodes;
    GraphEdge[] edges;

    // ── helpers ──────────────────────────────────────────────────────────────

    GraphNode* findNode(string id) {
        foreach (ref n; nodes)
            if (n.id == id)
                return &n;
        return null;
    }

    void addNode(GraphNode n) {
        if (findNode(n.id) is null)
            nodes ~= n;
    }

    void addEdge(GraphEdge e) {
        foreach (ref ex; edges)
            if (ex.fromId == e.fromId && ex.toId == e.toId)
                return;
        edges ~= e;
    }

    void clear() {
        nodes = [];
        edges = [];
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

private enum NODE_W = 84;  /// node pixel width  (at scale 1.0)
private enum NODE_H = 28;  /// node pixel height (at scale 1.0)

/// Return a 1–2 char kind badge string.
private string kindBadge(SymbolKind k) {
    final switch (k) {
        case SymbolKind.File:        return "Fi";
        case SymbolKind.Module:      return "Mo";
        case SymbolKind.Namespace:   return "Ns";
        case SymbolKind.Package:     return "Pk";
        case SymbolKind.Class:       return "Cl";
        case SymbolKind.Method:      return "Me";
        case SymbolKind.Property:    return "Pr";
        case SymbolKind.Field:       return "Fi";
        case SymbolKind.Constructor: return "Ct";
        case SymbolKind.Enum:        return "En";
        case SymbolKind.Interface:   return "In";
        case SymbolKind.Function:    return "Fn";
        case SymbolKind.Variable:    return "Va";
        case SymbolKind.Constant:    return "Co";
        case SymbolKind.String:      return "St";
        case SymbolKind.Number:      return "Nu";
        case SymbolKind.Boolean:     return "Bo";
        case SymbolKind.Array:       return "Ar";
        case SymbolKind.Object:      return "Ob";
        case SymbolKind.Key:         return "Ke";
        case SymbolKind.Null:        return "Nu";
        case SymbolKind.EnumMember:  return "Em";
        case SymbolKind.Struct:      return "Sc";
        case SymbolKind.Event:       return "Ev";
        case SymbolKind.Operator:    return "Op";
        case SymbolKind.TypeParameter: return "Tp";
    }
}

/// Return the base fill colour for a node given its kind.
private uint kindColour(SymbolKind k) {
    switch (k) {
        case SymbolKind.Class:
        case SymbolKind.Struct:
        case SymbolKind.Interface:
            return 0x1F4788;
        case SymbolKind.Function:
        case SymbolKind.Method:
        case SymbolKind.Constructor:
            return 0x2D6A2D;
        case SymbolKind.Enum:
        case SymbolKind.EnumMember:
            return 0x7B3F00;
        case SymbolKind.Variable:
        case SymbolKind.Field:
        case SymbolKind.Property:
            return 0x4A3F6B;
        case SymbolKind.Module:
        case SymbolKind.Namespace:
        case SymbolKind.Package:
            return 0x555555;
        default:
            return 0x3A3A3A;
    }
}

/// Clamp a float to [lo, hi].
private float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/// Add two RGB colours channel-wise, clamped to 0xFF per channel.
private uint addColour(uint c, uint delta) {
    uint r = ((c >> 16) & 0xFF) + ((delta >> 16) & 0xFF);
    uint g = ((c >>  8) & 0xFF) + ((delta >>  8) & 0xFF);
    uint b = ( c        & 0xFF) + ( delta         & 0xFF);
    if (r > 0xFF) r = 0xFF;
    if (g > 0xFF) g = 0xFF;
    if (b > 0xFF) b = 0xFF;
    return (r << 16) | (g << 8) | b;
}

// ─────────────────────────────────────────────────────────────────────────────
// SymbolGraphWidget
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canvas widget that draws the symbol graph.
 *
 * Layout is handled by a simple force-directed algorithm run inside
 * `doLayout()`.  All rendering is done in `onDraw`.
 */
class SymbolGraphWidget : Widget {

    // ── public state ─────────────────────────────────────────────────────────

    /// Called when the user double-clicks a node.  Return true to consume.
    bool delegate(string filePath, int line) onNodeActivated;

    // ── private state ────────────────────────────────────────────────────────

    private SymbolGraphData _data;
    private SymbolTracker   _tracker;

    private float _scale    = 1.0f;
    private int   _offsetX  = 0;
    private int   _offsetY  = 0;

    private string _hoveredNodeId;
    private string _selectedNodeId;

    private bool   _colourByFile = false;
    private string _primaryFile;

    // pan-drag bookkeeping
    private bool _dragging;
    private int  _dragStartX, _dragStartY;
    private int  _dragOriginX, _dragOriginY;

    // ── construction ─────────────────────────────────────────────────────────

    this(string id, SymbolTracker tracker) {
        super(id);
        _tracker = tracker;
        layoutWidth  = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        focusable    = true;
    }

    // ── public API ───────────────────────────────────────────────────────────

    /// Replace the tracker (called when AI subsystem initialises later).
    @property void tracker(SymbolTracker t) { _tracker = t; }

    /// Toggle colouring by file/language vs. by symbol kind.
    @property bool colourByFile() const { return _colourByFile; }
    @property void colourByFile(bool v) { _colourByFile = v; invalidate(); }

    /// Load all symbols for a file and their cross-file references.
    void loadForFile(string filePath) {
        _primaryFile = filePath;
        _data.clear();
        _selectedNodeId = "";
        _hoveredNodeId  = "";

        if (_tracker is null) return;

        CodeSymbol[] syms = _tracker.getFileSymbols(filePath);
        foreach (ref s; syms) {
            GraphNode n;
            n.id       = s.fullyQualifiedName.length ? s.fullyQualifiedName : s.name;
            n.label    = s.name;
            n.filePath = s.filePath;
            n.line     = s.location.start.line;
            n.kind     = s.kind;
            _data.addNode(n);
        }

        // Build reference edges
        foreach (ref s; syms) {
            string fqn = s.fullyQualifiedName.length ? s.fullyQualifiedName : s.name;
            SymbolReference[] refs = _tracker.getReferences(s.name);
            foreach (ref r; refs) {
                // Add a node for the referencing file if it differs
                if (r.filePath != filePath) {
                    GraphNode refNode;
                    refNode.id       = r.filePath;
                    refNode.label    = r.filePath.baseName;
                    refNode.filePath = r.filePath;
                    refNode.line     = r.location.start.line;
                    refNode.kind     = SymbolKind.File;
                    _data.addNode(refNode);

                    GraphEdge e;
                    e.fromId       = fqn;
                    e.toId         = refNode.id;
                    e.isDefinition = r.isDefinition;
                    _data.addEdge(e);
                }
            }
        }

        doLayout();
        invalidate();
    }

    /// Load a star graph centred on a fully-qualified symbol name.
    void loadForSymbol(string fqn) {
        _data.clear();
        _selectedNodeId = "";
        _hoveredNodeId  = "";

        if (_tracker is null || fqn.length == 0) return;

        // Find the centre symbol
        CodeSymbol[] found = _tracker.findSymbols(fqn);
        if (found.length == 0) {
            Log.w("SymbolGraphWidget: no symbol found for '", fqn, "'");
            invalidate();
            return;
        }

        // Use exact match if possible, else first result
        CodeSymbol centre = found[0];
        foreach (ref s; found)
            if (s.fullyQualifiedName == fqn) { centre = s; break; }

        _primaryFile = centre.filePath;

        string centreId = centre.fullyQualifiedName.length
                            ? centre.fullyQualifiedName : centre.name;

        GraphNode cn;
        cn.id       = centreId;
        cn.label    = centre.name;
        cn.filePath = centre.filePath;
        cn.line     = centre.location.start.line;
        cn.kind     = centre.kind;
        cn.x        = 0.5f;
        cn.y        = 0.5f;
        cn.isPinned = true;
        _data.addNode(cn);

        // Fan out to every reference site
        SymbolReference[] refs = _tracker.getReferences(found[0].name);
        foreach (ref r; refs) {
            GraphNode rn;
            rn.id       = r.filePath ~ ":" ~ r.location.start.line.to!string;
            rn.label    = r.filePath.baseName;
            rn.filePath = r.filePath;
            rn.line     = r.location.start.line;
            rn.kind     = SymbolKind.File;
            _data.addNode(rn);

            GraphEdge e;
            e.fromId       = centreId;
            e.toId         = rn.id;
            e.isDefinition = r.isDefinition;
            _data.addEdge(e);
        }

        doLayout();
        invalidate();
    }

    /// Run a simple force-directed layout, storing normalised [0,1] positions.
    void doLayout() {
        immutable int N = cast(int)_data.nodes.length;
        if (N == 0) return;

        // Give unpinned nodes a pseudo-random starting spread
        float step = 1.0f / (N + 1);
        foreach (i, ref n; _data.nodes) {
            if (!n.isPinned) {
                // Spread on a rough grid-ish arrangement seeded by index
                n.x = 0.1f + step * (i % cast(int)(sqrt(cast(float)N) + 1));
                n.y = 0.1f + step * (i / cast(int)(sqrt(cast(float)N) + 1));
            }
        }

        // Force-directed relaxation — 20 iterations
        enum float REPEL   = 0.008f;
        enum float ATTRACT = 0.05f;
        enum float DAMP    = 0.8f;

        float[] vx = new float[N];
        float[] vy = new float[N];
        vx[] = 0f;
        vy[] = 0f;

        foreach (iter; 0 .. 20) {
            // Repulsion between every pair of nodes
            foreach (i; 0 .. N) {
                foreach (j; i + 1 .. N) {
                    float dx = _data.nodes[i].x - _data.nodes[j].x;
                    float dy = _data.nodes[i].y - _data.nodes[j].y;
                    float dist2 = dx * dx + dy * dy;
                    if (dist2 < 1e-6f) dist2 = 1e-6f;
                    float force = REPEL / dist2;
                    float fx = dx * force;
                    float fy = dy * force;
                    if (!_data.nodes[i].isPinned) { vx[i] += fx; vy[i] += fy; }
                    if (!_data.nodes[j].isPinned) { vx[j] -= fx; vy[j] -= fy; }
                }
            }

            // Attraction along edges
            foreach (ref e; _data.edges) {
                GraphNode* a = _data.findNode(e.fromId);
                GraphNode* b = _data.findNode(e.toId);
                if (a is null || b is null) continue;

                // Find indices
                int ai = -1, bi = -1;
                foreach (i, ref n; _data.nodes) {
                    if (n.id == a.id) ai = cast(int)i;
                    if (n.id == b.id) bi = cast(int)i;
                }
                if (ai < 0 || bi < 0) continue;

                float dx = b.x - a.x;
                float dy = b.y - a.y;
                float dist = sqrt(dx * dx + dy * dy);
                if (dist < 1e-4f) continue;

                float fx = dx * ATTRACT;
                float fy = dy * ATTRACT;
                if (!_data.nodes[ai].isPinned) { vx[ai] += fx; vy[ai] += fy; }
                if (!_data.nodes[bi].isPinned) { vx[bi] -= fx; vy[bi] -= fy; }
            }

            // Integrate
            foreach (i; 0 .. N) {
                if (_data.nodes[i].isPinned) continue;
                vx[i] *= DAMP;
                vy[i] *= DAMP;
                _data.nodes[i].x = clampf(_data.nodes[i].x + vx[i], 0.05f, 0.95f);
                _data.nodes[i].y = clampf(_data.nodes[i].y + vy[i], 0.05f, 0.95f);
            }
        }

        // Normalise to [0.1, 0.9]
        if (N > 1) {
            float minX = _data.nodes[0].x, maxX = minX;
            float minY = _data.nodes[0].y, maxY = minY;
            foreach (ref n; _data.nodes) {
                if (n.x < minX) minX = n.x;
                if (n.x > maxX) maxX = n.x;
                if (n.y < minY) minY = n.y;
                if (n.y > maxY) maxY = n.y;
            }
            float rangeX = maxX - minX; if (rangeX < 1e-4f) rangeX = 1f;
            float rangeY = maxY - minY; if (rangeY < 1e-4f) rangeY = 1f;
            foreach (ref n; _data.nodes) {
                if (!n.isPinned) {
                    n.x = 0.1f + 0.8f * (n.x - minX) / rangeX;
                    n.y = 0.1f + 0.8f * (n.y - minY) / rangeY;
                }
            }
        }
    }

    // ── accessors ─────────────────────────────────────────────────────────────

    /// Number of nodes currently in the graph.
    @property int nodeCount() const { return cast(int)_data.nodes.length; }
    /// Number of edges currently in the graph.
    @property int edgeCount() const { return cast(int)_data.edges.length; }

    void resetView() {
        _scale   = 1.0f;
        _offsetX = 0;
        _offsetY = 0;
        invalidate();
    }

    void clearGraph() {
        _data.clear();
        _selectedNodeId = "";
        _hoveredNodeId  = "";
        invalidate();
    }

    // ── colour helpers ─────────────────────────────────────────────────────────

    /// Return the fill colour for a node, respecting the colourByFile toggle.
    private uint nodeColour(const ref GraphNode n) {
        if (_colourByFile) {
            uint c = fileGraphColour(n.filePath);
            if (n.filePath == _primaryFile)
                c = addColour(c, 0x181818);
            return c;
        }
        return kindColour(n.kind);
    }

    // ── coordinate helpers ────────────────────────────────────────────────────

    private int nodePx(const ref GraphNode n, const ref Rect rc) const {
        return rc.left + _offsetX + cast(int)(n.x * rc.width  * _scale);
    }
    private int nodePy(const ref GraphNode n, const ref Rect rc) const {
        return rc.top  + _offsetY + cast(int)(n.y * rc.height * _scale);
    }

    /// Return the id of the node whose bounding box contains (px, py), or "".
    string hitTestNode(int px, int py, Rect rc) const {
        int hw = cast(int)(NODE_W * _scale / 2);
        int hh = cast(int)(NODE_H * _scale / 2);
        foreach (ref n; _data.nodes) {
            int cx = nodePx(n, rc);
            int cy = nodePy(n, rc);
            if (px >= cx - hw && px <= cx + hw &&
                py >= cy - hh && py <= cy + hh)
                return n.id;
        }
        return "";
    }

    // ── drawing ───────────────────────────────────────────────────────────────

    override void onDraw(DrawBuf buf) {
        Rect rc = _pos;
        // Background
        buf.fillRect(rc, 0x1E1E1E);

        if (_data.nodes.length == 0) {
            // Empty state hint
            auto f = FontManager.instance.getFont(12, 400, false, FontFamily.SansSerif, "");
            if (f !is null) {
                dstring hint = "No symbols loaded — open a file or search a symbol"d;
                int tw = f.textSize(hint).x;
                f.drawText(buf,
                    rc.left + (rc.width  - tw) / 2,
                    rc.top  + (rc.height - f.height) / 2,
                    hint, 0x555555);
            }
            return;
        }

        immutable int hw = cast(int)(NODE_W * _scale / 2);
        immutable int hh = cast(int)(NODE_H * _scale / 2);

        // ── Draw edges ────────────────────────────────────────────────────────
        foreach (ref e; _data.edges) {
            const GraphNode* a = _data.findNode(e.fromId);
            const GraphNode* b = _data.findNode(e.toId);
            if (a is null || b is null) continue;

            int ax = nodePx(*a, rc);
            int ay = nodePy(*a, rc);
            int bx = nodePx(*b, rc);
            int by = nodePy(*b, rc);

            uint edgeColour = e.isDefinition ? 0x6688AA : 0x444466;
            buf.drawLine(Point(ax, ay), Point(bx, by), edgeColour);

            // Small arrowhead  (draw a tiny square at the destination end)
            int mx = (ax + bx) / 2;
            int my = (ay + by) / 2;
            buf.fillRect(Rect(mx - 2, my - 2, mx + 2, my + 2), edgeColour);
        }

        // ── Draw nodes ────────────────────────────────────────────────────────
        auto labelFont = FontManager.instance.getFont(
            cast(int)(11 * _scale + 0.5f), 400, false, FontFamily.SansSerif, "");
        auto badgeFont = FontManager.instance.getFont(
            cast(int)( 9 * _scale + 0.5f), 400, false, FontFamily.SansSerif, "");

        foreach (ref n; _data.nodes) {
            int cx = nodePx(n, rc);
            int cy = nodePy(n, rc);

            bool isHovered  = (n.id == _hoveredNodeId);
            bool isSelected = (n.id == _selectedNodeId);

            uint baseCol = nodeColour(n);
            if (isHovered) baseCol = addColour(baseCol, 0x202020);

            Rect nr = Rect(cx - hw, cy - hh, cx + hw, cy + hh);

            // Selection border — draw a slightly larger rect first
            if (isSelected) {
                Rect sr = Rect(nr.left - 2, nr.top - 2, nr.right + 2, nr.bottom + 2);
                buf.fillRect(sr, 0x4A90E2);
            }

            buf.fillRect(nr, baseCol);

            // Label
            if (labelFont !is null) {
                dstring lbl = n.label.to!dstring;
                // Truncate if too wide
                int maxW = nr.width - 6;
                while (lbl.length > 1 && labelFont.textSize(lbl).x > maxW)
                    lbl = lbl[0 .. $ - 1];
                int tw = labelFont.textSize(lbl).x;
                int tx = nr.left + (nr.width  - tw)           / 2;
                int ty = nr.top  + (nr.height - labelFont.height) / 2;
                labelFont.drawText(buf, tx, ty, lbl, 0xEEEEEE);
            }

            // Kind badge — top-left corner
            if (badgeFont !is null) {
                dstring badge = kindBadge(n.kind).to!dstring;
                badgeFont.drawText(buf, nr.left + 2, nr.top + 1, badge, 0x778899);
            }
        }
    }

    // ── mouse handling ────────────────────────────────────────────────────────

    override bool onMouseEvent(MouseEvent event) {
        Rect rc = _pos;

        if (event.action == MouseAction.Move) {
            if (_dragging) {
                // Pan
                _offsetX = _dragOriginX + (event.x - _dragStartX);
                _offsetY = _dragOriginY + (event.y - _dragStartY);
                invalidate();
                return true;
            }
            // Hover detection
            string hid = hitTestNode(event.x, event.y, rc);
            if (hid != _hoveredNodeId) {
                _hoveredNodeId = hid;
                invalidate();
            }
            return true;
        }

        if (event.action == MouseAction.ButtonDown) {
            bool middleOrRight =
                event.button == MouseButton.Middle ||
                event.button == MouseButton.Right;

            if (middleOrRight) {
                // Start pan drag
                _dragging    = true;
                _dragStartX  = event.x;
                _dragStartY  = event.y;
                _dragOriginX = _offsetX;
                _dragOriginY = _offsetY;
                return true;
            }

            if (event.button == MouseButton.Left) {
                string nid = hitTestNode(event.x, event.y, rc);
                if (nid != _selectedNodeId) {
                    _selectedNodeId = nid;
                    invalidate();
                }
                setFocus();
                return true;
            }
        }

        if (event.action == MouseAction.ButtonUp) {
            if (_dragging &&
                (event.button == MouseButton.Middle ||
                 event.button == MouseButton.Right))
            {
                _dragging = false;
                return true;
            }
        }

        if (event.action == MouseAction.ButtonDown && event.doubleClick) {
            if (event.button == MouseButton.Left) {
                string nid = hitTestNode(event.x, event.y, rc);
                if (nid.length > 0) {
                    const GraphNode* n = _data.findNode(nid);
                    if (n !is null && onNodeActivated !is null)
                        onNodeActivated(n.filePath, n.line);
                }
                return true;
            }
        }

        if (event.action == MouseAction.Wheel) {
            float factor = event.wheelDelta > 0 ? 1.1f : (1.0f / 1.1f);
            _scale = clampf(_scale * factor, 0.3f, 3.0f);
            invalidate();
            return true;
        }

        return super.onMouseEvent(event);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SymbolGraphPanel  (DockWindow host)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Dockable panel that hosts `SymbolGraphWidget` together with a small toolbar.
 */
class SymbolGraphPanel : DockWindow {

    // ── fields ────────────────────────────────────────────────────────────────

    private SymbolGraphWidget _graphWidget;
    private SymbolTracker     _tracker;
    private EditLine          _searchBox;
    private Button            _searchBtn;
    private Button            _fitBtn;
    private Button            _resetBtn;
    private TextWidget        _statusBar;

    // ── construction ─────────────────────────────────────────────────────────

    this(string id, SymbolTracker tracker) {
        super(id);
        _tracker = tracker;
        _caption.text = "Symbol Graph"d;
    }

    /// True if a SymbolTracker has been set.
    @property bool hasTracker() const { return _tracker !is null; }

    /// Inject or replace the tracker after construction.
    @property void tracker(SymbolTracker t) {
        _tracker = t;
        if (_graphWidget)
            _graphWidget.tracker = t;
    }

    // ── DockWindow body ───────────────────────────────────────────────────────

    override protected Widget createBodyWidget() {
        layoutWidth  = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        auto root = new VerticalLayout("sg_root");
        root.layoutWidth  = FILL_PARENT;
        root.layoutHeight = FILL_PARENT;

        // ── Toolbar ───────────────────────────────────────────────────────────
        auto toolbar = new HorizontalLayout("sg_toolbar");
        toolbar.layoutWidth  = FILL_PARENT;
        toolbar.layoutHeight = WRAP_CONTENT;
        toolbar.backgroundColor(0x252526);
        toolbar.padding(Rect(4, 2, 4, 2));

        _searchBox = new EditLine("sg_search");
        _searchBox.layoutWidth = FILL_PARENT;
        _searchBox.minWidth    = 140;
        _searchBox.setDefaultPopupMenu();
        _searchBox.contentChange = delegate(EditableContent content) {
            // live update on every keystroke
            string q = content.text.to!string.strip;
            if (q.length > 2)
                _onSearch(q);
        };

        _searchBtn = new Button("sg_searchbtn", "🔍"d);
        _searchBtn.click = delegate(Widget src) {
            _onSearch(_searchBox.text.to!string.strip);
            return true;
        };

        _fitBtn = new Button("sg_fit", "Fit"d);
        _fitBtn.click = delegate(Widget src) {
            _graphWidget.resetView();
            return true;
        };

        _resetBtn = new Button("sg_reset", "Reset"d);
        _resetBtn.click = delegate(Widget src) {
            _graphWidget.clearGraph();
            _updateStatus();
            return true;
        };

        _statusBar = new TextWidget("sg_status", ""d);
        _statusBar.fontSize(10);
        _statusBar.textColor(0x888888);
        _statusBar.padding(Rect(8, 0, 4, 0));

        auto colourModeBtn = new Button("sg_colourmode", "By File"d);
        colourModeBtn.fontSize(10);
        colourModeBtn.tooltipText = "Toggle colouring: by symbol kind vs by file/language"d;
        colourModeBtn.click = delegate(Widget src) {
            bool next = !_graphWidget.colourByFile;
            _graphWidget.colourByFile = next;
            (cast(Button)src).text = next ? "By Kind"d : "By File"d;
            return true;
        };

        toolbar.addChild(_searchBox);
        toolbar.addChild(_searchBtn);
        toolbar.addChild(_fitBtn);
        toolbar.addChild(_resetBtn);
        toolbar.addChild(colourModeBtn);
        toolbar.addChild(_statusBar);

        // ── Graph canvas ──────────────────────────────────────────────────────
        _graphWidget = new SymbolGraphWidget("sg_canvas", _tracker);
        _graphWidget.layoutWidth  = FILL_PARENT;
        _graphWidget.layoutHeight = FILL_PARENT;

        // Wire navigation callback — callers can override after construction
        _graphWidget.onNodeActivated = delegate(string fp, int line) {
            Log.d("SymbolGraphPanel: node activated fp=", fp, " line=", line);
            return false; // let frame handle it
        };

        root.addChild(toolbar);
        root.addChild(_graphWidget);

        return root;
    }

    // ── public API ────────────────────────────────────────────────────────────

    /// Load the graph for all symbols in a file.
    void showForFile(string filePath) {
        if (_graphWidget is null) return;
        _graphWidget.loadForFile(filePath);
        _updateStatus();
    }

    /// Load the star graph for a fully-qualified symbol name.
    void showForSymbol(string fqn) {
        if (_graphWidget is null) return;
        _graphWidget.loadForSymbol(fqn);
        _updateStatus();
    }

    // ── private helpers ───────────────────────────────────────────────────────

    private void _onSearch(string query) {
        if (query.length == 0) return;
        showForSymbol(query);
    }

    private void _updateStatus() {
        if (_statusBar is null || _graphWidget is null) return;
        string s = format("%d nodes  %d edges",
                          _graphWidget.nodeCount,
                          _graphWidget.edgeCount);
        _statusBar.text = s.to!dstring;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience free function
// ─────────────────────────────────────────────────────────────────────────────

/// Create and return a ready-to-dock SymbolGraphPanel.
SymbolGraphPanel createSymbolGraphPanel(SymbolTracker tracker) {
    return new SymbolGraphPanel("symbolGraphPanel", tracker);
}
