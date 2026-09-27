module dlangide.ui.terminalpanel;

import std.conv, std.string, std.format, std.path;
import dlangui;
import dlangui.widgets.docks;
import dlangui.core.logger;
import dlangide.ui.terminal;

class TerminalPanel : VerticalLayout {

    private TerminalWidget _term;
    private TextWidget     _shellLabel;
    private Button         _btnVerbose;
    private Button         _btn256c;
    private bool           _use256color = false;

    this() {
        super("terminalPanel");
        layoutWidth  = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        // ── Toolbar ──────────────────────────────────────────────────────────
        auto toolbar = new HorizontalLayout("termToolbar");
        toolbar.layoutWidth  = FILL_PARENT;
        toolbar.layoutHeight = WRAP_CONTENT;
        toolbar.backgroundColor = 0x1A1A1A;
        toolbar.padding(Rect(4, 2, 4, 2));

        // Shell indicator label
        _shellLabel = new TextWidget("termShellLabel");
        _shellLabel.text = detectShellLabel();
        _shellLabel.textColor = 0x7EC87E;
        _shellLabel.fontSize = 11;
        toolbar.addChild(_shellLabel);

        // Spacer
        auto spacer = new Widget("termToolbarSpacer");
        spacer.layoutWidth = FILL_PARENT;
        toolbar.addChild(spacer);

        // Clear button
        auto btnClear = new Button("termBtnClear", "Clear"d);
        btnClear.fontSize = 11;
        btnClear.click = delegate(Widget src) {
            _term.resetTerminal();
            _term.invalidate();
            return true;
        };
        toolbar.addChild(btnClear);

        // Verbose toggle
        _btnVerbose = new Button("termBtnVerbose", "Verbose \u2610"d);
        _btnVerbose.fontSize = 11;
        _btnVerbose.click = delegate(Widget src) {
            _term.verboseMode = !_term.verboseMode;
            _btnVerbose.text = _term.verboseMode ? "Verbose \u2611"d : "Verbose \u2610"d;
            return true;
        };
        toolbar.addChild(_btnVerbose);

        // 256-colour toggle
        _btn256c = new Button("termBtn256c", "256c \u2610"d);
        _btn256c.fontSize = 11;
        _btn256c.click = delegate(Widget src) {
            _use256color = !_use256color;
            _btn256c.text = _use256color ? "256c \u2611"d : "256c \u2610"d;
            if (_term.device) {
                _term.device.termType = _use256color ? "xterm-256color" : "xterm";
            }
            return true;
        };
        toolbar.addChild(_btn256c);

        // Settings placeholder
        auto btnSettings = new Button("termBtnSettings", "\u2699"d);
        btnSettings.fontSize = 11;
        btnSettings.click = delegate(Widget src) {
            Log.d("TerminalPanel: settings");
            return true;
        };
        toolbar.addChild(btnSettings);

        addChild(toolbar);

        // ── Terminal widget ───────────────────────────────────────────────────
        _term = new TerminalWidget("terminal", true);
        _term.layoutWidth  = FILL_PARENT;
        _term.layoutHeight = FILL_PARENT;
        _term.backgroundColor = 0x1A1A1A;

        addChild(_term);
    }

    /// Focus the terminal input
    void focusTerminal() {
        _term.setFocus();
    }

    /// Access the underlying TerminalWidget
    @property TerminalWidget terminal() { return _term; }

    private dstring detectShellLabel() {
        import std.process : environment;
        string sh = environment.get("SHELL", "");
        if (!sh.length)
            return "\u25cf shell"d;
        string base = baseName(sh);
        return cast(dstring)("\u25cf " ~ base);
    }
}
