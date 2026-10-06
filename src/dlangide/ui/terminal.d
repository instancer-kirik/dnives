module dlangide.ui.terminal;

import dlangui.widgets.widget;
import dlangui.widgets.controls;
import dlangui.widgets.scrollbar;

struct TerminalAttr {
    ubyte bgColor = 0;
    ubyte textColor = 7;
    ubyte flags = 0;
}

struct TerminalChar {
    TerminalAttr attr;
    dchar ch = ' ';
}

__gshared static uint[16] TERMINAL_PALETTE = [
    0x000000, // black
    0xFF0000,
    0x00FF00,
    0xFFFF00,
    0x0000FF,
    0xFF00FF,
    0x00FFFF,
    0xC0C0C0, // white
    0x808080,
    0x800000,
    0x008000,
    0x808000,
    0x000080,
    0x800080,
    0x008080,
    0xFFFFFF,
];

uint attrToColor(ubyte v) {
    if (v >= 16)
        return 0;
    return TERMINAL_PALETTE[v];
}

struct TerminalLine {
    TerminalChar[] line;
    bool overflowFlag;
    bool eolFlag;
    void clear() {
        line.length = 0;
        overflowFlag = false;
        eolFlag = false;
    }
    void markLineOverflow() {}
    void markLineEol() {}
    void putCharAt(dchar ch, int x, TerminalAttr currentAttr) {
        if (x >= line.length) {
            TerminalChar d;
            d.attr = currentAttr;
            d.ch = ' ';
            while (x >= line.length) {
                line.assumeSafeAppend;
                line ~= d;
            }
        }
        line[x].attr = currentAttr;
        line[x].ch = ch;
    }
}

struct TerminalContent {
    TerminalLine[] lines;
    Rect rc;
    FontRef font;
    TerminalAttr currentAttr;
    TerminalAttr defAttr;
    int maxBufferLines = 3000;
    int topLine;
    int width; // width in chars
    int height; // height in chars
    int charw; // single char width
    int charh; // single char height
    int cursorx;
    int cursory;
    bool focused;
    bool _lineWrap = true;
    @property void lineWrap(bool v) {
        _lineWrap = v;
    }
    void clear() {
        lines.length = 0;
        cursorx = cursory = topLine= 0;
    }
    void resetTerminal() {
        for (int i = topLine; i < cast(int)lines.length; i++) {
            lines[i] = TerminalLine.init;
        }
        cursorx = 0;
        cursory = topLine;
    }
    @property int screenTopLine() {
        int y = cast(int)lines.length - height;
        if (y < 0)
            y = 0;
        return y;
    }
    void eraseScreen(int direction, bool forLine) {
        if (forLine) {
            for (int x = 0; x < width; x++) {
                if ((direction == 1 && x <= cursorx) || (direction < 1 && x >= cursorx) || (direction == 2))
                    putCharAt(' ', x, cursory);
            }
        } else {
            int screenTop = screenTopLine;
            for (int y = 0; y < height; y++) {
                int yy = screenTop + y;
                if ((direction == 1 && yy <= cursory) || (direction < 1 && yy >= cursory) || (direction == 2)) {
                    for (int x = 0; x < width; x++) {
                        putCharAt(' ', x, yy);
                    }
                }
            }
            if (direction == 2) {
                cursorx = 0;
                cursory = screenTop;
            }
        }
    }
    void moveCursorBy(int x, int y) {
        if (x) {
            cursorx += x;
            if (cursorx < 0)
                cursorx = 0;
            if (cursorx > width)
                cursorx = width;
        } else if (y) {
            int screenTop = screenTopLine;
            cursory += y;
            if (cursory < screenTop)
                cursory = screenTop;
            else if (cursory >= screenTop + height)
                cursory = screenTop + height - 1;
        }
    }
    void setAttributes(int[] attrs) {
        foreach (attr; attrs) {
            if (attr < 0)
                continue;
            if (attr >= 30 && attr <= 37) {
                currentAttr.textColor = cast(ubyte)(attr - 30);
            } else if (attr >= 40 && attr <= 47) {
                currentAttr.bgColor = cast(ubyte)(attr - 40);
            } else if (attr >= 0 && attr <= 10) {
                switch(attr) {
                    case 0:
                        currentAttr = defAttr;
                        break;
                    case 1:
                    case 2:
                    case 4:
                    case 5:
                    case 7:
                    case 8:
                    default:
                        break;

                }
            }
        }
    }
    void moveCursorTo(int x, int y) {
        int screenTop = screenTopLine;
        if (x < 0 || y < 0) {
            cursorx = 0;
            cursory = screenTop;
            return;
        }
        if (x >= 1 && x <= width + 1 && y >= 1 && x <= height) {
            cursorx = x - 1;
            cursory = screenTop + y - 1;
        }
    }
    void layout(FontRef font, Rect rc) {
        this.rc = rc;
        this.font = font;
        this.charw = font.charWidth('0');
        this.charh = font.height;
        if (charw < 1)
            charw = 8;
        if (charh < 1)
            charh = 16;
        int w = rc.width / charw;
        int h = rc.height / charh;
        setViewSize(w, h);
    }
    void setViewSize(int w, int h) {
        if (h < 2)
            h = 2;
        if (w < 16)
            w = 16;
        width = w;
        height = h;
    }
    void draw(DrawBuf buf) {
        Rect lineRect = rc;
        dchar[] text;
        text.length = 1;
        text[0] = ' ';
        int screenTopLine = cast(int)lines.length - height;
        if (screenTopLine < 0)
            screenTopLine = 0;
        for (uint i = 0; i < height && i + topLine < lines.length; i++) {
            lineRect.bottom = lineRect.top + charh;
            TerminalLine * p = &lines[i + topLine];
            // draw line in rect
            for (int x = 0; x < width; x++) {
                bool isCursorPos = x == cursorx && i + topLine == cursory;
                TerminalChar ch = x < p.line.length ? p.line[x] : TerminalChar.init;
                uint bgcolor = attrToColor(ch.attr.bgColor);
                uint textcolor = attrToColor(ch.attr.textColor);
                if (cellSelected(x, i + topLine)) {
                    bgcolor = 0x3A6EA5;
                    textcolor = 0xFFFFFF;
                }
                if (isCursorPos && focused) {
                    // invert
                    uint tmp = bgcolor;
                    bgcolor = textcolor;
                    textcolor = tmp;
                }
                Rect charrc = lineRect;
                charrc.left = lineRect.left + x * charw;
                charrc.right = charrc.left + charw;
                charrc.bottom = charrc.top + charh;
                buf.fillRect(charrc, bgcolor);
                if (isCursorPos) {
                    buf.drawFrame(charrc, focused ? (textcolor | 0xC0000000) : (textcolor | 0x80000000), Rect(1,1,1,1));
                }
                if (ch.ch >= ' ') {
                    text[0] = ch.ch;
                    font.drawText(buf, charrc.left, charrc.top, text, textcolor);
                }
            }
            lineRect.top = lineRect.bottom;
        }
    }

