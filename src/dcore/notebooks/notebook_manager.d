module dcore.notebooks.notebook_manager;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.file;
import std.json;
import std.path;
import std.process;
import std.string;
import std.typecons;
import std.uuid;

import dlangui.core.logger;
import dlangui.core.signals;
import dlangui.widgets.widget;
import dlangui.widgets.tabs;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;

import dcore.notebooks.notebook;
import dcore.notebooks.executor;
import dcore.notebooks.widgets.notebook_widget;
import dcore.utils.signals : Signal;

/**
 * Notebook session information
 */
struct NotebookSession {
    string id;
    Notebook notebook;
    NotebookWidget widget;
    string filePath;
    bool modified;
    SysTime lastAccessed;

    this(Notebook nb, NotebookWidget w, string path = "") {
        id = randomUUID().toString();
        notebook = nb;
        widget = w;
        filePath = path;
        modified = false;
        lastAccessed = Clock.currTime();
    }
}

/**
 * Notebook workspace for organizing related notebooks
 */
class NotebookWorkspace {
    private string _id;
    private string _name;
    private string _path;
    private string _description;
    private NotebookSession[string] _notebooks;
    private JSONValue _metadata;
    private SysTime _created;
    private SysTime _lastModified;

    // Signals
    Signal!(NotebookSession) onNotebookAdded;
    Signal!(NotebookSession) onNotebookRemoved;
    Signal!() onWorkspaceChanged;

    this(string name, string path) {
        _id = randomUUID().toString();
        _name = name;
        _path = path;
        _description = "";
        _created = Clock.currTime();
        _lastModified = Clock.currTime();
        _metadata = JSONValue.emptyObject;

        // Ensure workspace directory exists
        if (!exists(_path)) {
            try {
                mkdirRecurse(_path);
            } catch (Exception e) {
                Log.e("Failed to create workspace directory: ", e.msg);
            }
        }
    }

    // Properties
    @property string id() const { return _id; }
    @property string name() const { return _name; }
    @property void name(string value) {
        if (_name != value) {
            _name = value;
            _lastModified = Clock.currTime();
            onWorkspaceChanged.emit();
        }
    }

    @property string path() const { return _path; }
    @property string description() const { return _description; }
    @property void description(string value) {
        if (_description != value) {
            _description = value;
            _lastModified = Clock.currTime();
            onWorkspaceChanged.emit();
        }
    }

    @property SysTime created() const { return _created; }
    @property SysTime lastModified() const { return _lastModified; }

    /**
     * Get all notebook sessions
     */
    NotebookSession[] getAllSessions() {
        return _notebooks.values.dup;
    }

    /**
     * Get notebook session by ID
     */
    NotebookSession* getSession(string sessionId) {
        return sessionId in _notebooks;
    }

    /**
     * Add notebook session
     */
    void addSession(NotebookSession session) {
        _notebooks[session.id] = session;
        _lastModified = Clock.currTime();
        onNotebookAdded.emit(session);
        onWorkspaceChanged.emit();
    }

    /**
     * Remove notebook session
     */
    bool removeSession(string sessionId) {
        if (sessionId in _notebooks) {
            auto session = _notebooks[sessionId];
            _notebooks.remove(sessionId);
            _lastModified = Clock.currTime();
            onNotebookRemoved.emit(session);
            onWorkspaceChanged.emit();
            return true;
        }
        return false;
    }

    /**
     * Create new notebook in this workspace
     */
    NotebookSession createNotebook(string name = "") {
        if (name.length == 0) {
            name = format("Untitled-%d", _notebooks.length + 1);
        }

        auto notebook = new Notebook(name);
        auto widget = new NotebookWidget(notebook);

        string filePath = buildPath(_path, name ~ ".notebook");
        auto session = NotebookSession(notebook, widget, filePath);

        addSession(session);
        return session;
    }

    /**
     * Add notebook from template
     */
    NotebookSession addNotebookFromTemplate(Notebook template_) {
        auto notebook = new Notebook(template_.name ~ " (from template)");
        // Copy sections from template
        foreach (section; template_.sections) {
            auto newSection = new NotebookSection(section.name, section.level);
            foreach (cell; section.cells()) {
                auto newCell = new NotebookCell(cell.type, cell.source);
                newSection.addCell(newCell);
            }
            notebook.addSection(newSection);
        }

        auto widget = new NotebookWidget(notebook);
        string filePath = buildPath(_path, notebook.name ~ ".notebook");
        auto session = NotebookSession(notebook, widget, filePath);

        addSession(session);
        return session;
    }

