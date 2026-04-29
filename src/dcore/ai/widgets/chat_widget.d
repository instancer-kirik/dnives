module dcore.ai.widgets.chat_widget;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.range;
import std.json;
import std.datetime;
import std.exception;
import std.conv;
import std.format;
import std.typecons;
import std.uuid;
import core.time;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.lists;
import dlangui.widgets.tabs;
import dlangui.widgets.tree;
import dlangui.widgets.layouts;
import dlangui.widgets.popup;
import dlangui.widgets.scrollbar;
import dlangui.dialogs.dialog;
import dlangui.core.logger;
import dlangui.core.events;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;

import dcore.core;
import dcore.ai.ai_backend;
import dcore.ai.context_manager;
import dcore.ai.chatgpt_importer;
import dcore.code.symbol_tracker;
import dlangui.widgets.combobox;

/**
 * ChatMessage - Represents a single chat message
 */
struct ChatMessage {
    string id;
    AIMessage.Role role;
    string content;
    string[] attachments;     // File paths or references
    string[] codeBlocks;      // Extracted code blocks
    DateTime timestamp;
    bool isStreaming;
    string source = "local";  // local | imported_chatgpt
    string externalId;        // Original message ID from imported source
    string parentMessageId;   // Parent relationship for imported/threaded data

    this(AIMessage.Role role, string content) {
        this.id = randomUUID().toString();
        this.role = role;
        this.content = content;
        this.timestamp = cast(DateTime)Clock.currTime();
        this.isStreaming = false;
    }
}

/**
 * ChatThread - Represents a conversation thread
 */
struct ChatThread {
    string id;
    string title;
    string workspacePath;
    ChatMessage[] messages;
    string[] contextFiles;
    string currentSymbol;
    DateTime created;
    DateTime lastActivity;
    JSONValue metadata;
    string source = "local";      // local | imported_chatgpt
    string externalId;            // Original conversation id from imported source
    string importPath;            // Source file path for imports

    this(string title, string workspacePath) {
        this.id = randomUUID().toString();
        this.title = title;
        this.workspacePath = workspacePath;
        this.created = cast(DateTime)Clock.currTime();
        this.lastActivity = cast(DateTime)Clock.currTime();
        this.metadata = JSONValue.emptyObject;
        this.source = "local";
    }
}

/**
 * FileReference - References to files in context
 */
struct FileReference {
    string filePath;
    string displayName;
    int[] relevantLines;
    bool isPinned;
    DateTime addedAt;

    this(string filePath) {
        this.filePath = filePath;
        this.displayName = baseName(filePath);
        this.addedAt = cast(DateTime)Clock.currTime();
        this.isPinned = false;
    }
}

/**
 * ChatWidget - AI chat interface with split view and context management
 *
 * Features:
 * - Split pane with chat and context view
 * - Thread management for conversations
 * - File reference management
 * - Code block handling and application
 * - Streaming responses
 * - Context window management
 */
class ChatWidget : HorizontalLayout {
    // Core components
    private DCore _core;
    private AIBackendManager _aiBackend;
    private ContextManager _contextManager;
    private SymbolTracker _symbolTracker;

    // UI components - Left pane (chat)
    private VerticalLayout _leftPane;
    private HorizontalLayout _chatToolbar;      // view bar strip at top of chat pane
    private TextWidget _threadSourceBadge;       // shows "local" / "ChatGPT" source
    private ComboBox _backendCombo;              // backend selector
    private HorizontalLayout _continueBanner;    // shown for imported threads
    private Button _continueBtn;
    private TabWidget _threadTabs;
    private ScrollWidget _chatScroll;
    private VerticalLayout _chatContainer;
    private HorizontalLayout _inputContainer;
    private EditBox _inputBox;
    private Button _sendButton;
    private Button _attachButton;
    private Button _stopButton;

    // UI components - Right pane (context)
    private VerticalLayout _rightPane;
    private TabWidget _contextTabs;
    private TreeWidget _fileTree;
    private EditLine _symbolSearch;
    private ListWidget _contextFiles;
    private EditBox _contextPreview;

    // State
    private ChatThread[string] _threads;
    private string _currentThreadId;
    private FileReference[string] _fileReferences;
    private bool _isStreaming;
    private string _streamingMessageId;
    private string _selectedBackend;   // "" means use AIBackendManager default
    private string[] _backendNames;    // parallel to combobox items
    private bool _suppressTabChange;   // guard against re-entrant tab events
    
    // Bulk selection state
    private string[] _selectedMessageIds;     // Selected message IDs
    private string[string] _selectedBlockIds; // Selected block IDs (key: blockId, value: messageId)
    private bool _bulkSelectionMode = false;  // Whether bulk selection mode is active

    // Configuration
    private int _maxMessageLength = 4000;
    private bool _showLineNumbers = true;
    private bool _autoScroll = true;
    private bool _contextPaneVisible = false;  // hidden by default to avoid squish

    /// Called when the user clicks "API Keys" — wire this up externally to open settings
    void delegate() onOpenSettings;

    /**
     * Constructor
     */
    this(DCore core, AIBackendManager aiBackend, ContextManager contextManager, SymbolTracker symbolTracker) {
        super("AI_CHAT");
        _core = core;
        _aiBackend = aiBackend;
        _contextManager = contextManager;
        _symbolTracker = symbolTracker;

        // Set splitter properties
        orientation = Orientation.Horizontal;
        // Layout position setup - using HorizontalLayout instead of splitter
        // splitterPosition = 60; // 60% for chat, 40% for context

        initializeUI();
        setupEventHandlers();

        Log.i("ChatWidget: Initialized");
    }

    /**
     * Initialize the user interface
     */
    private void initializeUI() {
        // Create left pane (chat interface)
        _leftPane = new VerticalLayout("CHAT_PANE");
        _leftPane.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        createChatInterface();
        addChild(_leftPane);

        // Create right pane (context management) - hidden by default
        _rightPane = new VerticalLayout("CONTEXT_PANE");
        _rightPane.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _rightPane.layoutWeight = 35;
        _rightPane.minWidth = 180;
        _rightPane.visibility = Visibility.Gone;

        createContextInterface();
        addChild(_rightPane);

        // Create initial thread
        createNewThread("New Conversation");
    }

    /**
     * Create the chat interface (left pane)
     */
    private void createChatInterface() {
        // --- View bar: backend selector + thread source badge ---
        createChatToolbar();

        // Thread tabs
        _threadTabs = new TabWidget("THREAD_TABS");
        _threadTabs.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _threadTabs.tabClose = delegate(string tabId) {
            deleteThread(tabId);
        };
        _leftPane.addChild(_threadTabs);

        // --- Continue banner (shown only for imported threads) ---
        createContinueBanner();

        // Chat area with scroll
        _chatScroll = new ScrollWidget("CHAT_SCROLL");
        _chatScroll.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _chatScroll.backgroundColor = 0x1E1E1E;

        _chatContainer = new VerticalLayout("CHAT_CONTAINER");
        _chatContainer.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _chatContainer.padding(Rect(10, 10, 10, 10));
        _chatScroll.contentWidget = _chatContainer;

        _leftPane.addChild(_chatScroll);

        // Input area
        _inputContainer = new HorizontalLayout("INPUT_CONTAINER");
        _inputContainer.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _inputContainer.minHeight(56);
        _inputContainer.padding(Rect(8, 8, 8, 8));
        _inputContainer.backgroundColor(0x1A1A1A);

        _attachButton = new Button("ATTACH_BTN", "📎");
        _attachButton.tooltipText = "Attach files or symbols";
        _inputContainer.addChild(_attachButton);

        _inputBox = new EditBox("INPUT_BOX");
        _inputBox.layoutWidth(FILL_PARENT);
        _inputBox.layoutHeight(WRAP_CONTENT);
        _inputBox.minHeight(40);
        _inputBox.maxHeight(200);  // Allow expanding up to 200px
        _inputBox.padding(Rect(8, 6, 8, 6));
        _inputBox.tooltipText = "Type a message. Enter to send, Shift+Enter for new line"d;
        _inputBox.vscrollbarMode = ScrollBarMode.Auto;  // Show scrollbar when needed
        _inputContainer.addChild(_inputBox);

        _sendButton = new Button("SEND_BTN", "Send");
        _sendButton.enabled = false;
        _inputContainer.addChild(_sendButton);

        _stopButton = new Button("STOP_BTN", "Stop");
        _stopButton.enabled = false;
        _stopButton.visibility = Visibility.Gone;
        _inputContainer.addChild(_stopButton);

        _leftPane.addChild(_inputContainer);
    }

