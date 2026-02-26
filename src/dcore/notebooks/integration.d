module dcore.notebooks.integration;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.json;
import std.path;
import std.string;

import dlangui.core.logger;
import dlangui.core.signals;
import dlangui.widgets.controls;
import dlangui.widgets.docks;
import dlangui.widgets.layouts;
import dlangui.widgets.menu;
import dlangui.widgets.tabs;
import dlangui.widgets.tree;
import dlangui.widgets.widget;

import dcore.core;
import dcore.components.cccore;
import dcore.notebooks.notebook;
import dcore.notebooks.notebook_manager;
import dcore.notebooks.executor;
import dcore.notebooks.widgets.notebook_widget;
import dcore.utils.signals : Signal;

/**
 * Notebook integration with Dnives IDE
 */
class NotebookIntegration {
    private NotebookManager _manager;
    private DockHost _dockHost;
    private Widget _notebooksPanel;
    private Widget _workspaceExplorer;
    private bool _initialized;

    // Core references
    private DCore _dcore;
    private CCCore _cccore;
    private Widget _mainWindow;

    // Menu items and actions
    private MenuItem _notebookMenu;
    private Action[] _notebookActions;

    // Signals
    Signal!() onIntegrationReady;

    this() {
        _initialized = false;
        setupNotebookManager();
        createActions();
    }

    /**
     * Initialize integration with IDE core
     */
    void initialize(DockHost dockHost) {
        if (_initialized) return;

        _dockHost = dockHost;
        createNotebookDocks();
        registerMenuItems();
        setupKeyBindings();

        _initialized = true;
        onIntegrationReady.emit();

        Log.i("Notebook integration initialized");
    }

    /**
     * Initialize with DCore and CCCore references
     */
    void initialize(DCore dcore, CCCore cccore, Widget mainWindow) {
        _dcore = dcore;
        _cccore = cccore;
        _mainWindow = mainWindow;

        // Get dock host from main window if available
        auto dockHost = cast(DockHost)mainWindow;
        if (dockHost !is null) {
            initialize(dockHost);
        } else {
            Log.w("Main window is not a DockHost, notebook docking may not work");
            _initialized = true;
        }
    }

    /**
     * Get the notebook manager
     */
    NotebookManager getManager() {
        return _manager;
    }

    /**
     * Create new notebook
     */
    void createNewNotebook() {
        if (_manager !is null) {
            auto session = _manager.createNotebook();
            Log.i("Created new notebook: ", session.notebook.name);
        }
    }

    /**
     * Open notebook from file
     */
    void openNotebook(string filePath = "") {
        if (filePath.length == 0) {
            // In a real implementation, show file dialog
            // For now, just create a new notebook
            createNewNotebook();
            return;
        }

        if (_manager !is null) {
            try {
                auto session = _manager.openNotebook(filePath);
                Log.i("Opened notebook: ", filePath);
            } catch (Exception e) {
                Log.e("Failed to open notebook: ", e.msg);
            }
        }
    }

    /**
     * Save active notebook
     */
    void saveActiveNotebook() {
        if (_manager !is null) {
            auto activeSession = getActiveNotebookSession();
            if (activeSession !is null) {
                _manager.saveNotebook(activeSession.id);
            }
        }
    }

    /**
     * Save all notebooks
     */
    void saveAllNotebooks() {
        if (_manager !is null) {
            _manager.saveAllNotebooks();
        }
    }

    /**
     * Close active notebook
     */
    void closeActiveNotebook() {
        if (_manager !is null) {
            auto activeSession = getActiveNotebookSession();
            if (activeSession !is null) {
                _manager.closeNotebook(activeSession.id);
            }
        }
    }

    /**
     * Execute all cells in active notebook
     */
    void executeActiveNotebook() {
        if (_manager !is null) {
            _manager.executeActiveNotebook();
        }
    }

    /**
     * Clear all outputs in active notebook
     */
    void clearActiveNotebookOutputs() {
        if (_manager !is null) {
            _manager.clearActiveNotebookOutputs();
        }
    }

    /**
     * Create new workspace
     */
    void createNewWorkspace(string name = "New Workspace") {
        if (_manager !is null) {
            _manager.createWorkspace(name);
            updateWorkspaceExplorer();
        }
    }

    /**
     * Show notebook templates dialog
     */
    void showTemplatesDialog() {
        // This would show a dialog with notebook templates
        // For now, create a data analysis template
        auto notebook = NotebookTemplates.createDataAnalysisTemplate();
        auto session = _manager.getActiveWorkspace().addNotebookFromTemplate(notebook);
        Log.i("Created notebook from template");
    }

