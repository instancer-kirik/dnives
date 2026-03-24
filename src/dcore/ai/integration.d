module dcore.ai.integration;

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
import dlangui;
import dlangui.core.logger;
import dlangui.widgets.docks;
import dlangui.widgets.widget;
import dlangui.widgets.menu;
import dlangui.dialogs.filedlg;
import dlangui.dialogs.dialog;
import dlangui.core.types;
import dlangui.core.events;

import dcore.core;
import dcore.components.cccore;
// MainWindow is the old/deprecated CompyutinatorCode window.
// Keep the import only for the dynamic-cast guard in integrateWithMainWindow()
// and setupKeyboardShortcuts(); the field type is now plain Widget.
import dcore.ui.mainwindow : MainWindow;
import dcore.lsp.lspmanager;
import dcore.ai.ai_manager;
import dcore.ai.ai_backend;
import dcore.ai.context_manager;
import dcore.ai.code_action_manager;
import dcore.ai.widgets.chat_widget;
import dcore.code.symbol_tracker;

/**
 * AIIntegration - Integrates AI chat system with DCore
 *
 * This class handles the integration of the AI chat system with the existing
 * DCore architecture, providing:
 * - Menu integration for AI features
 * - Keyboard shortcuts for AI actions
 * - Event handling between AI and editor systems
 * - Configuration management
 * - Dock window management
 */
class AIIntegration {
    private DCore _core;
    private CCCore _ccCore;
    // Stored as Widget so IDEFrame (and any other AppFrame subclass) can be
    // passed without depending on the deprecated MainWindow type.
    private Widget _mainWindow;
    private LSPManager _lspManager;

    // AI system components
    private AIManager _aiManager;
    private CodeActionManager _codeActionManager;

    // UI integration
    private DockWindow _aiChatDock;
    private bool _isInitialized = false;

    /**
     * Constructor
     */
    this(DCore core, CCCore ccCore, Widget mainWindow) {
        _core = core;
        _ccCore = ccCore;
        _mainWindow = mainWindow;

        Log.i("AIIntegration: Initialized");
    }

    /**
     * Update CCCore and MainWindow references after construction.
     * Use this instead of creating a second instance when references become available.
     */
    void updateReferences(CCCore ccCore, Widget mainWindow) {
        _ccCore = ccCore;
        _mainWindow = mainWindow;

        // If already initialised, re-run the window integration steps
        // so shortcuts and file-open callbacks are wired to the real window.
        if (_isInitialized) {
            integrateWithMainWindow();
            setupKeyboardShortcuts();
        }

        Log.i("AIIntegration: References updated");
    }

    /** Returns true once initialize() has completed successfully. */
    bool isInitialized() const { return _isInitialized; }

    /**
     * Initialize AI integration
     */
    void initialize(LSPManager lspManager) {
        if (_isInitialized) {
            Log.w("AIIntegration: Already initialized");
            return;
        }

        _lspManager = lspManager;

        try {
            // Initialize AI manager
            _aiManager = new AIManager(_core, _lspManager);
            _aiManager.initialize();

            // Initialize code action manager
            _codeActionManager = new CodeActionManager(_core, _lspManager);
            _codeActionManager.initialize();

            // Set up AI manager events
            setupAIManagerEvents();

            // Set up code action manager events
            setupCodeActionManagerEvents();

            // Integrate with main window
            integrateWithMainWindow();

            // Menu items will be added during main menu creation
            // addMenuItems(); // Deprecated approach

            // Set up keyboard shortcuts
            setupKeyboardShortcuts();

            _isInitialized = true;
            Log.i("AIIntegration: Successfully initialized");

        } catch (Exception e) {
            Log.e("AIIntegration: Failed to initialize: ", e.msg);
            throw e;
        }
    }

    /**
     * Create and show the AI chat dock
     */
    void createAIChatDock() {
        if (!_isInitialized || !_mainWindow || _aiChatDock)
            return;

        // dockHost is a MainWindow-specific property; no-op for IDEFrame
        // (IDEFrame calls createAIChatDockInHost directly with its own DockHost).
        auto mw = cast(MainWindow)_mainWindow;
        if (!mw) {
            Log.w("AIIntegration: createAIChatDock — host is not a MainWindow, use createAIChatDockInHost instead");
            return;
        }

        auto dockHost = mw.dockHost;
        if (!dockHost) {
            Log.e("AIIntegration: No dock host available");
            return;
        }

        _aiManager.createChatDock(dockHost);
        _aiChatDock = _aiManager.chatDock;

        Log.i("AIIntegration: Created AI chat dock");
    }

