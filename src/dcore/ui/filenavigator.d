module dcore.ui.filenavigator;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.tree;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.popup;
import dlangui.core.signals;
import dlangui.graphics.drawbuf;
import dlangui.graphics.colors;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.algorithm;
import std.array;
import std.conv;

import dcore.core;
import dcore.search.fuzzysearch;
import dcore.ui.thememanager;

/**
 * FileTreeItem - Tree item representing a file or directory
 */
class FileTreeItem : TreeItem {
    private string _fullPath;
    private bool _isDirectory;
    private bool _isExpanded;
    private bool _isLoaded;
    
    /**
     * Constructor
     */
    this(string fullPath, bool isDirectory) {
        super(baseName(fullPath));
        _fullPath = fullPath;
        _isDirectory = isDirectory;
        _isExpanded = false;
        _isLoaded = false;
        
        // Set icon based on file type
        if (isDirectory) {
            super.iconRes = "folder";
        } else {
            // Determine icon based on extension
            string ext = extension(fullPath).toLower();
                
            switch (ext) {
                case ".d":
                    super.iconRes = "d-file";
                    break;
                case ".c":
                case ".cpp":
                case ".h":
                case ".hpp":
                    super.iconRes = "cpp-file";
                    break;
                case ".js":
                case ".ts":
                    super.iconRes = "js-file";
                    break;
                case ".html":
                case ".css":
                    super.iconRes = "html-file";
                    break;
                case ".json":
                    super.iconRes = "json-file";
                    break;
                case ".md":
                    super.iconRes = "markdown-file";
                    break;
                case ".txt":
                    super.iconRes = "text-file";
                    break;
                default:
                    super.iconRes = "file";
                    break;
            }
        }
    }
    
    /**
     * Get full path
     */
    @property string fullPath() { return _fullPath; }
    
    /**
     * Check if item is a directory
     */
    @property bool isDirectory() { return _isDirectory; }
    
    /**
     * Check if directory is expanded
     */
    @property bool isExpanded() { return _isExpanded; }
    @property void isExpanded(bool value) { _isExpanded = value; }
    
    /**
     * Check if directory contents are loaded
     */
    @property bool isLoaded() { return _isLoaded; }
    @property void isLoaded(bool value) { _isLoaded = value; }
}

/**
 * FileNavigator - File system navigator with tree view and search
 */
class FileNavigator : VerticalLayout {
    private bool onTreeKeyEvent(Widget source, KeyEvent event) {
        return false; // Let default handler process
    }
    // Signal handlers
    void delegate(string) onFileSelected;
    void delegate(string) onFileCreated;
    void delegate(string) onFileRenamed;
    void delegate(string) onFileDeleted;
    
    // UI Components
    private EditLine _searchBox;
    private TreeWidget _fileTree;
    private string _rootPath;
    private DCore _core;
    private ThemeManager _themeManager;
    
    // Search state
    private FuzzyMatcher _matcher;
    private bool _isInSearchMode;
    private string _currentSearchQuery;
    
    // Context menu
    private PopupMenu _contextMenu;
    private string _contextMenuPath;
    
    /**
     * Constructor
     */
    this(string id = null) {
        super(id);
        
        // Create fuzzy matcher
        FuzzyOptions options;
        options.maxResults = 100;
        _matcher = new FuzzyMatcher(options);
        
        // Set layout properties
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        
        // Create search box
        _searchBox = new EditLine("FILE_SEARCH");
        _searchBox.layoutWidth = FILL_PARENT;
        _searchBox.text = "Search files..."d;
        _searchBox.backgroundColor = 0x2A2A2A;
        _searchBox.textColor = 0xEAEAEA;
        
        import dlangui.core.events;
        _searchBox.keyEvent = delegate(Widget source, KeyEvent event) {
            if (event.action == KeyAction.Text) {
                onSearchChanged(_searchBox.text.toUTF8());
                return true;
            }
            return false;
        };
        
        addChild(_searchBox);
        
        // Create file tree
        _fileTree = new TreeWidget("FILE_TREE");
        _fileTree.layoutWidth = FILL_PARENT;
        _fileTree.layoutHeight = FILL_PARENT;
        _fileTree.backgroundColor = 0x00000000; // Transparent
        
        // We'll use mouse events directly
        _fileTree.mouseEvent = &onTreeMouseEvent;
        
        addChild(_fileTree);
        
        // Initialize state
        _isInSearchMode = false;
        _currentSearchQuery = "";
        
        // Create context menu
        createContextMenu();
    }
    
    /**
     * Set core reference
     */
    void setCore(DCore core) {
        _core = core;
    }
    
    /**
     * Set theme manager
     */
    void setThemeManager(ThemeManager themeManager) {
        // Store but don't use directly since there's a conflict with dlangui's Theme
        _themeManager = themeManager;
        applyTheme();
    }
    