    /**
     * Export active notebook
     */
    void exportActiveNotebook(string format = "livemd") {
        auto activeSession = getActiveNotebookSession();
        if (activeSession !is null) {
            string outputPath = activeSession.filePath.setExtension("." ~ format);
            _manager.exportNotebook(activeSession.id, format, outputPath);
        }
    }

    /**
     * Get active notebook session
     */
    private NotebookSession* getActiveNotebookSession() {
        if (_manager is null) return null;

        auto activeWorkspace = _manager.getActiveWorkspace();
        if (activeWorkspace is null) return null;

        // This would get the currently active tab
        // For now, return the first session if any exist
        auto sessions = activeWorkspace.getAllSessions();
        return sessions.length > 0 ? &sessions[0] : null;
    }

    private void setupNotebookManager() {
        _manager = new NotebookManager();

        // Connect manager signals
        _manager.onWorkspaceAdded.connect(&onWorkspaceAdded);
        _manager.onWorkspaceRemoved.connect(&onWorkspaceRemoved);
        _manager.onActiveWorkspaceChanged.connect(&onActiveWorkspaceChanged);
        _manager.onNotebookOpened.connect(&onNotebookOpened);
        _manager.onNotebookClosed.connect(&onNotebookClosed);
    }

    private void createActions() {
        _notebookActions = [
            new Action(1001, "New Notebook"d, null, KeyCode.KEY_N, KeyFlag.Control | KeyFlag.Alt),
            new Action(1002, "Open Notebook"d, null, KeyCode.KEY_O, KeyFlag.Control | KeyFlag.Alt),
            new Action(1003, "Save Notebook"d, null, KeyCode.KEY_S, KeyFlag.Control | KeyFlag.Alt),
            new Action(1004, "Save All Notebooks"d, null),
            new Action(1005, "Close Notebook"d, null, KeyCode.KEY_W, KeyFlag.Control | KeyFlag.Alt),
            new Action(1006, "Execute All Cells"d, null, KeyCode.KEY_R, KeyFlag.Control | KeyFlag.Alt),
            new Action(1007, "Clear All Outputs"d, null),
            new Action(1008, "New Workspace"d, null),
            new Action(1009, "Notebook Templates"d, null),
            new Action(1010, "Export Notebook"d, null),
        ];

        // TODO: Set action handlers - dlangui 0.10.8 doesn't have onTriggered signal
        // Actions are handled through menu item callbacks instead
        // foreach (action; _notebookActions) {
        //     action.onTriggered.connect(&onActionTriggered);
        // }
    }

    private void createNotebookDocks() {
        if (_dockHost is null) return;

        // Create main notebooks panel
        auto notebookDock = new DockWindow("notebooks");
        notebookDock.caption.text = "Notebooks"d;
        _manager.initializeUI(notebookDock);
        _dockHost.addDockedWindow(notebookDock);

        // Create workspace explorer dock
        auto explorerDock = new DockWindow("workspace_explorer");
        explorerDock.caption.text = "Workspace Explorer"d;
        explorerDock.dockAlignment = DockAlignment.Left;
        _workspaceExplorer = createWorkspaceExplorer();
        explorerDock.bodyWidget = _workspaceExplorer;
        _dockHost.addDockedWindow(explorerDock);

        // Create notebook outline dock
        auto outlineDock = new DockWindow("notebook_outline");
        outlineDock.caption.text = "Notebook Outline"d;
        outlineDock.dockAlignment = DockAlignment.Right;
        auto outlineWidget = createNotebookOutline();
        outlineDock.bodyWidget = outlineWidget;
        _dockHost.addDockedWindow(outlineDock);
    }

    private Widget createWorkspaceExplorer() {
        auto explorer = new VerticalLayout("workspace_explorer");

        // Workspace selector
        auto workspaceHeader = new HorizontalLayout();
        workspaceHeader.addChild(new TextWidget(null, "Workspaces"));

        auto newWorkspaceBtn = new Button("new_workspace", "+");
        newWorkspaceBtn.click = (Widget w) {
            createNewWorkspace();
            return true;
        };
        workspaceHeader.addChild(newWorkspaceBtn);
        explorer.addChild(workspaceHeader);

        // Workspace tree
        auto workspaceTree = new TreeWidget("workspace_tree");
        updateWorkspaceTree(workspaceTree);
        explorer.addChild(workspaceTree);

        return explorer;
    }

