module dcore.ui.uimanager;

import dlangui.core.logger;
import dlangui.widgets.widget;
import dlangui.widgets.menu;
import dlangui.widgets.tabs;
import dlangui.widgets.layouts;
import dlangui.widgets.docks;
import dlangui.widgets.controls;
import dlangui.widgets.statusline;
import dlangui.widgets.toolbars;
import dlangui.widgets.editors;
import dlangui.core.events;

import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.conv;

import dcore.core;
import dcore.ui.thememanager;
import dcore.ui.radialmenu;
import dcore.ui.mainwindow;
import dcore.editor.editormanager;
import dcore.input.keyboardmanager;
import dcore.vault.vault;

/**
 * UIManager - Manages UI components and layout
 *
 * Responsible for:
 * - Managing window layout
 * - Coordinating UI components
 * - Handling themes and styling
 * - Managing toolbars and status bar
 * - Providing context menus and dialogs
 */
class UIManager {
    private DCore _core;
    private MainWindow _mainWindow;
    private ThemeManager _themeManager;
    private RadialMenu _radialMenu;
    private DockHost _dockHost;
    private TabWidget _centralTabs;
    private StatusLine _statusLine;
    private MainMenu _mainMenu;

    // UI state
    private bool _sidebarVisible = true;
    private bool _terminalVisible = true;
    private bool _statusBarVisible = true;

    /**
     * Constructor
     */
    this(DCore core) {
        _core = core;
        Log.i("UIManager: Initializing");

        // Create theme manager
        string themesDir = buildPath(core.getConfigDir(), "themes");
        _themeManager = new ThemeManager(core, themesDir);

        // Create radial menu
        _radialMenu = new RadialMenu("RADIAL_MENU");
        _radialMenu.setThemeManager(_themeManager);
        _radialMenu.onItemSelected.connect(&handleRadialMenuSelection);
    }

    /**
     * Set main window reference
     */
    void setMainWindow(MainWindow window) {
        _mainWindow = window;
        Log.i("UIManager: Main window set");
    }

    /**
     * Initialize UI
     */
    void initialize() {
        if (!_mainWindow) {
            Log.e("UIManager: Cannot initialize, main window not set");
            return;
        }

        Log.i("UIManager: Starting initialization");

        // Load themes
        _themeManager.loadThemes();

        // Apply current theme to main window
        _themeManager.applyThemeToWidget(_mainWindow);

        // Initialize UI components
        initMainMenu();
        initToolbars();
        initDockLayout();
        initStatusBar();

        // Connect keyboard shortcuts
        connectKeyboardShortcuts();

        // Setup radial menu items
        setupRadialMenu();

        Log.i("UIManager: Initialization complete");
    }

    /**
     * Initialize main menu
     */
    private void initMainMenu() {
        // Main menu is already created by MainWindow
        // We just need to update it with our actions
        if (!_mainWindow)
            return;

        // MainWindow already has a menu structure, we can access it through onAction handler
        Log.i("UIManager: Main menu is handled by MainWindow");

    }

    /**
     * Initialize toolbars
     */
    private void initToolbars() {
        // MainWindow already creates toolbars
        Log.i("UIManager: Toolbars handled by MainWindow");


    }

    /**
     * Initialize dock layout
     */
    private void initDockLayout() {
        // MainWindow creates its own dock layout
        _dockHost = _mainWindow.dockHost;
        if (!_dockHost) {
            Log.e("UIManager: Could not get dock host from main window");
            return;
        }

        // Get central tabs from MainWindow
        _centralTabs = _mainWindow.centralTabs;
        if (!_centralTabs) {
            Log.e("UIManager: Could not get central tabs from main window");
            return;
        }

        // Set editor tabs to editor manager
        if (_core && _core.editorManager) {
            _core.editorManager.setEditorTabWidget(_centralTabs);
        }

        // Add welcome tab
        auto welcomeWidget = createWelcomeWidget();
        if (welcomeWidget)
            _centralTabs.addTab(welcomeWidget, "Welcome"d);

        // Add explorer dock
        auto explorerPanel = new DockWindow("EXPLORER");
        explorerPanel.caption.text = "Explorer"d;
        explorerPanel.dockAlignment = DockAlignment.Left;
        explorerPanel.layoutWidth = 200;
        
        if (_core) {
            import dcore.widgets.filesystembrowser;
            auto browser = new FileSystemBrowser("FILE_BROWSER");
            explorerPanel.bodyWidget = browser;
        }

        _dockHost.addDockedWindow(explorerPanel);

        // Add terminal dock
        auto terminalPanel = new DockWindow("TERMINAL");
        terminalPanel.caption.text = "Terminal"d;
        terminalPanel.dockAlignment = DockAlignment.Bottom;
        terminalPanel.layoutHeight = 200;
        
        auto terminalEdit = new EditBox("TERMINAL_EDIT");
        terminalEdit.readOnly = true;
        terminalEdit.backgroundColor = 0x000000; // Black background
        terminalEdit.textColor = 0x00FF00; // Green text
        terminalEdit.text = "Terminal ready\n> "d;
        terminalPanel.bodyWidget = terminalEdit;
        
        _dockHost.addDockedWindow(terminalPanel);

        // Add output dock
        auto outputPanel = new DockWindow("OUTPUT");
        outputPanel.caption.text = "Output"d;
        outputPanel.dockAlignment = DockAlignment.Bottom;
        outputPanel.layoutHeight = 150;
        
        auto outputEdit = new EditBox("OUTPUT_EDIT");
        outputEdit.readOnly = true;
        outputPanel.bodyWidget = outputEdit;
        
        _dockHost.addDockedWindow(outputPanel);

        Log.i("UIManager: Dock layout initialized");
    }

