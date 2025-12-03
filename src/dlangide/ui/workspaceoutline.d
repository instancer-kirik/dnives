module dlangide.ui.workspaceoutline;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.tree;
import dlangui.widgets.editors;
import dlangui.widgets.menu;
import dlangui.widgets.popup;
import dlangui.core.events;
import dlangui.core.signals;
import dlangui.graphics.drawbuf;
import dlangui.graphics.resources;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.utf;
import std.json;
import std.stdio;
import std.regex;
import std.typecons;
import std.datetime;
import std.format;
import std.process;

import dcore.core;
import dcore.vault.workspace;
import dlangide.ui.inlinediffeditor;
import dlangide.ui.fileoutline;

/// Represents a workspace item (project, folder, file, etc.)
struct WorkspaceItem {
    string name;               // Display name
    string path;               // Full file system path
    WorkspaceItemType type;    // Type of item
    WorkspaceItem[] children;  // Child items
    WorkspaceItem* parent;     // Parent item

    // Additional metadata
    string description;        // Project description
    string version_;           // Version string
    string[] dependencies;     // Dependencies list
    string buildSystem;        // Build system (dub, cmake, etc.)
    bool isExpanded;          // UI expansion state
    bool hasChanges;          // Has uncommitted changes
    bool hasConflicts;        // Has merge conflicts
    int fileCount;            // Total files in subtree
    long totalSize;           // Total size in bytes
    SysTime lastModified;     // Last modification time

    // Status indicators
    BuildStatus buildStatus;   // Build status
    VCSStatus vcsStatus;      // Version control status
    TestStatus testStatus;    // Test status
    double health;            // Code health score (0.0-1.0)
}

/// Types of workspace items
enum WorkspaceItemType {
    Workspace,      // Root workspace
    Project,        // Individual project
    Folder,         // Directory
    File,           // Regular file
    SourceFile,     // Source code file
    TestFile,       // Test file
    ConfigFile,     // Configuration file
    BuildFile,      // Build script/config
    Documentation,  // Documentation file
    Resource,       // Resource file (images, etc.)
    Dependency,     // External dependency
    VirtualFolder,  // Virtual grouping folder
    GitSubmodule,   // Git submodule
    Link,          // Symbolic link
    Unknown
}

/// Build status for projects
enum BuildStatus {
    Unknown,
    Success,
    Failed,
    InProgress,
    Warning,
    Skipped
}

/// Version control status
enum VCSStatus {
    Unknown,
    Clean,
    Modified,
    Added,
    Deleted,
    Renamed,
    Conflicted,
    Untracked,
    Ignored
}

/// Test status for projects/files
enum TestStatus {
    Unknown,
    Passed,
    Failed,
    Running,
    Skipped,
    NoTests
}

/// Configuration for workspace outline
struct WorkspaceConfig {
    bool showHiddenFiles = false;
    bool showDependencies = true;
    bool showTestFiles = true;
    bool showBuildFiles = true;
    bool showVirtualFolders = true;
    bool groupByType = false;
    bool sortAlphabetically = true;
    bool showFileIcons = true;
    bool showLineCount = false;
    bool showFileSize = false;
    bool showModificationTime = false;
    bool autoRefresh = true;
    int refreshInterval = 5000; // milliseconds
    string[] excludePatterns = [".git", ".dub", "node_modules", "*.o", "*.obj"];
    string[] includePatterns = ["*.d", "*.di", "*.py", "*.js", "*.ts", "*.c", "*.cpp", "*.h"];
}

/// Workspace outline widget providing hierarchical project/file view
class WorkspaceOutlineWidget : VerticalLayout {
    private {
        // UI Components
        HorizontalLayout _toolbar;
        TreeWidget _workspaceTree;
        ScrollWidget _scrollArea;

        // Toolbar controls
        Button _refreshBtn;
        Button _expandAllBtn;
        Button _collapseAllBtn;
        Button _newProjectBtn;
        Button _newFolderBtn;
        Button _newFileBtn;
        Button _settingsBtn;
        ComboBox _viewModeCombo;
        EditLine _searchField;

        // Data
        WorkspaceItem _rootItem;
        WorkspaceItem[] _filteredItems;
        WorkspaceConfig _config;
        DCore _dcore;

        // Search and filtering
        string _searchQuery;
        bool _caseSensitiveSearch = false;

        // File system watchers
        bool _watchingFileSystem = false;
        SysTime _lastRefreshTime;

        // Context menus
        Menu _fileContextMenu;
        Menu _folderContextMenu;
        Menu _projectContextMenu;

        // Drag and drop support
        bool _supportDragDrop = true;
    }

    // Events
    Signal!(WorkspaceItem) onItemSelected;
    Signal!(WorkspaceItem) onItemDoubleClicked;
    Signal!(WorkspaceItem) onItemRightClicked;
    Signal!(string) onFileOpened;
    Signal!(string) onProjectOpened;
    Signal!(WorkspaceItem, WorkspaceItem) onItemMoved;
    Signal!(WorkspaceItem, string) onItemRenamed;
    Signal!(WorkspaceItem) onItemDeleted;

    this(DCore dcore) {
        super("workspaceOutline");
        _dcore = dcore;
        _config = WorkspaceConfig();

        createUI();
        setupEventHandlers();
        createContextMenus();
        initializeWorkspace();
    }