    private Widget createNotebookOutline() {
        auto outline = new VerticalLayout("notebook_outline");
        outline.addChild(new TextWidget(null, "Notebook Outline"));

        // This would show the structure of the active notebook
        auto outlineTree = new TreeWidget("outline_tree");
        outline.addChild(outlineTree);

        return outline;
    }

    private void updateWorkspaceExplorer() {
        if (_workspaceExplorer !is null) {
            auto tree = cast(TreeWidget)_workspaceExplorer.childById("workspace_tree");
            if (tree !is null) {
                updateWorkspaceTree(tree);
            }
        }
    }

    private void updateWorkspaceTree(TreeWidget tree) {
        if (_manager is null) return;

        tree.clearAllItems();

        foreach (workspace; _manager.getWorkspaces()) {
            // Create workspace item with statistics included in name
            auto stats = workspace.getStats();
            dstring workspaceName = workspace.name.to!dstring;
            if (stats.totalNotebooks > 0) {
                workspaceName ~= format(" (%d notebooks)", stats.totalNotebooks).to!dstring;
            }
            auto workspaceItem = tree.items.newChild("workspace_" ~ workspace.id, workspaceName, null);

            // Add notebooks
            foreach (session; workspace.getAllSessions()) {
                // Create notebook name with modification indicator and statistics
                dstring notebookName = session.notebook.name.to!dstring;
                if (session.modified) {
                    notebookName ~= " *";
                }

                // Add notebook statistics to name
                auto nbStats = session.notebook.getStats();
                if (nbStats.totalCells > 0) {
                    string statsText = format(" (%d cells", nbStats.totalCells);
                    if (nbStats.executedCells > 0) {
                        statsText ~= format(", %d executed", nbStats.executedCells);
                    }
                    statsText ~= ")";
                    notebookName ~= statsText.to!dstring;
                }

                auto notebookItem = workspaceItem.newChild("notebook_" ~ session.id, notebookName, null);
            }
        }
    }

    private void registerMenuItems() {
        // This would integrate with the main IDE menu system
        // For now, we'll assume menu integration is handled elsewhere
        Log.i("Notebook menu items registered");
    }

    private void setupKeyBindings() {
        // Register keyboard shortcuts for notebook actions
        foreach (action; _notebookActions) {
            // TODO: dlangui 0.10.8 doesn't have acceleratorKey property
            // Check accelerators array instead if needed
            Log.d("Registered shortcut for action: ", action.id);
        }
    }

    private void onActionTriggered(Action action) {
        switch (action.id) {
            case 1001: // "notebook.new"
                createNewNotebook();
                break;
            case 1002: // "notebook.open"
                openNotebook();
                break;
            case 1003: // "notebook.save"
                saveActiveNotebook();
                break;
            case 1004: // "notebook.saveAll"
                saveAllNotebooks();
                break;
            case 1005: // "notebook.close"
                closeActiveNotebook();
                break;
            case 1006: // "notebook.execute"
                executeActiveNotebook();
                break;
            case 1007: // "notebook.clearOutputs"
                clearActiveNotebookOutputs();
                break;
            case 1008: // "notebook.newWorkspace"
                createNewWorkspace();
                break;
            case 1009: // "notebook.templates"
                showTemplatesDialog();
                break;
            case 1010: // "notebook.export"
                exportActiveNotebook();
                break;
            default:
                Log.w("Unknown notebook action: ", action.id);
                break;
        }
    }

    // Manager signal handlers
    private void onWorkspaceAdded(NotebookWorkspace workspace) {
        updateWorkspaceExplorer();
        Log.i("Workspace added: ", workspace.name);
    }

    private void onWorkspaceRemoved(NotebookWorkspace workspace) {
        updateWorkspaceExplorer();
        Log.i("Workspace removed: ", workspace.name);
    }

    private void onActiveWorkspaceChanged(NotebookWorkspace workspace) {
        updateWorkspaceExplorer();
        if (workspace !is null) {
            Log.i("Active workspace changed to: ", workspace.name);
        }
    }

    private void onNotebookOpened(NotebookSession session) {
        updateWorkspaceExplorer();
        Log.i("Notebook opened: ", session.notebook.name);
    }

    private void onNotebookClosed(NotebookSession session) {
        updateWorkspaceExplorer();
        Log.i("Notebook closed: ", session.notebook.name);
    }
}

/**
 * Extension of NotebookWorkspace to support templates
 */
