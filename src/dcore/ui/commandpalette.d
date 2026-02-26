module dcore.ui.commandpalette;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.popup;
import dlangui.widgets.controls;
import dlangui.widgets.layouts;
import dlangui.core.signals;
import dlangui.core.events;
import dlangui.graphics.drawbuf;
import dlangui.graphics.colors;
import dlangui.dml.parser;
import dlangui.platforms.common.platform;

import std.string;
import std.array;
import std.algorithm;
import std.conv;
import std.path;

import dcore.core;
import dcore.ui.thememanager;
import dcore.search.fuzzysearch;
import dcore.input.keyboardmanager;

/**
 * CommandPaletteResult - Visual representation of a search result
 */
class CommandPaletteResult : HorizontalLayout {
    private string _id;
    private string _type;
    private string _text;
    private string _detailText;
    private dstring _displayText;
    private TextWidget _typeIcon;
    private TextWidget _label;
    private TextWidget _detail;
    
    /**
     * Constructor
     */
    this(string id, string type, string text, string detailText = null) {
        super(null);
        _id = id;
        _type = type;
        _text = text;
        _displayText = text.toUTF32;
        _detailText = detailText;
        
        // Default style (can be themed)
        backgroundColor = 0x00000000; // Transparent
        layoutWidth = FILL_PARENT;
        padding(Rect(8, 6, 8, 6));
        minHeight = 36;
        
        // Create child widgets
        _typeIcon = new TextWidget("TYPE_" ~ id);
        _typeIcon.text = getTypeIcon(type);
        _typeIcon.fontSize = 18;
        _typeIcon.minWidth = 30;
        _typeIcon.textColor = getTypeColor(type);
        addChild(_typeIcon);
        
        auto contentLayout = new VerticalLayout("CONTENT_" ~ id);
        contentLayout.layoutWidth = FILL_PARENT;
        
        _label = new TextWidget("LABEL_" ~ id);
        _label.text = text.toUTF32();
        _displayText = _label.text;
        _label.layoutWidth = FILL_PARENT;
        contentLayout.addChild(_label);
        
        if (detailText && detailText.length > 0) {
            _detail = new TextWidget("DETAIL_" ~ id);
            _detail.text = detailText.toUTF32();
            _detail.textColor = 0x808080;
            _detail.fontSize = 12;
            _detail.layoutWidth = FILL_PARENT;
            contentLayout.addChild(_detail);
        }
        
        addChild(contentLayout);
    }
    
    /**
     * Get type icon (can be extended for more types)
     */
    private dstring getTypeIcon(string type) {
        switch(type) {
            case "command":
                return "⚙"d;
            case "file":
                return "📄"d;
            case "folder":
                return "📁"d;
            case "symbol":
                return "🔍"d;
            case "recent":
                return "⌚"d;
            default:
                return "●"d;
        }
    }
    
    /**
     * Get color based on type
     */
    private uint getTypeColor(string type) {
        switch(type) {
            case "command":
                return 0x6060FF; // Blue
            case "file":
                return 0x60A060; // Green
            case "folder":
                return 0xA06060; // Red
            case "symbol":
                return 0xA0A060; // Yellow
            case "recent":
                return 0x60A0A0; // Cyan
            default:
                return 0xA0A0A0; // Gray
        }
    }
    
    /**
     * Update with highlighted match
     */
    void setHighlightedMatch(FuzzyMatch match) {
        if (match.matchPositions.length == 0) {
            _label.text = _displayText;
            return;
        }
    
        // Create standard text with formatting
        dstring text = _text.toUTF32();
    
        // Use HTML-like formatting
        dstring formatted;
        int lastPos = 0;
    
        foreach (pos; match.matchPositions) {
            if (pos >= 0 && pos < _text.length) {
                // Add text before match
                if (pos > lastPos)
                    formatted ~= text[lastPos..pos];
            
                // Add highlighted character
                formatted ~= "<b>"d ~ text[pos..pos+1] ~ "</b>"d;
            
                lastPos = pos + 1;
            }
        }
    
        // Add remaining text
        if (lastPos < text.length)
            formatted ~= text[lastPos..$];
    
        _label.text = formatted;
    }
    
    /**
     * Getters for properties
     */
    @property string resultId() { return _id; }
    @property string resultType() { return _type; }
    @property string resultText() { return _text; }
    @property string resultDetailText() { return _detailText; }
}

/**
 * CommandPalette - A popup command palette with fuzzy search
 */