    void clearExtraLines(ref int yy) {
        int y = cast(int)lines.length;
        if (y >= maxBufferLines) {
            int delta = y - maxBufferLines;
            for (uint i = 0; i + delta < maxBufferLines && i + delta < lines.length; i++) {
                lines[i] = lines[i + delta];
            }
            lines.length = lines.length - delta;
            yy -= delta;
            topLine -= delta;
            if (topLine < 0)
                topLine = 0;
        }
    }

    TerminalLine * getLine(ref int yy) {
        if (yy < 0)
            yy = 0;
        while(yy >= cast(int)lines.length) {
            lines ~= TerminalLine.init;
        }
        clearExtraLines(yy);
        return &lines[yy];
    }
    void putCharAt(dchar ch, ref int x, ref int y) {
        if (x < 0)
            x = 0;
        TerminalLine * line = getLine(y);
        if (x >= width) {
            if (!_lineWrap) {
                x = width > 0 ? width - 1 : 0;
            } else {
                line.markLineOverflow();
                y++;
                line = getLine(y);
                x = 0;
            }
        }
        line.putCharAt(ch, x, currentAttr);
        ensureCursorIsVisible();
    }
    int tabSize = 8;
    // supports printed characters and \r \n \t
    void putChar(dchar ch) {
        if (ch == '\a') {
            // bell
            return;
        }
        if (ch == '\b') {
            // backspace
            if (cursorx > 0) {
                cursorx--;
                putCharAt(' ', cursorx, cursory);
                ensureCursorIsVisible();
            }
            return;
        }
        if (ch == '\r') {
            cursorx = 0;
            ensureCursorIsVisible();
            return;
        }
        if (ch == '\n' || ch == '\f' || ch == '\v') {
            TerminalLine * line = getLine(cursory);
            line.markLineEol();
            cursory++;
            line = getLine(cursory);
            cursorx = 0;
            ensureCursorIsVisible();
            return;
        }
        if (ch == '\t') {
            int newx = (cursorx + tabSize) / tabSize * tabSize;
            if (newx > width) {
                TerminalLine * line = getLine(cursory);
                line.markLineEol();
                cursory++;
                line = getLine(cursory);
                cursorx = 0;
            } else {
                for (int x = cursorx; x < newx; x++) {
                    putCharAt(' ', cursorx, cursory);
                    cursorx++;
                }
            }
            ensureCursorIsVisible();
            return;
        }
        putCharAt(ch, cursorx, cursory);
        cursorx++;
        ensureCursorIsVisible();
    }

    void ensureCursorIsVisible() {
        topLine = cast(int)lines.length - height;
        if (topLine < 0)
            topLine = 0;
        if (cursory < topLine)
            cursory = topLine;
    }

    void updateScrollBar(ScrollBar sb) {
        sb.pageSize = height;
        sb.maxValue = cast(int)lines.length;
        sb.position = topLine;
    }

    void scrollTo(int y) {
        if (y + height > lines.length)
            y = cast(int)lines.length - height;
        if (y < 0)
            y = 0;
        topLine = y;
    }

    int selX0 = -1, selY0, selX1, selY1;

    bool hasSelection() { return selX0 >= 0; }

    void clearSelection() { selX0 = -1; }

    void setSelection(int x0, int y0, int x1, int y1) {
        selX0 = x0; selY0 = y0; selX1 = x1; selY1 = y1;
    }

    bool cellSelected(int x, int y) {
        if (selX0 < 0)
            return false;
        long a = cast(long)selY0 * 100000 + selX0;
        long b = cast(long)selY1 * 100000 + selX1;
        if (a > b) { auto t = a; a = b; b = t; }
        long c = cast(long)y * 100000 + x;
        return c >= a && c <= b;
    }

    void cellAt(int px, int py, out int x, out int y) {
        x = charw > 0 ? (px - rc.left) / charw : 0;
        y = charh > 0 ? topLine + (py - rc.top) / charh : 0;
        if (x < 0) x = 0;
        if (x >= width) x = width > 0 ? width - 1 : 0;
        if (y < 0) y = 0;
        if (y >= cast(int)lines.length)
            y = lines.length ? cast(int)lines.length - 1 : 0;
    }

    void selectWordAt(int x, int y) {
        if (y < 0 || y >= cast(int)lines.length) {
            setSelection(x, y, x, y);
            return;
        }
        auto line = lines[y].line;
        int a = x, b = x;
        bool word(dchar ch) { return ch > ' ' && ch != '(' && ch != ')' && ch != '"' && ch != '\''; }
        while (a > 0 && a < cast(int)line.length && word(line[a - 1].ch))
            a--;
        while (b + 1 < cast(int)line.length && word(line[b + 1].ch))
            b++;
        setSelection(a, y, b, y);
    }

    void selectAll() {
        if (!lines.length) {
            clearSelection();
            return;
        }
        int last = cast(int)lines.length - 1;
        int endx = cast(int)lines[last].line.length;
        if (endx > 0) endx--;
        setSelection(0, 0, endx, last);
    }

    dstring selectedText() {
        if (!hasSelection())
            return null;
        int x0 = selX0, y0 = selY0, x1 = selX1, y1 = selY1;
        if (y0 > y1 || (y0 == y1 && x0 > x1)) {
            auto tx = x0; x0 = x1; x1 = tx;
            auto ty = y0; y0 = y1; y1 = ty;
        }
        dchar[] out_;
        for (int y = y0; y <= y1 && y < cast(int)lines.length; y++) {
            auto line = lines[y].line;
            int from = y == y0 ? x0 : 0;
            int to = y == y1 ? x1 : cast(int)line.length - 1;
            if (from < 0) from = 0;
            for (int x = from; x <= to && x < cast(int)line.length; x++)
                out_ ~= line[x].ch;
            if (y < y1)
                out_ ~= '\n';
        }
        while (out_.length && (out_[$-1] == ' ' || out_[$-1] == '\n'))
            out_.length--;
        return cast(dstring)out_;
    }

}