    /**
     * Apply current theme
     */
    void applyTheme() {
        if (_themeManager) {
            // Use hardcoded values for consistency
            backgroundColor = 0x2A2A2A;
            _fileTree.backgroundColor = 0x2A2A2A;
            
            // Update search box with default colors
            _searchBox.backgroundColor = 0x2A2A2A;  // Dark background
            _searchBox.textColor = 0xEAEAEA;        // Light text
        }
    }
    
    /**
     * Set root path
     */
    void setRootPath(string path) {
        if (!exists(path)) {
            Log.e("FileNavigator: Path does not exist: ", path);
            return;
        }
        
        _rootPath = path;
        refresh();
    }
    
    /**
     * Refresh the file tree
     */
    void refresh() {
        if (!_rootPath || _rootPath.length == 0)
            return;
            
        // Clear tree
        _fileTree.items.clear();
        
        // Add root item
        FileTreeItem rootItem = new FileTreeItem(_rootPath, true);
        _fileTree.items.addChild(rootItem);
        // Mark root item as expanded
        rootItem.isExpanded = true;
        
        // Load root directory contents
        loadDirectoryContents(rootItem);
        
        // Mark as loaded
        rootItem.isLoaded = true;
        
        Log.i("FileNavigator: Loaded root path: ", _rootPath);
    }
    
    /**
     * Load directory contents
     */
    private void loadDirectoryContents(FileTreeItem parentItem) {
        if (!parentItem || !parentItem.isDirectory)
            return;
            
        string dirPath = parentItem.fullPath;
        
        try {
            // Get directory contents
            DirEntry[] entries;
            
            // First collect directories
            foreach (entry; dirEntries(dirPath, SpanMode.shallow)) {
                if (entry.isDir && !baseName(entry.name).startsWith(".")) {
                    entries ~= entry;
                }
            }
            
            // Sort directories
            sort!((a, b) => baseName(a.name) < baseName(b.name))(entries);
            
            // Add directories to tree
            foreach (entry; entries) {
                FileTreeItem item = new FileTreeItem(entry.name, true);
                
                // Add placeholder child to show expand arrow
                TreeItem placeholder = new TreeItem("placeholder");
                placeholder.text = "Loading..."d;
                item.addChild(placeholder);
                
                parentItem.addChild(item);
            }
            
            // Clear entries for files
            entries = [];
            
            // Then collect files
            foreach (entry; dirEntries(dirPath, SpanMode.shallow)) {
                if (!entry.isDir && !baseName(entry.name).startsWith(".")) {
                    entries ~= entry;
                }
            }
            
            // Sort files
            sort!((a, b) => baseName(a.name) < baseName(b.name))(entries);
            
            // Add files to tree
            foreach (entry; entries) {
                try {
                    FileTreeItem item = new FileTreeItem(entry.name, false);
                    parentItem.addChild(item);
                } catch (Exception e) {
                    Log.e("Error adding file to tree: ", e.msg);
                }
            }
            
            // Mark as loaded
            parentItem.isLoaded = true;
        } catch (Exception e) {
            Log.e("FileNavigator: Error loading directory: ", e.msg);
        }
    }
    
    /**
     * Handle tree item selection
     */
    private bool onTreeMouseEvent(Widget source, MouseEvent event) {
        if (event.action == MouseAction.ButtonUp) {
            auto tree = cast(TreeWidget)source;
            if (!tree)
                return false;
                
            // Simplified mouse handling - use direct widget access
            if (event.button == MouseButton.Left) {
                // Just handle as a simple click
                auto items = tree.items;
                auto item = items.selectedItem;
                if (item !is null) {
                    if (event.action == MouseAction.ButtonUp)
                        return onItemClicked(items, item);
                }
            }
        }
        return false;
    }
    
    /**
     * Handle tree item activation
     */
    private bool onItemActivated(TreeItems source, TreeItem item) {
        FileTreeItem fileItem = cast(FileTreeItem)item;
        if (!fileItem)
            return false;
            
        if (fileItem.isDirectory) {
            // Just mark it as loaded
            fileItem.isLoaded = true;
        } else {
            // Open the file
            if (onFileSelected !is null)
                onFileSelected(fileItem.fullPath);
        }
        
        return true;
    }
    
    /**
     * Handle tree item expansion
     */
    private bool onItemExpanded(TreeItems source, TreeItem item, bool expanded) {
        FileTreeItem fileItem = cast(FileTreeItem)item;
        if (!fileItem || !fileItem.isDirectory)
            return false;
            
        fileItem.isExpanded = expanded;
        
        if (expanded && !fileItem.isLoaded) {
            // Load contents
            try {
                // Clear existing children
                while (item.childCount > 0)
                    item.removeChild(0);
                loadDirectoryContents(fileItem);
                fileItem.isLoaded = true;
            } catch (Exception e) {
                Log.e("Error loading directory contents: ", e.msg);
            }
        }
        
        return true;
    }
    