class CommandPalette : PopupWidget {
    // Signals
    Signal!(string, string) onCommandSelected;
    import dcore.utils.signals : Signal;
    Signal!() onDismissed;
    
    // UI components
    private EditLine _searchBox;
    private VerticalLayout _resultsLayout;
    private ScrollWidget _resultsScroll;
    private TextWidget _statusText;
    private CommandPaletteResult[] _resultWidgets;
    private int _selectedIndex = -1;
    
    // Search state
    private FuzzyMatcher _matcher;
    private string _currentQuery;
    private SearchResult[] _currentResults;
    private string _mode = "all"; // all, command, file, symbol
    
    // Data sources
    private DCore _core;
    private string[] _commands;
    private string[] _filePaths;
    private string[] _recentItems;
    
    // UI State
    private int _width = 600;
    private int _maxResults = 10;
    private int _maxHeight = 400;
    
    /**
     * Constructor
     */
    this(string id = null) {
        // Create the main layout first
        auto mainLayout = new VerticalLayout("MAIN_LAYOUT");
        mainLayout.layoutWidth = FILL_PARENT;
        mainLayout.padding(Rect(0, 0, 0, 0));
    
        // Initialize popup with content - use null window for now, we'll set it later
        super(mainLayout, null);
        if (id)
            _id = id;
    
        // Create fuzzy matcher
        FuzzyOptions options;
        options.maxResults = 20;
        _matcher = new FuzzyMatcher(options);
    
        // Set up layout
        padding(Rect(4, 4, 4, 4));
        layoutWidth = WRAP_CONTENT;
        layoutHeight = WRAP_CONTENT;
        backgroundColor = 0x2A2A2A;
    
        // Search box
        _searchBox = new EditLine("SEARCH_BOX");
        _searchBox.layoutWidth = FILL_PARENT;
        _searchBox.minWidth = _width;
        _searchBox.fontSize = 16;
        _searchBox.backgroundColor = 0x333333;
        _searchBox.textColor = 0xE0E0E0;
    
        // Connect to content change event via key handler
        _searchBox.layoutWidth = FILL_PARENT;
        _searchBox.keyEvent = delegate(Widget source, KeyEvent event) {
            if (event.action == KeyAction.Text || event.action == KeyAction.KeyDown) {
                onSearchTextChanged(_searchBox.text.toUTF8());
            }
            return handleSearchKeyEvent(source, event);
        };
    
        mainLayout.addChild(_searchBox);
    
        // Results container
        _resultsLayout = new VerticalLayout("RESULTS_LAYOUT");
        _resultsLayout.layoutWidth = FILL_PARENT;
        _resultsLayout.minWidth = _width;
    
        _resultsScroll = new ScrollWidget("RESULTS_SCROLL");
        _resultsScroll.layoutWidth = FILL_PARENT;
        _resultsScroll.layoutHeight = FILL_PARENT;
        _resultsScroll.maxHeight = _maxHeight;
        _resultsScroll.backgroundColor = 0x00000000; // Transparent
        _resultsScroll.contentWidget = _resultsLayout;
    
        mainLayout.addChild(_resultsScroll);
    
        // Status text
        _statusText = new TextWidget("STATUS_TEXT");
        _statusText.layoutWidth = FILL_PARENT;
        _statusText.textColor = 0x808080;
        _statusText.fontSize = 12;
        _statusText.text = "⌘+P: Files  ⌘+O: Symbols  ⌘+.: Commands"d;
        _statusText.alignment = Align.Right;
        _statusText.padding(Rect(0, 4, 4, 4));
    
        mainLayout.addChild(_statusText);
    }
    
    /**
     * Set core reference
     */
    void setCore(DCore core) {
        _core = core;
    }
    
    /**
     * Set data sources
     */
    void setCommands(string[] commands) {
        _commands = commands;
    }
    
    void setFilePaths(string[] filePaths) {
        _filePaths = filePaths;
    }
    
    void setRecentItems(string[] recentItems) {
        _recentItems = recentItems;
    }
    
    /**
     * Set mode (filter type)
     */
    void setMode(string mode) {
        _mode = mode;
        
        // Update hint text based on mode
        switch(mode) {
            case "command":
                _searchBox.textToSetWidgetSize = "Type to search commands..."d;
                break;
            case "file":
                _searchBox.textToSetWidgetSize = "Type to search files..."d;
                break;
            case "symbol":
                _searchBox.textToSetWidgetSize = "Type to search symbols..."d;
                break;
            default:
                _searchBox.textToSetWidgetSize = "Type to search commands, files, symbols..."d;
                break;
        }
        
        // Update search results for current query
        if (_currentQuery && _currentQuery.length > 0) {
            updateSearch(_currentQuery);
        } else {
            showDefaultResults();
        }
    }
    