    /**
     * Create welcome widget
     */
    private Widget createWelcomeWidget() {
        auto widget = new VerticalLayout("WELCOME");
        widget.padding(Rect(20, 20, 20, 20));

        // Title
        auto title = new TextWidget("WELCOME_TITLE", "Welcome to CompyutinatorCode"d);
        title.textColor = 0x3080E0;
        title.fontSize = 24;
        title.alignment = Align.HCenter;
        widget.addChild(title);

        // Subtitle
        auto subtitle = new TextWidget("WELCOME_SUBTITLE", "D language implementation"d);
        subtitle.fontSize = 16;
        subtitle.alignment = Align.HCenter;
        widget.addChild(subtitle);

        // Spacer
        widget.addChild(new VSpacer());

        // Quick start buttons
        auto buttonLayout = new HorizontalLayout("QUICK_START");
        buttonLayout.alignment = Align.HCenter;

        auto newProjectBtn = new Button("NEW_PROJECT", "New Project"d);
        auto openProjectBtn = new Button("OPEN_PROJECT", "Open Project"d);
        auto openFileBtn = new Button("OPEN_FILE", "Open File"d);

        buttonLayout.addChild(newProjectBtn);
        buttonLayout.addChild(new HSpacer());
        buttonLayout.addChild(openProjectBtn);
        buttonLayout.addChild(new HSpacer());
        buttonLayout.addChild(openFileBtn);

        widget.addChild(buttonLayout);

        // Add more spacer
        widget.addChild(new VSpacer());

        return widget;
    }

    /**
     * Initialize status bar
     */
    private void initStatusBar() {
        _statusLine = _mainWindow.statusLine();
        if (!_statusLine) {
            Log.e("UIManager: Could not get status line from main window");
            return;
        }

        // Regular status
        _statusLine.setStatusText("Ready"d);

        // Right panels
        _statusLine.setStatusText("LINE_COL", "Line: 1, Col: 1"d);
        _statusLine.setStatusText("ENCODING", "UTF-8"d);

        Log.i("UIManager: Status bar initialized");
    }

    /**
     * Update status line text
     */
    void updateStatusLine(string text) {
        if (_statusLine)
            _statusLine.setStatusText("STATUS", text.to!dstring());
    }

    /**
     * Update status line position text
     */
    void updatePositionStatus(int line, int column) {
        if (_statusLine)
            _statusLine.setStatusText("LINE_COL", format("Line: %d, Col: %d", line, column).to!dstring());
    }

    /**
     * Connect keyboard shortcuts
     */
    private void connectKeyboardShortcuts() {
        // TODO: Implement keyboard manager integration
        // For now, keyboard events will be handled directly

        Log.i("UIManager: Keyboard shortcuts connected");
    }

    /**
     * Handle keyboard events
     */
    private bool handleKeyEvent(Widget source, KeyEvent event) {
        // Let keyboard manager handle it first
        // TODO: Check keyboard manager when implemented

        // Check for radial menu shortcut (Alt+Space)
        if (event.action == KeyAction.KeyDown &&
            event.keyCode == KeyCode.SPACE &&
            (event.flags & KeyFlag.Alt) != 0) {
            // Show radial menu at cursor position
            // For now, show at center of window
            Point cursorPos = Point(_mainWindow.width / 2, _mainWindow.height / 2);
            showRadialMenu(cursorPos);
            return true;
        }

        return false;
    }