    /**
     * Create the top toolbar strip (view bar) for the chat pane.
     * Contains the thread source badge and the backend selector.
     */
    private void createChatToolbar() {
        _chatToolbar = new HorizontalLayout("CHAT_TOOLBAR");
        _chatToolbar.layoutWidth = FILL_PARENT;
        _chatToolbar.layoutHeight = WRAP_CONTENT;
        _chatToolbar.padding = Rect(8, 4, 8, 4);
        _chatToolbar.backgroundColor = 0x252526;

        // Thread source badge — updated by updateThreadBar()
        _threadSourceBadge = new TextWidget("THREAD_SOURCE_BADGE", "● local"d);
        _threadSourceBadge.textColor = 0x5B9ECF;
        _threadSourceBadge.fontSize = 11;
        _chatToolbar.addChild(_threadSourceBadge);

        // Flexible spacer
        auto spacer = new Widget("TOOLBAR_SPACER");
        spacer.layoutWidth = FILL_PARENT;
        spacer.layoutWeight = 1;
        _chatToolbar.addChild(spacer);

        // New Thread button
        auto newThreadBtn = new Button("NEW_THREAD_BTN", "+ New Thread");
        newThreadBtn.fontSize = 10;
        newThreadBtn.tooltipText = "Create a new conversation thread";
        newThreadBtn.click = delegate(Widget source) {
            createNewThread("New Conversation");
            return true;
        };
        _chatToolbar.addChild(newThreadBtn);

        // Context pane toggle
        auto ctxToggleBtn = new Button("CTX_TOGGLE_BTN", "Context ▸");
        ctxToggleBtn.fontSize = 10;
        ctxToggleBtn.tooltipText = "Show/hide the context and files panel";
        ctxToggleBtn.click = delegate(Widget source) {
            _contextPaneVisible = !_contextPaneVisible;
            if (_rightPane) {
                _rightPane.visibility = _contextPaneVisible ? Visibility.Visible : Visibility.Gone;
                _leftPane.layoutWeight = _contextPaneVisible ? 65 : 100;
            }
            auto btn = cast(Button)source;
            if (btn) btn.text = _contextPaneVisible ? "Context ◂" : "Context ▸";
            requestLayout();
            return true;
        };
        _chatToolbar.addChild(ctxToggleBtn);

        // Bulk selection controls
        auto bulkSelectBtn = new Button("BULK_SELECT_BTN", "☐ Select");
        bulkSelectBtn.fontSize = 10;
        bulkSelectBtn.tooltipText = "Toggle bulk selection mode";
        bulkSelectBtn.click = delegate(Widget source) {
            toggleBulkSelectionMode();
            return true;
        };
        _chatToolbar.addChild(bulkSelectBtn);
        
        auto copySelectedBtn = new Button("COPY_SELECTED_BTN", "📋 Copy Selected");
        copySelectedBtn.fontSize = 10;
        copySelectedBtn.tooltipText = "Copy selected messages and blocks";
        copySelectedBtn.enabled = false;
        copySelectedBtn.click = delegate(Widget source) {
            copySelectedContent();
            return true;
        };
        _chatToolbar.addChild(copySelectedBtn);
        
        auto exportSelectedBtn = new Button("EXPORT_SELECTED_BTN", "💾 Export");
        exportSelectedBtn.fontSize = 10;
        exportSelectedBtn.tooltipText = "Export selected content to file";
        exportSelectedBtn.enabled = false;
        exportSelectedBtn.click = delegate(Widget source) {
            exportSelectedContent();
            return true;
        };
        _chatToolbar.addChild(exportSelectedBtn);
        
        // Flexible spacer
        auto spacer2 = new Widget("TOOLBAR_SPACER2");
        spacer2.layoutWidth = FILL_PARENT;
        spacer2.layoutWeight = 1;
        _chatToolbar.addChild(spacer2);

        // "Backend:" label
        auto backendLabel = new TextWidget("BACKEND_LABEL", "Backend: "d);
        backendLabel.textColor = 0x9B9B9B;
        backendLabel.fontSize = 11;
        _chatToolbar.addChild(backendLabel);

        // Backend selector — populated lazily via populateBackendSelector()
        _backendCombo = new ComboBox("BACKEND_COMBO", ["openai"d, "anthropic"d, "ollama"d]);
        _backendCombo.selectedItemIndex = 0;
        _backendNames = ["openai", "anthropic", "ollama"];
        _selectedBackend = "";   // empty == use AIBackendManager default

        _backendCombo.itemClick = delegate(Widget source, int index) {
            if (index >= 0 && index < cast(int)_backendNames.length) {
                _selectedBackend = _backendNames[index];
                Log.i("ChatWidget: Backend selected: ", _selectedBackend);
            }
            return true;
        };

        _chatToolbar.addChild(_backendCombo);

        // "API Keys..." button — opens IDE Preferences at the AI settings page
        auto apiKeysBtn = new Button("API_KEYS_BTN", "⚙ API Keys");
        apiKeysBtn.fontSize = 10;
        apiKeysBtn.tooltipText = "Configure API keys and models (Preferences → AI)";
        apiKeysBtn.click = delegate(Widget source) {
            if (onOpenSettings)
                onOpenSettings();
            return true;
        };
        _chatToolbar.addChild(apiKeysBtn);

        _leftPane.addChild(_chatToolbar);
    }

    /**
     * Create the continue banner shown below thread tabs for imported threads.
     */
    private void createContinueBanner() {
        _continueBanner = new HorizontalLayout("CONTINUE_BANNER");
        _continueBanner.layoutWidth = FILL_PARENT;
        _continueBanner.layoutHeight = WRAP_CONTENT;
        _continueBanner.padding = Rect(10, 5, 10, 5);
        _continueBanner.backgroundColor = 0x1E2A1E;
        _continueBanner.visibility = Visibility.Gone;

        auto importIcon = new TextWidget("IMPORT_ICON", "📥  "d);
        importIcon.textColor = 0x7EC87E;
        importIcon.fontSize = 11;
        _continueBanner.addChild(importIcon);

        auto importInfo = new TextWidget("IMPORT_INFO", "Imported conversation"d);
        importInfo.textColor = 0xA0A0A0;
        importInfo.fontSize = 11;
        _continueBanner.addChild(importInfo);

        auto bannerSpacer = new Widget("BANNER_SPACER");
        bannerSpacer.layoutWidth = FILL_PARENT;
        bannerSpacer.layoutWeight = 1;
        _continueBanner.addChild(bannerSpacer);

        _continueBtn = new Button("CONTINUE_BTN", "▶  Continue"d);
        _continueBtn.click = delegate(Widget source) {
            continueImportedThread();
            return true;
        };
        _continueBanner.addChild(_continueBtn);

        _leftPane.addChild(_continueBanner);
    }

    /**
     * Populate the backend selector from the live backend manager.
     * Call this after the AI backend manager is fully initialised.
     */
    void populateBackendSelector() {
        if (!_backendCombo || !_aiBackend) return;

        // Always list all registered backends so the user can select one
        // regardless of whether an API key has been configured yet.
        // (isAvailable() performs a live network check which would block and
        //  return false before keys are entered.)
        _backendNames = ["openai", "anthropic", "ollama"];

        dstring[] labels = ["OpenAI"d, "Anthropic"d, "Ollama (local)"d];
        _backendCombo.items = labels;

        // Pre-select the current default
        string def = _aiBackend.defaultBackend;
        foreach (i, name; _backendNames) {
            if (name == def) {
                _backendCombo.selectedItemIndex = cast(int)i;
                break;
            }
        }
        // _selectedBackend stays "" so AIBackendManager default is used
        // until the user explicitly picks something
    }

    /**
     * Update the view bar and continue banner to reflect the current thread.
     */
    private void updateThreadBar() {
        if (_currentThreadId.empty || _currentThreadId !in _threads) return;

        auto thread = _threads[_currentThreadId];
        bool isImported = (thread.source == "imported_chatgpt");

        // Update source badge
        if (_threadSourceBadge) {
            if (isImported) {
                _threadSourceBadge.text = "📥  ChatGPT"d;
                _threadSourceBadge.textColor = 0xE8A44A;
            } else {
                _threadSourceBadge.text = "●  local"d;
                _threadSourceBadge.textColor = 0x5B9ECF;
            }
        }

        // Show/hide continue banner and update message count
        if (_continueBanner) {
            _continueBanner.visibility = isImported ? Visibility.Visible : Visibility.Gone;

            if (isImported) {
                auto infoWidget = cast(TextWidget)_continueBanner.childById("IMPORT_INFO");
                if (infoWidget) {
                    infoWidget.text = format("Imported from ChatGPT · %d messages",
                                            thread.messages.length).to!dstring;
                }
            }
        }
    }

    /**
     * Begin continuing an imported thread.
     * The imported messages are already in the thread's message list so the
     * AI will see the full history as context.  All we need to do is focus
     * the input box and hide the banner.
     */
    private void continueImportedThread() {
        if (_inputBox)
            _inputBox.setFocus();

        // Dismiss the banner — user has acknowledged they want to continue
        if (_continueBanner)
            _continueBanner.visibility = Visibility.Gone;

        Log.i("ChatWidget: Continuing imported thread '",
              _currentThreadId, "' with backend: ",
              _selectedBackend.empty ? "(default)" : _selectedBackend);
    }

    /**
     * Toggle bulk selection mode on/off
     */
    private void toggleBulkSelectionMode() {
        _bulkSelectionMode = !_bulkSelectionMode;
        
        auto selectBtn = cast(Button)_chatToolbar.childById("BULK_SELECT_BTN");
        if (selectBtn) {
            selectBtn.text = _bulkSelectionMode ? "☑ Selected" : "☐ Select";
            selectBtn.backgroundColor = _bulkSelectionMode ? 0x2D5A2D : 0x3A3A3A;
        }
        
        // Update button states
        updateBulkActionButtons();
        
        // Refresh message widgets to show/hide selection checkboxes
        refreshMessageWidgets();
        
        Log.i("ChatWidget: Bulk selection mode ", _bulkSelectionMode ? "enabled" : "disabled");
    }