    /**
     * Create and show the AI chat dock using an externally provided DockHost.
     * Use this when MainWindow is not available (e.g. from IDEFrame).
     */
    void createAIChatDockInHost(DockHost dockHost) {
        if (!_isInitialized || !dockHost)
            return;

        // Already created — delegate visibility to manager
        if (_aiChatDock) {
            _aiManager.toggleChatPanel();
            return;
        }

        _aiManager.createChatDock(dockHost);

        // Capture the dock window the manager just created so our guard works
        _aiChatDock = _aiManager.chatDock;

        Log.i("AIIntegration: Created AI chat dock in external host");
    }

    /**
     * Ensure AI is initialized, then create/show chat dock in the given host.
     * Safe to call multiple times — idempotent.
     */
    void ensureOpenInHost(DockHost dockHost) {
        if (!_isInitialized) {
            Log.w("AIIntegration: Not initialized, cannot open chat");
            return;
        }
        createAIChatDockInHost(dockHost);
    }

    /**
     * Toggle AI chat panel visibility
     */
    void toggleAIChat() {
        if (!_isInitialized)
            return;

        // Sync _aiChatDock from manager in case it was created via ensureOpenInHost
        if (!_aiChatDock)
            _aiChatDock = _aiManager.chatDock;

        if (!_aiChatDock) {
            createAIChatDock();
            _aiChatDock = _aiManager.chatDock;
        }

        _aiManager.toggleChatPanel();
    }

    /**
     * Show AI code suggestions for current file
     */
    void showCodeSuggestions() {
        if (!_isInitialized || !_aiManager) {
            return;
        }

        // Get current file from editor (would need editor integration)
        string currentFile = getCurrentEditorFile();
        if (currentFile.empty) {
            Log.w("AIIntegration: No current file for suggestions");
            return;
        }

        // Generate suggestions
        _aiManager.generateCodeSuggestions([currentFile], "Please analyze this code and provide suggestions for improvements.");
    }

    /**
     * Ask AI about current selection
     */
    void askAboutSelection() {
        if (!_isInitialized) {
            return;
        }

        // Get current selection from editor (would need editor integration)
        string selection = getCurrentSelection();
        string currentFile = getCurrentEditorFile();

        if (selection.empty) {
            Log.w("AIIntegration: No text selected");
            return;
        }

        // Show chat and pre-fill with question about selection
        toggleAIChat();

        auto chatWidget = _aiManager.getChatWidget();
        if (chatWidget) {
            // Pre-fill input with context about selection
            string prompt = format("Please explain this code:\n\n```%s\n%s\n```",
                                 getFileLanguage(currentFile), selection);
            // Would need method to set input text in chat widget
        }
    }

    /**
     * Start AI refactoring session
     */
    void startRefactoringSession() {
        if (!_isInitialized || !_aiManager || !_codeActionManager) {
            return;
        }

        string currentFile = getCurrentEditorFile();
        if (currentFile.empty) {
            return;
        }

        // Create a code session for tracking changes
        string sessionId = _aiManager.startCodeSession("AI Refactoring Session");

        // Show chat and suggest refactoring
        toggleAIChat();

        Log.i("AIIntegration: Started refactoring session: ", sessionId);
    }

    /**
     * Rollback last AI changes
     */
    void rollbackLastChanges() {
        if (!_isInitialized || !_codeActionManager) {
            return;
        }

        auto sessions = _aiManager.getActiveSessions();
        if (sessions.empty) {
            Log.i("AIIntegration: No active sessions to rollback");
            return;
        }

        // Rollback the most recent session
        auto lastSession = sessions[$-1];
        bool success = _aiManager.rollbackSession(lastSession.id);

        if (success) {
            Log.i("AIIntegration: Rolled back session: ", lastSession.description);
        } else {
            Log.e("AIIntegration: Failed to rollback session");
        }
    }