    private void createUI() {
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        margins = Rect(4, 4, 4, 4);

        // Create toolbar
        createToolbar();
        addChild(_toolbar);

        // Create tree view
        createWorkspaceTree();

        // Wrap tree in scroll area
        _scrollArea = new ScrollWidget("workspaceScroll");
        _scrollArea.layoutWidth = FILL_PARENT;
        _scrollArea.layoutHeight = FILL_PARENT;
        _scrollArea.contentWidget = _workspaceTree;
        addChild(_scrollArea);
    }

    private void createToolbar() {
        _toolbar = new HorizontalLayout("workspaceToolbar");
        _toolbar.layoutWidth = FILL_PARENT;
        _toolbar.layoutHeight = WRAP_CONTENT;
        _toolbar.backgroundColor = 0xFFF0F0F0;
        _toolbar.padding = Rect(2, 2, 2, 2);

        // Refresh button
        _refreshBtn = new Button("refresh", "🔄"d);
        _refreshBtn.tooltipText = "Refresh workspace"d;
        _refreshBtn.minWidth = 30;
        _toolbar.addChild(_refreshBtn);

        // Expand/Collapse buttons
        _expandAllBtn = new Button("expandAll", "⊞"d);
        _expandAllBtn.tooltipText = "Expand all"d;
        _expandAllBtn.minWidth = 30;
        _toolbar.addChild(_expandAllBtn);

        _collapseAllBtn = new Button("collapseAll", "⊟"d);
        _collapseAllBtn.tooltipText = "Collapse all"d;
        _collapseAllBtn.minWidth = 30;
        _toolbar.addChild(_collapseAllBtn);

        // Add separator
        Widget separator = new Widget("sep1");
        separator.minWidth = 5;
        _toolbar.addChild(separator);

        // New item buttons
        _newProjectBtn = new Button("newProject", "📁+"d);
        _newProjectBtn.tooltipText = "New project"d;
        _newProjectBtn.minWidth = 30;
        _toolbar.addChild(_newProjectBtn);

        _newFolderBtn = new Button("newFolder", "📂+"d);
        _newFolderBtn.tooltipText = "New folder"d;
        _newFolderBtn.minWidth = 30;
        _toolbar.addChild(_newFolderBtn);

        _newFileBtn = new Button("newFile", "📄+"d);
        _newFileBtn.tooltipText = "New file"d;
        _newFileBtn.minWidth = 30;
        _toolbar.addChild(_newFileBtn);

        // View mode combo
        _viewModeCombo = new ComboBox("viewMode",
            ["Tree View"d, "List View"d, "By Type"d, "By Status"d]);
        _viewModeCombo.minWidth = 100;
        _toolbar.addChild(_viewModeCombo);

        // Search field
        _searchField = new EditLine("search");
        _searchField.hint = "Search files..."d;
        _searchField.layoutWidth = FILL_PARENT;
        _toolbar.addChild(_searchField);

        // Settings button
        _settingsBtn = new Button("settings", "⚙"d);
        _settingsBtn.tooltipText = "Workspace settings"d;
        _settingsBtn.minWidth = 30;
        _toolbar.addChild(_settingsBtn);
    }

    private void createWorkspaceTree() {
        _workspaceTree = new TreeWidget("workspaceTree");
        _workspaceTree.layoutWidth = FILL_PARENT;
        _workspaceTree.layoutHeight = FILL_PARENT;

        // Configure tree appearance
        _workspaceTree.showRoot = true;
        _workspaceTree.allowMultipleSelection = true;
        _workspaceTree.enableDragAndDrop = _supportDragDrop;
    }

    private void setupEventHandlers() {
        // Toolbar button handlers
        _refreshBtn.click = delegate(Widget source) {
            refreshWorkspace();
            return true;
        };

        _expandAllBtn.click = delegate(Widget source) {
            expandAll();
            return true;
        };

        _collapseAllBtn.click = delegate(Widget source) {
            collapseAll();
            return true;
        };

        _newProjectBtn.click = delegate(Widget source) {
            createNewProject();
            return true;
        };

        _newFolderBtn.click = delegate(Widget source) {
            createNewFolder();
            return true;
        };

        _newFileBtn.click = delegate(Widget source) {
            createNewFile();
            return true;
        };

        _settingsBtn.click = delegate(Widget source) {
            showSettingsDialog();
            return true;
        };

        // View mode combo handler
        _viewModeCombo.onSelectionChange = delegate(Widget source, int itemIndex) {
            updateViewMode(itemIndex);
            return true;
        };

        // Search field handler
        _searchField.onContentChange = delegate(EditableContent source) {
            _searchQuery = _searchField.text.toUTF8();
            filterWorkspace();
            return true;
        };

        // Tree selection handler
        _workspaceTree.onItemSelected = delegate(TreeWidget source, TreeItem item) {
            if (item && item.tag) {
                auto workspaceItem = cast(WorkspaceItem*)item.tag;
                if (workspaceItem && onItemSelected.assigned) {
                    onItemSelected(*workspaceItem);
                }
            }
            return true;
        };

        // Tree double-click handler
        _workspaceTree.onItemDoubleClicked = delegate(TreeWidget source, TreeItem item) {
            if (item && item.tag) {
                auto workspaceItem = cast(WorkspaceItem*)item.tag;
                if (workspaceItem) {
                    handleItemDoubleClick(*workspaceItem);
                }
            }
            return true;
        };

        // Tree right-click handler
        _workspaceTree.onItemRightClicked = delegate(TreeWidget source, TreeItem item) {
            if (item && item.tag) {
                auto workspaceItem = cast(WorkspaceItem*)item.tag;
                if (workspaceItem) {
                    showContextMenu(*workspaceItem);
                }
            }
            return true;
        };
    }