class TerminalWidget : WidgetGroup, OnScrollHandler {
    protected ScrollBar _verticalScrollBar;
    protected TerminalContent _content;
    protected TerminalDevice _device;
    protected bool _interactive;
    private bool _pendingCreate = false;
    public bool verboseMode = false;
    /// Sparks on typing, burst on Enter.
    public bool effects = true;
    /// Panel handles tab and split shortcuts before the shell sees them.
    bool delegate(KeyEvent) hostKey;
    void delegate(TerminalWidget) hostFocus;
    private TermParticle[] _particles;
    private Random _rnd;
    private ulong _fxTimer;
    private bool _selecting;
    this() {
        this(null, false);
    }
    this(string ID, bool interactive = false) {
        super(ID);
        _interactive = interactive;
        styleId = "TERMINAL";
        focusable = interactive;
        _verticalScrollBar = new ScrollBar("VERTICAL_SCROLLBAR", Orientation.Vertical);
        _verticalScrollBar.minValue = 0;
        _verticalScrollBar.scrollEvent = this;
        addChild(_verticalScrollBar);
        _rnd = Random(unpredictableSeed);
        _device = new TerminalDevice();
        if (interactive) {
            _pendingCreate = true;
        } else {
            _setupDevice(false);
        }
    }

    /// returns the underlying TerminalDevice
    @property TerminalDevice device() { return _device; }

    private void _setupDevice(bool interactive) {
        TerminalWidget _this = this;
        if (_device.create(interactive)) {
            _device.onBytesRead = delegate (string data) {
                import dlangui.platforms.common.platform;
                Window w = window;
                if (w) {
                    w.executeInUiThread(delegate() {
                        if (w.isChild(_this)) {
                            write(data);
                            w.update(true);
                        }
                    });
                }
            };
        }
    }
    ~this() {
        if (_device)
            destroy(_device);
    }

    /// returns terminal/tty device (or named pipe for windows) name
    @property string deviceName() { return _device ? _device.deviceName : null; }

    void scrollTo(int y) {
        _content.scrollTo(y);
    }

    /// handle scroll event
    bool onScrollEvent(AbstractSlider source, ScrollEvent event) {
        switch(event.action) {
            /// space above indicator pressed
            case ScrollAction.PageUp:
                scrollTo(_content.topLine - (_content.height ? _content.height - 1 : 1));
                break;
            /// space below indicator pressed
            case ScrollAction.PageDown:
                scrollTo(_content.topLine + (_content.height ? _content.height - 1 : 1));
                break;
            /// up/left button pressed
            case ScrollAction.LineUp:
                scrollTo(_content.topLine - 1);
                break;
            /// down/right button pressed
            case ScrollAction.LineDown:
                scrollTo(_content.topLine + 1);
                break;
            /// slider pressed
            case ScrollAction.SliderPressed:
                break;
            /// dragging in progress
            case ScrollAction.SliderMoved:
                scrollTo(event.position);
                break;
            /// dragging finished
            case ScrollAction.SliderReleased:
                break;
            default:
                break;
        }
        return true;
    }

    /// check echo mode
    @property bool echo() { return _echo; }
    /// set echo mode
    @property void echo(bool b) { _echo = b; }

    Signal!TerminalInputHandler onBytesRead;
    protected bool _echo = false;
    bool handleTextInput(dstring str) {
        import std.utf;
        string s8 = toUTF8(str);
        if (effects && str.length && str[0] >= ' ')
            burstAtCursor(14, 3.2f);
        if (_echo)
            write(s8);
        if (_device)
            _device.write(s8);
        if (onBytesRead.assigned) {
            onBytesRead(s8);
        }
        return true;
    }

