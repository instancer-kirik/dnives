module dcore.ai.ai_manager;

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
import std.typecons;
import core.time;

import dlangui.core.logger;
import dlangui.widgets.widget;
import dlangui.widgets.docks;

import dcore.core;
import dcore.ai.ai_backend;
import dcore.ai.context_manager;
import dcore.ai.widgets.chat_widget;
import dcore.code.symbol_tracker;
import dcore.lsp.lspmanager;

/**
 * AIConfiguration - Configuration for AI system
 */
struct AIConfiguration {
    string defaultBackend = "openai";
    bool enableStreaming = true;
    bool enableCodeExecution = false;
    int maxContextTokens = 8000;
    int maxResponseTokens = 2000;
    double temperature = 0.7;
    string systemPrompt = "You are an expert coding assistant. Help users with code analysis, debugging, and development tasks.";

    // Backend configurations
    JSONValue openaiConfig;
    JSONValue anthropicConfig;
    JSONValue ollamaConfig;

    // Default initialization - structs in D automatically have default constructors
}

/**
 * AICodeAction - Represents an AI-suggested code action
 */
struct AICodeAction {
    enum Type {
        Replace,
        Insert,
        Delete,
        Refactor,
        Fix
    }

    string id;
    Type type;
    string filePath;
    int startLine;
    int endLine;
    string originalCode;
    string newCode;
    string description;
    string reasoning;
    bool isApplied;
    DateTime timestamp;

    this(Type type, string filePath, int startLine, int endLine, string newCode, string description) {
        import std.uuid;
        this.id = randomUUID().toString();
        this.type = type;
        this.filePath = filePath;
        this.startLine = startLine;
        this.endLine = endLine;
        this.newCode = newCode;
        this.description = description;
        this.isApplied = false;
        this.timestamp = cast(DateTime)Clock.currTime();
    }
}

/**
 * AICodeSession - Tracks code changes and rollback capability
 */
struct AICodeSession {
    string id;
    string description;
    AICodeAction[] actions;
    string[] modifiedFiles;
    DateTime created;
    bool isActive;

    this(string description) {
        import std.uuid;
        this.id = randomUUID().toString();
        this.description = description;
        this.created = cast(DateTime)Clock.currTime();
        this.isActive = true;
    }
}

/**
 * AIManager - Central coordinator for AI functionality
 *
 * Features:
 * - Manages AI backends and configuration
 * - Coordinates symbol tracking and context management
 * - Provides chat interface integration
 * - Handles automated code changes and rollback
 * - Manages AI sessions and state
 */
class AIManager {
    // Core components
    private DCore _core;
    private AIBackendManager _backendManager;
    private ContextManager _contextManager;
    private SymbolTracker _symbolTracker;
    private LSPManager _lspManager;

    // UI components
    private ChatWidget _chatWidget;
    private DockWindow _chatDock;

    // Configuration
    private AIConfiguration _config;
    private string _configPath;

    // State management
    private AICodeSession[] _sessions;
    private string _activeSessionId;
    private AICodeAction[string] _pendingActions; // id -> action

    // Events
    void delegate(AICodeAction action) onCodeActionGenerated;
    void delegate(AICodeAction action) onCodeActionApplied;
    void delegate(string sessionId) onSessionRollback;

    /**
     * Constructor
     */
    this(DCore core, LSPManager lspManager) {
        _core = core;
        _lspManager = lspManager;

        // Initialize configuration path
        _configPath = buildPath(_core.getConfigDir(), "ai_config.json");

        // Load configuration
        loadConfiguration();

        Log.i("AIManager: Initialized");
    }

    /**
     * Initialize the AI manager
     */
    void initialize() {
        try {
            // Initialize backend manager
            _backendManager = new AIBackendManager();
            _backendManager.initialize(buildBackendConfig());

            // Initialize symbol tracker
            _symbolTracker = new SymbolTracker(_core, _lspManager);
            _symbolTracker.initialize();

            // Initialize context manager
            _contextManager = new ContextManager(_core, _symbolTracker, _lspManager);
            _contextManager.initialize();

            // Create chat widget
            _chatWidget = new ChatWidget(_core, _backendManager, _contextManager, _symbolTracker);

            // Set up event handlers
            setupEventHandlers();

            Log.i("AIManager: Initialized successfully");

        } catch (Exception e) {
            Log.e("AIManager: Initialization failed: ", e.msg);
            throw e;
        }
    }