    /**
     * Update the enabled state of bulk action buttons
     */
    private void updateBulkActionButtons() {
        bool hasSelection = _selectedMessageIds.length > 0 || _selectedBlockIds.length > 0;
        
        auto copyBtn = cast(Button)_chatToolbar.childById("COPY_SELECTED_BTN");
        if (copyBtn) copyBtn.enabled = hasSelection;
        
        auto exportBtn = cast(Button)_chatToolbar.childById("EXPORT_SELECTED_BTN");
        if (exportBtn) exportBtn.enabled = hasSelection;
    }

    /**
     * Toggle selection of a message
     */
    private void toggleMessageSelection(string messageId) {
        if (!_bulkSelectionMode) return;
        
        auto index = _selectedMessageIds.countUntil!(a => a == messageId);
        if (index < _selectedMessageIds.length) {
            _selectedMessageIds = _selectedMessageIds[0..index] ~ _selectedMessageIds[index+1..$];
        } else {
            _selectedMessageIds ~= messageId;
        }
        
        updateBulkActionButtons();
        updateMessageSelectionUI(messageId);
    }

    /**
     * Toggle selection of a block
     */
    private void toggleBlockSelection(string blockId, string messageId) {
        if (!_bulkSelectionMode) return;
        
        if (blockId in _selectedBlockIds) {
            _selectedBlockIds.remove(blockId);
        } else {
            _selectedBlockIds[blockId] = messageId;
        }
        
        updateBulkActionButtons();
        updateBlockSelectionUI(blockId);
    }

    /**
     * Update UI for message selection
     */
    private void updateMessageSelectionUI(string messageId) {
        auto messageWidget = _chatContainer.childById("MSG_" ~ messageId);
        if (messageWidget) {
            bool isSelected = _selectedMessageIds.canFind(messageId);
            messageWidget.backgroundColor = isSelected ? 0x2D4A2D : 0x1E1E1E;
            
            // Update checkbox if present
            auto checkbox = cast(Button)messageWidget.childById("MSG_CHECKBOX_" ~ messageId);
            if (checkbox) {
                checkbox.text = isSelected ? "☑" : "☐";
            }
        }
    }

    /**
     * Update UI for block selection
     */
    private void updateBlockSelectionUI(string blockId) {
        auto blockWidget = _chatContainer.childById(blockId ~ "_LAYOUT");
        if (blockWidget) {
            bool isSelected = (blockId in _selectedBlockIds) !is null;
            blockWidget.backgroundColor = isSelected ? 0x2D4A2D : 0x1E1E1E;
            
            // Update checkbox if present
            auto checkbox = cast(Button)blockWidget.childById("BLOCK_CHECKBOX_" ~ blockId);
            if (checkbox) {
                checkbox.text = isSelected ? "☑" : "☐";
            }
        }
    }

    /**
     * Copy selected content to clipboard
     */
    private void copySelectedContent() {
        string content;
        
        // Add selected messages
        foreach (messageId; _selectedMessageIds) {
            auto found = _threads[_currentThreadId].messages.find!(m => m.id == messageId);
            if (!found.empty) {
                auto message = found[0];
                content ~= format("[%s] %s:\n%s\n\n", message.role, message.timestamp.toString(), message.content);
            }
        }
        
        // Add selected blocks
        foreach (blockId, messageId; _selectedBlockIds) {
            auto blockWidget = _chatContainer.childById(blockId);
            if (auto editBox = cast(MessageEditBox)blockWidget) {
                content ~= format("[Block from %s]:\n%s\n\n", messageId, editBox.text.to!string);
            }
        }
        
        if (!content.empty) {
            platform.setClipboardText(content.to!dstring);
            Log.i("ChatWidget: Copied selected content to clipboard");
        }
    }

    /**
     * Export selected content to file
     */
    private void exportSelectedContent() {
        if (_selectedMessageIds.length == 0 && _selectedBlockIds.length == 0) {
            Log.w("ChatWidget: No content selected for export");
            return;
        }

        string content = generateExportContent();
        
        if (content.empty) {
            Log.w("ChatWidget: No content to export");
            return;
        }

        // Generate filename with timestamp
        auto now = Clock.currTime();
        string timestamp = format("%04d%02d%02d_%02d%02d%02d", 
            now.year, now.month, now.day, now.hour, now.minute, now.second);
        string filename = format("dnives_export_%s.md", timestamp);

        // Show save dialog or use default location
        string exportPath = getExportPath(filename);
        
        try {
            std.file.write(exportPath, content);
            Log.i("ChatWidget: Exported content to ", exportPath);
            
            // Show success notification to user
            showExportSuccess(exportPath);
        } catch (Exception e) {
            Log.e("ChatWidget: Failed to export content: ", e.msg);
            showExportError(e.msg);
        }
    }

    /**
     * Generate formatted export content
     */
    private string generateExportContent() {
        string content;
        
        // Add header
        content ~= "# Dnives Chat Export\n\n";
        content ~= format("**Exported:** %s\n", Clock.currTime().toString());
        content ~= format("**Thread:** %s\n\n", _currentThreadId);
        
        // Add selected messages
        if (_selectedMessageIds.length > 0) {
            content ~= "## Selected Messages\n\n";
            
            foreach (messageId; _selectedMessageIds) {
                if (_currentThreadId in _threads) {
                    auto thread = _threads[_currentThreadId];
                    foreach (message; thread.messages) {
                        if (message.id == messageId) {
                            content ~= format("### %s - %s\n\n", 
                                message.role, message.timestamp.toString());
                            content ~= message.content ~ "\n\n";
                            content ~= "---\n\n";
                            break;
                        }
                    }
                }
            }
        }
        
        // Add selected blocks
        if (_selectedBlockIds.length > 0) {
            content ~= "## Selected Blocks\n\n";
            
            foreach (blockId, messageId; _selectedBlockIds) {
                content ~= format("### Block from %s\n\n", messageId);
                
                auto blockWidget = _chatContainer.childById(blockId);
                if (auto editBox = cast(MessageEditBox)blockWidget) {
                    content ~= editBox.getEditedText() ~ "\n\n";
                    content ~= "---\n\n";
                }
            }
        }
        
        return content;
    }

    /**
     * Get export path (simplified - in real implementation, show file dialog)
     */
    private string getExportPath(string filename) {
        // For now, use user's home directory
        // In real implementation, you'd show a file save dialog
        string homeDir = std.path.expandTilde("~");
        return std.path.buildPath(homeDir, "Downloads", filename);
    }

    /**
     * Show export success notification
     */
    private void showExportSuccess(string path) {
        // In real implementation, show a toast or notification
        Log.i("ChatWidget: Export successful: ", path);
    }

    /**
     * Show export error notification
     */
    private void showExportError(string error) {
        // In real implementation, show an error dialog
        Log.e("ChatWidget: Export failed: ", error);
    }

    /**
     * Refresh all message widgets to update selection UI
     */
    private void refreshMessageWidgets() {
        if (_currentThreadId.empty || _currentThreadId !in _threads) return;
        
        auto thread = _threads[_currentThreadId];
        foreach (message; thread.messages) {
            updateMessageSelectionUI(message.id);
            
            // Update block selections within this message
            auto contentLayout = cast(VerticalLayout)_chatContainer.childById("CONTENT_LAYOUT_" ~ message.id);
            if (contentLayout) {
                for (int i = 0; i < contentLayout.childCount; i++) {
                    if (auto blockLayout = cast(VerticalLayout)contentLayout.child(i)) {
                        string blockId = blockLayout.id.replace("_LAYOUT", "");
                        updateBlockSelectionUI(blockId);
                    }
                }
            }
        }
    }

    /**
     * Clear all selections
     */
    private void clearSelections() {
        _selectedMessageIds = null;
        _selectedBlockIds = null;
        updateBulkActionButtons();
        refreshMessageWidgets();
    }

    /**
     * Start editing a block with validation
     */
    private void startBlockEditing(string blockId, string messageId) {
        // Validate inputs
        if (blockId.empty || messageId.empty) {
            Log.e("ChatWidget: Cannot start editing - invalid block or message ID");
            return;
        }

        // Check if message exists
        if (_currentThreadId.empty || _currentThreadId !in _threads) {
            Log.e("ChatWidget: Cannot start editing - no active thread");
            return;
        }

        auto thread = _threads[_currentThreadId];
        ChatMessage targetMessage;
        bool messageExists = false;
        
        foreach (msg; thread.messages) {
            if (msg.id == messageId) {
                targetMessage = msg;
                messageExists = true;
                break;
            }
        }

        if (!messageExists) {
            Log.e("ChatWidget: Cannot start editing - message not found: ", messageId);
            return;
        }

        // Find the MessageEditBox and start editing
        auto contentBox = cast(MessageEditBox)_chatContainer.childById(blockId);
        if (!contentBox) {
            Log.e("ChatWidget: Cannot start editing - block widget not found: ", blockId);
            return;
        }

        if (contentBox.isEditing()) {
            Log.w("ChatWidget: Block already being edited: ", blockId);
            return;
        }

        contentBox.startEditing(blockId, messageId);
        
        // Update UI to show save button and hide edit button
        auto header = _chatContainer.childById(blockId ~ "_HEADER");
        if (header) {
            auto editBtn = header.childById(blockId ~ "_EDIT");
            auto saveBtn = header.childById(blockId ~ "_SAVE");
            
            if (editBtn) editBtn.visibility = Visibility.Gone;
            if (saveBtn) saveBtn.visibility = Visibility.Visible;
        }

        Log.i("ChatWidget: Started editing block ", blockId, " in message ", messageId);
    }