    override bool onKeyEvent(KeyEvent event) {
        if (event.action == KeyAction.Text) {
            dstring text = event.text;
            if (text.length)
                handleTextInput(text);
            return true;
        }
        if (event.action == KeyAction.KeyDown) {
            bool ctrl = (event.flags & KeyFlag.Control) != 0;
            bool shift = (event.flags & KeyFlag.Shift) != 0;
            if (ctrl && event.keyCode == KeyCode.TAB)
                return false;
            if (hostKey && ctrl && shift && hostKey(event))
                return true;
            if (ctrl && event.keyCode == KeyCode.KEY_C) {
                if (_content.hasSelection()) {
                    copySelection();
                    return true;
                }
                return handleTextInput("\x03");
            }
            if ((ctrl && event.keyCode == KeyCode.KEY_V) || (shift && event.keyCode == KeyCode.INS)) {
                pasteClipboard();
                return true;
            }
            if (ctrl && shift && event.keyCode == KeyCode.KEY_A) {
                _content.selectAll();
                invalidate();
                return true;
            }
            if (effects && event.keyCode == KeyCode.RETURN)
                burstAtCursor(90, 7.0f);
            dstring flagsstr;
            dstring flagsstr2;
            dstring flagsstr3;
            if ((event.flags & KeyFlag.MainFlags) == KeyFlag.Menu) {
                flagsstr = "1;1";
                flagsstr2 = ";1";
                flagsstr3 = "1";
            }
            if ((event.flags & KeyFlag.MainFlags) == KeyFlag.Shift) {
                flagsstr = "1;2";
                flagsstr2 = ";2";
                flagsstr3 = "2";
            }
            if ((event.flags & KeyFlag.MainFlags) == KeyFlag.Alt) {
                flagsstr = "1;3";
                flagsstr2 = ";3";
                flagsstr3 = "3";
            }
            if ((event.flags & KeyFlag.MainFlags) == KeyFlag.Control) {
                flagsstr = "1;5";
                flagsstr2 = ";5";
                flagsstr3 = ";5";
            }
            switch (event.keyCode) {
                case KeyCode.ESCAPE:
                    return handleTextInput("\x1b");
                case KeyCode.RETURN:
                    return handleTextInput("\n");
                case KeyCode.TAB:
                    return handleTextInput("\t");
                case KeyCode.BACK:
                    return handleTextInput("\x7f");
                case KeyCode.F1:
                    return handleTextInput("\x1bO" ~ flagsstr3 ~ "P");
                case KeyCode.F2:
                    return handleTextInput("\x1bO" ~ flagsstr3 ~ "Q");
                case KeyCode.F3:
                    return handleTextInput("\x1bO" ~ flagsstr3 ~ "R");
                case KeyCode.F4:
                    return handleTextInput("\x1bO" ~ flagsstr3 ~ "S");
                case KeyCode.F5:
                    return handleTextInput("\x1b[15" ~ flagsstr2 ~ "~");
                case KeyCode.F6:
                    return handleTextInput("\x1b[17" ~ flagsstr2 ~ "~");
                case KeyCode.F7:
                    return handleTextInput("\x1b[18" ~ flagsstr2 ~ "~");
                case KeyCode.F8:
                    return handleTextInput("\x1b[19" ~ flagsstr2 ~ "~");
                case KeyCode.F9:
                    return handleTextInput("\x1b[20" ~ flagsstr2 ~ "~");
                case KeyCode.F10:
                    return handleTextInput("\x1b[21" ~ flagsstr2 ~ "~");
                case KeyCode.F11:
                    return handleTextInput("\x1b[23" ~ flagsstr2 ~ "~");
                case KeyCode.F12:
                    return handleTextInput("\x1b[24" ~ flagsstr2 ~ "~");
                case KeyCode.LEFT:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "D");
                case KeyCode.RIGHT:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "C");
                case KeyCode.UP:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "A");
                case KeyCode.DOWN:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "B");
                case KeyCode.INS:
                    return handleTextInput("\x1b[2" ~ flagsstr2 ~ "~");
                case KeyCode.DEL:
                    return handleTextInput("\x1b[3" ~ flagsstr2 ~ "~");
                case KeyCode.HOME:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "H");
                case KeyCode.END:
                    return handleTextInput("\x1b[" ~ flagsstr ~ "F");
                case KeyCode.PAGEUP:
                    return handleTextInput("\x1b[5" ~ flagsstr2 ~ "~");
                case KeyCode.PAGEDOWN:
                    return handleTextInput("\x1b[6" ~ flagsstr2 ~ "~");
                default:
                    break;
            }
        }
        if (event.action == KeyAction.KeyUp) {
            switch (event.keyCode) {
                case KeyCode.ESCAPE:
                case KeyCode.RETURN:
                case KeyCode.TAB:
                case KeyCode.BACK:
                case KeyCode.F1:
                case KeyCode.F2:
                case KeyCode.F3:
                case KeyCode.F4:
                case KeyCode.F5:
                case KeyCode.F6:
                case KeyCode.F7:
                case KeyCode.F8:
                case KeyCode.F9:
                case KeyCode.F10:
                case KeyCode.F11:
                case KeyCode.F12:
                case KeyCode.UP:
                case KeyCode.DOWN:
                case KeyCode.LEFT:
                case KeyCode.RIGHT:
                case KeyCode.HOME:
                case KeyCode.END:
                case KeyCode.PAGEUP:
                case KeyCode.PAGEDOWN:
                    return true;
                default:
                    break;
            }
        }
        return super.onKeyEvent(event);
    }

    /**
    Measure widget according to desired width and height constraints. (Step 1 of two phase layout).

    */
    override void measure(int parentWidth, int parentHeight) {
        int w = (parentWidth == SIZE_UNSPECIFIED) ? font.charWidth('0') * 80 : parentWidth;
        int h = (parentHeight == SIZE_UNSPECIFIED) ? font.height * 10 : parentHeight;
        Rect rc = Rect(0, 0, w, h);
        applyMargins(rc);
        applyPadding(rc);
        _verticalScrollBar.measure(rc.width, rc.height);
        rc.right -= _verticalScrollBar.measuredWidth;
        measuredContent(parentWidth, parentHeight, rc.width, rc.height);
    }

    /// Set widget rectangle to specified value and layout widget contents. (Step 2 of two phase layout).
    override void layout(Rect rc) {
        if (visibility == Visibility.Gone) {
            return;
        }
        _pos = rc;
        _needLayout = false;
        applyMargins(rc);
        applyPadding(rc);
        Rect sbrc = rc;
        sbrc.left = sbrc.right - _verticalScrollBar.measuredWidth;
        _verticalScrollBar.layout(sbrc);
        rc.right = sbrc.left;
        _content.layout(font, rc);
        if (_pendingCreate) {
            _pendingCreate = false;
            _setupDevice(true);
        }
        notifyPtySize();
        if (outputChars.length) {
            // push buffered text
            write(""d);
            _needLayout = false;
        }
    }
    /// Draw widget at its position to buffer
    override void onDraw(DrawBuf buf) {
        if (visibility != Visibility.Visible)
            return;
        Rect rc = _pos;
        applyMargins(rc);
        auto saver = ClipRectSaver(buf, rc, alpha);
        DrawableRef bg = backgroundDrawable;
        if (!bg.isNull) {
            bg.drawTo(buf, rc, state);
        }
        applyPadding(rc);
        _verticalScrollBar.onDraw(buf);
        _content.draw(buf);
        drawParticles(buf);
    }

    override bool onMouseEvent(MouseEvent event) {
        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Right) {
            showTermMenu(event.x, event.y);
            return true;
        }
        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Middle) {
            pasteClipboard();
            return true;
        }
        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Left) {
            setFocus();
            int x, y;
            _content.cellAt(event.x, event.y, x, y);
            if (event.doubleClick)
                _content.selectWordAt(x, y);
            else if (event.tripleClick)
                _content.setSelection(0, y, _content.width - 1, y);
            else {
                _selecting = true;
                _content.setSelection(x, y, x, y);
            }
            invalidate();
            return true;
        }
        if (_selecting && (event.action == MouseAction.Move || event.action == MouseAction.FocusOut)) {
            int x, y;
            _content.cellAt(event.x, event.y, x, y);
            _content.selX1 = x;
            _content.selY1 = y;
            invalidate();
            return true;
        }
        if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Left) {
            _selecting = false;
            if (_content.hasSelection() && _content.selX0 == _content.selX1 && _content.selY0 == _content.selY1)
                _content.clearSelection();
            invalidate();
            return true;
        }
        return super.onMouseEvent(event);
    }

    override bool onTimer(ulong id) {
        if (id != _fxTimer)
            return super.onTimer(id);
        bool alive;
        foreach (ref p; _particles) {
            p.x += p.vx;
            p.y += p.vy;
            p.vy += 0.18f;
            p.life--;
            if (p.life > 0)
                alive = true;
        }
        if (!alive) {
            _particles.length = 0;
            cancelTimer(_fxTimer);
            _fxTimer = 0;
        }
        invalidate();
        return true;
    }

    private void ensureFxTimer() {
        if (!_fxTimer)
            _fxTimer = setTimer(16);
    }

    private void cursorPixels(out float x, out float y) {
        x = _content.rc.left + _content.cursorx * _content.charw;
        int row = _content.cursory - _content.topLine;
        y = _content.rc.top + row * _content.charh + _content.charh / 2;
    }

    private void burstAtCursor(int count, float speed) {
        float x, y;
        cursorPixels(x, y);
        uint[5] colors = [0xFFFFC14D, 0xFFFF6B2C, 0xFFFFF1A8, 0xFFFF3B30, 0xFFFFFFFF];
        for (int i = 0; i < count; i++) {
            float ang = uniform(0.0f, cast(float)(2.0 * PI), _rnd);
            float sp = uniform(0.6f, speed, _rnd);
            TermParticle p;
            p.x = x;
            p.y = y;
            p.vx = cos(ang) * sp;
            p.vy = sin(ang) * sp - uniform(0.0f, 2.0f, _rnd);
            p.size = uniform(1.5f, 4.0f, _rnd);
            p.color = colors[uniform(0, colors.length, _rnd)];
            p.life = uniform(10, 28, _rnd);
            p.lifeMax = p.life;
            _particles ~= p;
        }
        if (_particles.length > 800)
            _particles = _particles[$ - 800 .. $];
        ensureFxTimer();
    }

    private void drawParticles(DrawBuf buf) {
        foreach (p; _particles) {
            if (p.life <= 0)
                continue;
            ubyte a = cast(ubyte)(255 * p.life / (p.lifeMax ? p.lifeMax : 1));
            uint c = (p.color & 0x00FFFFFF) | (a << 24);
            int s = cast(int)p.size;
            if (s < 1) s = 1;
            buf.fillRect(Rect(cast(int)p.x, cast(int)p.y, cast(int)p.x + s, cast(int)p.y + s), c);
        }
    }

    void copySelection() {
        auto text = _content.selectedText();
        if (text.length)
            platform.setClipboardText(text);
    }

    void pasteClipboard() {
        dstring text = platform.getClipboardText();
        if (text.length)
            handleTextInput(text);
    }

    private bool onTermMenu(const Action a) {
        switch (a.id) {
            case TermMenu.Copy:
                copySelection();
                return true;
            case TermMenu.Paste:
                pasteClipboard();
                return true;
            case TermMenu.SelectAll:
                _content.selectAll();
                invalidate();
                return true;
            case TermMenu.ToggleFx:
                effects = !effects;
                return true;
            default:
                return false;
        }
    }

    private void showTermMenu(int x, int y) {
        import dlangui.widgets.menu;
        import dlangui.widgets.popup;
        auto menu = new MenuItem();
        menu.add(new Action(TermMenu.Copy, "Copy"d));
        menu.add(new Action(TermMenu.Paste, "Paste"d));
        menu.add(new Action(TermMenu.SelectAll, "Select All"d));
        menu.add(new Action(TermMenu.ToggleFx, effects ? "Effects On"d : "Effects Off"d));
        menu.menuItemAction = &onTermMenu;
        if (window)
            window.showPopup(new PopupMenu(menu), this, PopupAlign.Point, x, y);
    }

    private char[] outputBuffer;
    // write utf 8
    void write(string bytes) {
        if (!bytes.length)
            return;
        import std.utf;
        outputBuffer.assumeSafeAppend;
        outputBuffer ~= bytes;
        size_t index = 0;
        dchar[] decoded;
        decoded.assumeSafeAppend;
        dchar ch = 0;
        while (index < outputBuffer.length) {
            size_t oldindex = index;
            try {
                ch = decode(outputBuffer, index);
                decoded ~= ch;
            } catch (UTFException e) {
                if (index + 4 <= outputBuffer.length) {
                    // just append invalid character
                    ch = '?';
                    index++;
                }
            }
            if (oldindex == index)
                break;
        }
        if (index > 0) {
            // move content
            for (size_t i = 0; i + index < outputBuffer.length; i++)
                outputBuffer[i] = outputBuffer[i + index];
            outputBuffer.length = outputBuffer.length - index;
        }
        if (decoded.length)
            write(cast(dstring)decoded);
    }

    static bool parseParam(dchar[] buf, ref int index, ref int value) {
        if (index >= buf.length)
            return false;
        if (buf[index] < '0' || buf[index] > '9')
            return false;
        value = 0;
        while (index < buf.length && buf[index] >= '0' && buf[index] <= '9') {
            value = value * 10 + (buf[index] - '0');
            index++;
        }
        return true;
    }

    void handleInput(dstring chars) {
        import std.utf;
        _device.write(chars.toUTF8);
    }

    private void replyToHost(string s) {
        if (_device && s.length)
            _device.write(s);
    }

    /// Answer xterm terminfo queries so fish does not time out and print the raw request.
    /// Status 0 means the capability is unknown, which is enough for fish to move on.
    private void replyXtGetTcap(dchar[] payload) {
        if (payload.length < 2 || payload[0] != '+' || payload[1] != 'q')
            return;
        dchar[] hex = payload[2 .. $];
        size_t p = 0;
        while (p < hex.length) {
            size_t end = p;
            while (end < hex.length && hex[end] != ';')
                end++;
            if (end > p) {
                char[] out_;
                out_ ~= 0x1b;
                out_ ~= 'P';
                out_ ~= '0';
                out_ ~= '+';
                out_ ~= 'r';
                foreach (ch; hex[p .. end])
                    out_ ~= cast(char) ch;
                out_ ~= 0x1b;
                out_ ~= '\\';
                replyToHost(cast(string) out_);
            }
            p = end + 1;
        }
    }

    void resetTerminal() {
        _content.clear();
        _content.updateScrollBar(_verticalScrollBar);
    }

    private dchar[] outputChars;
    // write utf32
    void write(dstring chars) {
        if (!chars.length && !outputChars.length)
            return;
        outputChars.assumeSafeAppend;
        outputChars ~= chars;
        if (!_content.width)
            return;
        uint i = 0;
        for (; i < outputChars.length; i++) {
            bool unfinished = false;
            dchar ch = outputChars[i];
            dchar ch2 = i + 1 < outputChars.length ? outputChars[i + 1] : 0;
            dchar ch3 = i + 2 < outputChars.length ? outputChars[i + 2] : 0;
            //dchar ch4 = i + 3 < outputChars.length ? outputChars[i + 3] : 0;
            if (ch < ' ') {
                // control character
                if (ch == 27) {
                    if (ch2 == 0)
                        break; // unfinished ESC sequence
                    // ESC sequence
                    if (ch2 == '[') {
                        // ESC [
                        if (!ch3)
                            break; // unfinished
                        int param1 = -1;
                        int param2 = -1;
                        int[] extraParams;
                        int index = i + 2;
                        dchar priv = 0;
                        if (index < outputChars.length && (outputChars[index] == '?' || outputChars[index] == '>' || outputChars[index] == '=')) {
                            priv = outputChars[index];
                            index++;
                        }
                        parseParam(outputChars, index, param1);
                        if (index < outputChars.length && outputChars[index] == ';') {
                            index++;
                            parseParam(outputChars, index, param2);
                        }
                        while (index < outputChars.length && outputChars[index] == ';') {
                            index++;
                            int n = -1;
                            parseParam(outputChars, index, n);
                            if (n >= 0)
                                extraParams ~= n;
                        }
                        while (index < outputChars.length && outputChars[index] >= 0x20 && outputChars[index] <= 0x2F)
                            index++;
                        if (index >= outputChars.length)
                            break; // unfinished sequence: not enough chars
                        int param1def1 = param1 >= 1 ? param1 : 1;
                        ch3 = outputChars[index];
                        i = index;
                        if (ch3 == 'm') {
                            // set attributes
                            _content.setAttributes([param1, param2]);
                            if (extraParams.length)
                                _content.setAttributes(extraParams);
                        }
                        // command is parsed completely, ch3 == command type char

                        // ESC[7h and ESC[7l -- enable/disable line wrap
                        if (param1 == '7' && (ch3 == 'h' || ch3 == 'l')) {
                            _content.lineWrap(ch3 == 'h');
                            continue;
                        }
                        if (ch3 == 'H' || ch3 == 'f') {
                            _content.moveCursorTo(param2, param1);
                            continue;
                        }
                        if (ch3 == 'A') { // cursor up
                            _content.moveCursorBy(0, -param1def1);
                            continue;
                        }
                        if (ch3 == 'B') { // cursor down
                            _content.moveCursorBy(0, param1def1);
                            continue;
                        }
                        if (ch3 == 'C') { // cursor forward
                            _content.moveCursorBy(param1def1, 0);
                            continue;
                        }
                        if (ch3 == 'D') { // cursor back
                            _content.moveCursorBy(-param1def1, 0);
                            continue;
                        }
                        if (ch3 == 'K' || ch3 == 'J') {
                            _content.eraseScreen(param1, ch3 == 'K');
                            continue;
                        }
                        if (ch3 == 'c') {
                            // Primary / secondary device attributes. Fish waits ~10s if unanswered.
                            if (priv == '>')
                                replyToHost("\x1b[>0;0;0c");
                            else
                                replyToHost("\x1b[?64;1;2;6;9;15;22c");
                            continue;
                        }
                        if (ch3 == 'n' && param1 == 5) {
                            replyToHost("\x1b[0n");
                            continue;
                        }
                        if (ch3 == 'n' && param1 == 6) {
                            int row = _content.cursory - _content.topLine + 1;
                            int col = _content.cursorx + 1;
                            if (row < 1) row = 1;
                            if (col < 1) col = 1;
                            import std.conv : to;
                            replyToHost("\x1b[" ~ to!string(row) ~ ";" ~ to!string(col) ~ "R");
                            continue;
                        }
                    } else switch(ch2) {
                    case 'c':
                        _content.resetTerminal();
                        i++;
                        break;
                    case '=': // Set alternate keypad mode
                    case '>': // Set numeric keypad mode
                    case 'N': // Set single shift 2
                    case 'O': // Set single shift 3
                    case 'H': // Set a tab at the current column
                    case '<': // Enter/exit ANSI mode (VT52)
                        i++;
                        // ignore
                        break;
                    case '(': // default font
                    case ')': // alternate font
                        i++;
                        i++;
                        // ignore
                        break;
                    case 'P': {
                        // DCS — consume until BEL or ST. Fish XTGETTCAP is ESC P + q <hex> ST.
                        uint start = i + 2;
                        uint j = start;
                        bool closed = false;
                        while (j < outputChars.length) {
                            if (outputChars[j] == '\x07') {
                                replyXtGetTcap(outputChars[start .. j]);
                                i = j;
                                closed = true;
                                break;
                            }
                            if (outputChars[j] == '\x1b' && j + 1 < outputChars.length && outputChars[j + 1] == '\\') {
                                replyXtGetTcap(outputChars[start .. j]);
                                i = j + 1;
                                closed = true;
                                break;
                            }
                            j++;
                        }
                        if (!closed)
                            unfinished = true;
                        break;
                    }
                    case ']': {
                        // OSC sequence — consume until BEL (\007) or ST (ESC \)
                        // Format: ESC ] Ps ; Pt BEL  or  ESC ] Ps ; Pt ESC \
                        uint j = i + 2; // skip ESC ]
                        while (j < outputChars.length) {
                            if (outputChars[j] == '\x07') {
                                // terminated by BEL — skip everything including BEL
                                i = j;
                                break;
                            }
                            if (outputChars[j] == '\x1b' && j + 1 < outputChars.length && outputChars[j+1] == '\\') {
                                // terminated by ST (ESC \)
                                i = j + 1;
                                break;
                            }
                            j++;
                        }
                        if (j >= outputChars.length) {
                            // incomplete OSC — wait for more data
                            unfinished = true;
                        }
                        break;
                    }
                    default:
                        // unsupported
                        break;
                    }
                    if (unfinished)
                        break;
                } else switch(ch) {
                    case '\a': // bell
                    case '\f': // form feed
                    case '\v': // vtab
                    case '\r': // cr
                    case '\n': // lf
                    case '\t': // tab
                    case '\b': // backspace
                        _content.putChar(ch);
                        break;
                    default:
                        if (verboseMode)
                            Log.d("Terminal: unhandled ctrl char 0x", cast(uint)ch, " at pos ", i);
                        break;
                }
            } else {
                _content.putChar(ch);
            }
        }
        if (i > 0) {
            if (i == outputChars.length)
                outputChars.length = 0;
            else {
                for (uint j = 0; j + i < outputChars.length; j++)
                    outputChars[j] = outputChars[j + i];
                outputChars.length = outputChars.length - i;
            }
        }
        _content.updateScrollBar(_verticalScrollBar);
    }

    /// override to handle focus changes
    override protected void handleFocusChange(bool focused, bool receivedFocusFromKeyboard = false) {
        if (focused) {
            _content.focused = true;
            if (hostFocus)
                hostFocus(this);
        } else {
            _content.focused = false;
        }
        super.handleFocusChange(focused);
    }

    private int _ptyCols, _ptyRows;
    private void notifyPtySize() {
        version (Posix) {
            if (!_device)
                return;
            int cols = _content.width;
            int rows = _content.height;
            if (cols == _ptyCols && rows == _ptyRows)
                return;
            _ptyCols = cols;
            _ptyRows = rows;
            _device.setWindowSize(cols, rows, cols * _content.charw, rows * _content.charh);
        }
    }

}