    /**
     * Create the AI chat dock window
     */
    void createChatDock(DockHost dockHost) {
        if (!_chatWidget || !dockHost)
            return;

        // Simplified dock window creation - avoid API compatibility issues
        try {
            _chatDock = new DockWindow("AI_CHAT");
            _chatDock.bodyWidget = _chatWidget;
            dockHost.addDockedWindow(_chatDock);
        } catch (Exception e) {
            Log.w("AIManager: Could not create dock window: ", e.msg);
            // Fall back to not using docked window
        }

        Log.i("AIManager: Created chat dock window");
    }

    /**
     * Show/hide the AI chat panel
     */
    void toggleChatPanel() {
        if (_chatDock) {
            _chatDock.visibility = _chatDock.visibility == Visibility.Visible ?
                                  Visibility.Gone : Visibility.Visible;
        }
    }

    /**
     * Start a new AI session for code changes
     */
    string startCodeSession(string description) {
        auto session = AICodeSession(description);
        _sessions ~= session;
        _activeSessionId = session.id;

        Log.i("AIManager: Started new code session: ", session.id, " - ", description);
        return session.id;
    }

    /**
     * Apply a code action
     */
    bool applyCodeAction(string actionId) {
        if (actionId !in _pendingActions)
            return false;

        auto action = _pendingActions[actionId];

        try {
            // Read current file content
            if (!exists(action.filePath)) {
                Log.e("AIManager: File not found: ", action.filePath);
                return false;
            }

            auto lines = readText(action.filePath).split('\n');
            action.originalCode = lines[action.startLine..action.endLine+1].join('\n');

            // Apply the change based on type
            switch (action.type) {
                case AICodeAction.Type.Replace:
                    // Replace lines
                    lines = lines[0..action.startLine] ~
                           action.newCode.split('\n') ~
                           lines[action.endLine+1..$];
                    break;

                case AICodeAction.Type.Insert:
                    // Insert at position
                    lines = lines[0..action.startLine] ~
                           action.newCode.split('\n') ~
                           lines[action.startLine..$];
                    break;

                case AICodeAction.Type.Delete:
                    // Delete lines
                    lines = lines[0..action.startLine] ~
                           lines[action.endLine+1..$];
                    break;

                default:
                    Log.w("AIManager: Unsupported action type: ", action.type);
                    return false;
            }

            // Write back to file
            std.file.write(action.filePath, lines.join('\n'));

            // Mark as applied
            action.isApplied = true;
            _pendingActions[actionId] = action;

            // Add to active session
            if (!_activeSessionId.empty) {
                auto session = getSession(_activeSessionId);
                if (session) {
                    session.actions ~= action;
                    if (!session.modifiedFiles.canFind(action.filePath)) {
                        session.modifiedFiles ~= action.filePath;
                    }
                }
            }

            // Trigger event
            if (onCodeActionApplied)
                onCodeActionApplied(action);

            Log.i("AIManager: Applied code action: ", actionId);
            return true;

        } catch (Exception e) {
            Log.e("AIManager: Failed to apply code action: ", e.msg);
            return false;
        }
    }

    /**
     * Rollback a session
     */
    bool rollbackSession(string sessionId) {
        auto session = getSession(sessionId);
        if (!session || !session.isActive)
            return false;

        try {
            // Rollback actions in reverse order
            foreach_reverse (action; session.actions) {
                if (action.isApplied) {
                    rollbackAction(action);
                }
            }

            session.isActive = false;

            // Trigger event
            if (onSessionRollback)
                onSessionRollback(sessionId);

            Log.i("AIManager: Rolled back session: ", sessionId);
            return true;

        } catch (Exception e) {
            Log.e("AIManager: Failed to rollback session: ", e.msg);
            return false;
        }
    }

