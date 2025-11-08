module dcore.ai.widgets.chat_widget;

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
import dcore.code.symbol_tracker;

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

    this(string title, string workspacePath) {
        this.id = randomUUID().toString();
        this.title = title;
        this.workspacePath = workspacePath;
        this.created = cast(DateTime)Clock.currTime();
        this.lastActivity = cast(DateTime)Clock.currTime();
        this.metadata = JSONValue.emptyObject;
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
    private EditBox _symbolSearch;
    private ListWidget _contextFiles;
    private EditBox _contextPreview;

    // State
    private ChatThread[string] _threads;
    private string _currentThreadId;
    private FileReference[string] _fileReferences;
    private bool _isStreaming;
    private string _streamingMessageId;

    // Configuration
    private int _maxMessageLength = 4000;
    private bool _showLineNumbers = true;
    private bool _autoScroll = true;

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

        // Create right pane (context management)
        _rightPane = new VerticalLayout("CONTEXT_PANE");
        _rightPane.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        createContextInterface();
        addChild(_rightPane);

        // Create initial thread
        createNewThread("New Conversation");
    }

    /**
     * Create the chat interface (left pane)
     */
    private void createChatInterface() {
        // Thread tabs
        _threadTabs = new TabWidget("THREAD_TABS");
        _threadTabs.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _leftPane.addChild(_threadTabs);

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
        _inputContainer.padding(Rect(10, 10, 10, 10));

        _attachButton = new Button("ATTACH_BTN", "📎");
        _attachButton.tooltipText = "Attach files or symbols";
        _inputContainer.addChild(_attachButton);

        _inputBox = new EditBox("INPUT_BOX");
        _inputBox.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        // EditBox properties may not exist in this version
        // _inputBox.minLines = 2;
        // _inputBox.maxLines = 8;
        // _inputBox.placeholder = "Ask a question about your code...";
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
     * Create the context interface (right pane)
     */
    private void createContextInterface() {
        // Context tabs
        _contextTabs = new TabWidget("CONTEXT_TABS");
        _contextTabs.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // Files tab
        auto filesTab = _contextTabs.addTab("FILES", "Files"d);
        createFilesTab(filesTab);

        // Symbols tab
        auto symbolsTab = _contextTabs.addTab("SYMBOLS", "Symbols"d);
        createSymbolsTab(symbolsTab);

        // Context tab
        auto contextTab = _contextTabs.addTab("CONTEXT", "Context"d);
        createContextTab(contextTab);

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

        // Symbol search
        _symbolSearch = new EditBox("SYMBOL_SEARCH");
        _symbolSearch.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        _symbolSearch.placeholder = "Search symbols...";
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
        // Input box events
        _inputBox.contentChange = delegate(EditableContent source) {
            _sendButton.enabled = !_inputBox.text.empty && !_isStreaming;
        };

        _inputBox.keyEvent = delegate(Widget source, KeyEvent event) {
            if (event.action == KeyAction.KeyDown) {
                if (event.key == KeyCode.RETURN && event.modifiers & KeyFlag.Control) {
                    sendMessage();
                    return true;
                }
            }
            return false;
        };

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

        // File tree events
        _fileTree.selectionChange = delegate(TreeItems source, TreeItem selectedItem, bool activated) {
            if (activated && selectedItem) {
                string filePath = cast(string)selectedItem.tag;
                if (!filePath.empty) {
                    addFileReference(filePath);
                }
            }
        };

        // Symbol search
        _symbolSearch.contentChange = delegate(EditableContent source) {
            searchSymbols(_symbolSearch.text);
        };

        // Thread tab change
        _threadTabs.tabChanged = delegate(string tabId, bool activated) {
            if (activated) {
                switchToThread(tabId);
            }
        };
    }

    /**
     * Send a message to the AI
     */
    private void sendMessage() {
        string messageText = _inputBox.text.strip();
        if (messageText.empty || _isStreaming)
            return;

        // Add user message to current thread
        auto userMessage = ChatMessage(AIMessage.Role.User, messageText);
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

        // Stream the response
        try {
            _aiBackend.chatStream(messages, &onStreamChunk);
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
            _chatScroll.scrollToBottom();
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

        // Add tab
        auto tab = _threadTabs.addTab(thread.id, title.to!dstring);

        // Create context for this thread
        _contextManager.createConversation(workspacePath, _fileReferences.keys);

        // Switch to new thread
        _currentThreadId = thread.id;
        _threadTabs.selectTab(thread.id);

        return thread.id;
    }

    /**
     * Switch to a thread
     */
    private void switchToThread(string threadId) {
        if (threadId == _currentThreadId)
            return;

        _currentThreadId = threadId;
        refreshChatDisplay();
    }

    /**
     * Add message to thread
     */
    private void addMessageToThread(string threadId, ChatMessage message) {
        if (threadId !in _threads)
            return;

        auto thread = &_threads[threadId];
        thread.messages ~= message;
        thread.lastActivity = Clock.currTime();

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
            _chatScroll.scrollToBottom();
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

        // Message actions (for assistant messages)
        if (message.role == AIMessage.Role.Assistant && !message.content.empty) {
            auto actionsLayout = new HorizontalLayout("MSG_ACTIONS_" ~ message.id);
            actionsLayout.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);

            auto copyButton = new Button("COPY_" ~ message.id, "Copy");
            copyButton.click = delegate(Widget source) {
                platform.setClipboardText(message.content);
                return true;
            };
            actionsLayout.addChild(copyButton);

            if (hasCodeBlocks(message.content)) {
                auto applyButton = new Button("APPLY_" ~ message.id, "Apply Code");
                applyButton.click = delegate(Widget source) {
                    applyCodeFromMessage(message);
                    return true;
                };
                actionsLayout.addChild(applyButton);
            }

            messageLayout.addChild(actionsLayout);
        }

        return messageLayout;
    }

    /**
     * Create content widget for a message
     */
    private Widget createMessageContentWidget(ChatMessage message) {
        auto contentBox = new EditBox("CONTENT_" ~ message.id);
        contentBox.layoutWidth(FILL_PARENT).layoutHeight(WRAP_CONTENT);
        contentBox.readOnly = true;
        contentBox.text = message.content;
        contentBox.fontFamily = FontFamily.MonoSpace;
        contentBox.fontSize = 12;

        // Style based on role
        switch (message.role) {
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

        return contentBox;
    }

    /**
     * Update message display during streaming
     */
    private void updateMessageDisplay(ChatMessage message) {
        auto messageWidget = _chatContainer.childById("CONTENT_" ~ message.id);
        if (auto editBox = cast(EditBox)messageWidget) {
            editBox.text = message.content;
            if (message.isStreaming) {
                editBox.text ~= "▋"; // Cursor indicator
            }
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
        auto rootItem = _fileTree.createItem(baseName(workspace.path), null, true);
        rootItem.tag = cast(void*)workspace.path.dup.ptr;

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
                    auto dirItem = _fileTree.createItem(baseName(entry.name), parent, true);
                    dirItem.tag = cast(void*)entry.name.dup.ptr;
                    populateFileTreeRecursive(dirItem, entry.name, currentDepth + 1, maxDepth);
                } else if (isSourceFile(entry.name)) {
                    auto fileItem = _fileTree.createItem(baseName(entry.name), parent, false);
                    fileItem.tag = cast(void*)entry.name.dup.ptr;
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

        _contextFiles.clear();

        foreach (ref_, reference; _fileReferences) {
            auto item = new StringListItem(reference.displayName);
            item.tag = cast(void*)reference.filePath.dup.ptr;
            _contextFiles.addItem(item);
        }
    }

    /**
     * Update context preview
     */
    private void updateContextPreview() {
        if (!_contextPreview)
            return;

        if (_fileReferences.empty) {
            _contextPreview.text = "No context files selected.";
            return;
        }

        string contextText = _contextManager.getCodeContext(_fileReferences.keys);
        _contextPreview.text = contextText;
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
            _contextFiles.clear();

            foreach (symbol; symbols.take(20)) { // Limit results
                auto item = new StringListItem(symbol.name ~ " (" ~ baseName(symbol.filePath) ~ ")");
                item.tag = cast(void*)symbol.fullyQualifiedName.dup.ptr;
                _contextFiles.addItem(item);
            }
        }
    }

    /**
     * Show attach dialog
     */
    private void showAttachDialog() {
        // Create popup with attachment options
        auto menu = new PopupMenu();
        menu.addItem(new Action(1, "Attach Current File"));
        menu.addItem(new Action(2, "Attach Symbol..."));
        menu.addItem(new Action(3, "Attach Selection"));

        menu.menuItemAction = delegate(const Action action) {
            switch (action.id) {
                case 1:
                    attachCurrentFile();
                    break;
                case 2:
                    showSymbolAttachDialog();
                    break;
                case 3:
                    attachSelection();
                    break;
                default:
                    break;
            }
        };

        auto attachRect = _attachButton.pos;
        menu.popup(_attachButton.parent, attachRect.right, attachRect.bottom);
    }

    /**
     * Attach current file
     */
    private void attachCurrentFile() {
        // Get currently active file from editor
        // This would need integration with the editor system
        Log.i("ChatWidget: Would attach current file");
    }

    /**
     * Show symbol attach dialog
     */
    private void showSymbolAttachDialog() {
        // Show dialog to search and select symbols
        Log.i("ChatWidget: Would show symbol attach dialog");
    }

    /**
     * Attach current selection
     */
    private void attachSelection() {
        // Get current selection from editor
        Log.i("ChatWidget: Would attach current selection");
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
        export_["messages"] = JSONValue.emptyArray;

        foreach (message; thread.messages) {
            JSONValue msgJson = JSONValue.emptyObject;
            msgJson["role"] = message.role.to!string;
            msgJson["content"] = message.content;
            msgJson["timestamp"] = message.timestamp.toISOExtString();
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
     */
    void importConversation(string inputPath) {
        try {
            string content = readText(inputPath);
            JSONValue import_ = parseJSON(content);

            string title = import_["title"].str;
            auto thread = ChatThread(title, _core.getCurrentWorkspace().path);

            foreach (msgJson; import_["messages"].array) {
                ChatMessage msg;
                msg.role = msgJson["role"].str.to!(AIMessage.Role);
                msg.content = msgJson["content"].str;
                msg.timestamp = DateTime.fromISOExtString(msgJson["timestamp"].str);
                thread.messages ~= msg;
            }

            _threads[thread.id] = thread;
            auto tab = _threadTabs.addTab(thread.id, title.to!dstring);

            Log.i("ChatWidget: Imported conversation from ", inputPath);
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
