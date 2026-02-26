module dcore.editor.editor;

import dlangui;
import dlangui.widgets.editors;
import dlangui.widgets.widget;
import dlangui.widgets.menu;
import dlangui.widgets.popup;
import dlangui.core.signals;
import dlangui.core.events;
import dlangui.core.logger;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.path;
import std.regex;
import std.string;
import std.traits;
import std.utf;

import dcore.editor.syntax.highlighter;
import dcore.editor.syntax.tokenizer;
import dcore.editor.document;

/**
 * EditorWidget - Enhanced text editor for CompyutinatorCode
 *
 * Features:
 * - Syntax highlighting
 * - Line numbers
 * - Code folding
 * - Multiple cursors
 * - UTF-8 support
 * - Enhanced keyboard navigation
 * - Inline context menus
 * - Customizable styling
 */
class EditorWidget : EditBox {
    // Add alias to fix hidden method error
    alias showLineNumbers = EditWidgetBase.showLineNumbers;
    
    // Define Signal wrappers
    public struct SignalWrapper(T) {
        private T _handler;
        bool assigned() { return _handler !is null; }
        void connect(T handler) { _handler = handler; }
        void opCall(Parameters!T params) {
            if (_handler !is null)
                _handler(params);
        }
        alias emit = opCall;
        bool opCast(T : bool)() { return assigned(); }
    }
    
    // Signals
    SignalWrapper!(void delegate(string)) onFileLoaded;
    SignalWrapper!(void delegate(string)) onFileSaved;
    SignalWrapper!(void delegate(int, int)) onCursorMoved; // line, column
    SignalWrapper!(void delegate()) onTextChanged;
    SignalWrapper!(void delegate(string)) onLanguageChanged;
    SignalWrapper!(void delegate(KeyEvent)) onKeyboardShortcut;
    
    // Editor state
    private string _filePath;
    private string _language;
    private bool _modified = false;
    private bool _readOnly = false;
    private Document _document;
    
    // Syntax highlighting
    private SyntaxHighlighter _highlighter;
    
    // Appearance
    private int _tabSize = 4;
    private bool _showWhitespace = false;
    private bool _lineWrapping = false;
    private uint _lineNumberColor = 0x808080;
    private uint _currentLineColor = 0x303030;
    private uint _selectionColor = 0x204080;
    
    // Editing features
    private bool _autoIndent = true;
    private bool _autoCloseBrackets = true;
    private bool _autoCloseQuotes = true;
    
    // Code folding
    private int[] _foldedLines;
    private bool _codeFoldingEnabled = true;
    
    // Navigation history
    private struct CursorPosition {
        int line;
        int column;
        string filePath;
    }
    private CursorPosition[] _navigationHistory;
    private int _navigationIndex = -1;
    
    /**
     * Constructor
     */
    this(string id = null) {
        super(id);
        
        // Initialize document
        _document = new Document();
        
        // Setup appearance
        backgroundColor = 0x1E1E1E; // Dark background
        textColor = 0xD4D4D4;       // Light gray text
        fontFace = "DejaVu Sans Mono";
        fontSize = 12;
        
        // Enable word wrap
        wordWrap = _lineWrapping;
        
        // Set content type for syntax highlighting
        styleId = "edit_text_plain";
        
        // Connect signals
        keyEvent = &handleKeyEvent;
        focusChange = &handleFocusChanged;
        
        // Create highlighter
        _highlighter = new SyntaxHighlighter();
    }
    
    /**
     * Open a file in the editor
     */
    bool openFile(string filePath) {
        if (!exists(filePath)) {
            Log.e("EditorWidget: Cannot open file (not found): ", filePath);
            return false;
        }
        
        try {
            // Read file content
            string content = readText(filePath);
            
            // Set text
            text = content.toUTF32;
            
            // Set filepath and detect language
            _filePath = filePath;
            detectLanguage();
            
            // Reset modification flag
            _modified = false;
            
            // Reset cursor position
            setCaretPos(0, 0);
            
            // Emit signal
            onFileLoaded(filePath);
            
            Log.i("EditorWidget: File opened: ", filePath);
            return true;
        }
        catch (Exception e) {
            Log.e("EditorWidget: Error opening file: ", e.msg);
            return false;
        }
    }
    
