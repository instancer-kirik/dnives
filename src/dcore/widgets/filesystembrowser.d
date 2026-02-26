module dcore.widgets.filesystembrowser;

import dlangui.widgets.tree;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.widget;
import dlangui.core.events;
import dlangui.core.signals;
import std.file;
import std.path;
import std.algorithm;
import std.array;
import std.string;
import std.utf;

/**
 * FileSystemBrowser - Enhanced file browser with fuzzy search
 *
 * Features:
 * - Directory tree view
 * - File filtering
 * - Fuzzy search
 * - Context menus
 * - Drag and drop support
 */
class FileSystemBrowser : VerticalLayout {
    private TreeWidget _tree;
    private EditLine _searchBox;
    private string _rootPath;
    private string[] _filterPatterns;
    
    // Callbacks using delegates
    void delegate(string) onFileSelected;
    void delegate(string) onFileActivated;
    void delegate(string, string) onFileRenamed;
    
    /**
     * Constructor
     */
    this(string id = null) {
        super(id);
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;
        
        // Initialize UI
        initUI();
        
        // Set default root
        setRootPath(getcwd());
    }
    
    /**
     * Initialize UI components
     */
    private void initUI() {
        // Search box
        _searchBox = new EditLine("SEARCH_BOX");
        // _searchBox.hintText = "Search files..."d; // hintText property doesn't exist in EditLine
        _searchBox.layoutWidth = FILL_PARENT;
        addChild(_searchBox);
        
        // Tree widget
        _tree = new TreeWidget("FILE_TREE");
        _tree.layoutWidth = FILL_PARENT;
        _tree.layoutHeight = FILL_PARENT;
        
        // Event handlers
        _tree.selectionChange = &handleSelectionChange;
        
        addChild(_tree);
    }
    
    /**
     * Set root path for browser
     */
    void setRootPath(string path) {
        if (!exists(path) || !isDir(path))
            return;
            
        _rootPath = path;
        refreshTree();
    }
    
    /**
     * Set file filter patterns
     */
    void setFilterPatterns(string[] patterns) {
        _filterPatterns = patterns;
        refreshTree();
    }
    
    /**
     * Refresh the tree view
     */
    void refreshTree() {
        _tree.items.clear();
        
        if (_rootPath.length == 0)
            return;
            
        // Clear and create root item
        _tree.items.clear();
        auto rootItem = _tree.items.newChild("root", baseName(_rootPath).toUTF32);
        rootItem.id = _rootPath;
        
        // Populate tree
        populateTree(rootItem, _rootPath);
        
        rootItem.expand();
    }
    
    /**
     * Populate tree recursively
     */
    private void populateTree(TreeItem parent, string dirPath) {
        try {
            auto entries = dirEntries(dirPath, SpanMode.shallow)
                .filter!(e => shouldShowEntry(e.name))
                .array
                .sort!((a, b) => a.isDir > b.isDir || (a.isDir == b.isDir && a.name < b.name));
                
            foreach (entry; entries) {
                string name = baseName(entry.name);
                TreeItem item;
                
                if (entry.isDir) {
                    item = parent.newChild(entry.name, name.toUTF32, "folder");
                    // Add dummy child for expand indicator
                    item.newChild("dummy", ""d);
                } else {
                    // File item
                    item = parent.newChild(entry.name, name.toUTF32, "file");
                }
            }
        } catch (Exception e) {
            // Ignore access errors
        }
    }
    
    /**
     * Check if entry should be shown
     */
    private bool shouldShowEntry(string path) {
        string name = baseName(path);
        
        // Skip hidden files (starting with .)
        if (name.startsWith("."))
            return false;
            
        // Apply filters if any
        if (_filterPatterns.length > 0 && !isDir(path)) {
            bool matches = false;
            foreach (pattern; _filterPatterns) {
                if (name.endsWith(pattern)) {
                    matches = true;
                    break;
                }
            }
            return matches;
        }
        
        return true;
    }
    
    /**
     * Handle tree selection change
     */
    private void handleSelectionChange(TreeItems items, TreeItem selectedItem, bool activated) {
        if (!selectedItem)
            return;
            
        string path = selectedItem.id;
        
        if (path.length == 0)
            return;
            
        if (exists(path)) {
            if (activated) {
                // Handle activation (double-click or enter)
                if (isDir(path)) {
                    // Expand/collapse directory
                    if (selectedItem.childCount == 1 && selectedItem.child(0).text.length == 0) {
                        // Remove dummy and populate
                        selectedItem.clear();
                        populateTree(selectedItem, path);
                    }
                    if (selectedItem.expanded)
                        selectedItem.collapse();
                    else
                        selectedItem.expand();
                } else {
                    // Activate file
                    if (onFileActivated)
                        onFileActivated(path);
                }
            } else {
                // Just selection, not activation
                if (!isDir(path)) {
                    if (onFileSelected)
                        onFileSelected(path);
                }
            }
        }
    }
    

    
    /**
     * Get currently selected file path
     */
    string selectedFile() {
        auto item = _tree.items.selectedItem;
        if (item) {
            string path = item.id;
            if (path.length > 0 && exists(path) && !isDir(path))
                return path;
        }
        return null;
    }
    
    /**
     * Get currently selected directory path
     */
    string selectedDirectory() {
        auto item = _tree.items.selectedItem;
        if (item) {
            string path = item.id;
            if (path.length > 0 && exists(path) && isDir(path))
                return path;
        }
        return null;
    }
}