    private void createContextMenus() {
        // File context menu
        _fileContextMenu = new Menu();
        _fileContextMenu.addItem(new Action(1001, "Open"d, "document-open"d));
        _fileContextMenu.addItem(new Action(1002, "Open With..."d));
        _fileContextMenu.addSeparator();
        _fileContextMenu.addItem(new Action(1003, "Show Diff"d, "diff"d));
        _fileContextMenu.addItem(new Action(1004, "Show History"d, "history"d));
        _fileContextMenu.addSeparator();
        _fileContextMenu.addItem(new Action(1005, "Rename"d, "edit"d));
        _fileContextMenu.addItem(new Action(1006, "Delete"d, "delete"d));
        _fileContextMenu.addItem(new Action(1007, "Properties"d, "properties"d));

        // Folder context menu
        _folderContextMenu = new Menu();
        _folderContextMenu.addItem(new Action(2001, "New File"d, "document-new"d));
        _folderContextMenu.addItem(new Action(2002, "New Folder"d, "folder-new"d));
        _folderContextMenu.addSeparator();
        _folderContextMenu.addItem(new Action(2003, "Add Existing File..."d));
        _folderContextMenu.addItem(new Action(2004, "Import Project..."d));
        _folderContextMenu.addSeparator();
        _folderContextMenu.addItem(new Action(2005, "Open in Terminal"d, "terminal"d));
        _folderContextMenu.addItem(new Action(2006, "Open in File Manager"d, "folder"d));
        _folderContextMenu.addSeparator();
        _folderContextMenu.addItem(new Action(2007, "Rename"d, "edit"d));
        _folderContextMenu.addItem(new Action(2008, "Delete"d, "delete"d));

        // Project context menu
        _projectContextMenu = new Menu();
        _projectContextMenu.addItem(new Action(3001, "Build"d, "build"d));
        _projectContextMenu.addItem(new Action(3002, "Rebuild"d, "rebuild"d));
        _projectContextMenu.addItem(new Action(3003, "Clean"d, "clean"d));
        _projectContextMenu.addItem(new Action(3004, "Run"d, "run"d));
        _projectContextMenu.addItem(new Action(3005, "Debug"d, "debug"d));
        _projectContextMenu.addItem(new Action(3006, "Test"d, "test"d));
        _projectContextMenu.addSeparator();
        _projectContextMenu.addItem(new Action(3007, "Dependencies"d, "dependencies"d));
        _projectContextMenu.addItem(new Action(3008, "Properties"d, "properties"d));
        _projectContextMenu.addSeparator();
        _projectContextMenu.addItem(new Action(3009, "Close Project"d, "close"d));
    }

    private void initializeWorkspace() {
        if (_dcore && _dcore.vault && _dcore.vault.getCurrentWorkspace()) {
            loadWorkspaceFromVault();
        } else {
            createEmptyWorkspace();
        }
    }

    /// Load workspace from DCore vault
    void loadWorkspaceFromVault() {
        if (!_dcore || !_dcore.vault) {
            createEmptyWorkspace();
            return;
        }

        auto workspace = _dcore.vault.getCurrentWorkspace();
        if (!workspace) {
            createEmptyWorkspace();
            return;
        }

        _rootItem = WorkspaceItem();
        _rootItem.name = workspace.getName();
        _rootItem.path = workspace.getPath();
        _rootItem.type = WorkspaceItemType.Workspace;

        try {
            // Scan workspace directory
            scanDirectory(_rootItem.path, _rootItem);

            // Load project information
            loadProjectInfo(_rootItem);

            // Update tree display
            updateTreeDisplay();

            _lastRefreshTime = Clock.currTime();
            writeln("Loaded workspace: ", _rootItem.name);

        } catch (Exception e) {
            writeln("Error loading workspace: ", e.msg);
            createEmptyWorkspace();
        }
    }

    /// Create empty workspace structure
    void createEmptyWorkspace() {
        _rootItem = WorkspaceItem();
        _rootItem.name = "Empty Workspace";
        _rootItem.type = WorkspaceItemType.Workspace;

        updateTreeDisplay();
    }

    /// Refresh workspace from file system
    void refreshWorkspace() {
        if (_rootItem.path.length > 0 && exists(_rootItem.path)) {
            // Clear existing children
            _rootItem.children.length = 0;

            // Rescan directory
            scanDirectory(_rootItem.path, _rootItem);
            loadProjectInfo(_rootItem);

            // Update display
            updateTreeDisplay();

            _lastRefreshTime = Clock.currTime();
            writeln("Refreshed workspace");
        }
    }