class NotebookWorkspaceTemplates {
    /**
     * Add notebook from template
     */
    static NotebookSession addNotebookFromTemplate(NotebookWorkspace workspace, Notebook templateNotebook) {
        auto widget = new NotebookWidget(templateNotebook);
        string filePath = buildPath(workspace.path, templateNotebook.name ~ ".notebook");
        auto session = NotebookSession(templateNotebook, widget, filePath);

        workspace.addSession(session);
        return session;
    }
}

/**
 * Notebook file type handler for IDE file system integration
 */
class NotebookFileHandler {
    static bool canHandle(string filePath) {
        string ext = filePath.extension.toLower;
        return ext == ".notebook" || ext == ".livemd" || ext == ".ipynb";
    }

    static void openInIDE(string filePath) {
        // Get the notebook integration instance and open the file
        // This would be called by the IDE's file opening system
        auto integration = getNotebookIntegration();
        if (integration !is null) {
            integration.openNotebook(filePath);
        }
    }

    static string getFileTypeDescription() {
        return "Interactive Notebook";
    }

    static string[] getSupportedExtensions() {
        return [".notebook", ".livemd", ".ipynb"];
    }
}

/**
 * Global notebook integration instance
 */
private __gshared NotebookIntegration g_notebookIntegration;

/**
 * Get global notebook integration instance
 */
NotebookIntegration getNotebookIntegration() {
    if (g_notebookIntegration is null) {
        g_notebookIntegration = new NotebookIntegration();
    }
    return g_notebookIntegration;
}

/**
 * Initialize notebook system for the IDE with DCore architecture
 */
bool initializeNotebookSystem(DCore dcore, CCCore cccore, Widget mainWindow) {
    auto integration = getNotebookIntegration();
    integration.initialize(dcore, cccore, mainWindow);

    // Register file type handler
    // This would integrate with the IDE's file type system
    Log.i("Notebook system initialized with DCore architecture");
    return true;
}

/**
 * Initialize notebook system for the IDE (legacy)
 */
void initializeNotebookSystem(DockHost dockHost) {
    auto integration = getNotebookIntegration();
    integration.initialize(dockHost);

    // Register file type handler
    Log.i("Notebook file type handler registered");
}

/**
 * Cleanup notebook system
 */
void shutdownNotebookSystem() {
    if (g_notebookIntegration !is null) {
        g_notebookIntegration.saveAllNotebooks();
        g_notebookIntegration = null;
    }
    Log.i("Notebook system shutdown");
}

/**
 * Notebook-specific AI integration
 */
class NotebookAIIntegration {
    /**
     * Generate notebook from natural language description
     */
    static Notebook generateNotebookFromDescription(string description) {
        auto notebook = new Notebook("AI Generated Notebook");

        // This would use the existing AI system to generate notebook content
        // For now, create a basic structure
        auto section = notebook.sections()[0];
        section.name = "AI Generated Content";

        auto cell = section.cells()[0];
        cell.source = format("# AI Generated Notebook\n\nGenerated from: %s\n\nThis notebook was created using AI assistance.", description);

        // Add a code cell with basic D template
        auto codeCell = new NotebookCell(CellType.Code,
            "import std.stdio;\n\nvoid main() {\n    writeln(\"Hello from AI-generated notebook!\");\n}");
        section.addCell(codeCell);

        return notebook;
    }

    /**
     * Generate code cell from natural language
     */
    static NotebookCell generateCodeCell(string prompt, string language = "d") {
        // This would integrate with the AI chat system
        string generatedCode = format("// Generated from: %s\n// TODO: Implement actual AI generation\n\nimport std.stdio;\nwriteln(\"Generated code placeholder\");", prompt);

        auto cell = new NotebookCell(CellType.Code, generatedCode);
        cell.metadata = JSONValue(["ai_generated": JSONValue(true), "prompt": JSONValue(prompt)]);

        return cell;
    }

    /**
     * Explain code in a cell
     */
    static string explainCode(NotebookCell cell) {
        if (!cell.isCodeCell()) {
            return "This is not a code cell.";
        }

        // This would use AI to explain the code
        return format("This code cell contains:\n%s\n\n[AI explanation would go here]", cell.source);
    }

    /**
     * Suggest improvements for a cell
     */
    static string[] suggestImprovements(NotebookCell cell) {
        // This would use AI to suggest improvements
        return [
            "Consider adding error handling",
            "Add documentation comments",
            "Optimize for performance",
            "Add unit tests"
        ];
    }
}