import core.thread;
import std.math : PI, cos, sin;
import std.random : Random, uniform, unpredictableSeed;

struct TermParticle {
    float x, y, vx, vy, size;
    uint color;
    int life, lifeMax;
}

enum TermMenu : int {
    Copy = 92001,
    Paste = 92002,
    SelectAll = 92003,
    ToggleFx = 92004,
}

interface TerminalInputHandler {
    void onBytesReceived(string data);
}

class TerminalDevice : Thread {
    Signal!TerminalInputHandler onBytesRead;
    version (Windows) {
        import core.sys.windows.windows;
        HANDLE hpipe;
    } else {
        int masterfd;
        int slavefd = -1; // kept open to prevent EIO on master read
        import core.sys.posix.fcntl: open_=open, O_WRONLY, O_RDWR, O_NOCTTY;
        import core.sys.posix.unistd: close_=close;
        import core.sys.posix.unistd: write_=write;
        import core.sys.posix.unistd: read_=read;
        private int _shellPid = -1;
    }
    @property string deviceName() { return _name; }
    private string _name;
    private bool started;
    private bool closed;
    private bool connected;
    private string _termType = "xterm";
    @property string termType() { return _termType; }
    @property void termType(string t) { _termType = t; }

    this() {
        super(&threadProc);
    }
    ~this() {
        close();
    }