    /**
     * Rollback a single action
     */
    private bool rollbackAction(AICodeAction action) {
        if (!action.isApplied)
            return false;

        try {
            auto lines = readText(action.filePath).split('\n');

            switch (action.type) {
                case AICodeAction.Type.Replace:
                    // Restore original lines
                    auto originalLines = action.originalCode.split('\n');
                    auto newLines = action.newCode.split('\n');

                    // Replace the new lines with original
                    lines = lines[0..action.startLine] ~
                           originalLines ~
                           lines[action.startLine + newLines.length..$];
                    break;

                case AICodeAction.Type.Insert:
                    // Remove inserted lines
                    auto insertedLines = action.newCode.split('\n');
                    lines = lines[0..action.startLine] ~
                           lines[action.startLine + insertedLines.length..$];
                    break;

                case AICodeAction.Type.Delete:
                    // Restore deleted lines
                    auto restoredLines = action.originalCode.split('\n');
                    lines = lines[0..action.startLine] ~
                           restoredLines ~
                           lines[action.startLine..$];
                    break;

                default:
                    return false;
            }

            std.file.write(action.filePath, lines.join('\n'));
            return true;

        } catch (Exception e) {
            Log.e("AIManager: Failed to rollback action: ", e.msg);
            return false;
        }
    }

    /**
     * Generate code suggestions for current context
     */
    void generateCodeSuggestions(string[] files, string prompt = "") {
        if (!_backendManager || files.empty)
            return;

        try {
            // Get code context
            string contextString = _contextManager.getCodeContext(files);

            // Build messages
            AIMessage[] messages;

            // System message with instructions
            string systemMessage = _config.systemPrompt ~
                "\n\nAnalyze the following code and provide specific, actionable suggestions:\n\n" ~
                contextString;
            messages ~= AIMessage(AIMessage.Role.System, systemMessage);

            // User prompt
            if (prompt.empty) {
                prompt = "Please review this code and suggest improvements, fixes, or optimizations. " ~
                        "Provide specific code changes that can be applied.";
            }
            messages ~= AIMessage(AIMessage.Role.User, prompt);

            // Send to AI
            auto response = _backendManager.chat(messages);

            // Parse response for code actions
            auto actions = parseCodeActionsFromResponse(response.content, files);

            // Add to pending actions
            foreach (action; actions) {
                _pendingActions[action.id] = action;

                if (onCodeActionGenerated)
                    onCodeActionGenerated(action);
            }

            Log.i("AIManager: Generated ", actions.length, " code suggestions");

        } catch (Exception e) {
            Log.e("AIManager: Failed to generate code suggestions: ", e.msg);
        }
    }

    /**
     * Parse code actions from AI response
     */
    private AICodeAction[] parseCodeActionsFromResponse(string response, string[] files) {
        AICodeAction[] actions;

        // Simple parsing - in practice, this would be more sophisticated
        // Look for code blocks and file references
        auto lines = response.split('\n');

        // This is a placeholder implementation
        // Real implementation would parse structured responses or use AI to extract actions

        return actions;
    }

    /**
     * Get available AI backends
     */
    string[] getAvailableBackends() {
        if (_backendManager)
            return _backendManager.getAvailableBackends();
        return [];
    }

    /**
     * Switch AI backend
     */
    void switchBackend(string backendName) {
        if (!_backendManager)
            return;

        auto backend = _backendManager.getBackend(backendName);
        if (backend && backend.isAvailable()) {
            _config.defaultBackend = backendName;
            saveConfiguration();
            Log.i("AIManager: Switched to backend: ", backendName);
        }
    }

    /**
     * Update AI configuration
     */
    void updateConfiguration(AIConfiguration config) {
        _config = config;
        saveConfiguration();

        // Reinitialize backends if needed
        if (_backendManager) {
            _backendManager.initialize(buildBackendConfig());
        }
    }

    /**
     * Get current configuration
     */
    AIConfiguration getConfiguration() {
        return _config;
    }

    /**
     * Get session by ID
     */
    private AICodeSession* getSession(string sessionId) {
        foreach (ref session; _sessions) {
            if (session.id == sessionId) {
                return &session;
            }
        }
        return null;
    }

    /**
     * Get active sessions
     */
    AICodeSession[] getActiveSessions() {
        return _sessions.filter!(s => s.isActive).array;
    }

    /**
     * Get pending actions
     */
    AICodeAction[] getPendingActions() {
        return _pendingActions.values.filter!(a => !a.isApplied).array;
    }