    /**
     * Load notebook from file into this workspace
     */
    NotebookSession loadNotebook(string filePath) {
        try {
            auto notebook = Notebook.load(filePath);
            if (notebook is null) {
                throw new Exception("Failed to load notebook");
            }

            auto widget = new NotebookWidget(notebook);
            auto session = NotebookSession(notebook, widget, filePath);

            addSession(session);
            Log.i("Loaded notebook into workspace: ", filePath);
            return session;
        } catch (Exception e) {
            Log.e("Failed to load notebook: ", e.msg);
            throw e;
        }
    }

    /**
     * Save workspace configuration
     */
    bool save() {
        try {
            string configPath = buildPath(_path, ".workspace.json");
            auto json = toJSON();
            std.file.write(configPath, json.toPrettyString());
            Log.i("Saved workspace: ", _name);
            return true;
        } catch (Exception e) {
            Log.e("Failed to save workspace: ", e.msg);
            return false;
        }
    }

    /**
     * Load workspace from configuration
     */
    static NotebookWorkspace load(string path) {
        try {
            string configPath = buildPath(path, ".workspace.json");
            if (!exists(configPath)) {
                // Create new workspace if config doesn't exist
                string name = baseName(path);
                return new NotebookWorkspace(name, path);
            }

            auto content = cast(string)std.file.read(configPath);
            auto json = parseJSON(content);
            return fromJSON(json, path);
        } catch (Exception e) {
            Log.e("Failed to load workspace from ", path, ": ", e.msg);
            return null;
        }
    }

    /**
     * Convert to JSON
     */
    JSONValue toJSON() const {
        JSONValue json = JSONValue.emptyObject;
        json["id"] = _id;
        json["name"] = _name;
        json["description"] = _description;
        json["created"] = _created.toISOExtString();
        json["last_modified"] = _lastModified.toISOExtString();
        json["metadata"] = _metadata;

        // Save notebook references (not full content)
        JSONValue notebooks = JSONValue.emptyArray;
        foreach (session; _notebooks.values) {
            if (session.filePath.length > 0) {
                JSONValue nbRef = JSONValue.emptyObject;
                nbRef["id"] = session.id;
                nbRef["name"] = session.notebook.name;
                nbRef["file_path"] = session.filePath;
                nbRef["modified"] = session.modified;
                nbRef["last_accessed"] = session.lastAccessed.toISOExtString();
                notebooks.array ~= nbRef;
            }
        }
        json["notebooks"] = notebooks;

        return json;
    }

    /**
     * Load from JSON
     */
    static NotebookWorkspace fromJSON(JSONValue json, string path) {
        string id = json["id"].str;
        string name = json["name"].str;
        string description = ("description" in json) ? json["description"].str : "";

        auto workspace = new NotebookWorkspace(name, path);
        workspace._id = id;
        workspace._description = description;

        if ("created" in json) {
            try {
                workspace._created = SysTime.fromISOExtString(json["created"].str);
            } catch (Exception e) {
                Log.w("Failed to parse workspace creation time");
            }
        }

        if ("last_modified" in json) {
            try {
                workspace._lastModified = SysTime.fromISOExtString(json["last_modified"].str);
            } catch (Exception e) {
                Log.w("Failed to parse workspace modification time");
            }
        }

        if ("metadata" in json) {
            workspace._metadata = json["metadata"];
        }

        return workspace;
    }

    /**
     * Get workspace statistics
     */
    struct WorkspaceStats {
        size_t totalNotebooks;
        size_t modifiedNotebooks;
        size_t totalCells;
        size_t executedCells;
        SysTime lastActivity;
    }