    /**
     * Save current content to file
     */
    bool saveFile(string filePath = null) {
        string targetPath = filePath ? filePath : _filePath;
        
        if (!targetPath || targetPath.length == 0) {
            Log.e("EditorWidget: Cannot save file (no path specified)");
            return false;
        }
        
        try {
            // Get text content
            dstring content = text;
            
            // Write to file
            std.file.write(targetPath, std.utf.toUTF8(content));
            
            // Update filepath if different
            if (filePath && filePath != _filePath) {
                _filePath = filePath;
                detectLanguage();
            }
            
            // Reset modification flag
            _modified = false;
            
            // Emit signal
            onFileSaved(_filePath);
            
            Log.i("EditorWidget: File saved: ", _filePath);
            return true;
        }
        catch (Exception e) {
            Log.e("EditorWidget: Error saving file: ", e.msg);
            return false;
        }
    }
    
    /**
     * Detect language based on file extension
     */
    private void detectLanguage() {
        if (!_filePath || _filePath.length == 0)
            return;
            
        string ext = extension(_filePath).toLower();
        
        // Determine language based on extension
        switch (ext) {
            case ".d":
                _language = "d";
                break;
            case ".c":
            case ".h":
                _language = "c";
                break;
            case ".cpp":
            case ".hpp":
            case ".cc":
                _language = "cpp";
                break;
            case ".js":
                _language = "javascript";
                break;
            case ".py":
                _language = "python";
                break;
            case ".rs":
                _language = "rust";
                break;
            case ".html":
                _language = "html";
                break;
            case ".css":
                _language = "css";
                break;
            case ".json":
                _language = "json";
                break;
            case ".md":
                _language = "markdown";
                break;
            default:
                _language = "text";
                break;
        }
        
        // Update syntax highlighter
        if (_highlighter)
            _highlighter.setLanguage(_language);
            
        // Emit signal
        onLanguageChanged(_language);
    }
    
    /**
     * Set language manually
     */
    void setLanguage(string language) {
        _language = language;
        
        // Update syntax highlighter
        if (_highlighter)
            _highlighter.setLanguage(language);
            
        // Emit signal
        onLanguageChanged(_language);
    }
    
    /**
     * Get current language
     */
    string getLanguage() {
        return _language;
    }
    
    /**
     * Get file path
     */
    string getFilePath() {
        return _filePath;
    }
    
    /**
     * Check if content is modified
     */
    bool isModified() {
        return _modified;
    }
    
    /**
     * Set read-only mode
     */
    void setReadOnly(bool readOnly) {
        _readOnly = readOnly;
        // Update UI state as needed
    }
    

    
    /**
     * Set tab size
     */
    void setTabSize(int size) {
        if (size < 1 || size > 8)
            return;
        _tabSize = size;
        // Update UI state
    }
    
    /**
     * Enable/disable code folding
     */
    void enableCodeFolding(bool enable) {
        _codeFoldingEnabled = enable;
        // Update UI state
    }
    
    /**
     * Navigate to line
     */
    void gotoLine(int line) {
        if (line < 0)
            return;
            
        // Calculate position
        int pos = 0;
        for (int i = 0; i < line && i < _document.lineCount; i++) {
            pos += _document.getLine(i).length + 1; // +1 for newline
        }
        
        // Set cursor position
        int lineNum = 0, columnPos = 0;
        if (content) {
            // Get line and column from the content's position
            // Convert offset to line and column
            dstring txt = content.text;
            for(int i = 0; i < pos && i < txt.length; i++) {
                if (txt[i] == '\n') {
                    lineNum++;
                    columnPos = 0;
                } else {
                    columnPos++;
                }
            }
        }
        setCaretPos(lineNum, columnPos);
        
        // Ensure line is visible
        scrollToCursor();
    }
    
    /**
     * Save current position in navigation history
     */
    private void saveCurrentPosition() {
        auto pos = CursorPosition(cursorLine, cursorColumn, _filePath);
        
        // Remove future history if we're in the middle
        if (_navigationIndex >= 0 && _navigationIndex < _navigationHistory.length - 1) {
            _navigationHistory = _navigationHistory[0 .. _navigationIndex + 1];
        }
        
        // Add to history
        _navigationHistory ~= pos;
        _navigationIndex = cast(int)_navigationHistory.length - 1;
        
        // Limit history size
        const int MAX_HISTORY = 100;
        if (_navigationHistory.length > MAX_HISTORY) {
            _navigationHistory = _navigationHistory[$ - MAX_HISTORY .. $];
            _navigationIndex = cast(int)_navigationHistory.length - 1;
        }
    }
    
    /**
     * Navigate back in history
     */
    void navigateBack() {
        if (_navigationIndex <= 0 || _navigationHistory.length <= 1)
            return;
            
        _navigationIndex--;
        auto pos = _navigationHistory[_navigationIndex];
        
        // Check if we need to switch files
        if (pos.filePath != _filePath) {
            // TODO: Signal to parent that we need to switch files
        } else {
            // Navigate to position
            gotoLine(pos.line);
            // TODO: Set column position
        }
    }
    
