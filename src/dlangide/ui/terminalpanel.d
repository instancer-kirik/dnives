module dlangide.ui.terminalpanel;

import std.conv, std.string, std.format, std.path;
import dlangui;
import dlangui.widgets.docks;
import dlangui.widgets.tabs;
import dlangui.core.logger;
import dlangide.ui.terminal;

/// One cell that holds either a shell or a split of two cells.
class TermSlot : FrameLayout {
    this(string id) {
        super(id);
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
    }
}

class TerminalPanel : VerticalLayout {

    private TabWidget _tabs;
    private TextWidget _shellLabel;
    private Button _btnVerbose;
    private Button _btn256c;
    private bool _use256color = false;
    private bool _effects = true;
    private int _seq;
    private TerminalWidget _focused;

    this() {
        super("terminalPanel");
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        auto toolbar = new HorizontalLayout("termToolbar");
        toolbar.styleId = "TERM_BAR";
        toolbar.layoutWidth = FILL_PARENT;
        toolbar.layoutHeight = WRAP_CONTENT;

        _shellLabel = new TextWidget("termShellLabel");
        _shellLabel.styleId = "TERM_BAR_LABEL";
        _shellLabel.text = detectShellLabel();
        toolbar.addChild(_shellLabel);

        auto spacer = new Widget("termToolbarSpacer");
        spacer.layoutWidth = FILL_PARENT;
        toolbar.addChild(spacer);

        toolbar.addChild(toolButton("New tab  Ctrl+Shift+T", "+", &newTab));
        toolbar.addChild(toolButton("Split right  Ctrl+Shift+R", "|", &splitRight));
        toolbar.addChild(toolButton("Split down  Ctrl+Shift+D", "\u2014", &splitDown));
        toolbar.addChild(toolButton("Close pane  Ctrl+Shift+W", "\u00d7", &closePane));

        auto btnClear = new Button("termBtnClear", "Clear"d);
        btnClear.styleId = "TERM_BAR_BUTTON";
        btnClear.click = delegate(Widget src) {
            if (_focused) {
                _focused.resetTerminal();
                _focused.invalidate();
            }
            return true;
        };
        toolbar.addChild(btnClear);

        _btnVerbose = new Button("termBtnVerbose", "Verbose \u2610"d);
        _btnVerbose.styleId = "TERM_BAR_BUTTON";
        _btnVerbose.click = delegate(Widget src) {
            if (!_focused)
                return true;
            _focused.verboseMode = !_focused.verboseMode;
            _btnVerbose.text = _focused.verboseMode ? "Verbose \u2611"d : "Verbose \u2610"d;
            return true;
        };
        toolbar.addChild(_btnVerbose);

        _btn256c = new Button("termBtn256c", "256c \u2610"d);
        _btn256c.styleId = "TERM_BAR_BUTTON";
        _btn256c.click = delegate(Widget src) {
            _use256color = !_use256color;
            _btn256c.text = _use256color ? "256c \u2611"d : "256c \u2610"d;
            applyTermType(_focused);
            return true;
        };
        toolbar.addChild(_btn256c);

        addChild(toolbar);

        _tabs = new TabWidget("termTabs");
        _tabs.layoutWidth = FILL_PARENT;
        _tabs.layoutHeight = FILL_PARENT;
        _tabs.tabClose = (string id) { closeTab(id); };
        addChild(_tabs);

        newTab();
    }

    void focusTerminal() {
        if (_focused)
            _focused.setFocus();
    }

    @property TerminalWidget terminal() { return _focused; }

    @property void effects(bool v) {
        _effects = v;
        if (_focused)
            _focused.effects = v;
    }

    private Button toolButton(string tip, string label, bool delegate() fn) {
        auto b = new Button(null, to!dstring(label));
        b.styleId = "TERM_BAR_BUTTON";
        b.tooltipText = to!dstring(tip);
        b.click = delegate(Widget) { return fn(); };
        return b;
    }

    private bool newTab() {
        _seq++;
        string id = "termTab" ~ to!string(_seq);
        auto slot = new TermSlot(id);
        auto leaf = makeLeaf();
        slot.addChild(leaf);
        _tabs.addTab(slot, ("shell " ~ to!string(_seq)).to!dstring, null, true);
        _tabs.selectTab(id);
        if (auto t = firstTerm(leaf))
            t.setFocus();
        return true;
    }