    WorkspaceStats getStats() {
        WorkspaceStats stats;
        stats.totalNotebooks = _notebooks.length;
        stats.lastActivity = _lastModified;

        foreach (session; _notebooks.values) {
            if (session.modified) {
                stats.modifiedNotebooks++;
            }

            if (session.lastAccessed > stats.lastActivity) {
                stats.lastActivity = session.lastAccessed;
            }

            auto nbStats = session.notebook.getStats();
            stats.totalCells += nbStats.totalCells;
            stats.executedCells += nbStats.executedCells;
        }

        return stats;
    }
}

/**
 * Main notebook manager for the IDE
 */
class NotebookManager {
    private NotebookWorkspace[] _workspaces;
    private NotebookWorkspace _activeWorkspace;
    private NotebookExecutor _executor;
    private string _workspacesPath;
    private JSONValue _settings;

    // UI Components
    private TabWidget _notebookTabs;
    private Widget _workspacePanel;

    // Signals
    Signal!(NotebookWorkspace) onWorkspaceAdded;
    Signal!(NotebookWorkspace) onWorkspaceRemoved;
    Signal!(NotebookWorkspace) onActiveWorkspaceChanged;
    Signal!(NotebookSession) onNotebookOpened;
    Signal!(NotebookSession) onNotebookClosed;

    this(string workspacesPath = "") {
        if (workspacesPath.length == 0) {
            version(Windows) {
                workspacesPath = buildPath(environment.get("APPDATA", "."), "dnives", "notebooks");
            } else {
                workspacesPath = buildPath(environment.get("HOME", "."), ".dnives", "notebooks");
            }
        }

        _workspacesPath = workspacesPath;
        _executor = new NotebookExecutor();
        _settings = JSONValue.emptyObject;

        // Ensure workspaces directory exists
        if (!exists(_workspacesPath)) {
            try {
                mkdirRecurse(_workspacesPath);
            } catch (Exception e) {
                Log.e("Failed to create workspaces directory: ", e.msg);
            }
        }

        loadSettings();
        loadWorkspaces();

        Log.i("NotebookManager initialized with workspaces at: ", _workspacesPath);
    }

    /**
     * Create and initialize UI components
     */
    void initializeUI(Widget parent) {
        // Create main tab widget for notebooks
        _notebookTabs = new TabWidget("notebook_tabs");
        _notebookTabs.tabClose = delegate(string tabId) {
            closeNotebook(tabId);
        };

        parent.addChild(_notebookTabs);
    }

    /**
     * Get all workspaces
     */
    NotebookWorkspace[] getWorkspaces() {
        return _workspaces.dup;
    }

    /**
     * Get active workspace
     */
    NotebookWorkspace getActiveWorkspace() {
        return _activeWorkspace;
    }

    /**
     * Set active workspace
     */
    void setActiveWorkspace(NotebookWorkspace workspace) {
        if (_activeWorkspace != workspace) {
            _activeWorkspace = workspace;
            onActiveWorkspaceChanged.emit(workspace);
            Log.i("Active workspace changed to: ", workspace ? workspace.name : "none");
        }
    }

    /**
     * Create new workspace
     */
    NotebookWorkspace createWorkspace(string name) {
        string workspacePath = buildPath(_workspacesPath, name);
        auto workspace = new NotebookWorkspace(name, workspacePath);

        _workspaces ~= workspace;

        // Set as active if it's the first workspace
        if (_activeWorkspace is null) {
            setActiveWorkspace(workspace);
        }

        workspace.save();
        onWorkspaceAdded.emit(workspace);

        Log.i("Created new workspace: ", name);
        return workspace;
    }

    /**
     * Load workspace from directory
     */
    NotebookWorkspace loadWorkspace(string path) {
        auto workspace = NotebookWorkspace.load(path);
        if (workspace !is null) {
            _workspaces ~= workspace;
            onWorkspaceAdded.emit(workspace);
            Log.i("Loaded workspace: ", workspace.name);
        }
        return workspace;
    }

    /**
     * Remove workspace
     */
    bool removeWorkspace(NotebookWorkspace workspace) {
        if (workspace is null) return false;

        auto index = _workspaces.countUntil(workspace);
        if (index >= 0) {
            _workspaces = _workspaces[0..index] ~ _workspaces[index+1..$];

            if (_activeWorkspace == workspace) {
                _activeWorkspace = _workspaces.length > 0 ? _workspaces[0] : null;
                onActiveWorkspaceChanged.emit(_activeWorkspace);
            }

            onWorkspaceRemoved.emit(workspace);
            Log.i("Removed workspace: ", workspace.name);
            return true;
        }
        return false;
    }