    private void scanDirectory(string dirPath, ref WorkspaceItem parentItem) {
        if (!exists(dirPath) || !isDir(dirPath)) return;

        try {
            foreach (DirEntry entry; dirEntries(dirPath, SpanMode.shallow)) {
                if (shouldExcludeItem(entry.name)) continue;

                WorkspaceItem item;
                item.name = baseName(entry.name);
                item.path = entry.name;
                item.parent = &parentItem;
                item.lastModified = entry.timeLastModified;

                if (entry.isDir) {
                    item.type = determineDirectoryType(entry.name);

                    // Recursively scan subdirectories
                    if (item.type != WorkspaceItemType.VirtualFolder) {
                        scanDirectory(entry.name, item);
                    }

                    // Calculate folder statistics
                    item.fileCount = countFiles(item);
                    item.totalSize = calculateTotalSize(item);
                } else {
                    item.type = determineFileType(entry.name);
                    item.totalSize = entry.size;
                    item.fileCount = 1;
                }

                // Determine VCS status
                item.vcsStatus = getVCSStatus(entry.name);

                // Calculate health score
                item.health = calculateItemHealth(item);

                parentItem.children ~= item;
            }
        } catch (Exception e) {
            writeln("Error scanning directory ", dirPath, ": ", e.msg);
        }
    }

    private WorkspaceItemType determineDirectoryType(string dirPath) {
        string baseName = baseName(dirPath);

        // Check for special directories
        if (baseName == ".git") return WorkspaceItemType.VirtualFolder;
        if (baseName == "node_modules") return WorkspaceItemType.Dependency;
        if (baseName.endsWith(".dub")) return WorkspaceItemType.VirtualFolder;

        // Check for project markers
        if (exists(buildPath(dirPath, "dub.json")) ||
            exists(buildPath(dirPath, "dub.sdl")) ||
            exists(buildPath(dirPath, "package.json")) ||
            exists(buildPath(dirPath, "CMakeLists.txt")) ||
            exists(buildPath(dirPath, "Makefile"))) {
            return WorkspaceItemType.Project;
        }

        return WorkspaceItemType.Folder;
    }