    void threadProc() {
        started = true;
        Log.d("TerminalDevice threadProc() enter");
        version(Windows) {
            while (!closed) {
                Log.d("TerminalDevice -- Waiting for client");
                if (ConnectNamedPipe(hpipe, null)) {
                    connected = true;
                    // accept client
                    Log.d("TerminalDevice client connected");
                    char[16384] buf;
                    for (;;) {
                        if (closed)
                            break;
                        DWORD bytesRead = 0;
                        DWORD bytesAvail = 0;
                        DWORD bytesInMessage = 0;
                        // read data from client
                        //Log.d("TerminalDevice reading from pipe");
                        if (!PeekNamedPipe(hpipe, buf.ptr, cast(DWORD)1 /*buf.length*/, &bytesRead, &bytesAvail, &bytesInMessage)) {
                            break;
                        }
                        if (closed)
                            break;
                        if (!bytesRead) {
                            Sleep(10);
                            continue;
                        }
                        if (ReadFile(hpipe, &buf, 1, &bytesRead, null)) { //buf.length
                            Log.d("TerminalDevice bytes read: ", bytesRead);
                            if (closed)
                                break;
                            if (bytesRead && onBytesRead.assigned) {
                                onBytesRead(buf[0 .. bytesRead].dup);
                            }
                        } else {
                            break;
                        }
                    }
                    Log.d("TerminalDevice client disconnecting");
                    connected = false;
                    // disconnect client
                    FlushFileBuffers(hpipe);
                    DisconnectNamedPipe(hpipe);
                }
            }
        } else {
            // posix
            import core.stdc.errno : errno, EAGAIN, EINTR, EIO;
            char[4096] buf;
            while(!closed) {
                auto bytesRead = read_(masterfd, buf.ptr, buf.length);
                if (closed)
                    break;
                if (bytesRead > 0) {
                    if (onBytesRead.assigned)
                        onBytesRead(buf[0 .. bytesRead].dup);
                } else if (bytesRead == 0) {
                    break; // EOF
                } else {
                    int err = errno;
                    if (err == EINTR || err == EAGAIN) {
                        // retry
                        import core.thread : Thread;
                        import core.time : msecs;
                        Thread.sleep(msecs(10));
                        continue;
                    }
                    // EIO or other error — slave closed or not attached
                    break;
                }
            }
        }
        Log.d("TerminalDevice threadProc() exit");
    }