    /**
     * Create new notebook in active workspace
     */
    NotebookSession createNotebook(string name = "") {
        if (_activeWorkspace is null) {
            auto defaultWorkspace = createWorkspace("Default");
            setActiveWorkspace(defaultWorkspace);
        }

        auto session = _activeWorkspace.createNotebook(name);
        openNotebookInTab(session);
        return session;
    }

    /**
     * Open existing notebook file
     */
    NotebookSession openNotebook(string filePath) {
        try {
            // Check if notebook is already open
            foreach (workspace; _workspaces) {
                foreach (session; workspace.getAllSessions()) {
                    if (session.filePath == filePath) {
                        selectNotebookTab(session.id);
                        return session;
                    }
                }
            }

            // Load into active workspace or create one
            if (_activeWorkspace is null) {
                auto defaultWorkspace = createWorkspace("Default");
                setActiveWorkspace(defaultWorkspace);
            }

            auto session = _activeWorkspace.loadNotebook(filePath);
            openNotebookInTab(session);
            onNotebookOpened.emit(session);
            return session;

        } catch (Exception e) {
            Log.e("Failed to open notebook: ", e.msg);
            return NotebookSession.init;
        }
    }

    /**
     * Save notebook
     */
    bool saveNotebook(string sessionId) {
        auto session = findSession(sessionId);
        if (session !is null && session.notebook !is null) {
            if (session.notebook.save(session.filePath)) {
                session.modified = false;
                updateTabTitle(sessionId);
                return true;
            }
        }
        return false;
    }

    /**
     * Save all modified notebooks
     */
    void saveAllNotebooks() {
        foreach (workspace; _workspaces) {
            foreach (session; workspace.getAllSessions()) {
                if (session.modified && session.notebook !is null) {
                    session.notebook.save(session.filePath);
                    session.modified = false;
                }
            }
        }
        updateAllTabTitles();
        Log.i("Saved all modified notebooks");
    }

    /**
     * Close notebook
     */
    bool closeNotebook(string sessionId) {
        auto session = findSession(sessionId);
        if (session is null) return false;

        // Check if notebook has unsaved changes
        if (session.modified) {
            // In a real implementation, show save dialog
            // For now, just save automatically
            saveNotebook(sessionId);
        }

        // Remove from tabs
        if (_notebookTabs !is null) {
            _notebookTabs.removeTab(sessionId);
        }

        // Remove from workspace
        foreach (workspace; _workspaces) {
            if (workspace.removeSession(sessionId)) {
                onNotebookClosed.emit(*session);
                Log.i("Closed notebook: ", session.notebook.name);
                return true;
            }
        }

        return false;
    }

    /**
     * Execute all cells in active notebook
     */
    void executeActiveNotebook() {
        auto activeSession = getActiveSession();
        if (activeSession !is null && activeSession.notebook !is null) {
            _executor.executeNotebook(activeSession.notebook);
        }
    }

    /**
     * Clear all outputs in active notebook
     */
    void clearActiveNotebookOutputs() {
        auto activeSession = getActiveSession();
        if (activeSession !is null && activeSession.notebook !is null) {
            _executor.clearAllOutputs(activeSession.notebook);
        }
    }

    /**
     * Export notebook to different formats
     */
    bool exportNotebook(string sessionId, string format, string outputPath) {
        auto session = findSession(sessionId);
        if (session is null || session.notebook is null) return false;

        try {
            switch (format.toLower) {
                case "livemd":
                    auto content = session.notebook.toLiveMD();
                    std.file.write(outputPath, content);
                    break;

                case "json":
                    auto json = session.notebook.toJSON();
                    std.file.write(outputPath, json.toPrettyString());
                    break;

                default:
                    Log.e("Unsupported export format: ", format);
                    return false;
            }

            Log.i("Exported notebook to: ", outputPath);
            return true;
        } catch (Exception e) {
            Log.e("Failed to export notebook: ", e.msg);
            return false;
        }
    }