    /**
     * Setup AI manager event handlers
     */
    private void setupAIManagerEvents() {
        // Handle code actions generated by AI
        _aiManager.onCodeActionGenerated = delegate(AICodeAction action) {
            Log.i("AIIntegration: Code action generated: ", action.description);

            // Could show notification or prompt user
            // For now, just log the action
        };

        _aiManager.onCodeActionApplied = delegate(AICodeAction action) {
            Log.i("AIIntegration: Code action applied: ", action.description);

            // Refresh editor if the current file was modified
            string currentFile = getCurrentEditorFile();
            if (action.filePath == currentFile) {
                refreshCurrentEditor();
            }
        };

        _aiManager.onSessionRollback = delegate(string sessionId) {
            Log.i("AIIntegration: Session rolled back: ", sessionId);

            // Refresh all open editors
            refreshAllEditors();
        };
    }

    /**
     * Setup code action manager event handlers
     */
    private void setupCodeActionManagerEvents() {
        _codeActionManager.onChangeSetApplied = delegate(CodeChangeSet changeSet) {
            Log.i("AIIntegration: ChangeSet applied: ", changeSet.description);

            // Refresh affected files in editors
            foreach (filePath; changeSet.affectedFiles) {
                refreshEditorFile(filePath);
            }
        };

        _codeActionManager.onValidationComplete = delegate(string filePath, ValidationResult result) {
            if (!result.isValid) {
                Log.w("AIIntegration: Validation failed for ", filePath);
                foreach (error; result.errors) {
                    Log.w("  Error: ", error);
                }
            }
        };

        _codeActionManager.onConflictDetected = delegate(string message) {
            Log.w("AIIntegration: Conflict detected: ", message);
            // Could show conflict resolution dialog
        };
    }

    /**
     * Integrate with main window
     */
    private void integrateWithMainWindow() {
        if (!_mainWindow) {
            return;
        }

        // onFileOpened / onFileClosed are MainWindow-specific delegates.
        // Guard with a dynamic cast so this is a no-op when the host is
        // IDEFrame or any other Widget that doesn't carry those hooks.
        if (auto mw = cast(MainWindow)_mainWindow) {
            mw.onFileOpened = delegate(string filePath) {
                if (_aiManager) {
                    auto symbolTracker = _aiManager.getSymbolTracker();
                    if (symbolTracker) {
                        symbolTracker.addFileToWatch(filePath);
                    }
                }
            };

            mw.onFileClosed = delegate(string filePath) {
                // Could remove from AI tracking if no longer needed
            };
        }
    }

    /**
     * Create AI menu items that can be added to main menu during creation
     */
    public MenuItem createAIMenuItems() {
        // Create AI menu
        auto aiMenu = new MenuItem(new Action(0, "AI"d));

        // Chat actions
        aiMenu.add(new MenuItem(new Action(ActionId.AI_TOGGLE_CHAT, "Toggle AI Chat"d, "F4")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_NEW_CONVERSATION, "New Conversation"d, "Ctrl+Shift+N")));

        aiMenu.addSeparator();