    /**
     * Setup event handlers
     */
    private void setupEventHandlers() {
        // Set up internal event handling
        onCodeActionGenerated = delegate(AICodeAction action) {
            Log.i("AIManager: Code action generated: ", action.description);
        };

        onCodeActionApplied = delegate(AICodeAction action) {
            Log.i("AIManager: Code action applied: ", action.id);

            // Trigger symbol tracker refresh for modified files
            if (_symbolTracker) {
                _symbolTracker.addFileToWatch(action.filePath);
            }
        };

        onSessionRollback = delegate(string sessionId) {
            Log.i("AIManager: Session rolled back: ", sessionId);
        };
    }

    /**
     * Build backend configuration
     */
    private JSONValue buildBackendConfig() {
        JSONValue config = JSONValue.emptyObject;

        config["default_backend"] = _config.defaultBackend;

        if (_config.openaiConfig.type != JSONType.null_) {
            config["openai"] = _config.openaiConfig;
        }

        if (_config.anthropicConfig.type != JSONType.null_) {
            config["anthropic"] = _config.anthropicConfig;
        }

        if (_config.ollamaConfig.type != JSONType.null_) {
            config["ollama"] = _config.ollamaConfig;
        }

        return config;
    }

    /**
     * Load configuration from file
     */
    private void loadConfiguration() {
        _config = AIConfiguration();

        if (!exists(_configPath))
            return;

        try {
            string content = readText(_configPath);
            JSONValue json = parseJSON(content);

            if ("default_backend" in json)
                _config.defaultBackend = json["default_backend"].str;
            if ("enable_streaming" in json)
                _config.enableStreaming = json["enable_streaming"].get!bool;
            if ("enable_code_execution" in json)
                _config.enableCodeExecution = json["enable_code_execution"].get!bool;
            if ("max_context_tokens" in json)
                _config.maxContextTokens = json["max_context_tokens"].get!int;
            if ("max_response_tokens" in json)
                _config.maxResponseTokens = json["max_response_tokens"].get!int;
            if ("temperature" in json)
                _config.temperature = json["temperature"].get!double;
            if ("system_prompt" in json)
                _config.systemPrompt = json["system_prompt"].str;

            if ("openai" in json)
                _config.openaiConfig = json["openai"];
            if ("anthropic" in json)
                _config.anthropicConfig = json["anthropic"];
            if ("ollama" in json)
                _config.ollamaConfig = json["ollama"];

            Log.i("AIManager: Loaded configuration from ", _configPath);

        } catch (Exception e) {
            Log.w("AIManager: Failed to load configuration: ", e.msg);
        }
    }

    /**
     * Save configuration to file
     */
    private void saveConfiguration() {
        try {
            JSONValue json = JSONValue.emptyObject;

            json["default_backend"] = _config.defaultBackend;
            json["enable_streaming"] = _config.enableStreaming;
            json["enable_code_execution"] = _config.enableCodeExecution;
            json["max_context_tokens"] = _config.maxContextTokens;
            json["max_response_tokens"] = _config.maxResponseTokens;
            json["temperature"] = _config.temperature;
            json["system_prompt"] = _config.systemPrompt;

            if (_config.openaiConfig.type != JSONType.null_)
                json["openai"] = _config.openaiConfig;
            if (_config.anthropicConfig.type != JSONType.null_)
                json["anthropic"] = _config.anthropicConfig;
            if (_config.ollamaConfig.type != JSONType.null_)
                json["ollama"] = _config.ollamaConfig;

            // Ensure config directory exists
            string configDir = dirName(_configPath);
            if (!exists(configDir))
                mkdirRecurse(configDir);

            std.file.write(_configPath, json.toPrettyString());

            Log.i("AIManager: Saved configuration to ", _configPath);

        } catch (Exception e) {
            Log.e("AIManager: Failed to save configuration: ", e.msg);
        }
    }

    /**
     * Get chat widget for external access
     */
    ChatWidget getChatWidget() {
        return _chatWidget;
    }

    /**
     * Get context manager for external access
     */
    ContextManager getContextManager() {
        return _contextManager;
    }

    /**
     * Get symbol tracker for external access
     */
    SymbolTracker getSymbolTracker() {
        return _symbolTracker;
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        if (_contextManager)
            _contextManager.cleanup();

        if (_symbolTracker)
            _symbolTracker.cleanup();

        if (_backendManager)
            _backendManager.cleanup();

        if (_chatWidget)
            _chatWidget.cleanup();

        _sessions.length = 0;
        _pendingActions.clear();

        Log.i("AIManager: Cleaned up");
    }
}