    /**
     * Get notebook statistics across all workspaces
     */
    struct ManagerStats {
        size_t totalWorkspaces;
        size_t totalNotebooks;
        size_t modifiedNotebooks;
        size_t totalCells;
        size_t executedCells;
        SysTime lastActivity;
    }

    ManagerStats getStats() {
        ManagerStats stats;
        stats.totalWorkspaces = _workspaces.length;
        stats.lastActivity = SysTime.min;

        foreach (workspace; _workspaces) {
            auto wsStats = workspace.getStats();
            stats.totalNotebooks += wsStats.totalNotebooks;
            stats.modifiedNotebooks += wsStats.modifiedNotebooks;
            stats.totalCells += wsStats.totalCells;
            stats.executedCells += wsStats.executedCells;

            if (wsStats.lastActivity > stats.lastActivity) {
                stats.lastActivity = wsStats.lastActivity;
            }
        }

        return stats;
    }

    private void loadSettings() {
        try {
            string settingsPath = buildPath(_workspacesPath, "settings.json");
            if (exists(settingsPath)) {
                auto content = cast(string)std.file.read(settingsPath);
                _settings = parseJSON(content);
            }
        } catch (Exception e) {
            Log.w("Failed to load notebook settings: ", e.msg);
            _settings = JSONValue.emptyObject;
        }
    }

    private void saveSettings() {
        try {
            string settingsPath = buildPath(_workspacesPath, "settings.json");
            std.file.write(settingsPath, _settings.toPrettyString());
        } catch (Exception e) {
            Log.e("Failed to save notebook settings: ", e.msg);
        }
    }

    private void loadWorkspaces() {
        try {
            if (!exists(_workspacesPath)) return;

            foreach (DirEntry entry; dirEntries(_workspacesPath, SpanMode.shallow)) {
                if (entry.isDir) {
                    auto workspace = loadWorkspace(entry.name);
                    if (workspace !is null && _activeWorkspace is null) {
                        setActiveWorkspace(workspace);
                    }
                }
            }

            // Create default workspace if none exist
            if (_workspaces.length == 0) {
                auto defaultWorkspace = createWorkspace("Default");
                setActiveWorkspace(defaultWorkspace);
            }

        } catch (Exception e) {
            Log.e("Failed to load workspaces: ", e.msg);
        }
    }

    private void openNotebookInTab(NotebookSession session) {
        if (_notebookTabs is null) return;

        auto tab = _notebookTabs.addTab(session.widget, session.notebook.name.to!dstring, null, true);
        _notebookTabs.selectTab(session.id);

        // Connect notebook change signal to update tab title
        session.widget.onNotebookChanged.connect(() {
            session.modified = true;
            updateTabTitle(session.id);
        });
    }

    private void selectNotebookTab(string sessionId) {
        if (_notebookTabs !is null) {
            _notebookTabs.selectTab(sessionId);
        }
    }

    private void updateTabTitle(string sessionId) {
        auto session = findSession(sessionId);
        if (session !is null && _notebookTabs !is null) {
            string title = session.notebook.name;
            if (session.modified) {
                title ~= " *";
            }
            _notebookTabs.renameTab(sessionId, title.to!dstring);
        }
    }

    private void updateAllTabTitles() {
        foreach (workspace; _workspaces) {
            foreach (session; workspace.getAllSessions()) {
                updateTabTitle(session.id);
            }
        }
    }

    private NotebookSession* findSession(string sessionId) {
        foreach (workspace; _workspaces) {
            auto session = workspace.getSession(sessionId);
            if (session !is null) {
                return session;
            }
        }
        return null;
    }

    private NotebookSession* getActiveSession() {
        if (_notebookTabs is null) return null;

        string activeTabId = _notebookTabs.selectedTabId;
        return findSession(activeTabId);
    }
}

/**
 * Notebook template system for creating common notebook types
 */
