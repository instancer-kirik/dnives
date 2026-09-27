module dlangide.ui.filepanel;

import std.string, std.path, std.file, std.conv, std.format, std.algorithm, std.array,
    std.process, std.utf;
import dlangui;
import dlangui.widgets.docks;
import dlangui.widgets.tree;
import dlangui.widgets.menu;
import dlangui.core.logger;
import dlangide.workspace.workspace;
import dlangide.workspace.project;
import dlangide.ui.commands;
import dlangide.ui.wspanel : ProjectItemType, SourceFileSelectionHandler, WorkspaceActionHandler;

// ---------------------------------------------------------------------------
// FilterableTreeItem — TreeItem subclass that supports explicit filter visibility
// ---------------------------------------------------------------------------
private class FilterableTreeItem : TreeItem {
    private bool _filterVisible = true;

    this(string id, dstring label, string iconRes = null) {
        super(id, label, iconRes);
    }

    /// Set whether this item passes the current filter.
    @property void filterVisible(bool v) {
        _filterVisible = v;
    }

    override bool isVisible() {
        if (!_filterVisible)
            return false;
        return super.isVisible();
    }
}

// ---------------------------------------------------------------------------
// Custom actions used only inside FilePanel (ids in range 5000–5099)
// ---------------------------------------------------------------------------
private enum FilePanelAction : int {
    CopyPath           = 5001,
    CopyRelativePath   = 5002,
    Rename             = 5003,
    DeleteFolder       = 5004,
    ShowSymbolGraph    = 5010,
    RevealInExplorer   = 5011,
    NewFileHere        = 5020,
    OpenInTerminal     = 5030,
}

// ---------------------------------------------------------------------------
// FilePanel
// ---------------------------------------------------------------------------

/// Sidebar dock panel showing the full project / workspace file tree with
/// toolbar and context-sensitive right-click menus.
class FilePanel : DockWindow {

    // ---- widgets ----------------------------------------------------------
    private TreeWidget        _tree;
    private HorizontalLayout  _toolbar;
    private EditLine          _searchBox;

    // ---- model ------------------------------------------------------------
    private Workspace         _workspace;

    // ---- signals (re-used from WorkspacePanel interface) ------------------
    Signal!SourceFileSelectionHandler sourceFileSelectionListener;
    Signal!WorkspaceActionHandler     workspaceActionListener;

    // ---- user-supplied delegates ------------------------------------------
    /// Called when the user requests to open a file.  Return true if handled.
    bool delegate(string path) onFileOpen;

    /// Called when the user wants to reveal a path in the OS file manager.
    bool delegate(string path) onFileReveal;

    /// Called when the user requests the symbol dependency graph for a file.
    bool delegate(string path) onSymbolGraphRequest;

    // ---- state ------------------------------------------------------------
    private bool[string] _itemStates;

    // -----------------------------------------------------------------------
    this(string id) {
        super(id);
        _caption.text = "Files"d;
    }

    // -----------------------------------------------------------------------
    // Body widget
    // -----------------------------------------------------------------------
    override protected Widget createBodyWidget() {
        auto vbox = new VerticalLayout("filepanel_body");
        vbox.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);

        // ---- toolbar ------------------------------------------------------
        _toolbar = new HorizontalLayout("filepanel_toolbar");
        _toolbar.layoutWidth(FILL_PARENT);
        _toolbar.backgroundColor = 0x252526;
        _toolbar.padding(Rect(2, 2, 2, 2));

        auto btnRefresh = new ImageButton("fp_btn_refresh", "view-refresh");
        btnRefresh.tooltipText = "Refresh"d;
        btnRefresh.click = delegate(Widget src) {
            reloadItems();
            return true;
        };

        auto btnNewFile = new ImageButton("fp_btn_newfile", "document-new");
        btnNewFile.tooltipText = "New File"d;
        btnNewFile.click = delegate(Widget src) {
            if (workspaceActionListener.assigned)
                workspaceActionListener(ACTION_FILE_NEW_SOURCE_FILE);
            return true;
        };

        auto btnNewFolder = new ImageButton("fp_btn_newfolder", "folder-new");
        btnNewFolder.tooltipText = "New Folder"d;
        btnNewFolder.click = delegate(Widget src) {
            if (workspaceActionListener.assigned)
                workspaceActionListener(ACTION_FILE_NEW_DIRECTORY);
            return true;
        };

        _searchBox = new EditLine("fp_search");
        _searchBox.layoutWidth(FILL_PARENT);

        _searchBox.contentChange = delegate(EditableContent content) {
            filterTree(content.text.to!string);
        };