    private bool splitRight() { return split(false); }
    private bool splitDown() { return split(true); }

    private bool split(bool down) {
        auto slot = slotOf(_focused);
        if (!slot || slot.childCount != 1)
            return false;
        auto leaf = slot.removeChild(0);
        auto box = down ? cast(Widget) new VerticalLayout("split") : new HorizontalLayout("split");
        box.layoutWidth = FILL_PARENT;
        box.layoutHeight = FILL_PARENT;
        auto keep = new TermSlot("slot" ~ to!string(++_seq));
        auto extra = new TermSlot("slot" ~ to!string(++_seq));
        leaf.layoutWidth = FILL_PARENT;
        leaf.layoutHeight = FILL_PARENT;
        keep.addChild(leaf);
        extra.addChild(makeLeaf());
        box.addChild(keep);
        box.addChild(extra);
        slot.addChild(box);
        if (auto t = firstTerm(extra))
            t.setFocus();
        requestLayout();
        return true;
    }

    private bool closePane() {
        auto slot = slotOf(_focused);
        if (!slot)
            return false;
        auto box = slot.parent;
        auto grand = box ? cast(TermSlot) box.parent : null;
        if (grand && box.childCount == 2 && (cast(HorizontalLayout) box || cast(VerticalLayout) box)) {
            Widget other = box.child(0) is slot ? box.child(1) : box.child(0);
            box.removeChild(other);
            grand.removeAllChildren(true);
            grand.addChild(other);
            if (auto t = firstTerm(other))
                t.setFocus();
            requestLayout();
            return true;
        }
        string id = _tabs.selectedTabId;
        if (_tabs.tabCount > 1) {
            closeTab(id);
        } else {
            slot.removeAllChildren(true);
            auto leaf = makeLeaf();
            slot.addChild(leaf);
            if (auto t = firstTerm(leaf))
                t.setFocus();
        }
        return true;
    }

    private void closeTab(string id) {
        if (!id.length)
            return;
        bool last = _tabs.tabCount <= 1;
        _tabs.removeTab(id);
        if (last)
            newTab();
        else if (auto body = _tabs.tabBody(_tabs.selectedTabId)) {
            if (auto t = firstTerm(body))
                t.setFocus();
        }
    }

    private Widget makeLeaf() {
        _seq++;
        auto leaf = new VerticalLayout("leaf");
        leaf.layoutWidth = FILL_PARENT;
        leaf.layoutHeight = FILL_PARENT;
        auto term = new TerminalWidget("terminal" ~ to!string(_seq), true);
        term.layoutWidth = FILL_PARENT;
        term.layoutHeight = FILL_PARENT;
        term.backgroundColor = 0x1A1A1A;
        term.effects = _effects;
        term.hostKey = &onHostKey;
        term.hostFocus = &onHostFocus;
        applyTermType(term);
        leaf.addChild(term);
        _focused = term;
        return leaf;
    }

    private bool onHostKey(KeyEvent event) {
        if (event.action != KeyAction.KeyDown)
            return false;
        switch (event.keyCode) {
            case KeyCode.KEY_T: return newTab();
            case KeyCode.KEY_R: return splitRight();
            case KeyCode.KEY_D: return splitDown();
            case KeyCode.KEY_W: return closePane();
            default: return false;
        }
    }

    private void onHostFocus(TerminalWidget term) {
        _focused = term;
        _btnVerbose.text = term.verboseMode ? "Verbose \u2611"d : "Verbose \u2610"d;
    }

    private void applyTermType(TerminalWidget term) {
        if (term && term.device)
            term.device.termType = _use256color ? "xterm-256color" : "xterm";
    }

    private TermSlot slotOf(TerminalWidget term) {
        if (!term || !term.parent)
            return null;
        return cast(TermSlot) term.parent.parent;
    }

    private TerminalWidget firstTerm(Widget w) {
        if (auto t = cast(TerminalWidget) w)
            return t;
        if (!w)
            return null;
        for (int i = 0; i < w.childCount; i++) {
            if (auto t = firstTerm(w.child(i)))
                return t;
        }
        return null;
    }

    private dstring detectShellLabel() {
        import std.process : environment;
        string sh = environment.get("SHELL", "");
        if (!sh.length)
            return "\u25cf shell"d;
        string base = baseName(sh);
        return cast(dstring)("\u25cf " ~ base);
    }
}