    /**
     * Navigate forward in history
     */
    void navigateForward() {
        if (_navigationIndex >= _navigationHistory.length - 1)
            return;
            
        _navigationIndex++;
        auto pos = _navigationHistory[_navigationIndex];
        
        // Check if we need to switch files
        if (pos.filePath != _filePath) {
            // TODO: Signal to parent that we need to switch files
        } else {
            // Navigate to position
            gotoLine(pos.line);
            // TODO: Set column position
        }
    }
    
    /**
     * Handle key events
     */
    bool handleKeyEvent(Widget source, KeyEvent event) {
        if (event.action == KeyAction.KeyDown) {
            // First check for advanced keyboard shortcuts
            if (processKeyboardShortcut(event))
                return true;
                
            // Then check for editing commands
            if (processEditingKeyCommand(event))
                return true;
        }
        
        // Let the base class handle the event
        return false;
    }
    
    /**
     * Process keyboard shortcuts
     */
    private bool processKeyboardShortcut(KeyEvent event) {
        // Example implementation of keyboard shortcuts
        
        // Ctrl+G - Go to line
        if (event.keyCode == KeyCode.KEY_G && (event.flags & KeyFlag.Control) != 0) {
            // TODO: Show go to line dialog
            return true;
        }
        
        // Ctrl+S - Save
        if (event.keyCode == KeyCode.KEY_S && (event.flags & KeyFlag.Control) != 0) {
            saveFile();
            return true;
        }
        
        // Emit signal for other components to handle
        onKeyboardShortcut(event);
        return false;
    }
    
    /**
     * Process editing key commands
     */
    private bool processEditingKeyCommand(KeyEvent event) {
        // Auto-indent on Enter
        if (event.keyCode == KeyCode.RETURN && _autoIndent) {
            // Get current line
            int line = cursorLine;
            if (line >= 0) {
                // Get line content
                dstring lineText = _document.getLine(line);
                
                // Calculate indentation
                dstring indent;
                foreach (ch; lineText) {
                    if (ch == ' ' || ch == '\t')
                        indent ~= ch;
                    else
                        break;
                }
                
                // Adjust indentation based on line content
                if (lineText.endsWith("{") || lineText.endsWith("(") || lineText.endsWith(":")) {
                    // Increase indentation
                    for (int i = 0; i < _tabSize; i++)
                        indent ~= ' ';
                }
                
                // Insert newline and indentation
                if (indent.length > 0) {
                    TextPosition pos = caretPos();
                    // Convert line and column to offset
                    int offset = 0;
                    dstring txt = text;
                    for (int i = 0; i < pos.line; i++) {
                        size_t lineEnd = txt.indexOf('\n');
                        if (lineEnd == -1)
                            break;
                        offset += lineEnd + 1;
                        txt = txt[lineEnd + 1 .. $];
                    }
                    offset += pos.pos;
                    text = text[0 .. offset] ~ "\n"d ~ indent ~ text[offset .. $];
                    return true;
                }
            }
        }
        
        // Auto-close brackets
        if (_autoCloseBrackets) {
            switch (event.keyCode) {
                case '(':
                    TextPosition pos = caretPos();
                    // Convert line and column to offset
                    int offset = 0;
                    dstring txt = text;
                    for (int i = 0; i < pos.line; i++) {
                        size_t lineEnd = txt.indexOf('\n');
                        if (lineEnd == -1)
                            break;
                        offset += lineEnd + 1;
                        txt = txt[lineEnd + 1 .. $];
                    }
                    offset += pos.pos;
                    text = text[0 .. offset] ~ "[]"d ~ text[offset .. $];
                    // Move cursor inside brackets
                    setCaretPos(pos.line, pos.pos + 1);
                    return true;
                case '[':
                    TextPosition pos = caretPos();
                    // Convert line and column to offset
                    int offset = 0;
                    dstring txt = text;
                    for (int i = 0; i < pos.line; i++) {
                        size_t lineEnd = txt.indexOf('\n');
                        if (lineEnd == -1)
                            break;
                        offset += lineEnd + 1;
                        txt = txt[lineEnd + 1 .. $];
                    }
                    offset += pos.pos;
                    text = text[0 .. offset] ~ "[]"d ~ text[offset .. $];
                    // Move cursor inside brackets
                    setCaretPos(pos.line, pos.pos + 1);
                    return true;
                case '{':
                    TextPosition pos = caretPos();
                    // Convert line and column to offset
                    int offset = 0;
                    if (content !is null) {
                        dstring text = content.text;
                        int currentLine = 0;
                        int currentCol = 0;
                        for (int i = 0; i < text.length; i++) {
                            if (currentLine == pos.line && currentCol == pos.pos) {
                                offset = i;
                                break;
                            }
                            if (text[i] == '\n') {
                                currentLine++;
                                currentCol = 0;
                            } else {
                                currentCol++;
                            }
                        }
                    }
                    text = text[0 .. offset] ~ "{}"d ~ text[offset .. $];
                    // Move cursor inside brackets
                    setCaretPos(pos.line, pos.pos + 1);
                    return true;
                default:
                    break;
            }
        }
        
        // Auto-close quotes
        if (_autoCloseQuotes) {
            switch (event.keyCode) {
                case '"':
                    auto pos = caretPos();
                    dstring txt = content.text;
                    int offset = 0;
                    for(int i = 0; i < txt.length; i++) {
                        int currentLine = 0;
                        int currentCol = 0;
                        if (currentLine == pos.line && currentCol == pos.pos) {
                            offset = i;
                            break;
                        }
                        if (txt[i] == '\n') {
                            currentLine++;
                            currentCol = 0;
                        } else {
                            currentCol++;
                        }
                    }
                    text = text[0 .. offset] ~ "\"\""d ~ text[offset .. $];
                    setCaretPos(pos.line, pos.pos + 1);
                    return true;
                case '\'':
                    TextPosition pos = caretPos();
                    // Convert line and column to offset
                    int offset = 0;
                    if (content !is null) {
                        dstring txt = content.text;
                        int currentLine = 0;
                        int currentCol = 0;
                        for (int i = 0; i < txt.length; i++) {
                            if (currentLine == pos.line && currentCol == pos.pos) {
                                offset = i;
                                break;
                            }
                            if (txt[i] == '\n') {
                                currentLine++;
                                currentCol = 0;
                            } else {
                                currentCol++;
                            }
                        }
                    }
                    text = text[0 .. offset] ~ "\"\""d ~ text[offset .. $];
                    setCaretPos(pos.line, pos.pos + 1);
                    return true;
                default:
                    break;
            }
        }
        
        return false;
    }
    