        _toolbar.addChild(btnRefresh);
        _toolbar.addChild(btnNewFile);
        _toolbar.addChild(btnNewFolder);
        _toolbar.addChild(_searchBox);

        // ---- tree ---------------------------------------------------------
        _tree = new TreeWidget("fp_tree", ScrollBarMode.Auto, ScrollBarMode.Auto);
        _tree.layoutWidth(FILL_PARENT).layoutHeight(FILL_PARENT);
        _tree.backgroundColor = 0x1E1E1E;
        _tree.fontSize = 13;
        _tree.noCollapseForSingleTopLevelItem = true;
        _tree.selectionChange     = &onTreeItemSelected;
        _tree.expandedChange.connect(&onTreeExpandedStateChange);
        _tree.popupMenu           = &buildContextMenu;

        vbox.addChild(_toolbar);
        vbox.addChild(_tree);
        return vbox;
    }

    // -----------------------------------------------------------------------
    // Tree item selection
    // -----------------------------------------------------------------------
    private void onTreeItemSelected(TreeItems source, TreeItem selected, bool activated) {
        if (!selected)
            return;
        if (_workspace) {
            ProjectItem pi = cast(ProjectItem) selected.objectParam;
            if (pi && pi.filename.length)
                _workspace.selectedWorkspaceItem = pi.filename;
        }
        if (selected.intParam == ProjectItemType.SourceFile) {
            if (sourceFileSelectionListener.assigned) {
                ProjectSourceFile sf = cast(ProjectSourceFile) selected.objectParam;
                if (sf)
                    sourceFileSelectionListener(sf, activated);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Expand/collapse persistence (mirrors WorkspacePanel logic)
    // -----------------------------------------------------------------------
    private void onTreeExpandedStateChange(TreeItems source, TreeItem item) {
        ProjectItem pi = cast(ProjectItem) item.objectParam;
        if (pi)
            saveItemState(pi.filename, item.expanded);
    }

    private void saveItemState(string path, bool expanded) {
        if (expanded)
            _itemStates[path] = true;
        else
            _itemStates.remove(path);
        if (_workspace) {
            string[] arr;
            arr.assumeSafeAppend;
            foreach (k, v; _itemStates)
                arr ~= k;
            _workspace.expandedItems = arr;
        }
    }

    private bool restoreItemState(string path) {
        if (auto p = path in _itemStates)
            return *p;
        return false;
    }

    private void readExpandedStateFromWorkspace() {
        _itemStates.clear();
        if (_workspace)
            foreach (item; _workspace.expandedItems)
                _itemStates[item] = true;
    }

    // -----------------------------------------------------------------------
    // Context menu builder
    // -----------------------------------------------------------------------
    private MenuItem buildContextMenu(TreeItems source, TreeItem item) {
        if (!item)
            return null;

        MenuItem menu = new MenuItem();

        final switch (item.intParam) {

        case ProjectItemType.SourceFile:
            appendAction(menu, ACTION_PROJECT_FOLDER_OPEN_ITEM.clone(), item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.CopyPath,         "Copy Path"d,          item);
            appendCustom(menu, FilePanelAction.CopyRelativePath, "Copy Relative Path"d, item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.Rename,           "Rename"d,             item);
            appendAction(menu, ACTION_PROJECT_FOLDER_REMOVE_ITEM.clone(), item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.ShowSymbolGraph,  "Show Symbol Graph"d,  item);
            appendCustom(menu, FilePanelAction.RevealInExplorer, "Reveal in Explorer"d, item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.NewFileHere,      "New File Here"d,      item);
            break;

        case ProjectItemType.SourceFolder:
            appendAction(menu, ACTION_FILE_NEW_SOURCE_FILE.clone(), item);
            appendAction(menu, ACTION_FILE_NEW_DIRECTORY.clone(),   item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.Rename,           "Rename"d,             item);
            appendCustom(menu, FilePanelAction.DeleteFolder,     "Delete Folder"d,      item);
            menu.addSeparator();
            appendCustom(menu, FilePanelAction.OpenInTerminal,   "Open in Terminal"d,   item);
            appendCustom(menu, FilePanelAction.RevealInExplorer, "Reveal in Explorer"d, item);
            break;

        case ProjectItemType.Project:
            appendAction(menu, ACTION_PROJECT_BUILD.clone(),   item);
            appendAction(menu, ACTION_PROJECT_REBUILD.clone(), item);
            appendAction(menu, ACTION_PROJECT_CLEAN.clone(),   item);
            menu.addSeparator();
            appendAction(menu, ACTION_PROJECT_FOLDER_REFRESH.clone(), item);
            appendCustom(menu, FilePanelAction.RevealInExplorer, "Reveal in Explorer"d, item);
            appendAction(menu, ACTION_PROJECT_SETTINGS.clone(), item);
            break;

        case ProjectItemType.Workspace:
        case ProjectItemType.None:
            return null;
        }

        menu.updateActionState(this);
        return menu;
    }

    /// Append a dlangui Action-based menu item, attaching objectParam and handler.
    private void appendAction(MenuItem menu, Action a, TreeItem item) {
        a.objectParam = item.objectParam;
        MenuItem mi = new MenuItem(a);
        mi.menuItemAction = (const Action act) {
            handleContextAction(act, item);
            return true;
        };
        menu.add(mi);
    }

    /// Append a custom (FilePanel-local) action menu item.
    private void appendCustom(MenuItem menu, FilePanelAction id, dstring label, TreeItem item) {
        Action a = new Action(cast(int) id, label);
        a.objectParam = item.objectParam;
        MenuItem mi = new MenuItem(a);
        mi.menuItemAction = (const Action act) {
            handleContextAction(act, item);
            return true;
        };
        menu.add(mi);
    }

    // -----------------------------------------------------------------------
    // Context action handler
    // -----------------------------------------------------------------------
    private void handleContextAction(const Action a, TreeItem item) {
        ProjectItem pi   = cast(ProjectItem) item.objectParam;
        string      path = pi ? pi.filename : "";

        switch (a.id) {

        case FilePanelAction.CopyPath:
            if (path.length)
                platform.setClipboardText(path.to!dstring);
            break;

        case FilePanelAction.CopyRelativePath:
            if (path.length && _workspace) {
                string root     = dirName(_workspace.filename);
                string relative = relativePath(path, root);
                platform.setClipboardText(relative.to!dstring);
            }
            break;

        case FilePanelAction.ShowSymbolGraph:
            if (path.length && onSymbolGraphRequest !is null)
                onSymbolGraphRequest(path);
            break;

        case FilePanelAction.RevealInExplorer:
            if (path.length) {
                if (onFileReveal !is null) {
                    onFileReveal(path);
                } else {
                    // Fallback: open the containing directory in the OS file manager.
                    string dir = isDir(path) ? path : dirName(path);
                    browse(dir);
                }
            }
            break;

        case FilePanelAction.OpenInTerminal:
            if (path.length) {
                string dir = isDir(path) ? path : dirName(path);
                version (Windows) {
                    spawnShell("start cmd /K \"cd /d " ~ dir ~ "\"");
                } else version (OSX) {
                    spawnShell("open -a Terminal " ~ escapeShellFileName(dir));
                } else {
                    // Generic X11 — try common terminal emulators in order.
                    spawnShell("xterm -e 'cd " ~ escapeShellFileName(dir) ~ " && exec $SHELL' &");
                }
            }
            break;

        default:
            // Delegate all other actions (e.g. build/rebuild/open/rename/delete)
            // to the host IDE through the workspaceActionListener signal.
            if (workspaceActionListener.assigned)
                workspaceActionListener(a);
            break;
        }
    }

    // -----------------------------------------------------------------------
    // Workspace property + reloadItems
    // -----------------------------------------------------------------------
    @property Workspace workspace() {
        return _workspace;
    }

    @property void workspace(Workspace w) {
        _workspace = w;
        readExpandedStateFromWorkspace();
        reloadItems();
    }

    void reloadItems() {
        if (!_tree)
            return;

        _tree.expandedChange.disconnect(&onTreeExpandedStateChange);
        _tree.selectionChange.disconnect(&onTreeItemSelected);
        _tree.clearAllItems();

        if (_workspace) {
            TreeItem defaultItem = null;

            TreeItem root = _tree.items.newChild(
                _workspace.filename,
                _workspace.name,
                "project-development");
            root.intParam = ProjectItemType.Workspace;

            foreach (project; _workspace.projects) {
                string icon = project.isDependency
                    ? "project-d-dependency"
                    : "project-d";
                auto p = new FilterableTreeItem(project.filename, project.name, icon);
                root.addChild(p);
                p.intParam    = ProjectItemType.Project;
                p.objectParam = project;

                if (restoreItemState(project.filename))
                    p.expand();
                else
                    p.collapse();

                if (_workspace.startupProject is project)
                    defaultItem = p;

                addProjectItems(p, project.items);
            }

            _tree.items.setDefaultItem(defaultItem);

            // If no expand state is recorded, auto-expand the startup project.
            if (!_itemStates.length && _workspace.startupProject) {
                string fn = _workspace.startupProject.filename;
                if (TreeItem si = _tree.items.findItemById(fn)) {
                    si.expand();
                    saveItemState(fn, true);
                }
            }

            // Restore selection.
            string sel = _workspace.selectedWorkspaceItem;
            if (sel.length)
                _tree.selectItem(sel);

        } else {
            _tree.items.newChild("none", "No workspace"d, "project-development");
        }

        _tree.expandedChange.connect(&onTreeExpandedStateChange);
        _tree.selectionChange.connect(&onTreeItemSelected);
    }

    /// Returns the icon name for a file based on its detected language.
    private string fileIcon(string filePath) {
        import dcore.lang.language_profile : detectLanguage;
        switch (detectLanguage(filePath)) {
            case "d":          return "text-d";
            case "json":       return "text-json";
            case "dml":        return "text-dml";
            case "python":     return "text-other";
            case "javascript":
            case "typescript": return "text-other";
            default:           return "text-other";
        }
    }

    /// Recursively populate tree from a ProjectItem hierarchy.
    private void addProjectItems(TreeItem root, ProjectItem items) {
        for (int i = 0; i < items.childCount; i++) {
            ProjectItem child = items.child(i);
            if (child.isFolder) {
                auto p = new FilterableTreeItem(child.filename, child.name, "folder");
                root.addChild(p);
                p.intParam    = ProjectItemType.SourceFolder;
                p.objectParam = child;
                if (restoreItemState(child.filename))
                    p.expand();
                else
                    p.collapse();
                addProjectItems(p, child);
            } else {
                auto p = new FilterableTreeItem(child.filename, child.name, fileIcon(child.filename));
                root.addChild(p);
                p.intParam    = ProjectItemType.SourceFile;
                p.objectParam = child;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Filter / search
    // -----------------------------------------------------------------------

    /// Show only tree items whose display name contains `query` (case-insensitive).
    /// Pass an empty string to restore full visibility.
    void filterTree(string query) {
        if (!_tree)
            return;
        string q = query.toLower.strip;
        applyFilter(_tree.items, q);
        // Notify the tree widget that content visibility has changed.
        if (_tree.items.contentListener.assigned)
            _tree.items.contentListener(_tree.items);
    }

    /// Returns true when the item or any of its descendants matches, so that
    /// parent folders of matching files remain visible.
    private bool applyFilter(TreeItem node, string query) {
        if (!node)
            return false;

        bool anyChildVisible = false;
        for (int i = 0; i < node.childCount; i++) {
            TreeItem child = node.child(i);
            bool childMatch = applyFilter(child, query);
            if (childMatch)
                anyChildVisible = true;
        }

        bool selfMatch = query.length == 0
            || node.text.to!string.toLower.canFind(query);
        bool visible = selfMatch || anyChildVisible;

        if (auto fn = cast(FilterableTreeItem) node)
            fn.filterVisible = visible;
        return visible;
    }

    // -----------------------------------------------------------------------
    // Public helpers (mirror WorkspacePanel API so callers can be swapped)
    // -----------------------------------------------------------------------

    /// Attempt to locate and highlight a ProjectItem in the tree.
    bool selectItem(ProjectItem projectItem) {
        if (!_tree)
            return false;
        if (projectItem) {
            TreeItem ti = _tree.findItemById(projectItem.filename);
            if (ti) {
                if (ti.parent && !ti.parent.isFullyExpanded)
                    _tree.items.toggleExpand(ti.parent);
                _tree.makeItemVisible(ti);
                _tree.selectItem(ti);
                return true;
            }
        } else {
            _tree.clearSelection();
            return true;
        }
        return false;
    }

    /// Find a source file by its filesystem path across all projects.
    ProjectSourceFile findSourceFileItem(string filename,
                                         bool fullFileName = true,
                                         dstring projectName = null) {
        if (_workspace)
            return _workspace.findSourceFileItem(filename, fullFileName, projectName);
        return null;
    }

    // -----------------------------------------------------------------------
    // DockWindow overrides
    // -----------------------------------------------------------------------
    override protected bool onCloseButtonClick(Widget source) {
        hide();
        return true;
    }

    void hide() {
        visibility = Visibility.Gone;
        if (parent)
            parent.layout(parent.pos);
    }

    void activate() {
        if (visibility == Visibility.Gone) {
            visibility = Visibility.Visible;
            if (parent)
                parent.layout(parent.pos);
        }
        setFocus();
    }

    override bool handleAction(const Action a) {
        if (workspaceActionListener.assigned)
            return workspaceActionListener(a);
        return false;
    }
}