class NotebookTemplates {
    static Notebook createDataAnalysisTemplate() {
        auto notebook = new Notebook("Data Analysis Notebook");

        notebook.sections()[0].cells()[0].source =
            "# Data Analysis Notebook\n\n" ~
            "This notebook template provides a structured approach to data analysis using D.\n\n" ~
            "## Sections:\n" ~
            "1. **Data Loading** - Import and load your datasets\n" ~
            "2. **Data Exploration** - Examine data structure and statistics\n" ~
            "3. **Data Visualization** - Create charts and plots\n" ~
            "4. **Analysis** - Perform statistical analysis\n" ~
            "5. **Results** - Document findings and conclusions";

        // Add sections with sample code
        auto loadingSection = new NotebookSection("Data Loading", 2);
        auto loadingCell = new NotebookCell(CellType.Code,
            "import std.csv;\n" ~
            "import std.stdio;\n" ~
            "import std.array;\n\n" ~
            "// Load CSV data\n" ~
            "auto records = File(\"data.csv\").byLine\n" ~
                "    .map!(line => line.splitter(',').array)\n" ~
                "    .array;\n\n" ~
                "writeln(\"Loaded \", records.length, \" records\");");
        loadingSection.addCell(loadingCell);
        notebook.addSection(loadingSection);

        return notebook;
    }

    static Notebook createChartingTemplate() {
        auto notebook = new Notebook("Data Charting Notebook");

        // Set name and metadata
        notebook.metadata["author"] = "Dnives Charting Engine";
        notebook.metadata["tags"] = JSONValue(["charting", "visualization", "data-viz"]);

        // Introduction Section
        auto introSection = new NotebookSection("Charting Introduction", 1);
        introSection.addCell(new NotebookCell(CellType.Markdown, 
            "# Data Charting & Visualization\n\n" ~
            "This notebook is optimized for creating visual representations of data. " ~
            "It includes presets for common chart types and data structures used in Astroloper.\n\n" ~
            "### Available Visualizers:\n" ~
            "- **Line Charts** - For temporal data\n" ~
            "- **Radial Charts** - For cyclical/astro data\n" ~
            "- **Bar Charts** - For comparative analysis"));
        notebook.addSection(introSection);

        // Data Preparation Section
        auto dataSection = new NotebookSection("Data Preparation", 2);
        dataSection.addCell(new NotebookCell(CellType.Code, 
            "import std.stdio;\nimport std.algorithm;\n\n" ~
            "void main() {\n" ~
            "    // Sample data for charting\n" ~
            "    auto data = [10, 25, 15, 30, 20];\n" ~
            "    writeln(\"Data prepared for visualization: \", data);\n" ~
            "}"));
        notebook.addSection(dataSection);

        // Visualization Section
        auto vizSection = new NotebookSection("Visualization", 2);
        vizSection.addCell(new NotebookCell(CellType.Code, 
            "// TODO: Integrate with dcore.viz for rendering\n" ~
            "void main() {\n" ~
            "    writeln(\"🚀 Rendering chart...\");\n" ~
            "}"));
        notebook.addSection(vizSection);

        return notebook;
    }

    static Notebook createAlgorithmNotebook() {
        auto notebook = new Notebook("Algorithm Development");

        notebook.sections()[0].cells()[0].source =
            "# Algorithm Development Notebook\n\n" ~
            "Use this template to develop, test, and document algorithms in D.\n\n" ~
            "## Structure:\n" ~
            "- **Problem Definition** - Describe the problem to solve\n" ~
            "- **Algorithm Design** - Plan your approach\n" ~
            "- **Implementation** - Code the solution\n" ~
            "- **Testing** - Verify correctness\n" ~
            "- **Performance Analysis** - Measure and optimize";

        return notebook;
    }

    static Notebook createLearningNotebook() {
        auto notebook = new Notebook("D Language Learning");

        notebook.sections()[0].cells()[0].source =
            "# D Language Learning Notebook\n\n" ~
            "Interactive learning environment for the D programming language.\n\n" ~
            "Try running the code examples and experiment with modifications!";

        auto section = new NotebookSection("Basic Syntax", 2);
        auto cell = new NotebookCell(CellType.Code,
            "import std.stdio;\n\n" ~
            "void main() {\n" ~
            "    writeln(\"Hello, D!\");\n" ~
            "    \n" ~
            "    // Variables and types\n" ~
            "    int x = 42;\n" ~
            "    string message = \"D is awesome!\";\n" ~
            "    \n" ~
            "    writeln(\"x = \", x);\n" ~
            "    writeln(message);\n" ~
            "}");
        section.addCell(cell);
        notebook.addSection(section);

        return notebook;
    }
}
