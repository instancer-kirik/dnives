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
import dlangui.core.logger;
import dlangui.widgets.docks;
import dlangui.widgets.widget;
import dlangui.widgets.menu;
import dlangui.core.events;

import dcore.core;
import dcore.components.cccore;
import dcore.ui.mainwindow;
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
    private MainWindow _mainWindow;
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
    this(DCore core, CCCore ccCore, MainWindow mainWindow) {
        _core = core;
        _ccCore = ccCore;
        _mainWindow = mainWindow;

        Log.i("AIIntegration: Initialized");
    }

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

            // Add menu items
            addMenuItems();

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
        if (!_isInitialized || !_mainWindow || _aiChatDock) {
            return;
        }

        auto dockHost = _mainWindow.dockHost;
        if (!dockHost) {
            Log.e("AIIntegration: No dock host available");
            return;
        }

        // Create the chat dock using AI manager
        _aiManager.createChatDock(dockHost);

        Log.i("AIIntegration: Created AI chat dock");
    }

    /**
     * Toggle AI chat panel visibility
     */
    void toggleAIChat() {
        if (!_isInitialized) {
            return;
        }

        if (!_aiChatDock) {
            createAIChatDock();
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

        // Set up window events
        _mainWindow.onFileOpened = delegate(string filePath) {
            // Notify AI system about new file
            if (_aiManager) {
                auto symbolTracker = _aiManager.getSymbolTracker();
                if (symbolTracker) {
                    symbolTracker.addFileToWatch(filePath);
                }
            }
        };

        _mainWindow.onFileClosed = delegate(string filePath) {
            // Could remove from AI tracking if no longer needed
        };
    }

    /**
     * Add AI menu items to main menu
     */
    private void addMenuItems() {
        if (!_mainWindow) {
            return;
        }

        auto mainMenu = _mainWindow.getMainMenu();
        if (!mainMenu) {
            return;
        }

        // Create AI menu
        auto aiMenu = mainMenu.addSubmenu(null, "AI"d);

        // Chat actions
        aiMenu.addAction(new Action(ActionId.AI_TOGGLE_CHAT, "Toggle AI Chat"d, "F4"));
        aiMenu.addAction(new Action(ActionId.AI_NEW_CONVERSATION, "New Conversation"d, "Ctrl+Shift+N"));

        aiMenu.addSeparator();

        // Code actions
        aiMenu.addAction(new Action(ActionId.AI_CODE_SUGGESTIONS, "Get Code Suggestions"d, "Ctrl+Shift+S"));
        aiMenu.addAction(new Action(ActionId.AI_ASK_SELECTION, "Ask About Selection"d, "Ctrl+Shift+A"));
        aiMenu.addAction(new Action(ActionId.AI_REFACTOR, "Start Refactoring"d, "Ctrl+Shift+R"));

        aiMenu.addSeparator();

        // Session management
        aiMenu.addAction(new Action(ActionId.AI_ROLLBACK, "Rollback Changes"d, "Ctrl+Shift+Z"));
        aiMenu.addAction(new Action(ActionId.AI_SESSIONS, "Manage Sessions..."d));

        aiMenu.addSeparator();

        // Configuration
        aiMenu.addAction(new Action(ActionId.AI_SETTINGS, "AI Settings..."d));

        Log.i("AIIntegration: Added AI menu items");
    }

    /**
     * Setup keyboard shortcuts
     */
    private void setupKeyboardShortcuts() {
        if (!_mainWindow) {
            return;
        }

        // Register keyboard shortcuts
        _mainWindow.addKeyboardShortcut("F4", ActionId.AI_TOGGLE_CHAT);
        _mainWindow.addKeyboardShortcut("Ctrl+Shift+N", ActionId.AI_NEW_CONVERSATION);
        _mainWindow.addKeyboardShortcut("Ctrl+Shift+S", ActionId.AI_CODE_SUGGESTIONS);
        _mainWindow.addKeyboardShortcut("Ctrl+Shift+A", ActionId.AI_ASK_SELECTION);
        _mainWindow.addKeyboardShortcut("Ctrl+Shift+R", ActionId.AI_REFACTOR);
        _mainWindow.addKeyboardShortcut("Ctrl+Shift+Z", ActionId.AI_ROLLBACK);

        Log.i("AIIntegration: Setup keyboard shortcuts");
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
    AI_SETTINGS = 9007
}