    bool write(string msg) {
        if (!msg.length)
            return true;
        if (closed || !started)
            return false;
        version (Windows) {
            if (!connected)
                return false;
            for (;;) {
                DWORD bytesWritten = 0;
                if (WriteFile(hpipe, cast(char*)msg.ptr, cast(int)msg.length, &bytesWritten, null) != TRUE) {
                    return false;
                }
                if (bytesWritten < msg.length)
                    msg = msg[bytesWritten .. $];
                else
                    break;
            }
        } else {
            // linux/posix
            if (masterfd && masterfd != -1) {
                auto bytesRead = write_(masterfd, msg.ptr, msg.length);
            }

        }
        return true;
    }
    void close() {
        if (closed)
            return;
        closed = true;
        version (Posix) {
            killShell();
        }
        if (!started)
            return;
        version (Windows) {
            import std.string;
            // ping terminal to handle closed flag
            HANDLE h = CreateFileA(
                               _name.toStringz,   // pipe name
                               GENERIC_READ |  // read and write access
                               GENERIC_WRITE,
                               0,              // no sharing
                               null,           // default security attributes
                               OPEN_EXISTING,  // opens existing pipe
                               0,              // default attributes
                               null);
            if (h != INVALID_HANDLE_VALUE) {
                DWORD bytesWritten = 0;
                WriteFile(h, "stop".ptr, 4, &bytesWritten, null);
                CloseHandle(h);
            }
        } else {
            // Close both fds to unblock the read() in threadProc (returns EIO)
            if (slavefd != -1) {
                close_(slavefd);
                slavefd = -1;
            }
            if (masterfd && masterfd != -1) {
                close_(masterfd);
                masterfd = 0;
            }
        }
        join(false);
        version (Windows) {
            if (hpipe && hpipe != INVALID_HANDLE_VALUE) {
                CloseHandle(hpipe);
                hpipe = null;
            }
        }
            _name = null;
    }
    version (Posix) {
        /// Spawn a shell process on the slave PTY.
        /// Returns false if fork/exec failed.
        bool spawnShell() {
            import core.sys.posix.unistd : fork, setsid, dup2, execv, _exit;
            import core.sys.posix.fcntl : open_c = open, O_RDWR, O_NOCTTY;
            import core.sys.posix.sys.ioctl : ioctl, TIOCSCTTY;
            import core.stdc.stdlib : getenv;
            import core.sys.posix.stdlib : setenv;
            import core.sys.posix.unistd : close_c = close;
            import core.memory : GC;
            import std.string : toStringz;

            // Resolve shell path before forking — avoids D allocations in child
            const(char)* userShell = getenv("SHELL");
            const(char)* shell = (userShell && *userShell) ? userShell : "/bin/bash";
            immutable(char)* slaveName = _name.toStringz;

            // Disable GC around fork to prevent the child from corrupting the GC state
            GC.disable();
            auto pid = fork();
            if (pid != 0)
                GC.enable(); // re-enable in parent immediately

            if (pid < 0)
                return false;

            if (pid == 0) {
                // ── Child process ──────────────────────────────────────
                // ONLY async-signal-safe / C calls from here on.
                // Do NOT call any D runtime, GC, or logging functions.

                setsid();

                // Open slave WITHOUT O_NOCTTY so it becomes controlling terminal
                int slavefd_c = open_c(slaveName, O_RDWR);
                if (slavefd_c < 0)
                    _exit(1);

                // Make slave the controlling terminal (required by fish and other shells)
                ioctl(slavefd_c, TIOCSCTTY, 0);

                dup2(slavefd_c, 0);
                dup2(slavefd_c, 1);
                dup2(slavefd_c, 2);
                if (slavefd_c > 2)
                    close_c(slavefd_c);

                // Close parent's slave and master fds in child
                if (slavefd != -1)
                    close_c(slavefd);
                close_c(masterfd);

                setenv("TERM", _termType.ptr, 1);

                const(char)*[2] args = [shell, null];
                execv(shell, args.ptr);

                const(char)* sh = "/bin/sh";
                const(char)*[2] args2 = [sh, null];
                execv(sh, args2.ptr);

                _exit(127);
                assert(0);
            }

            // ── Parent ─────────────────────────────────────────────────
            _shellPid = pid;
            Log.i("TerminalDevice: spawned shell pid=", pid, " on ", _name);
            return true;
        }

        void setWindowSize(int cols, int rows, int xpix, int ypix) {
            import core.sys.posix.sys.ioctl : ioctl, TIOCSWINSZ, winsize;
            import core.sys.posix.signal : kill;
            enum SIGWINCH = 28;
            if (masterfd <= 0 || cols < 2 || rows < 2)
                return;
            winsize ws;
            ws.ws_col = cast(ushort) cols;
            ws.ws_row = cast(ushort) rows;
            ws.ws_xpixel = cast(ushort) xpix;
            ws.ws_ypixel = cast(ushort) ypix;
            ioctl(masterfd, TIOCSWINSZ, &ws);
            if (_shellPid > 0)
                kill(_shellPid, SIGWINCH);
        }

        void killShell() {
            if (_shellPid > 0) {
                import core.sys.posix.signal : kill, SIGHUP;
                kill(_shellPid, SIGHUP);
                _shellPid = -1;
            }
        }
    }