    /**
     * Setup radial menu items
     */
    private void setupRadialMenu() {
        _radialMenu.clearItems();

        _radialMenu.addItem("file.new", "New File", "document-new", "Create a new file");
        _radialMenu.addItem("file.open", "Open", "document-open", "Open an existing file");
        _radialMenu.addItem("file.save", "Save", "document-save", "Save the current file");
        _radialMenu.addItem("edit.find", "Find", "edit-find", "Search for text");
        _radialMenu.addItem("edit.replace", "Replace", "edit-find-replace", "Find and replace text");
        _radialMenu.addItem("tools.build", "Build", "system-run", "Build the project");
        _radialMenu.addItem("tools.run", "Run", "media-playback-start", "Run the application");
        _radialMenu.addItem("nav.goto_symbol", "Go to Symbol", "go-jump", "Navigate to symbol");

        Log.i("UIManager: Radial menu initialized");
    }

    /**
     * Show radial menu at position
     */
    void showRadialMenu(Point position) {
        _radialMenu.showAtPos(position);
    }

    /**
     * Handle radial menu selection
     */
    private void handleRadialMenuSelection(string actionId) {
        // Execute the action
        executeAction(actionId);
    }

    /**
     * Handle menu/toolbar action
     */
    private bool handleAction(Widget source, const Action action) {
        import std.conv : to;
        string actionId = action.id.to!string;

        // Execute the action
        return executeAction(actionId);
    }

    /**
     * Execute an action by ID
     */
    bool executeAction(string actionId) {
        // Try to execute via keyboard manager first
        // TODO: Check keyboard manager for action when implemented
        // if (_core && _core.keyboardManager) {
        //     if (_core.keyboardManager.executeAction(actionId))
        //         return true;
        // }

        // Handle theme changes
        if (actionId.startsWith("view.theme.")) {
            string themeName = actionId["view.theme.".length .. $];
            if (_themeManager && _themeManager.setCurrentTheme(themeName)) {
                _themeManager.applyThemeToWidget(_mainWindow);
                return true;
            }
        }

        // Handle standard actions
        switch (actionId) {
            // File actions
            case "file.new":
                // TODO: Create new file
                Log.i("UIManager: New file action");
                return true;

            case "file.open":
                // TODO: Show open file dialog
                Log.i("UIManager: Open file action");
                return true;

            case "file.save":
                if (_core && _core.editorManager) {
                    _core.editorManager.saveCurrentFile();
                    return true;
                }
                return false;

            case "file.exit":
                if (_mainWindow.window)
                    _mainWindow.window.close();
                return true;

            // View actions
            case "view.explorer":
                toggleExplorer();
                return true;

            case "view.terminal":
                toggleTerminal();
                return true;

            // Navigation actions
            case "nav.goto_line":
                // TODO: Show go to line dialog
                Log.i("UIManager: Go to line action");
                return true;

            default:
                Log.i("UIManager: Unhandled action: ", actionId);
                return false;
        }
    }

    /**
     * Toggle explorer panel
     */
    void toggleExplorer() {
        if (!_dockHost)
            return;

        auto explorerDock = _dockHost.childById!DockWindow("EXPLORER");
        if (explorerDock) {
            explorerDock.visibility = explorerDock.visibility == Visibility.Visible ? Visibility.Gone : Visibility.Visible;
            _sidebarVisible = explorerDock.visible;
        }
    }

    /**
     * Toggle terminal panel
     */
    void toggleTerminal() {
        if (!_dockHost)
            return;

        auto terminalDock = _dockHost.childById!DockWindow("TERMINAL");
        if (terminalDock) {
            terminalDock.visibility = terminalDock.visibility == Visibility.Visible ? Visibility.Gone : Visibility.Visible;
            _terminalVisible = terminalDock.visible;
        }
    }

    /**
     * Handle workspace changed event
     */
    void onWorkspaceChanged(Workspace workspace) {
        if (!workspace)
            return;

        // Update window title
        if (_mainWindow) {
            if (_mainWindow.window)
                _mainWindow.window.windowCaption = ("CompyutinatorCode - " ~ workspace.name).to!dstring();
        }

        // Update status
        updateStatusLine("Workspace: " ~ workspace.name);

        Log.i("UIManager: Workspace changed to: ", workspace.name);
    }

    /**
     * Get theme manager
     */
    ThemeManager getThemeManager() {
        return _themeManager;
    }

    /**
     * Get dock host
     */
    DockHost getDockHost() {
        return _dockHost;
    }

    /**
     * Get central tabs
     */
    TabWidget getCentralTabs() {
        return _centralTabs;
    }
}