    /**
     * Show the command palette
     */
    void show() {
        // Reset state
        _currentQuery = "";
        _selectedIndex = -1;
        
        // Show default results based on mode
        showDefaultResults();
        
        // Position in the center top of the screen
        int x = 400; // Default position
        int y = 200; // Default position
        
        // Use default screen dimensions
        x = 400;
        y = 200;
        
        PopupAnchor anchor;
        anchor.x = x;
        anchor.y = y;
        anchor.alignment = PopupAlign.Point;
        _anchor = anchor;
        // Get the current window from the widget
        Window win = window();
        if (win)
            win.showPopup(this);
        
        // Focus search box
        _searchBox.setFocus();
    }
    
    /**
     * Show default results (recents, common commands)
     */
    private void showDefaultResults() {
        clearResults();
        
        // Show different default results based on mode
        switch(_mode) {
            case "command":
                // Show most common commands
                if (_commands.length > 0) {
                    foreach(i, cmd; _commands[0..min($, _maxResults)]) {
                        addResultWidget(SearchResult("command", cmd, cmd, ""));
                    }
                }
                break;
                
            case "file":
                // Show recent files
                if (_recentItems.length > 0) {
                    foreach(item; _recentItems) {
                        if (item.length > 0) {
                            addResultWidget(SearchResult("recent", item, baseName(item), dirName(item)));
                        }
                    }
                }
                break;
                
            default:
                // Show mix of recents and commands
                if (_recentItems.length > 0) {
                    foreach(i, item; _recentItems[0..min($, 5)]) {
                        if (item.length > 0) {
                            addResultWidget(SearchResult("recent", item, baseName(item), dirName(item)));
                        }
                    }
                }
                
                if (_commands.length > 0) {
                    foreach(i, cmd; _commands[0..min($, 5)]) {
                        addResultWidget(SearchResult("command", cmd, cmd, ""));
                    }
                }
                break;
        }
        
        // Select first result
        if (_resultWidgets.length > 0) {
            selectResult(0);
        }
    }
    
    /**
     * Clear all results
     */
    private void clearResults() {
        _resultsLayout.removeAllChildren();
        _resultWidgets.length = 0;
        _selectedIndex = -1;
    }
    
    /**
     * Add a result widget from search result
     */
    private void addResultWidget(SearchResult result) {
        FuzzyMatch match = result.match;
        string id = result.type ~ "_" ~ to!string(_resultWidgets.length);
        
        // Create widget based on result type
        CommandPaletteResult widget = new CommandPaletteResult(
            id, result.type, result.name, result.details);
            
        // Set highlighted text if there's a match
        if (match.matchPositions.length > 0) {
            widget.setHighlightedMatch(match);
        }
        
        // Add mouse handler
        widget.mouseEvent = delegate(Widget source, MouseEvent event) {
            if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Left) {
                // Select this result
                for (int i = 0; i < _resultWidgets.length; i++) {
                    if (_resultWidgets[i] is widget) {
                        selectResult(i);
                        break;
                    }
                }
                return true;
            } else if (event.action == MouseAction.ButtonUp && event.button == MouseButton.Left) {
                // Activate this result
                activateCurrentResult();
                return true;
            }
            return false;
        };
        