        // Code actions
        aiMenu.add(new MenuItem(new Action(ActionId.AI_CODE_SUGGESTIONS, "Get Code Suggestions"d, "Ctrl+Shift+S")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_ASK_SELECTION, "Ask About Selection"d, "Ctrl+Shift+A")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_REFACTOR, "Start Refactoring"d, "Ctrl+Shift+R")));

        aiMenu.addSeparator();

        // Session management
        aiMenu.add(new MenuItem(new Action(ActionId.AI_ROLLBACK, "Rollback Changes"d, "Ctrl+Shift+Z")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_SESSIONS, "Manage Sessions..."d)));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_IMPORT_CHATGPT_EXPORT, "Import ChatGPT Export..."d)));

        aiMenu.addSeparator();

        // Configuration
        aiMenu.add(new MenuItem(new Action(ActionId.AI_SETTINGS, "AI Settings..."d)));

        Log.i("AIIntegration: Created AI menu items");
        return aiMenu;
    }

    /**
     * Add AI menu items to main menu (deprecated - use createAIMenuItems instead)
     */
    private void addMenuItems() {
        // getMainMenu() is MainWindow-specific; no-op for IDEFrame which builds
        // its own menu in frame.d.
        auto mw = cast(MainWindow)_mainWindow;
        if (!mw) {
            return;
        }

        auto mainMenu = mw.getMainMenu();
        if (!mainMenu) {
            return;
        }

        // Create AI menu
        auto aiMenu = new MenuItem(new Action(0, "AI"d));

        // Chat actions
        aiMenu.add(new MenuItem(new Action(ActionId.AI_TOGGLE_CHAT, "Toggle AI Chat"d, "F4")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_NEW_CONVERSATION, "New Conversation"d, "Ctrl+Shift+N")));

        aiMenu.addSeparator();

        // Code actions
        aiMenu.add(new MenuItem(new Action(ActionId.AI_CODE_SUGGESTIONS, "Get Code Suggestions"d, "Ctrl+Shift+S")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_ASK_SELECTION, "Ask About Selection"d, "Ctrl+Shift+A")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_REFACTOR, "Start Refactoring"d, "Ctrl+Shift+R")));

        aiMenu.addSeparator();

        // Session management
        aiMenu.add(new MenuItem(new Action(ActionId.AI_ROLLBACK, "Rollback Changes"d, "Ctrl+Shift+Z")));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_SESSIONS, "Manage Sessions..."d)));
        aiMenu.add(new MenuItem(new Action(ActionId.AI_IMPORT_CHATGPT_EXPORT, "Import ChatGPT Export..."d)));

        aiMenu.addSeparator();

        // Configuration
        aiMenu.add(new MenuItem(new Action(ActionId.AI_SETTINGS, "AI Settings..."d)));

        // This method is deprecated - menu items should be created during menu creation
        // using createAIMenuItems() method
        Log.w("AIIntegration: addMenuItems() is deprecated");
    }

    /**
     * Setup keyboard shortcuts
     */
    private void setupKeyboardShortcuts() {
        if (!_mainWindow) {
            return;
        }

        // addKeyboardShortcut is a MainWindow-specific API.
        // IDEFrame registers its shortcuts via its own acceleratorMap / action
        // handling, so this is a no-op for the current IDE host.
        if (auto mw = cast(MainWindow)_mainWindow) {
            mw.addKeyboardShortcut("F4", ActionId.AI_TOGGLE_CHAT);
            mw.addKeyboardShortcut("Ctrl+Shift+N", ActionId.AI_NEW_CONVERSATION);
            mw.addKeyboardShortcut("Ctrl+Shift+S", ActionId.AI_CODE_SUGGESTIONS);
            mw.addKeyboardShortcut("Ctrl+Shift+A", ActionId.AI_ASK_SELECTION);
            mw.addKeyboardShortcut("Ctrl+Shift+R", ActionId.AI_REFACTOR);
            mw.addKeyboardShortcut("Ctrl+Shift+Z", ActionId.AI_ROLLBACK);

            Log.i("AIIntegration: Setup keyboard shortcuts");
        }
    }

    /**
     * Handle menu actions
     */
    bool handleMenuAction(const Action action) {
        if (!_isInitialized) {
            return false;
        }

        switch (action.id) {
            case ActionId.AI_TOGGLE_CHAT:
                toggleAIChat();
                return true;

            case ActionId.AI_NEW_CONVERSATION:
                if (_aiChatDock && _aiManager) {
                    auto chatWidget = _aiManager.getChatWidget();
                    if (chatWidget) {
                        chatWidget.createNewThread("New Conversation");
                    }
                }
                return true;

            case ActionId.AI_CODE_SUGGESTIONS:
                showCodeSuggestions();
                return true;

            case ActionId.AI_ASK_SELECTION:
                askAboutSelection();
                return true;

            case ActionId.AI_REFACTOR:
                startRefactoringSession();
                return true;

            case ActionId.AI_ROLLBACK:
                rollbackLastChanges();
                return true;

            case ActionId.AI_SESSIONS:
                showSessionManager();
                return true;

            case ActionId.AI_IMPORT_CHATGPT_EXPORT:
                importChatGPTExport();
                return true;

            case ActionId.AI_SETTINGS:
                showAISettings();
                return true;

            default:
                return false;
        }
    }

    /**
     * Show session manager dialog
     */
    private void showSessionManager() {
        // Would create and show session management dialog
        Log.i("AIIntegration: Would show session manager");
    }

    /**
     * Import ChatGPT export file into chat threads
     */
    private void importChatGPTExport() {
        if (!_aiManager) {
            Log.w("AIIntegration: AI manager not initialized");
            return;
        }

        auto chatWidget = _aiManager.getChatWidget();
        if (!chatWidget) {
            Log.w("AIIntegration: Chat widget is not available");
            return;
        }

        auto dlg = new FileDialog(UIString.fromRaw("Import ChatGPT Export"), _mainWindow.window);
        dlg.addFilter(FileFilterEntry(UIString.fromRaw("JSON Files (*.json)"), "*.json"));
        dlg.addFilter(FileFilterEntry(UIString.fromRaw("All Files (*)"), "*"));

        dlg.dialogResult = delegate(Dialog sender, const Action result) {
            if (result.id == ACTION_OPEN.id) {
                string filename = result.stringParam;
                if (filename.empty) {
                    return;
                }

                try {
                    chatWidget.importConversation(filename);
                    Log.i("AIIntegration: Imported ChatGPT export from ", filename);
                } catch (Exception e) {
                    Log.e("AIIntegration: Failed importing ChatGPT export: ", e.msg);
                }
            }
        };

        dlg.show();
    }

    /**
     * Show AI settings dialog
     */
    private void showAISettings() {
        // Would create and show AI configuration dialog
        Log.i("AIIntegration: Would show AI settings");
    }

    /**
     * Get current file from editor (placeholder)
     */
    private string getCurrentEditorFile() {
        // This would integrate with the editor system
        // For now, return empty string
        return "";
    }

    /**
     * Get current text selection (placeholder)
     */
    private string getCurrentSelection() {
        // This would integrate with the editor system
        return "";
    }

    /**
     * Get programming language for file
     */
    private string getFileLanguage(string filePath) {
        if (filePath.empty) return "text";

        string ext = extension(filePath).toLower();
        switch (ext) {
            case ".d", ".di": return "d";
            case ".js": return "javascript";
            case ".ts": return "typescript";
            case ".py": return "python";
            case ".rs": return "rust";
            case ".c": return "c";
            case ".cpp", ".cxx", ".cc": return "cpp";
            case ".h": return "c";
            case ".hpp", ".hxx": return "cpp";
            default: return "text";
        }
    }

    /**
     * Refresh current editor (placeholder)
     */
    private void refreshCurrentEditor() {
        // Would refresh/reload current editor
        Log.i("AIIntegration: Would refresh current editor");
    }

    /**
     * Refresh all open editors (placeholder)
     */
    private void refreshAllEditors() {
        // Would refresh/reload all open editors
        Log.i("AIIntegration: Would refresh all editors");
    }

    /**
     * Refresh specific editor file (placeholder)
     */
    private void refreshEditorFile(string filePath) {
        // Would refresh/reload specific editor file
        Log.i("AIIntegration: Would refresh editor file: ", filePath);
    }

    /**
     * Get AI manager for external access
     */
    AIManager getAIManager() {
        return _aiManager;
    }

    /**
     * Get code action manager for external access
     */
    CodeActionManager getCodeActionManager() {
        return _codeActionManager;
    }

    /**
     * Check if AI integration is initialized
     */
    bool isInitialized() {
        return _isInitialized;
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        if (_codeActionManager) {
            _codeActionManager.cleanup();
        }

        if (_aiManager) {
            _aiManager.cleanup();
        }

        _isInitialized = false;
        Log.i("AIIntegration: Cleaned up");
    }
}

/**
 * Action IDs for AI menu items
 */
enum ActionId {
    AI_TOGGLE_CHAT = 9000,
    AI_NEW_CONVERSATION = 9001,
    AI_CODE_SUGGESTIONS = 9002,
    AI_ASK_SELECTION = 9003,
    AI_REFACTOR = 9004,
    AI_ROLLBACK = 9005,
    AI_SESSIONS = 9006,
    AI_SETTINGS = 9007,
    AI_IMPORT_CHATGPT_EXPORT = 9008
}