    /**
     * Handle tree item click
     */
    bool onItemClicked(TreeItems source, TreeItem item) {
        FileTreeItem fileItem = cast(FileTreeItem)item;
        if (!fileItem)
            return false;
            
        if (!fileItem.isDirectory) {
            // Select the file
            // Notify file selection
            if (onFileSelected !is null)
                onFileSelected(fileItem.fullPath);
        }
        
        return true;
    }
    
    /**
     * Handle tree item right click
     */
    bool onItemRightClicked(TreeItems source, TreeItem item, int x, int y) {
        FileTreeItem fileItem = cast(FileTreeItem)item;
        if (!fileItem)
            return false;
            
        // Store path for context menu actions
        _contextMenuPath = fileItem.fullPath;
        
        // Just handle file selection directly for now
        if (fileItem && !fileItem.isDirectory) {
            if (onFileSelected !is null) {
                onFileSelected(fileItem.fullPath);
            }
        } else if (fileItem && fileItem.isDirectory) {
            // For directories, toggle expansion
            fileItem.isExpanded = !fileItem.isExpanded;
        }
        
        return true;
    }
    
    /**
     * Create context menu
     */
    private void createContextMenu() {
        // Simplified implementation - just create an empty menu
        _contextMenu = new PopupMenu(new MenuItem());
    }
    
    /**
     * Handle context menu actions
     */
    private bool handleContextMenuAction(MenuItem source, Action action) {
        // Simplified implementation - always return true
        return true;
    }
    
    /**
     * Create a new file
     */
    private void createNewFile(string parentPath) {
        // TODO: Show dialog to get file name
        string fileName = "new_file.txt";
        string newPath;
        
        if (isDir(parentPath)) {
            newPath = buildPath(parentPath, fileName);
        } else {
            newPath = buildPath(dirName(parentPath), fileName);
        }
        
        try {
            // Create empty file
            std.file.write(newPath, "");
            
            // Refresh parent directory
            refreshDirectory(dirName(newPath));
            
            // Notify listeners
            if (onFileCreated !is null)
                onFileCreated(newPath);
            
            Log.i("FileNavigator: Created file: ", newPath);
        } catch (Exception e) {
            Log.e("FileNavigator: Error creating file: ", e.msg);
        }
    }
    
    /**
     * Create a new folder
     */
    private void createNewFolder(string parentPath) {
        // TODO: Show dialog to get folder name
        string folderName = "new_folder";
        string newPath;
        
        if (isDir(parentPath)) {
            newPath = buildPath(parentPath, folderName);
        } else {
            newPath = buildPath(dirName(parentPath), folderName);
        }
        
        try {
            // Create directory
            mkdirRecurse(newPath);
            
            // Refresh parent directory
            refreshDirectory(dirName(newPath));
            
            Log.i("FileNavigator: Created folder: ", newPath);
        } catch (Exception e) {
            Log.e("FileNavigator: Error creating folder: ", e.msg);
        }
    }
    
    /**
     * Rename file or folder
     */
    private void renameFileOrFolder(string path) {
        // TODO: Show dialog to get new name
        string newName = baseName(path) ~ "_renamed";
        string newPath = buildPath(dirName(path), newName);
        
        try {
            // Rename file or folder
            rename(path, newPath);
            
            // Refresh parent directory
            refreshDirectory(dirName(path));
            
            // Notify listeners
            if (onFileRenamed !is null)
                onFileRenamed(newPath);
            
            Log.i("FileNavigator: Renamed: ", path, " to ", newPath);
        } catch (Exception e) {
            Log.e("FileNavigator: Error renaming: ", e.msg);
        }
    }
    
    /**
     * Delete file or folder
     */
    private void deleteFileOrFolder(string path) {
        // TODO: Show confirmation dialog
        
        try {
            if (isDir(path)) {
                // Remove directory recursively
                rmdirRecurse(path);
            } else {
                // Remove file
                remove(path);
            }
            
            // Refresh parent directory
            refreshDirectory(dirName(path));
            
            // Notify listeners
            if (onFileDeleted !is null)
                onFileDeleted(path);
            
            Log.i("FileNavigator: Deleted: ", path);
        } catch (Exception e) {
            Log.e("FileNavigator: Error deleting: ", e.msg);
        }
    }
    
    /**
     * Refresh a specific directory
     */

    private void refreshDirectory(string dirPath) {
        // Find the directory item in the tree
        FileTreeItem dirItem = findItemByPath(dirPath);
        
        if (dirItem) {
            // Clear and reload
            while (dirItem.childCount > 0)
                dirItem.removeChild(0);
            dirItem.isLoaded = false;
            loadDirectoryContents(dirItem);
        } else {
            // If not found, refresh the whole tree
            refresh();
        }
    }
    