        // Add to layout
        _resultsLayout.addChild(widget);
        _resultWidgets ~= widget;
    }
    
    /**
     * Select a result by index
     */
    private void selectResult(int index) {
        // Clear previous selection
        if (_selectedIndex >= 0 && _selectedIndex < _resultWidgets.length) {
            _resultWidgets[_selectedIndex].backgroundColor = 0x00000000; // Transparent
        }
        
        // Set new selection
        _selectedIndex = index;
        
        if (_selectedIndex >= 0 && _selectedIndex < _resultWidgets.length) {
            _resultWidgets[_selectedIndex].backgroundColor = 0x404080; // Highlight color
            
            // Make selected item visible by setting appropriate scroll position
            if (_resultWidgets[_selectedIndex].parent) {
                int itemTop = _resultWidgets[_selectedIndex].pos.top - _resultsScroll.pos.top;
                int itemBottom = itemTop + _resultWidgets[_selectedIndex].height;
                int visibleHeight = _resultsScroll.height;
                
                // If item is outside visible area, scroll to make it visible
                if (itemTop < 0 || itemBottom > visibleHeight) {
                    // Simplify scroll approach - just move the content
                    auto vp = _resultsScroll.scrollPos;
                    // Since scrollTo is protected, we need to use the scrollbar directly
                    if (_resultsScroll.vscrollbar) {
                        _resultsScroll.vscrollbar.position = itemTop;
                    }
                }
            }
        }
    }
    
    /**
     * Handle search text changed
     */
    private void onSearchTextChanged(string text) {
        _currentQuery = text;
        
        if (text.length > 0) {
            updateSearch(text);
        } else {
            showDefaultResults();
        }
    }
    
    // Removed function as we're using direct delegate now
    
    /**
     * Update search results with query
     */
    private void updateSearch(string query) {
        clearResults();
        
        // Different search based on mode
        _currentResults.length = 0;
        
        switch(_mode) {
            case "command":
                // Search only commands
                if (_commands.length > 0) {
                    _currentResults = _matcher.search(query, _commands, "command");
                }
                break;
                
            case "file":
                // Search only files
                if (_filePaths.length > 0) {
                    _currentResults = _matcher.searchFiles(query, _filePaths);
                }
                break;
                
            default:
                // Search everything
                SearchResult[] commandResults;
                SearchResult[] fileResults;
                
                if (_commands.length > 0) {
                    commandResults = _matcher.search(query, _commands, "command");
                }
                
                if (_filePaths.length > 0) {
                    fileResults = _matcher.searchFiles(query, _filePaths);
                }
                
                // Combine results, limiting each category
                _currentResults.length = 0;
                if (commandResults.length > 0) {
                    _currentResults ~= commandResults[0..min($, 5)];
                }
                if (fileResults.length > 0) {
                    _currentResults ~= fileResults[0..min($, 15)];
                }
                
                // Re-sort combined results
                sort(_currentResults);
                break;
        }
        
        // Add result widgets
        foreach(result; _currentResults) {
            addResultWidget(result);
        }
        
        // Select first result if available
        if (_resultWidgets.length > 0) {
            selectResult(0);
        }
    }
    
    /**
     * Handle keyboard events for search box
     */
    private bool handleSearchKeyEvent(Widget source, KeyEvent event) {
        if (event.action == KeyAction.KeyDown) {
            if (event.keyCode == KeyCode.DOWN) {
                // Next result
                if (_resultWidgets.length > 0) {
                    int nextIndex = cast(int)((_selectedIndex + 1) % _resultWidgets.length);
                    selectResult(nextIndex);
                }
                return true;
            } else if (event.keyCode == KeyCode.UP) {
                // Previous result
                if (_resultWidgets.length > 0) {
                    int prevIndex = cast(int)((_selectedIndex - 1 + _resultWidgets.length) % _resultWidgets.length);
                    selectResult(prevIndex);
                }
                return true;
            } else if (event.keyCode == KeyCode.RETURN) {
                // Activate selected result
                activateCurrentResult();
                return true;
            } else if (event.keyCode == KeyCode.ESCAPE) {
                // Dismiss palette
                dismiss();
                return true;
            } else if (event.keyCode == KeyCode.KEY_P && (event.flags & KeyFlag.Control) != 0) {
                // Switch to file mode
                setMode("file");
                updateSearch(_searchBox.text.toUTF8());
                return true;
            } else if (event.keyCode == KeyCode.KEY_O && (event.flags & KeyFlag.Control) != 0) {
                // Switch to symbol mode
                setMode("symbol");
                updateSearch(_searchBox.text.toUTF8());
                return true;
            } else if (event.keyCode == KeyCode.KEY_PERIOD && (event.flags & KeyFlag.Control) != 0) {
                // Switch to command mode
                setMode("command");
                updateSearch(_searchBox.text.toUTF8());
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * Activate the currently selected result
     */
    private void activateCurrentResult() {
        if (_selectedIndex >= 0 && _selectedIndex < _resultWidgets.length) {
            // Get the result
            CommandPaletteResult result = _resultWidgets[_selectedIndex];
            
            // Emit signal
            onCommandSelected.emit(result.resultType, result.resultText);
            
            // Dismiss the palette
            dismiss();
        }
    }
    
    /**
     * Dismiss the palette
     */
    void dismiss() {
        close();
        onDismissed.emit();
    }
    
    /**
     * Handle key events for palette
     */
    override bool onKeyEvent(KeyEvent event) {
        if (event.action == KeyAction.KeyDown && event.keyCode == KeyCode.ESCAPE) {
            dismiss();
            return true;
        }
        
        return super.onKeyEvent(event);
    }
}