    private WorkspaceItemType determineFileType(string filePath) {
        string ext = extension(filePath).toLower();
        string baseName = baseName(filePath).toLower();

        // Source files
        if ([".d", ".di", ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp",
             ".py", ".js", ".ts", ".rs", ".go", ".java", ".cs"].canFind(ext)) {
            return WorkspaceItemType.SourceFile;
        }

        // Test files
        if (baseName.canFind("test") || baseName.canFind("spec") ||
            filePath.canFind("/test/") || filePath.canFind("\\test\\")) {
            return WorkspaceItemType.TestFile;
        }

        // Build files
        if (["dub.json", "dub.sdl", "package.json", "makefile", "cmakelist.txt",
             "build.gradle", "pom.xml", "cargo.toml"].canFind(baseName) ||
            [".mk", ".cmake"].canFind(ext)) {
            return WorkspaceItemType.BuildFile;
        }

        // Config files
        if ([".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".config"].canFind(ext) ||
            ["config", "settings", ".env"].canFind(baseName)) {
            return WorkspaceItemType.ConfigFile;
        }

        // Documentation
        if ([".md", ".txt", ".rst", ".adoc"].canFind(ext) ||
            ["readme", "changelog", "license", "authors"].canFind(baseName)) {
            return WorkspaceItemType.Documentation;
        }

        // Resources
        if ([".png", ".jpg", ".jpeg", ".gif", ".bmp", ".svg", ".ico",
             ".wav", ".mp3", ".ogg", ".flac"].canFind(ext)) {
            return WorkspaceItemType.Resource;
        }

        return WorkspaceItemType.File;
    }

    private bool shouldExcludeItem(string itemPath) {
        string baseName = baseName(itemPath);

        // Check exclude patterns
        foreach (pattern; _config.excludePatterns) {
            if (globMatch(baseName, pattern)) {
                return true;
            }
        }

        // Check if hidden files should be excluded
        if (!_config.showHiddenFiles && baseName.startsWith(".")) {
            return true;
        }

        return false;
    }

    private void loadProjectInfo(ref WorkspaceItem item) {
        foreach (ref child; item.children) {
            if (child.type == WorkspaceItemType.Project) {
                loadSingleProjectInfo(child);
            }

            // Recursively process children
            loadProjectInfo(child);
        }
    }

    private void loadSingleProjectInfo(ref WorkspaceItem project) {
        // Try to load DUB project info
        string dubJson = buildPath(project.path, "dub.json");
        string dubSdl = buildPath(project.path, "dub.sdl");

        if (exists(dubJson)) {
            loadDubProjectInfo(project, dubJson);
        } else if (exists(dubSdl)) {
            loadDubSdlProjectInfo(project, dubSdl);
        }

        // Try to load other project types
        string packageJson = buildPath(project.path, "package.json");
        if (exists(packageJson)) {
            loadNodeProjectInfo(project, packageJson);
        }

        // Get build status
        project.buildStatus = getBuildStatus(project.path);
        project.testStatus = getTestStatus(project.path);
    }

    private void loadDubProjectInfo(ref WorkspaceItem project, string dubJsonPath) {
        try {
            string content = readText(dubJsonPath);
            JSONValue json = parseJSON(content);

            if ("name" in json) {
                project.name = json["name"].str;
            }
            if ("description" in json) {
                project.description = json["description"].str;
            }
            if ("version" in json) {
                project.version_ = json["version"].str;
            }

            // Load dependencies
            if ("dependencies" in json) {
                foreach (key, value; json["dependencies"].object) {
                    project.dependencies ~= key;
                }
            }

            project.buildSystem = "DUB";

        } catch (Exception e) {
            writeln("Error parsing dub.json: ", e.msg);
        }
    }

    private void loadDubSdlProjectInfo(ref WorkspaceItem project, string dubSdlPath) {
        try {
            string content = readText(dubSdlPath);
            // Simple SDL parsing - would need proper parser for production
            auto lines = content.splitLines();

            foreach (line; lines) {
                string trimmed = line.strip();
                if (trimmed.startsWith("name ")) {
                    auto parts = trimmed.split();
                    if (parts.length > 1) {
                        project.name = parts[1].strip(`"`);
                    }
                } else if (trimmed.startsWith("description ")) {
                    project.description = trimmed["description ".length..$].strip(`"`);
                }
            }

            project.buildSystem = "DUB";

        } catch (Exception e) {
            writeln("Error parsing dub.sdl: ", e.msg);
        }
    }

    private void loadNodeProjectInfo(ref WorkspaceItem project, string packageJsonPath) {
        try {
            string content = readText(packageJsonPath);
            JSONValue json = parseJSON(content);

            if ("name" in json) {
                project.name = json["name"].str;
            }
            if ("description" in json) {
                project.description = json["description"].str;
            }
            if ("version" in json) {
                project.version_ = json["version"].str;
            }

            project.buildSystem = "NPM";

        } catch (Exception e) {
            writeln("Error parsing package.json: ", e.msg);
        }
    }

    private VCSStatus getVCSStatus(string itemPath) {
        // Simple Git status check - would need proper Git integration
        string gitDir = findGitDirectory(itemPath);
        if (gitDir.empty) return VCSStatus.Unknown;

        // For now, return a default status
        return VCSStatus.Clean;
    }

    private string findGitDirectory(string startPath) {
        string currentPath = startPath;

        while (currentPath.length > 1) {
            string gitPath = buildPath(currentPath, ".git");
            if (exists(gitPath)) {
                return gitPath;
            }
            currentPath = dirName(currentPath);
        }

        return "";
    }

    private BuildStatus getBuildStatus(string projectPath) {
        // Check for build artifacts or status files
        if (exists(buildPath(projectPath, ".dub", "build"))) {
            return BuildStatus.Success;
        }

        return BuildStatus.Unknown;
    }

    private TestStatus getTestStatus(string projectPath) {
        // Check for test results or configuration
        if (exists(buildPath(projectPath, "test"))) {
            return TestStatus.Passed;
        }

        return TestStatus.NoTests;
    }

    private int countFiles(WorkspaceItem item) {
        int count = item.type != WorkspaceItemType.Folder &&
                   item.type != WorkspaceItemType.Project ? 1 : 0;

        foreach (child; item.children) {
            count += countFiles(child);
        }

        return count;
    }

    private long calculateTotalSize(WorkspaceItem item) {
        long size = item.totalSize;

        foreach (child; item.children) {
            size += calculateTotalSize(child);
        }

        return size;
    }

    private double calculateItemHealth(WorkspaceItem item) {
        double health = 0.5; // Base health score

        // Boost health for well-structured projects
        if (item.type == WorkspaceItemType.Project) {
            if (!item.description.empty) health += 0.1;
            if (!item.version_.empty) health += 0.1;
            if (item.dependencies.length > 0) health += 0.1;
        }

        // Reduce health for problematic indicators
        if (item.vcsStatus == VCSStatus.Conflicted) health -= 0.3;
        if (item.buildStatus == BuildStatus.Failed) health -= 0.2;

        return clamp(health, 0.0, 1.0);
    }

    private void handleItemDoubleClick(WorkspaceItem item) {
        final switch (item.type) {
            case WorkspaceItemType.File:
            case WorkspaceItemType.SourceFile:
            case WorkspaceItemType.TestFile:
            case WorkspaceItemType.ConfigFile:
            case WorkspaceItemType.Documentation:
                if (onFileOpened.assigned) {
                    onFileOpened(item.path);
                }
                break;

            case WorkspaceItemType.Project:
                if (onProjectOpened.assigned) {
                    onProjectOpened(item.path);
                }
                break;

            case WorkspaceItemType.Folder:
            case WorkspaceItemType.VirtualFolder:
                // Toggle expansion
                item.isExpanded = !item.isExpanded;
                updateTreeDisplay();
                break;

            case WorkspaceItemType.Workspace:
            case WorkspaceItemType.BuildFile:
            case WorkspaceItemType.Resource:
            case WorkspaceItemType.Dependency:
            case WorkspaceItemType.GitSubmodule:
            case WorkspaceItemType.Link:
            case WorkspaceItemType.Unknown:
                // Do nothing or show properties
                break;
        }

        if (onItemDoubleClicked.assigned) {
            onItemDoubleClicked(item);
        }
    }

    private void showContextMenu(WorkspaceItem item) {
        Menu contextMenu;

        final switch (item.type) {
            case WorkspaceItemType.File:
            case WorkspaceItemType.SourceFile:
            case WorkspaceItemType.TestFile:
            case WorkspaceItemType.ConfigFile:
            case WorkspaceItemType.Documentation:
            case WorkspaceItemType.BuildFile:
            case WorkspaceItemType.Resource:
                contextMenu = _fileContextMenu;
                break;

            case WorkspaceItemType.Project:
                contextMenu = _projectContextMenu;
                break;

            case WorkspaceItemType.Folder:
            case WorkspaceItemType.VirtualFolder:
            case WorkspaceItemType.Workspace:
                contextMenu = _folderContextMenu;
                break;

            case WorkspaceItemType.Dependency:
            case WorkspaceItemType.GitSubmodule:
            case WorkspaceItemType.Link:
            case WorkspaceItemType.Unknown:
                contextMenu = _fileContextMenu; // Default to file menu
                break;
        }

        if (contextMenu) {
            // Show context menu at cursor position
            // contextMenu.show(Platform.instance.mousePosition);
        }

        if (onItemRightClicked.assigned) {
            onItemRightClicked(item);
        }
    }

    private void filterWorkspace() {
        if (_searchQuery.empty) {
            _filteredItems = [_rootItem];
        } else {
            _filteredItems = filterItemsRecursive([_rootItem]);
        }

        updateTreeDisplay();
    }

    private WorkspaceItem[] filterItemsRecursive(WorkspaceItem[] items) {
        WorkspaceItem[] filtered;

        foreach (item; items) {
            bool include = false;

            // Check if item name matches search
            string searchLower = _caseSensitiveSearch ? _searchQuery : _searchQuery.toLower();
            string itemName = _caseSensitiveSearch ? item.name : item.name.toLower();

            if (itemName.canFind(searchLower)) {
                include = true;
            }

            // Check if any children match
            auto filteredChildren = filterItemsRecursive(item.children);
            if (!filteredChildren.empty) {
                include = true;
                // Update item with filtered children
                WorkspaceItem filteredItem = item;
                filteredItem.children = filteredChildren;
                filtered ~= filteredItem;
            } else if (include) {
                filtered ~= item;
            }
        }

        return filtered;
    }

    private void updateTreeDisplay() {
        _workspaceTree.clearAllItems();

        foreach (ref item; _filteredItems) {
            auto treeItem = createTreeItem(item);
            _workspaceTree.addChild(treeItem);
        }
    }

    private TreeItem createTreeItem(ref WorkspaceItem item) {
        auto treeItem = new TreeItem(generateItemText(item).toUTF32());
        treeItem.tag = &item;

        // Set icon based on item type
        treeItem.iconId = getItemIcon(item.type);

        // Set text color based on status
        if (item.hasConflicts) {
            treeItem.textColor = 0xFFFF0000; // Red for conflicts
        } else if (item.hasChanges) {
            treeItem.textColor = 0xFFFF6600; // Orange for changes
        } else if (item.health < 0.5) {
            treeItem.textColor = 0xFFCC6600; // Dark orange for low health
        }

        // Add children recursively
        foreach (ref child; item.children) {
            auto childItem = createTreeItem(child);
            treeItem.addChild(childItem);
        }

        // Set expansion state
        treeItem.expanded = item.isExpanded;

        return treeItem;
    }

    private string generateItemText(WorkspaceItem item) {
        string text = item.name;

        // Add additional info based on configuration
        if (_config.showFileSize && item.totalSize > 0) {
            text ~= format(" (%s)", formatFileSize(item.totalSize));
        }

        if (_config.showModificationTime) {
            text ~= format(" [%s]", formatModificationTime(item.lastModified));
        }

        // Add status indicators
        if (item.buildStatus != BuildStatus.Unknown) {
            text ~= " " ~ getBuildStatusIcon(item.buildStatus);
        }

        if (item.testStatus != TestStatus.Unknown && item.testStatus != TestStatus.NoTests) {
            text ~= " " ~ getTestStatusIcon(item.testStatus);
        }

        return text;
    }

    private string getItemIcon(WorkspaceItemType type) {
        final switch (type) {
            case WorkspaceItemType.Workspace: return "workspace";
            case WorkspaceItemType.Project: return "project";
            case WorkspaceItemType.Folder: return "folder";
            case WorkspaceItemType.File: return "file";
            case WorkspaceItemType.SourceFile: return "source-file";
            case WorkspaceItemType.TestFile: return "test-file";
            case WorkspaceItemType.ConfigFile: return "config-file";
            case WorkspaceItemType.BuildFile: return "build-file";
            case WorkspaceItemType.Documentation: return "documentation";
            case WorkspaceItemType.Resource: return "resource";
            case WorkspaceItemType.Dependency: return "dependency";
            case WorkspaceItemType.VirtualFolder: return "virtual-folder";
            case WorkspaceItemType.GitSubmodule: return "git-submodule";
            case WorkspaceItemType.Link: return "link";
            case WorkspaceItemType.Unknown: return "unknown";
        }
    }

    private string getBuildStatusIcon(BuildStatus status) {
        final switch (status) {
            case BuildStatus.Success: return "✓";
            case BuildStatus.Failed: return "✗";
            case BuildStatus.InProgress: return "⚠";
            case BuildStatus.Warning: return "⚠";
            case BuildStatus.Skipped: return "○";
            case BuildStatus.Unknown: return "";
        }
    }

    private string getTestStatusIcon(TestStatus status) {
        final switch (status) {
            case TestStatus.Passed: return "✓";
            case TestStatus.Failed: return "✗";
            case TestStatus.Running: return "⚠";
            case TestStatus.Skipped: return "○";
            case TestStatus.NoTests: return "";
            case TestStatus.Unknown: return "";
        }
    }

    private string formatFileSize(long bytes) {
        const double KB = 1024.0;
        const double MB = KB * 1024.0;
        const double GB = MB * 1024.0;

        if (bytes >= GB) {
            return format("%.1f GB", bytes / GB);
        } else if (bytes >= MB) {
            return format("%.1f MB", bytes / MB);
        } else if (bytes >= KB) {
            return format("%.1f KB", bytes / KB);
        } else {
            return format("%d B", bytes);
        }
    }

    private string formatModificationTime(SysTime time) {
        return time.toSimpleString();
    }

    private void updateViewMode(int mode) {
        // Implementation for different view modes
        final switch (mode) {
            case 0: // Tree View (default)
                break;
            case 1: // List View
                // Flatten the tree structure
                break;
            case 2: // By Type
                // Group items by type
                break;
            case 3: // By Status
                // Group items by VCS/build status
                break;
        }

        updateTreeDisplay();
    }

    private void expandAll() {
        expandAllRecursive(_rootItem, true);
        updateTreeDisplay();
    }

    private void collapseAll() {
        expandAllRecursive(_rootItem, false);
        updateTreeDisplay();
    }

    private void expandAllRecursive(ref WorkspaceItem item, bool expand) {
        item.isExpanded = expand;
        foreach (ref child; item.children) {
            expandAllRecursive(child, expand);
        }
    }

    private void createNewProject() {
        // Show new project dialog
        auto dialog = new NewProjectDialog(window);
        dialog.onProjectCreated.connect((string projectPath) {
            refreshWorkspace();
        });
        dialog.show();
    }

    private void createNewFolder() {
        // Get selected item
        auto selectedItem = getSelectedItem();
        if (!selectedItem) return;

        // Show new folder dialog
        auto dialog = new InputDialog("New Folder"d, "Folder name:"d, window);
        dialog.onInputAccepted.connect((string folderName) {
            createFolderInItem(*selectedItem, folderName);
        });
        dialog.show();
    }

    private void createNewFile() {
        // Get selected item
        auto selectedItem = getSelectedItem();
        if (!selectedItem) return;

        // Show new file dialog
        auto dialog = new InputDialog("New File"d, "File name:"d, window);
        dialog.onInputAccepted.connect((string fileName) {
            createFileInItem(*selectedItem, fileName);
        });
        dialog.show();
    }

    private WorkspaceItem* getSelectedItem() {
        auto selectedTreeItem = _workspaceTree.selectedItem;
        if (selectedTreeItem && selectedTreeItem.tag) {
            return cast(WorkspaceItem*)selectedTreeItem.tag;
        }
        return null;
    }

    private void createFolderInItem(WorkspaceItem parentItem, string folderName) {
        string folderPath = buildPath(parentItem.path, folderName);

        try {
            mkdirRecurse(folderPath);

            // Add to workspace structure
            WorkspaceItem newItem;
            newItem.name = folderName;
            newItem.path = folderPath;
            newItem.type = WorkspaceItemType.Folder;
            newItem.parent = &parentItem;
            newItem.lastModified = Clock.currTime();

            parentItem.children ~= newItem;
            updateTreeDisplay();

            writeln("Created folder: ", folderPath);
        } catch (Exception e) {
            writeln("Error creating folder: ", e.msg);
        }
    }

    private void createFileInItem(WorkspaceItem parentItem, string fileName) {
        string filePath = buildPath(parentItem.path, fileName);

        try {
            std.file.write(filePath, "");

            // Add to workspace structure
            WorkspaceItem newItem;
            newItem.name = fileName;
            newItem.path = filePath;
            newItem.type = determineFileType(filePath);
            newItem.parent = &parentItem;
            newItem.lastModified = Clock.currTime();
            newItem.totalSize = 0;
            newItem.fileCount = 1;

            parentItem.children ~= newItem;
            updateTreeDisplay();

            // Open the new file
            if (onFileOpened.assigned) {
                onFileOpened(filePath);
            }

            writeln("Created file: ", filePath);
        } catch (Exception e) {
            writeln("Error creating file: ", e.msg);
        }
    }

    private void showSettingsDialog() {
        auto dialog = new WorkspaceSettingsDialog(_config, window);
        dialog.onConfigChanged.connect((WorkspaceConfig newConfig) {
            _config = newConfig;
            refreshWorkspace();
        });
        dialog.show();
    }

    /// Get current workspace item structure
    @property WorkspaceItem rootItem() {
        return _rootItem;
    }

    /// Get current configuration
    @property WorkspaceConfig config() {
        return _config;
    }

    /// Set configuration
    @property void config(WorkspaceConfig cfg) {
        _config = cfg;
        refreshWorkspace();
    }

    /// Export workspace structure as JSON
    JSONValue exportWorkspace() {
        JSONValue result = JSONValue.emptyObject;
        result["name"] = JSONValue(_rootItem.name);
        result["path"] = JSONValue(_rootItem.path);
        result["timestamp"] = JSONValue(Clock.currTime().toISOExtString());
        result["structure"] = serializeWorkspaceItem(_rootItem);
        result["config"] = serializeWorkspaceConfig(_config);
        return result;
    }

    private JSONValue serializeWorkspaceItem(WorkspaceItem item) {
        JSONValue itemJson = JSONValue.emptyObject;
        itemJson["name"] = JSONValue(item.name);
        itemJson["path"] = JSONValue(item.path);
        itemJson["type"] = JSONValue(to!string(item.type));
        itemJson["description"] = JSONValue(item.description);
        itemJson["version"] = JSONValue(item.version_);
        itemJson["buildSystem"] = JSONValue(item.buildSystem);
        itemJson["fileCount"] = JSONValue(item.fileCount);
        itemJson["totalSize"] = JSONValue(item.totalSize);
        itemJson["health"] = JSONValue(item.health);
        itemJson["buildStatus"] = JSONValue(to!string(item.buildStatus));
        itemJson["vcsStatus"] = JSONValue(to!string(item.vcsStatus));
        itemJson["testStatus"] = JSONValue(to!string(item.testStatus));

        JSONValue[] childrenArray;
        foreach (child; item.children) {
            childrenArray ~= serializeWorkspaceItem(child);
        }
        itemJson["children"] = JSONValue(childrenArray);

        return itemJson;
    }

    private JSONValue serializeWorkspaceConfig(WorkspaceConfig config) {
        JSONValue configJson = JSONValue.emptyObject;
        configJson["showHiddenFiles"] = JSONValue(config.showHiddenFiles);
        configJson["showDependencies"] = JSONValue(config.showDependencies);
        configJson["showTestFiles"] = JSONValue(config.showTestFiles);
        configJson["showBuildFiles"] = JSONValue(config.showBuildFiles);
        configJson["showVirtualFolders"] = JSONValue(config.showVirtualFolders);
        configJson["groupByType"] = JSONValue(config.groupByType);
        configJson["sortAlphabetically"] = JSONValue(config.sortAlphabetically);
        configJson["showFileIcons"] = JSONValue(config.showFileIcons);
        configJson["showLineCount"] = JSONValue(config.showLineCount);
        configJson["showFileSize"] = JSONValue(config.showFileSize);
        configJson["showModificationTime"] = JSONValue(config.showModificationTime);
        configJson["autoRefresh"] = JSONValue(config.autoRefresh);
        configJson["refreshInterval"] = JSONValue(config.refreshInterval);
        configJson["excludePatterns"] = JSONValue(config.excludePatterns);
        configJson["includePatterns"] = JSONValue(config.includePatterns);
        return configJson;
    }

    /// Find workspace item by path
    WorkspaceItem* findItemByPath(string path) {
        return findItemByPathRecursive(_rootItem, path);
    }

    private WorkspaceItem* findItemByPathRecursive(ref WorkspaceItem item, string path) {
        if (item.path == path) {
            return &item;
        }

        foreach (ref child; item.children) {
            auto found = findItemByPathRecursive(child, path);
            if (found) return found;
        }

        return null;
    }

    /// Cleanup resources
    void cleanup() {
        // Stop file system watching if enabled
        _watchingFileSystem = false;

        // Clear data structures
        _rootItem.children.length = 0;
        _filteredItems.length = 0;
    }
}

/// Simple input dialog for creating new items
class InputDialog : Dialog {
    private {
        EditLine _inputField;
        string _prompt;
    }