    /**
     * Find a tree item by path
     */
    private FileTreeItem findItemByPath(string path) {
        // Recursive function to search the tree
        FileTreeItem findRecursive(TreeItem item, string searchPath) {
            FileTreeItem fileItem = cast(FileTreeItem)item;
            if (!fileItem)
                return null;
                
            if (fileItem.fullPath == searchPath)
                return fileItem;
                
            // Search children
            for (int i = 0; i < item.childCount; i++) {
                TreeItem child = item.child(i);
                FileTreeItem result = findRecursive(child, searchPath);
                if (result)
                    return result;
            }
            
            return null;
        }
        
        // Start search from root items
        foreach (TreeItem item; _fileTree.items) {
            FileTreeItem result = findRecursive(item, path);
            if (result)
                return result;
        }
        
        return null;
    }
    
    /**
     * Handle search box changes
     */
    private void onSearchChanged(string query) {
        _currentSearchQuery = query;
        
        if (query.length == 0) {
            // Exit search mode
            _isInSearchMode = false;
            refresh();
            return;
        }
        
        // Enter search mode
        _isInSearchMode = true;
        
        // Clear tree
        _fileTree.items.clear();
        
        // Search for files
        searchFiles(query);
    }
    
    /**
     * Perform file search
     */
    private void searchFiles(string query) {
        if (!_rootPath || _rootPath.length == 0)
            return;
            
        try {
            // Collect all files in the project
            string[] filePaths;
            
            void collectFiles(string dir) {
                try {
                    foreach (entry; dirEntries(dir, SpanMode.shallow)) {
                        if (entry.isDir && !baseName(entry.name).startsWith(".")) {
                            collectFiles(entry.name);
                        } else if (!entry.isDir && !baseName(entry.name).startsWith(".")) {
                            filePaths ~= entry.name;
                        }
                    }
                } catch (Exception e) {
                    // Skip directories we can't access
                }
            }
            
            collectFiles(_rootPath);
            
            // Perform fuzzy search
            auto results = _matcher.searchFiles(query, filePaths);
            
            // Add results to tree
            foreach (result; results) {
                // Create path segments
                string relativePath = result.path.replace(_rootPath ~ dirSeparator, "");
                string[] segments = relativePath.split(dirSeparator);
                
                // Create virtual directory structure based on path
                TreeItem currentParent = _fileTree.items;
                string currentPath = _rootPath;
                
                for (int i = 0; i < segments.length - 1; i++) {
                    currentPath = buildPath(currentPath, segments[i]);
                    
                    // Check if segment already exists in current parent
                    TreeItem existingItem = null;
                    for (int j = 0; j < currentParent.childCount; j++) {
                        TreeItem child = currentParent.child(j);
                        FileTreeItem fileItem = cast(FileTreeItem)child;
                        if (fileItem && fileItem.text == segments[i].toUTF32()) {
                            existingItem = child;
                            break;
                        }
                    }
                    
                    if (existingItem) {
                        currentParent = existingItem;
                    } else {
                        // Create new virtual directory
                        FileTreeItem newItem = new FileTreeItem(currentPath, true);
                        if (newItem.hasChildren)
                            newItem.expand();
                        currentParent.addChild(newItem);
                        currentParent = newItem;
                    }
                }
                
                // Add file as leaf
                FileTreeItem fileItem = new FileTreeItem(result.path, false);
                currentParent.addChild(fileItem);
            }
            
            // Expand all virtual directories
            for (int i = 0; i < _fileTree.items.childCount; i++) {
                TreeItem item = _fileTree.items.child(i);
                expandAll(item);
            }
            
        } catch (Exception e) {
            Log.e("FileNavigator: Error searching files: ", e.msg);
        }
    }
    
    /**
     * Expand all items recursively
     */
    private void expandAll(TreeItem item) {
        if (item && item.hasChildren) {
            item.expand();
            for (int i = 0; i < item.childCount; i++) {
                expandAll(item.child(i));
            }
        }
    }
    
    /**
     * Get currently selected file path
     */
    string getSelectedPath() {
        TreeItem selectedItem = _fileTree.items.selectedItem;
        if (!selectedItem)
            return null;
            
        FileTreeItem fileItem = cast(FileTreeItem)selectedItem;
        if (!fileItem)
            return null;
            
        return fileItem.fullPath;
    }
    
    /**
     * Select file by path
     */
    bool selectFile(string path) {
        FileTreeItem item = findItemByPath(path);
        
        if (item) {
            _fileTree.items.selectItem(item);
            _fileTree.invalidate();
            return true;
        }
        
        return false;
    }
}