    /**
     * Save block editing with validation and context update
     */
    private void saveBlockEditing(string blockId) {
        if (blockId.empty) {
            Log.e("ChatWidget: Cannot save editing - invalid block ID");
            return;
        }

        auto contentBox = cast(MessageEditBox)_chatContainer.childById(blockId);
        if (!contentBox || !contentBox.isEditing()) {
            Log.e("ChatWidget: Cannot save - block not being edited: ", blockId);
            return;
        }

        string newText = contentBox.getEditedText();
        string originalText = contentBox.getOriginalText();

        // Validate content changes
        if (newText == originalText) {
            Log.i("ChatWidget: No changes detected for block ", blockId);
            contentBox.cancelEditing();
        } else {
            // Validate content (basic checks)
            if (!validateBlockContent(newText)) {
                Log.e("ChatWidget: Invalid content for block ", blockId);
                return;
            }

            // Save the changes
            contentBox.saveEditing();
            
            // Update the underlying message content
            updateMessageContent(blockId, newText);
            
            // Update context manager about the change
            // Note: ContextManager may not have updateConversationContext method
            // This would be implemented based on actual ContextManager API

            Log.i("ChatWidget: Saved changes for block ", blockId);
        }

        // Update UI to hide save button and show edit button
        auto header = _chatContainer.childById(blockId ~ "_HEADER");
        if (header) {
            auto editBtn = header.childById(blockId ~ "_EDIT");
            auto saveBtn = header.childById(blockId ~ "_SAVE");
            
            if (editBtn) editBtn.visibility = Visibility.Visible;
            if (saveBtn) saveBtn.visibility = Visibility.Gone;
        }
    }

    /**
     * Validate block content before saving
     */
    private bool validateBlockContent(string content) {
        // Basic validation
        if (content.length > 50000) { // 50KB limit
            Log.e("ChatWidget: Content too large");
            return false;
        }

        // Check for null bytes
        if (content.canFind('\0')) {
            Log.e("ChatWidget: Content contains null bytes");
            return false;
        }

        // Additional validation can be added here
        // - Syntax checking for code blocks
        // - Content type validation
        // - Security checks

        return true;
    }

    /**
     * Update message content when a block is edited
     */
    private void updateMessageContent(string blockId, string newContent) {
        if (_currentThreadId.empty || _currentThreadId !in _threads) return;

        auto thread = _threads[_currentThreadId];
        string messageId = blockId.split("_")[1];
        
        foreach (ref message; thread.messages) {
            if (message.id == messageId) {
                // Find and replace the block in the message content
                // This is a simplified approach - in practice, you'd want better block tracking
                string oldContent = message.content;
                
                // Try to identify the block boundaries and replace
                // This is complex - for now, we'll append a note about the edit
                message.content ~= "\n\n[Edited block: " ~ blockId ~ "]\n" ~ newContent;
                
                Log.i("ChatWidget: Updated content for message ", messageId);
                break;
            }
        }
    }

    /**
     * Create the context interface (right pane)
     */
    private void createContextInterface() {
        // Context tabs
        _contextTabs = new TabWidget("CONTEXT_TABS");
        _contextTabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // Files tab
        auto filesWidget = new VerticalLayout("filesTab");
        auto filesTab = _contextTabs.addTab(filesWidget, "Files"d);
        createFilesTab(filesWidget);

        // Symbols tab
        auto symbolsWidget = new VerticalLayout("symbolsTab");
        auto symbolsTab = _contextTabs.addTab(symbolsWidget, "Symbols"d);
        createSymbolsTab(symbolsWidget);

        // Context tab
        auto contextWidget = new VerticalLayout("contextTab");
        auto contextTab = _contextTabs.addTab(contextWidget, "Context"d);
        createContextTab(contextWidget);

        _rightPane.addChild(_contextTabs);
    }

    /**
     * Create the files tab
     */
    private void createFilesTab(Widget parent) {
        auto filesLayout = new VerticalLayout("FILES_LAYOUT");
        filesLayout.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // File tree
        _fileTree = new TreeWidget("FILE_TREE");
        _fileTree.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        populateFileTree();

        filesLayout.addChild(_fileTree);
        parent.addChild(filesLayout);
    }

    /**
     * Create the symbols tab
     */
    private void createSymbolsTab(Widget parent) {
        auto symbolsLayout = new VerticalLayout("SYMBOLS_LAYOUT");
        symbolsLayout.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // Symbol search - single line EditLine for search
        _symbolSearch = new EditLine("SYMBOL_SEARCH");
        _symbolSearch.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _symbolSearch.text = "Search symbols..."d;
        symbolsLayout.addChild(_symbolSearch);

        // Context files list
        _contextFiles = new ListWidget("CONTEXT_FILES");
        _contextFiles.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        symbolsLayout.addChild(_contextFiles);

        parent.addChild(symbolsLayout);
    }

    /**
     * Create the context tab
     */
    private void createContextTab(Widget parent) {
        auto contextLayout = new VerticalLayout("CONTEXT_LAYOUT");
        contextLayout.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // Context preview
        _contextPreview = new EditBox("CONTEXT_PREVIEW");
        _contextPreview.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _contextPreview.readOnly = true;
        _contextPreview.text = "Context will appear here...";
        contextLayout.addChild(_contextPreview);

        parent.addChild(contextLayout);
    }

    /**
     * Setup event handlers
     */
    private void setupEventHandlers() {
        // Button events
        _sendButton.click = delegate(Widget source) {
            sendMessage();
            return true;
        };

        _stopButton.click = delegate(Widget source) {
            stopGeneration();
            return true;
        };

        _attachButton.click = delegate(Widget source) {
            showAttachDialog();
            return true;
        };

        // Input box Enter-to-send, Shift+Enter for newline
        _inputBox.keyEvent = delegate(Widget source, KeyEvent event) {
            if (event.action == KeyAction.KeyDown && event.keyCode == KeyCode.RETURN) {
                // Check if Shift is pressed for newline, otherwise send
                if (!(event.flags & KeyFlag.Shift)) {
                    sendMessage();
                    return true;  // Handled
                }
                // Let Shift+Enter pass through for newline
            }
            return false;  // Not handled, let default processing
        };

        // Input box text change to enable/disable send button
        _inputBox.contentChange = delegate(EditableContent source) {
            bool hasText = !_inputBox.text.strip().empty;
            _sendButton.enabled = hasText && !_isStreaming;
        };

        // Set up keyboard shortcuts for bulk operations
        setupKeyboardShortcuts();

        // File tree events
        _fileTree.selectionChange = delegate(TreeItems source, TreeItem selectedItem, bool activated) {
            if (activated && selectedItem) {
                string filePath = selectedItem.id;
                if (!filePath.empty && filePath != "root") {
                    addFileReference(filePath);
                }
            }
        };

        // Context files list - click to remove
        _contextFiles.itemClick = delegate(Widget source, int itemIndex) {
            if (itemIndex >= 0 && itemIndex < _fileReferences.length) {
                // Get the file path by index
                int currentIndex = 0;
                string filePathToRemove;
                foreach (path, ref_; _fileReferences) {
                    if (currentIndex == itemIndex) {
                        filePathToRemove = path;
                        break;
                    }
                    currentIndex++;
                }

                if (!filePathToRemove.empty) {
                    removeFileReference(filePathToRemove);
                    Log.i("ChatWidget: Removed file from context: ", baseName(filePathToRemove));
                }
            }
            return true;
        };

        // Symbol search
        _symbolSearch.contentChange = delegate(EditableContent source) {
            searchSymbols(_symbolSearch.text.to!string);
        };

        // Thread tab change — guarded to prevent re-entrancy during bulk tab ops
        _threadTabs.tabChanged = delegate(string tabId, string newTabId) {
            if (!_suppressTabChange)
                switchToThread(newTabId);
        };
    }

    /**
     * Setup keyboard shortcuts for bulk operations (placeholder)
     */
    private void setupKeyboardShortcuts() {
        // Keyboard shortcuts will be added later
        // Need to check dlangui API for proper event handling
        Log.i("ChatWidget: Keyboard shortcuts setup placeholder");
    }

    /**
     * Send a message to the AI
     */
    private void sendMessage() {
        string messageText = _inputBox.text.strip().to!string;
        if (messageText.empty || _isStreaming)
            return;

        // Add user message to current thread
        auto userMessage = ChatMessage(AIMessage.Role.User, messageText);
        userMessage.source = "local";
        addMessageToThread(_currentThreadId, userMessage);

        // Clear input
        _inputBox.text = "";
        _sendButton.enabled = false;

        // Start AI response
        startAIResponse(messageText);
    }