    Signal!(string) onInputAccepted;

    this(dstring title, dstring prompt, Window parent) {
        super(title, parent, DialogFlag.Modal, 300, 150);
        _prompt = prompt.toUTF8();
        createUI();
    }

    private void createUI() {
        VerticalLayout content = new VerticalLayout();
        content.layoutWidth = FILL_PARENT;
        content.layoutHeight = FILL_PARENT;
        content.margins = Rect(10, 10, 10, 10);

        // Prompt label
        TextWidget promptLabel = new TextWidget();
        promptLabel.text = _prompt.toUTF32();
        content.addChild(promptLabel);

        // Input field
        _inputField = new EditLine("input");
        _inputField.layoutWidth = FILL_PARENT;
        content.addChild(_inputField);

        // Buttons
        HorizontalLayout buttonLayout = new HorizontalLayout();
        buttonLayout.layoutWidth = FILL_PARENT;

        Widget spacer = new Widget();
        spacer.layoutWidth = FILL_PARENT;
        buttonLayout.addChild(spacer);

        Button cancelBtn = new Button("cancel", "Cancel"d);
        cancelBtn.click = delegate(Widget source) {
            close(StandardAction.Cancel);
            return true;
        };
        buttonLayout.addChild(cancelBtn);

        Button okBtn = new Button("ok", "OK"d);
        okBtn.click = delegate(Widget source) {
            string input = _inputField.text.toUTF8();
            if (input.length > 0 && onInputAccepted.assigned) {
                onInputAccepted(input);
            }
            close(StandardAction.Ok);
            return true;
        };
        buttonLayout.addChild(okBtn);

        content.addChild(buttonLayout);
        addChild(content);

        // Focus the input field
        _inputField.setFocus();
    }
}

/// Settings dialog for workspace configuration
class WorkspaceSettingsDialog : Dialog {
    private {
        WorkspaceConfig _config;
        // UI controls would be added here
    }

    Signal!(WorkspaceConfig) onConfigChanged;

    this(WorkspaceConfig config, Window parent) {
        super(UIString.fromRaw("Workspace Settings"), parent, DialogFlag.Modal, 400, 600);
        _config = config;
        createUI();
    }

    private void createUI() {
        // Implementation would be similar to OutlineSettingsDialog
        // but for workspace-specific settings
    }
}

/// New project creation dialog
class NewProjectDialog : Dialog {
    Signal!(string) onProjectCreated;

    this(Window parent) {
        super(UIString.fromRaw("New Project"), parent, DialogFlag.Modal, 500, 400);
        createUI();
    }

    private void createUI() {
        // Implementation for new project wizard
    }
}

/// Factory function to create workspace outline widget
WorkspaceOutlineWidget createWorkspaceOutlineWidget(DCore dcore) {
    return new WorkspaceOutlineWidget(dcore);
}