    /**
     * Handle focus changes
     */
    bool handleFocusChanged(Widget source, bool focused) {
        if (focused) {
            // Editor received focus
        } else {
            // Editor lost focus
        }
        return false;
    }
    
    /**
     * Override drawing to implement custom rendering
     */
    override void onDraw(DrawBuf buf) {
        // Call base class to draw text
        super.onDraw(buf);
        
        // Draw line numbers if enabled
        if (showLineNumbers) {
            drawLineNumbers(buf);
        }
        
        // Draw current line highlight
        drawCurrentLineHighlight(buf);
        
        // Draw code folding indicators if enabled
        if (_codeFoldingEnabled) {
            drawCodeFoldingIndicators(buf);
        }
    }
    
    /**
     * Draw line numbers
     */
    private void drawLineNumbers(DrawBuf buf) {
        // Implementation for drawing line numbers
    }
    
    /**
     * Draw current line highlight
     */
    private void drawCurrentLineHighlight(DrawBuf buf) {
        // Implementation for highlighting the current line
    }
    
    /**
     * Draw code folding indicators
     */
    private void drawCodeFoldingIndicators(DrawBuf buf) {
        // Implementation for drawing code folding indicators
    }
    
    /**
     * Get cursor line
     */
    @property int cursorLine() {
        // Calculate line from caret position
        int line = 0;
        int pos = 0;
        dstring txt = text;
        
        TextPosition currentPos = TextPosition();
        currentPos.line = 0;
        currentPos.pos = 0;
        TextPosition caretPosition = caretPos();
        for (int i = 0; i < txt.length && (currentPos.line < caretPosition.line || (currentPos.line == caretPosition.line && currentPos.pos <= caretPosition.pos)); i++) {
            if (txt[i] == '\n') {
                line++;
            }
            pos++;
        }
        
        return line;
    }
    
    /**
     * Get cursor column
     */
    @property int cursorColumn() {
        // Calculate column from caret position
        int col = 0;
        int pos = 0;
        dstring txt = text;
        
        TextPosition currentPos = TextPosition();
        currentPos.line = 0;
        currentPos.pos = 0;
        TextPosition caretPosition = caretPos();
        for (int i = 0; i < txt.length && (currentPos.line < caretPosition.line || (currentPos.line == caretPosition.line && currentPos.pos < caretPosition.pos)); i++) {
            if (txt[i] == '\n') {
                col = 0;
            } else {
                col++;
            }
            pos++;
        }
        
        return col;
    }
    
    /**
     * Scroll to ensure cursor is visible
     */
    void scrollToCursor() {
        ensureCaretVisible();
    }
}