    /**
     * Start AI response generation
     */
    private void startAIResponse(string userMessage) {
        if (!_aiBackend || _isStreaming)
            return;

        _isStreaming = true;
        _sendButton.enabled = false;
        _stopButton.enabled = true;
        _stopButton.visibility = Visibility.Visible;

        // Create assistant message for streaming
        auto assistantMessage = ChatMessage(AIMessage.Role.Assistant, "");
        assistantMessage.isStreaming = true;
        assistantMessage.source = "local";
        _streamingMessageId = assistantMessage.id;
        addMessageToThread(_currentThreadId, assistantMessage);

        // Gather context
        string[] contextFiles = _fileReferences.keys;
        string contextString = _contextManager.getCodeContext(contextFiles);

        // Build message history
        AIMessage[] messages;

        // Add system message with context
        if (!contextString.empty) {
            messages ~= AIMessage(AIMessage.Role.System,
                "You are an AI coding assistant. Here is the current code context:\n\n" ~ contextString);
        }

        // Add conversation history
        if (_currentThreadId in _threads) {
            auto thread = _threads[_currentThreadId];
            foreach (msg; thread.messages) {
                if (!msg.isStreaming || !msg.content.empty) {
                    messages ~= AIMessage(msg.role, msg.content);
                }
            }
        }

        // Stream the response — routes to the backend the user selected in
        // the toolbar, or falls back to AIBackendManager's default.
        try {
            _aiBackend.chatStreamWith(_selectedBackend, messages, &onStreamChunk);
        } catch (Exception e) {
            Log.e("ChatWidget: AI request failed: ", e.msg);
            finishStreaming("Sorry, there was an error processing your request: " ~ e.msg);
        }
    }

    /**
     * Handle streaming chunks
     */
    private void onStreamChunk(AIStreamChunk chunk) {
        if (!_isStreaming || _streamingMessageId.empty)
            return;

        // Update the streaming message
        if (_currentThreadId in _threads) {
            auto thread = &_threads[_currentThreadId];
            foreach (ref msg; thread.messages) {
                if (msg.id == _streamingMessageId) {
                    msg.content ~= chunk.content;
                    updateMessageDisplay(msg);
                    break;
                }
            }
        }

        if (chunk.isComplete) {
            finishStreaming();
        }

        // Auto-scroll if enabled
        if (_autoScroll) {
            // Scroll to bottom using vscrollbar
            if (_chatScroll.vscrollbar) {
                _chatScroll.vscrollbar.position = _chatScroll.vscrollbar.maxValue;
            }
        }
    }

    /**
     * Finish streaming response
     */
    private void finishStreaming(string finalContent = null) {
        _isStreaming = false;
        _streamingMessageId = "";
        _sendButton.enabled = !_inputBox.text.empty;
        _stopButton.enabled = false;
        _stopButton.visibility = Visibility.Gone;

        // Update final message if provided
        if (!finalContent.empty && _currentThreadId in _threads) {
            auto thread = &_threads[_currentThreadId];
            if (!thread.messages.empty) {
                thread.messages[$-1].content = finalContent;
                thread.messages[$-1].isStreaming = false;
                updateMessageDisplay(thread.messages[$-1]);
            }
        }

        // Mark streaming as complete
        if (_currentThreadId in _threads) {
            auto thread = &_threads[_currentThreadId];
            foreach (ref msg; thread.messages) {
                if (msg.isStreaming && msg.id == _streamingMessageId) {
                    msg.isStreaming = false;
                    break;
                }
            }
        }
    }

    /**
     * Stop AI generation
     */
    private void stopGeneration() {
        if (_isStreaming) {
            // TODO: Implement actual cancellation
            finishStreaming("[Generation stopped by user]");
        }
    }

    /**
     * Create a new thread
     */
    string createNewThread(string title) {
        auto workspace = _core.getCurrentWorkspace();
        string workspacePath = workspace ? workspace.path : "";

        auto thread = ChatThread(title, workspacePath);
        _threads[thread.id] = thread;

        // Suppress tabChanged callbacks while we mutate tab state to avoid
        // re-entrant refreshChatDisplay / updateThreadBar calls mid-operation.
        _suppressTabChange = true;
        scope(exit) _suppressTabChange = false;

        auto tabWidget = new VerticalLayout(thread.id);
        _threadTabs.addTab(tabWidget, title.to!dstring);

        // Create context for this thread
        _contextManager.createConversation(workspacePath, _fileReferences.keys);

        // Commit the switch — only one call path, no re-entrancy risk here.
        _currentThreadId = thread.id;
        _threadTabs.selectTab(thread.id);

        // Restore handler then do the one authoritative UI update.
        _suppressTabChange = false;
        refreshChatDisplay();
        updateThreadBar();

        return thread.id;
    }

    /**
     * Switch to a thread
     */
    private void switchToThread(string threadId) {
        if (threadId == _currentThreadId)
            return;

        _currentThreadId = threadId;
        if (_autoScroll) {
            // Scroll to bottom using vscrollbar
            if (_chatScroll.vscrollbar) {
                _chatScroll.vscrollbar.position = _chatScroll.vscrollbar.maxValue;
            }
        }
        refreshChatDisplay();
        updateThreadBar();
    }

    /**
     * Add message to thread
     */
    private void addMessageToThread(string threadId, ChatMessage message) {
        if (threadId !in _threads)
            return;

        auto thread = &_threads[threadId];
        thread.messages ~= message;
        thread.lastActivity = cast(DateTime)Clock.currTime();

        if (threadId == _currentThreadId) {
            addMessageToDisplay(message);
        }
    }

    /**
     * Add message to display
     */
    private void addMessageToDisplay(ChatMessage message) {
        auto messageWidget = createMessageWidget(message);
        _chatContainer.addChild(messageWidget);

        if (_autoScroll) {
            // scrollToBottom not available in dlangui 0.10.8
            // _chatScroll.scrollPosition = _chatScroll.fullContentHeight;
        }
    }

    /**
     * Create widget for a message
     */
    private Widget createMessageWidget(ChatMessage message) {
        auto messageLayout = new VerticalLayout("MSG_" ~ message.id);
        messageLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        messageLayout.margins = Rect(5, 10, 5, 10);

        // Message header
        auto headerLayout = new HorizontalLayout("MSG_HEADER_" ~ message.id);
        headerLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);

        string roleText;
        uint roleColor;
        switch (message.role) {
            case AIMessage.Role.User:
                roleText = "You";
                roleColor = 0x4A90E2;
                break;
            case AIMessage.Role.Assistant:
                roleText = "Assistant";
                roleColor = 0x7ED321;
                break;
            case AIMessage.Role.System:
                roleText = "System";
                roleColor = 0xF5A623;
                break;
            default:
                roleText = "Unknown";
                roleColor = 0x9B9B9B;
                break;
        }

        // Selection checkbox (shown in bulk selection mode)
        if (_bulkSelectionMode) {
            auto checkbox = new Button("MSG_CHECKBOX_" ~ message.id, "☐");
            checkbox.fontSize = 12;
            checkbox.minWidth(20);
            checkbox.backgroundColor = 0x3A3A3A;
            checkbox.click = delegate(Widget source) {
                toggleMessageSelection(message.id);
                return true;
            };
            headerLayout.addChild(checkbox);
        }

        auto roleLabel = new TextWidget("ROLE_" ~ message.id, roleText);
        roleLabel.textColor = roleColor;
        roleLabel.fontWeight = 600;
        headerLayout.addChild(roleLabel);

        auto timeLabel = new TextWidget("TIME_" ~ message.id,
            message.timestamp.toString()[11..19]); // HH:MM:SS
        timeLabel.textColor = 0x9B9B9B;
        timeLabel.fontSize = 10;
        timeLabel.alignment = Align.Right;
        headerLayout.addChild(timeLabel);

        messageLayout.addChild(headerLayout);

        // Message content
        auto contentWidget = createMessageContentWidget(message);
        messageLayout.addChild(contentWidget);

        // Message actions
        if (!message.content.empty) {
            auto actionsLayout = new HorizontalLayout("MSG_ACTIONS_" ~ message.id);
            actionsLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
            actionsLayout.padding(Rect(0, 5, 0, 0));

            auto copyButton = new Button("COPY_ALL_" ~ message.id, "Copy All");
            copyButton.fontSize = 10;
            copyButton.click = delegate(Widget source) {
                platform.setClipboardText(message.content.to!dstring);
                return true;
            };
            actionsLayout.addChild(copyButton);

            auto copyBlockedButton = new Button("COPY_BLOCKED_" ~ message.id, "Copy Blocked");
            copyBlockedButton.fontSize = 10;
            copyBlockedButton.click = delegate(Widget source) {
                auto contentLayout = _chatContainer.childById("CONTENT_LAYOUT_" ~ message.id);
                if (auto container = cast(VerticalLayout)contentLayout) {
                    string allBlockedText;
                    // Iterate over all block layouts
                    for (int i = 0; i < container.childCount; i++) {
                        if (auto blockLayout = cast(VerticalLayout)container.child(i)) {
                            // The MessageEditBox is the second child (index 1) in our blockLayout
                            // (index 0 is the header with Copy button)
                            if (blockLayout.childCount > 1) {
                                if (auto editBox = cast(MessageEditBox)blockLayout.child(1)) {
                                    allBlockedText ~= editBox.getBlockedText();
                                }
                            }
                        }
                    }
                    if (!allBlockedText.empty) {
                        platform.setClipboardText(allBlockedText.to!dstring);
                    }
                }
                return true;
            };
            actionsLayout.addChild(copyBlockedButton);

            if (message.role == AIMessage.Role.Assistant && hasCodeBlocks(message.content)) {
                auto applyButton = new Button("APPLY_" ~ message.id, "Apply Code");
                applyButton.fontSize = 10;
                applyButton.click = delegate(Widget source) {
                    applyCodeFromMessage(message);
                    return true;
                };
                actionsLayout.addChild(applyButton);
            }

            // Regenerate button for AI messages
            if (message.role == AIMessage.Role.Assistant) {
                auto regenerateBtn = new Button("REGEN_" ~ message.id, "🔄 Regenerate");
                regenerateBtn.fontSize = 10;
                regenerateBtn.click = delegate(Widget source) {
                    regenerateMessage(message.id);
                    return true;
                };
                actionsLayout.addChild(regenerateBtn);
            }

            // Delete button for all messages
            auto deleteBtn = new Button("DELETE_" ~ message.id, "🗑️ Delete");
            deleteBtn.fontSize = 10;
            deleteBtn.click = delegate(Widget source) {
                deleteMessage(message.id);
                return true;
            };
            actionsLayout.addChild(deleteBtn);

            messageLayout.addChild(actionsLayout);
        }