    bool create(bool interactive = false) {
        import std.string;
        version (Windows) {
            import std.uuid;
            _name = "\\\\.\\pipe\\dlangide-terminal-" ~ randomUUID().toString;
            SECURITY_ATTRIBUTES sa;
            sa.nLength = sa.sizeof;
            sa.bInheritHandle = TRUE;
            hpipe = CreateNamedPipeA(cast(const(char)*)_name.toStringz,
                             PIPE_ACCESS_DUPLEX | FILE_FLAG_WRITE_THROUGH | FILE_FLAG_FIRST_PIPE_INSTANCE, // dwOpenMode
                             //PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT, // | PIPE_REJECT_REMOTE_CLIENTS,
                             PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, // | PIPE_REJECT_REMOTE_CLIENTS,
                             1,
                             1, //16384,
                             1, //16384,
                             20,
                             &sa);
            if (hpipe == INVALID_HANDLE_VALUE) {
                Log.e("Failed to create named pipe for terminal, error=", GetLastError());
                close();
                return false;
            }
        } else {
            const(char) * s = null;
            {
                import core.sys.posix.fcntl;
                import core.sys.posix.stdio;
                import core.sys.posix.stdlib;
                //import core.sys.posix.unistd;
                masterfd = posix_openpt(O_RDWR | O_NOCTTY | O_SYNC);
                if (masterfd == -1) {
                    Log.e("posix_openpt failed - cannot open terminal");
                    close();
                    return false;
                }
                if (grantpt(masterfd) == -1 || unlockpt(masterfd) == -1) {
                    Log.e("grantpt / unlockpt failed - cannot open terminal");
                    close();
                    return false;
                }
                s = ptsname(masterfd);
                if (!s) {
                    Log.e("ptsname failed - cannot open terminal");
                    close();
                    return false;
                }
            }
            _name = fromStringz(s).dup;
            // Open slave side to prevent master read() returning EIO immediately
            slavefd = open_(_name.toStringz, O_RDWR | O_NOCTTY);
        }
        Log.i("ptty device created: ", _name);
        start();
        version (Posix) {
            if (interactive)
                spawnShell();
        }
        return true;
    }
}