        // Source/provenance badge
        auto sourceLayout = new HorizontalLayout("MSG_SOURCE_" ~ message.id);
        sourceLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);

        string sourceText = message.source.empty ? "local" : message.source;
        auto sourceBadge = new TextWidget("MSG_SOURCE_LABEL_" ~ message.id, ("Source: " ~ sourceText).to!dstring);
        sourceBadge.fontSize = 10;
        sourceBadge.textColor = 0x9B9B9B;
        sourceLayout.addChild(sourceBadge);

        if (!message.externalId.empty) {
            auto extId = new TextWidget("MSG_EXTERNAL_ID_" ~ message.id, (" · ID: " ~ message.externalId).to!dstring);
            extId.fontSize = 10;
            extId.textColor = 0x6F6F6F;
            sourceLayout.addChild(extId);
        }

        messageLayout.addChild(sourceLayout);

        return messageLayout;
    }

    /**
     * Specialized EditBox for chat messages that supports line blocking
     */
    class MessageEditBox : EditBox {
        private bool[] _blockedLines;
        private uint _blockedLineColor = 0x40555555; // Subtle highlight for blocked lines
        private bool _isEditing = false;
        private string _originalText;
        private string _blockId;
        private string _messageId;

        this(string ID) {
            super(ID);
            showLineNumbers = true;
            readOnly = true;
        }

        void toggleLineBlock(int lineIndex) {
            if (lineIndex < 0) return;
            if (lineIndex >= _blockedLines.length) {
                _blockedLines.length = lineIndex + 1;
            }
            _blockedLines[lineIndex] = !_blockedLines[lineIndex];
            invalidate();
        }

        bool isLineBlocked(int lineIndex) const {
            if (lineIndex >= 0 && lineIndex < _blockedLines.length)
                return _blockedLines[lineIndex];
            return false;
        }

        string getBlockedText() const {
            string result;
            auto lines = text.toUTF8().split('\n');
            foreach(i, line; lines) {
                if (isLineBlocked(cast(int)i)) {
                    result ~= line ~ "\n";
                }
            }
            return result;
        }

        override protected void drawLineBackground(DrawBuf buf, int lineIndex, Rect lineRect, Rect visibleRect) {
            if (isLineBlocked(lineIndex)) {
                buf.fillRect(lineRect, _blockedLineColor);
            }
            super.drawLineBackground(buf, lineIndex, lineRect, visibleRect);
        }

        override protected bool handleLeftPaneIconsMouseClick(MouseEvent event, Rect rc, int line) {
            if (event.button == MouseButton.Left) {
                toggleLineBlock(line);
                return true;
            }
            return super.handleLeftPaneIconsMouseClick(event, rc, line);
        }

        void startEditing(string blockId, string messageId) {
            if (_isEditing) return;
            
            _isEditing = true;
            _originalText = text.to!string;
            _blockId = blockId;
            _messageId = messageId;
            readOnly = false;
            backgroundColor = 0x1A1A1A; // Darker background for editing
            setFocus();
            
            Log.i("MessageEditBox: Started editing block ", blockId);
        }

        void saveEditing() {
            if (!_isEditing) return;
            
            _isEditing = false;
            readOnly = true;
            
            // Restore background based on content type
            if (_blockId.canFind("CODE")) {
                backgroundColor = 0x111111;
            } else {
                backgroundColor = 0x1E2A38; // Default for assistant content
            }
            
            // Notify parent about the change
            auto blockWidget = parent;
            if (blockWidget) {
                auto header = blockWidget.childById(_blockId ~ "_HEADER");
                if (header) {
                    auto saveBtn = header.childById(_blockId ~ "_SAVE");
                    if (saveBtn) saveBtn.visibility = Visibility.Gone;
                    
                    auto editBtn = header.childById(_blockId ~ "_EDIT");
                    if (editBtn) editBtn.visibility = Visibility.Visible;
                }
            }
            
            Log.i("MessageEditBox: Saved editing for block ", _blockId);
        }

        void cancelEditing() {
            if (!_isEditing) return;
            
            text = _originalText.to!dstring;
            _isEditing = false;
            readOnly = true;
            
            // Restore background based on content type
            if (_blockId.canFind("CODE")) {
                backgroundColor = 0x111111;
            } else {
                backgroundColor = 0x1E2A38; // Default for assistant content
            }
            
            Log.i("MessageEditBox: Cancelled editing for block ", _blockId);
        }

        bool isEditing() const { return _isEditing; }
        string getEditedText() const { return text.to!string; }
        string getOriginalText() const { return _originalText; }
    }

    /**
     * Create content widget for a message
     */
    private Widget createMessageContentWidget(ChatMessage message) {
        auto contentLayout = new VerticalLayout("CONTENT_LAYOUT_" ~ message.id);
        contentLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);

        renderMessageBlocks(contentLayout, message.content, message.id, message.role);

        return contentLayout;
    }

    /**
     * Render message content as a series of blocks
     */
    private void renderMessageBlocks(VerticalLayout container, string content, string messageId, AIMessage.Role role) {
        container.removeAllChildren();

        auto lines = content.split('\n');
        string currentBlock;
        bool inCodeBlock = false;
        int blockCount = 0;

        void flushBlock() {
            if (currentBlock.empty && !inCodeBlock) return;
            
            string blockId = format("BLOCK_%s_%d", messageId, blockCount++);
            auto blockWidget = createBlockWidget(currentBlock, blockId, inCodeBlock, role);
            container.addChild(blockWidget);
            currentBlock = "";
        }

        foreach (line; lines) {
            if (line.startsWith("```")) {
                flushBlock();
                inCodeBlock = !inCodeBlock;
                if (!inCodeBlock) {
                    // We just finished a code block, the opening/closing ``` are not part of content
                }
            } else {
                currentBlock ~= line ~ "\n";
            }
        }
        flushBlock();
    }

    /**
     * Create a widget for a single block of message content
     */
    private Widget createBlockWidget(string content, string blockId, bool isCode, AIMessage.Role role) {
        auto blockLayout = new VerticalLayout(blockId ~ "_LAYOUT");
        blockLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        blockLayout.padding(Rect(0, 2, 0, 2));

        auto header = new HorizontalLayout(blockId ~ "_HEADER");
        header.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        header.visibility = _bulkSelectionMode ? Visibility.Visible : Visibility.Gone;

        // Selection checkbox (shown in bulk selection mode)
        if (_bulkSelectionMode) {
            auto checkbox = new Button("BLOCK_CHECKBOX_" ~ blockId, "☐");
            checkbox.fontSize = 10;
            checkbox.minWidth(16);
            checkbox.backgroundColor = 0x3A3A3A;
            checkbox.click = delegate(Widget source) {
                // Extract messageId from blockId
                string messageId = blockId.split("_")[1];
                toggleBlockSelection(blockId, messageId);
                return true;
            };
            header.addChild(checkbox);
        }

        auto spacer = new Widget();
        spacer.layoutWidth(FILL_PARENT);
        spacer.layoutWeight = 1;
        header.addChild(spacer);

        auto copyBtn = new Button(blockId ~ "_COPY", "Copy");
        copyBtn.fontSize = 9;
        copyBtn.click = delegate(Widget source) {
            platform.setClipboardText(content.to!dstring);
            return true;
        };
        header.addChild(copyBtn);

        // Edit button (always visible for non-empty content)
        if (!content.empty) {
            auto editBtn = new Button(blockId ~ "_EDIT", "✏️");
            editBtn.fontSize = 9;
            editBtn.tooltipText = "Edit this block";
            editBtn.click = delegate(Widget source) {
                string messageId = blockId.split("_")[1];
                startBlockEditing(blockId, messageId);
                return true;
            };
            header.addChild(editBtn);

            // Save button (hidden by default, shown during editing)
            auto saveBtn = new Button(blockId ~ "_SAVE", "💾");
            saveBtn.fontSize = 9;
            saveBtn.tooltipText = "Save changes";
            saveBtn.visibility = Visibility.Gone;
            saveBtn.click = delegate(Widget source) {
                saveBlockEditing(blockId);
                return true;
            };
            header.addChild(saveBtn);
        }
        blockLayout.addChild(header);

        auto contentBox = new MessageEditBox(blockId);
        contentBox.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        contentBox.text = content.to!dstring;
        contentBox.fontFamily = FontFamily.MonoSpace;
        contentBox.fontSize = 12;
        contentBox.readOnly = true;

        if (isCode) {
            contentBox.backgroundColor = 0x111111;
        } else {
            // Style based on role
            switch (role) {
                case AIMessage.Role.User:
                    contentBox.backgroundColor = 0x2D2D2D;
                    break;
                case AIMessage.Role.Assistant:
                    contentBox.backgroundColor = 0x1E2A38;
                    break;
                case AIMessage.Role.System:
                    contentBox.backgroundColor = 0x2A1E1E;
                    break;
                default:
                    contentBox.backgroundColor = 0x252525;
                    break;
            }
        }

        blockLayout.addChild(contentBox);

        // Show header if there's content or in bulk selection mode
        if (!content.empty || _bulkSelectionMode) {
            header.visibility = Visibility.Visible;
        }

        return blockLayout;
    }

    /**
     * Update message display during streaming
     */
    private void updateMessageDisplay(ChatMessage message) {
        auto container = cast(VerticalLayout)_chatContainer.childById("CONTENT_LAYOUT_" ~ message.id);
        if (container) {
            renderMessageBlocks(container, message.content, message.id, message.role);
        }
    }

    /**
     * Check if message has code blocks
     */
    private bool hasCodeBlocks(string content) {
        return content.canFind("```");
    }

    /**
     * Apply code from a message
     */
    private void applyCodeFromMessage(ChatMessage message) {
        // Extract code blocks and show application dialog
        string[] codeBlocks = extractCodeBlocks(message.content);
        if (!codeBlocks.empty) {
            showCodeApplicationDialog(codeBlocks);
        }
    }

    /**
     * Extract code blocks from content
     */
    private string[] extractCodeBlocks(string content) {
        string[] blocks;

        auto lines = content.split('\n');
        bool inCodeBlock = false;
        string currentBlock;

        foreach (line; lines) {
            if (line.startsWith("```")) {
                if (inCodeBlock) {
                    // End of code block
                    if (!currentBlock.empty) {
                        blocks ~= currentBlock.strip();
                        currentBlock = "";
                    }
                    inCodeBlock = false;
                } else {
                    // Start of code block
                    inCodeBlock = true;
                }
            } else if (inCodeBlock) {
                currentBlock ~= line ~ "\n";
            }
        }

        return blocks;
    }

    /**
     * Show code application dialog
     */
    private void showCodeApplicationDialog(string[] codeBlocks) {
        // Create and show dialog for applying code changes
        // This would integrate with the editor and version control
        Log.i("ChatWidget: Would show code application dialog with ", codeBlocks.length, " blocks");
    }

    /**
     * Populate the file tree
     */
    private void populateFileTree() {
        if (!_fileTree)
            return;

        auto workspace = _core.getCurrentWorkspace();
        if (!workspace || !exists(workspace.path))
            return;

        // Clear existing items
        _fileTree.clearAllItems();

        // Add workspace root
        auto rootItem = _fileTree.items.newChild("root", baseName(workspace.path).to!dstring, null);
        rootItem.expand();

        // Populate recursively
        populateFileTreeRecursive(rootItem, workspace.path, 0, 3); // Max 3 levels deep
    }

    /**
     * Populate file tree recursively
     */
    private void populateFileTreeRecursive(TreeItem parent, string dirPath, int currentDepth, int maxDepth) {
        if (currentDepth >= maxDepth || !exists(dirPath) || !isDir(dirPath))
            return;

        try {
            foreach (DirEntry entry; dirEntries(dirPath, SpanMode.shallow)) {
                if (entry.name.startsWith("."))
                    continue;

                if (entry.isDir) {
                    auto dirItem = parent.newChild(entry.name, baseName(entry.name).to!dstring, null);
                    dirItem.expand();
                    populateFileTreeRecursive(dirItem, entry.name, currentDepth + 1, maxDepth);
                } else if (isSourceFile(entry.name)) {
                    auto fileItem = parent.newChild(entry.name, baseName(entry.name).to!dstring, null);
                }
            }
        } catch (Exception e) {
            Log.w("ChatWidget: Error populating file tree for ", dirPath, ": ", e.msg);
        }
    }

    /**
     * Check if file is a source file
     */
    private bool isSourceFile(string filePath) {
        string ext = extension(filePath).toLower();
        return [".d", ".di", ".js", ".ts", ".py", ".rs", ".c", ".cpp", ".h", ".hpp"].canFind(ext);
    }

    /**
     * Add file reference
     */
    private void addFileReference(string filePath) {
        if (filePath in _fileReferences)
            return;

        auto reference = FileReference(filePath);
        _fileReferences[filePath] = reference;

        // Update context files list
        updateContextFilesList();

        // Update context manager
        if (!_currentThreadId.empty) {
            _contextManager.updateConversationFocus(_currentThreadId, _fileReferences.keys);
        }

        // Update context preview
        updateContextPreview();
    }

    /**
     * Remove file reference
     */
    void removeFileReference(string filePath) {
        _fileReferences.remove(filePath);
        updateContextFilesList();
        updateContextPreview();
    }

    /**
     * Update context files list
     */
    private void updateContextFilesList() {
        if (!_contextFiles)
            return;

        if (_contextFiles.adapter) {
            _contextFiles.adapter.clear();
        } else {
            _contextFiles.ownAdapter = new StringListAdapter();
        }

        foreach (ref_, reference; _fileReferences) {
            auto adapter = cast(StringListAdapter)_contextFiles.adapter;
            if (adapter) {
                adapter.add(reference.displayName);
            }
        }
    }

    /**
     * Update context preview
     */
    private void updateContextPreview() {
        if (!_contextPreview)
            return;

        if (_fileReferences.empty) {
            _contextPreview.text = "No context files selected."d;
            return;
        }

        string contextText = _contextManager.getCodeContext(_fileReferences.keys);
        _contextPreview.text = contextText.to!dstring;
    }

    /**
     * Search symbols
     */
    private void searchSymbols(string query) {
        if (query.empty || !_symbolTracker)
            return;

        auto symbols = _symbolTracker.findSymbols(query);

        // Update context files list with symbol results
        if (_contextFiles) {
            if (_contextFiles.adapter) {
                _contextFiles.adapter.clear();
            }

            foreach (symbol; symbols.take(20)) { // Limit results
                string displayText = symbol.name ~ " (" ~ baseName(symbol.filePath) ~ ")";
                auto adapter = cast(StringListAdapter)_contextFiles.adapter;
                if (adapter) {
                    adapter.add(displayText);
                }
            }
        }
    }

    /**
     * Show attach dialog
     */
    private void showAttachDialog() {
        // Create popup with attachment options
        auto menuItem = new MenuItem(null);
        menuItem.add(new MenuItem(new Action(1, "Attach Current File"d)));
        menuItem.add(new MenuItem(new Action(2, "Attach Symbol..."d)));
        menuItem.add(new MenuItem(new Action(3, "Attach Selection"d)));

        auto menu = new PopupMenu(menuItem);

        menu.menuItemAction = (const Action action) {
            switch (action.id) {
                case 1:
                    attachCurrentFile();
                    return true;
                case 2:
                    showSymbolAttachDialog();
                    return true;
                case 3:
                    attachSelection();
                    return true;
                default:
                    return false;
            }
        };

        // Show popup using window.showPopup()
        auto popup = window.showPopup(menu, _attachButton, PopupAlign.Below);
        popup.flags = PopupFlags.CloseOnClickOutside;
    }

    /**
     * Attach current file from the active editor
     */
    private void attachCurrentFile() {
        if (!_core || !_core.editorManager) {
            Log.w("ChatWidget: Editor manager not available");
            return;
        }

        auto activeEditor = _core.editorManager.getActiveEditor();
        if (!activeEditor) {
            Log.w("ChatWidget: No active editor to attach file from");
            return;
        }

        string filePath = activeEditor.getFilePath();
        if (filePath.empty) {
            Log.w("ChatWidget: Active editor has no file path");
            return;
        }

        // Add file reference to context
        addFileReference(filePath);

        // Add a note to the input box about the attachment
        string currentInput = _inputBox.text.to!string;
        string attachmentNote = format("[Attached: %s]\n", baseName(filePath));
        if (currentInput.empty) {
            _inputBox.text = attachmentNote.to!dstring;
        } else {
            _inputBox.text = (currentInput ~ "\n" ~ attachmentNote).to!dstring;
        }

        Log.i("ChatWidget: Attached current file: ", filePath);
    }

    /**
     * Show symbol attach dialog
     */
    private void showSymbolAttachDialog() {
        // Show dialog to search and select symbols
        Log.i("ChatWidget: Would show symbol attach dialog");
    }

    /**
     * Attach current selection from the active editor
     */
    private void attachSelection() {
        if (!_core || !_core.editorManager) {
            Log.w("ChatWidget: Editor manager not available");
            return;
        }

        auto activeEditor = _core.editorManager.getActiveEditor();
        if (!activeEditor) {
            Log.w("ChatWidget: No active editor to get selection from");
            return;
        }

        // Get selected text via dlangui EditWidgetBase.getSelectedText()
        string selectedText = activeEditor.getSelectedText().to!string;

        if (selectedText.empty) {
            Log.w("ChatWidget: No text selected in active editor");
            // Still attach file even if no selection
            attachCurrentFile();
            return;
        }

        // Add selection to input box
        string currentInput = _inputBox.text.to!string;
        string fileName = baseName(activeEditor.getFilePath());
        string selectionWithContext = format("\n```\n// From %s\n%s\n```\n", fileName, selectedText);

        if (currentInput.empty) {
            _inputBox.text = selectionWithContext.to!dstring;
        } else {
            _inputBox.text = (currentInput ~ selectionWithContext).to!dstring;
        }

        // Also add file reference
        addFileReference(activeEditor.getFilePath());

        Log.i("ChatWidget: Attached selection (", selectedText.length, " chars) from ", fileName);
    }

    /**
     * Refresh chat display
     */
    private void refreshChatDisplay() {
        if (!_chatContainer)
            return;

        // Clear current display
        _chatContainer.removeAllChildren();

        // Add messages from current thread
        if (_currentThreadId in _threads) {
            auto thread = _threads[_currentThreadId];
            foreach (message; thread.messages) {
                addMessageToDisplay(message);
            }
        }
    }

    /**
     * Get current thread
     */
    ChatThread* getCurrentThread() {
        if (_currentThreadId in _threads) {
            return &_threads[_currentThreadId];
        }
        return null;
    }

    /**
     * Set auto-scroll preference
     */
    void setAutoScroll(bool enabled) {
        _autoScroll = enabled;
    }

    /**
     * Set show line numbers preference
     */
    void setShowLineNumbers(bool enabled) {
        _showLineNumbers = enabled;
        // Would update message displays
    }

    /**
     * Export conversation
     */
    void exportConversation(string threadId, string outputPath) {
        if (threadId !in _threads)
            return;

        auto thread = _threads[threadId];
        JSONValue export_ = JSONValue.emptyObject;
        export_["title"] = thread.title;
        export_["created"] = thread.created.toISOExtString();
        export_["source"] = thread.source;
        if (!thread.externalId.empty)
            export_["external_id"] = thread.externalId;
        if (!thread.importPath.empty)
            export_["import_path"] = thread.importPath;
        export_["messages"] = JSONValue.emptyArray;

        foreach (message; thread.messages) {
            JSONValue msgJson = JSONValue.emptyObject;
            msgJson["role"] = message.role.to!string;
            msgJson["content"] = message.content;
            msgJson["timestamp"] = message.timestamp.toISOExtString();
            msgJson["source"] = message.source;
            if (!message.externalId.empty)
                msgJson["external_id"] = message.externalId;
            if (!message.parentMessageId.empty)
                msgJson["parent_message_id"] = message.parentMessageId;
            export_["messages"].array ~= msgJson;
        }

        try {
            std.file.write(outputPath, export_.toPrettyString());
            Log.i("ChatWidget: Exported conversation to ", outputPath);
        } catch (Exception e) {
            Log.e("ChatWidget: Failed to export conversation: ", e.msg);
        }
    }

    /**
     * Import conversation
     *
     * Supports:
     * - Legacy internal export format
     * - ChatGPT export format (single conversation or array)
     */
    void importConversation(string inputPath) {
        // First, try ChatGPT export format using importer
        try {
            auto importer = new ChatGPTImporter();
            auto result = importer.importFromFile(inputPath);

            if (!result.threads.empty) {
                auto workspace = _core.getCurrentWorkspace();
                string workspacePath = workspace ? workspace.path : "";

                // Suppress tabChanged for the whole import batch — avoids
                // re-entrant refreshChatDisplay while we add many tabs at once.
                _suppressTabChange = true;
                scope(exit) _suppressTabChange = false;

                foreach (importedThread; result.threads) {
                    auto thread = ChatThread(importedThread.title, workspacePath);
                    thread.source = "imported_chatgpt";
                    thread.externalId = importedThread.id;
                    thread.importPath = inputPath;
                    thread.created = importedThread.createdAt;
                    thread.lastActivity = importedThread.updatedAt;
                    thread.metadata = importedThread.rawMetadata;

                    foreach (importedMessage; importedThread.messagesLinear) {
                        ChatMessage msg;
                        msg.id = randomUUID().toString();
                        msg.role = importedMessage.role;
                        msg.content = importedMessage.content;
                        msg.timestamp = importedMessage.timestamp;
                        msg.isStreaming = false;
                        msg.source = "imported_chatgpt";
                        msg.externalId = importedMessage.id;
                        msg.parentMessageId = importedMessage.parentId;
                        thread.messages ~= msg;
                    }

                    _threads[thread.id] = thread;

                    // Create a widget for the chat thread content
                    auto threadWidget = new VerticalLayout(thread.id);
                    threadWidget.layoutWidth = FILL_PARENT;
                    threadWidget.layoutHeight = FILL_PARENT;

                    _threadTabs.addTab(threadWidget, thread.title.to!dstring);
                }

                if (!_threads.empty) {
                    // Switch to most recently added imported thread
                    auto last = result.threads[$ - 1];
                    foreach (id, t; _threads) {
                        if (t.externalId == last.id && t.source == "imported_chatgpt") {
                            _currentThreadId = id;
                            // suppressTabChange is still true here from the
                            // scope above — safe to selectTab then do one
                            // authoritative refresh after.
                            _suppressTabChange = false;
                            _threadTabs.selectTab(id);
                            refreshChatDisplay();
                            updateThreadBar();
                            break;
                        }
                    }
                }

                Log.i("ChatWidget: Imported ChatGPT conversations from ", inputPath,
                      " (threads=", to!string(result.summary.importedConversations),
                      ", messages=", to!string(result.summary.totalMessages), ")");

                foreach (warn; result.summary.warnings) {
                    Log.w("ChatWidget Import warning: ", warn);
                }
                return;
            }
        } catch (Exception e) {
            Log.w("ChatWidget: ChatGPT import path failed, trying legacy format: ", e.msg);
        }

        // Fallback to legacy internal export format
        try {
            string content = readText(inputPath);
            JSONValue import_ = parseJSON(content);

            string title = import_["title"].str;
            auto workspace = _core.getCurrentWorkspace();
            string workspacePath = workspace ? workspace.path : "";
            auto thread = ChatThread(title, workspacePath);

            foreach (msgJson; import_["messages"].array) {
                ChatMessage msg;
                msg.role = msgJson["role"].str.to!(AIMessage.Role);
                msg.content = msgJson["content"].str;
                msg.timestamp = DateTime.fromISOExtString(msgJson["timestamp"].str);
                msg.source = "local";
                thread.messages ~= msg;
            }

            _threads[thread.id] = thread;
            // Create a widget for the chat thread content
            auto threadWidget = new VerticalLayout(thread.id);
            threadWidget.layoutWidth = FILL_PARENT;
            threadWidget.layoutHeight = FILL_PARENT;

            _threadTabs.addTab(threadWidget, title.to!dstring);

            Log.i("ChatWidget: Imported legacy conversation from ", inputPath);
        } catch (Exception e) {
            Log.e("ChatWidget: Failed to import conversation: ", e.msg);
        }
    }

    /**
     * Clear current conversation
     */
    void clearConversation() {
        if (_currentThreadId.empty)
            return;

        if (_currentThreadId in _threads) {
            _threads[_currentThreadId].messages.length = 0;
            refreshChatDisplay();
        }
    }

    /**
     * Delete thread
     */
    void deleteThread(string threadId) {
        if (threadId in _threads) {
            _threads.remove(threadId);
            _threadTabs.removeTab(threadId);

            if (threadId == _currentThreadId) {
                // Switch to first available thread or create new one
                if (_threads.empty) {
                    createNewThread("New Conversation");
                } else {
                    auto firstThread = _threads.values[0];
                    _currentThreadId = firstThread.id;
                    _threadTabs.selectTab(_currentThreadId);
                }
            }
        }
    }

    /**
     * Regenerate an AI message (delete it and request new response)
     */
    private void regenerateMessage(string messageId) {
        if (_currentThreadId.empty || _currentThreadId !in _threads)
            return;

        auto thread = &_threads[_currentThreadId];

        // Find the message and the user message that preceded it
        int messageIndex = -1;
        string userMessageContent;

        foreach (i, ref msg; thread.messages) {
            if (msg.id == messageId) {
                messageIndex = cast(int)i;
                break;
            }
        }

        if (messageIndex < 0) {
            Log.w("ChatWidget: Cannot regenerate - message not found: ", messageId);
            return;
        }

        // Look for preceding user message to regenerate from
        for (int i = messageIndex - 1; i >= 0; i--) {
            if (thread.messages[i].role == AIMessage.Role.User) {
                userMessageContent = thread.messages[i].content;
                break;
            }
        }

        if (userMessageContent.empty) {
            Log.w("ChatWidget: Cannot regenerate - no preceding user message found");
            return;
        }

        // Remove the AI message and all messages after it
        thread.messages = thread.messages[0..messageIndex];

        // Refresh display
        refreshChatDisplay();

        // Start new AI response from the user message
        Log.i("ChatWidget: Regenerating response for message after: ", userMessageContent[0..min(50, $)]);
        startAIResponse(userMessageContent);
    }

    /**
     * Delete a message from the current thread
     */
    private void deleteMessage(string messageId) {
        if (_currentThreadId.empty || _currentThreadId !in _threads)
            return;

        auto thread = &_threads[_currentThreadId];

        // Find and remove the message
        ChatMessage[] newMessages;
        bool found = false;

        foreach (ref msg; thread.messages) {
            if (msg.id != messageId) {
                newMessages ~= msg;
            } else {
                found = true;
            }
        }

        if (found) {
            thread.messages = newMessages;
            refreshChatDisplay();
            Log.i("ChatWidget: Deleted message ", messageId);
        }
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        _threads.clear();
        _fileReferences.clear();
        _currentThreadId = "";
        _streamingMessageId = "";
        _isStreaming = false;

        Log.i("ChatWidget: Cleaned up");
    }
}
