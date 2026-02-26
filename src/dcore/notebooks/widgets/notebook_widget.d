module dcore.notebooks.widgets.notebook_widget;

import dlangui.core.config;
import dlangui.core.logger;
import dlangui.core.signals;
import dlangui.graphics.colors;
import dlangui.graphics.drawbuf;
import dlangui.graphics.fonts;
import dlangui.widgets.controls;
import dlangui.widgets.combobox;
import dlangui.widgets.editors;
import dlangui.widgets.layouts;
import dlangui.widgets.menu;
import dlangui.widgets.popup;
import dlangui.widgets.scroll;
import dlangui.widgets.scrollbar;
import dcore.compat.splitter;
import dlangui.widgets.tabs;
import dlangui.widgets.tree;
import dlangui.widgets.widget;
import dlangui.widgets.winframe;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.format;
import std.json;
import std.string;
import std.typecons;

import dcore.notebooks.notebook;
import dcore.notebooks.executor;
import dcore.utils.signals : Signal;

/**
 * Individual cell widget that can be markdown or code
 */
class CellWidget : VerticalLayout {
    private NotebookCell _cell;
    private NotebookExecutor _executor;
    private CellHeaderWidget _header;
    private Widget _contentWidget;
    private Widget _outputWidget;
    private bool _isEditing;
    private bool _isSelected;

    // Signals
    Signal!(CellWidget) onCellSelected;
    Signal!(CellWidget) onCellDeleted;
    Signal!(CellWidget, CellWidget) onCellMoveRequest; // source, target
    Signal!() onContentChanged;

    this(NotebookCell cell, NotebookExecutor executor) {
        super("cell_widget");
        _cell = cell;
        _executor = executor;
        _isEditing = false;
        _isSelected = false;

        // Configure layout
        margins = Rect(4, 4, 4, 4);
        padding = Rect(8, 8, 8, 8);
        backgroundColor = 0xFFFFFF;

        setupUI();
        updateFromCell();

        // Connect cell signals
        if (_cell !is null) {
            _cell.onContentChanged.connect(&onCellContentChanged);
            _cell.onStateChanged.connect(&onCellStateChanged);
            _cell.onOutputChanged.connect(&onCellOutputChanged);
        }
    }

    @property NotebookCell cell() { return _cell; }
    @property bool isSelected() const { return _isSelected; }

    void setSelected(bool selected) {
        if (_isSelected != selected) {
            _isSelected = selected;
            updateSelection();
            if (selected) {
                onCellSelected.emit(this);
            }
        }
    }

    void startEditing() {
        _isEditing = true;
        updateContentWidget();
        requestLayout();
    }

    void stopEditing() {
        if (_isEditing) {
            _isEditing = false;
            saveContent();
            updateContentWidget();
            requestLayout();
        }
    }

    void executeCell() {
        if (_cell.isCodeCell() && _executor !is null) {
            auto kernelType = detectKernelType(_cell);
            _executor.executeCell(_cell, kernelType);
        }
    }

    private void setupUI() {
        // Create header
        _header = new CellHeaderWidget(_cell);
        _header.onExecuteClicked.connect(&executeCell);
        _header.onDeleteClicked.connect(() => onCellDeleted.emit(this));
        _header.onMoveUpClicked.connect(() => onCellMoveRequest.emit(this, null)); // null = move up
        _header.onMoveDownClicked.connect(() => onCellMoveRequest.emit(this, null)); // null = move down
        addChild(_header);

        // Create content area
        updateContentWidget();
    }

    private void updateContentWidget() {
        // Remove existing content widget
        if (_contentWidget !is null) {
            removeChild(_contentWidget);
            _contentWidget = null;
        }

        if (_isEditing) {
            // Create editor
            auto editor = new EditBox("cell_editor", _cell.source.to!dstring);
            // TODO: EditBox in dlangui 0.10.8 doesn't have multiline property - it's multiline by default
            // editor.multiline = true;
            editor.minHeight = 100;
            editor.maxHeight = 400;
            if (_cell.isCodeCell()) {
                editor.fontFace = "Courier New";
                editor.backgroundColor = 0xFFF8F8F8;
            }
            editor.contentChange = (EditableContent content) {
                if (_cell !is null) {
                    _cell.source = content.text.to!string;
                }
            };
            _contentWidget = editor;
        } else {
            if (_cell.isMarkdownCell()) {
                // Create markdown renderer
                _contentWidget = createMarkdownRenderer(_cell.source);
            } else {
                // Create code display
                _contentWidget = createCodeDisplay(_cell.source);
            }
        }

        addChild(_contentWidget);

        // Add output widget if needed
        updateOutputWidget();
    }

    private void updateOutputWidget() {
        // Remove existing output widget
        if (_outputWidget !is null) {
            removeChild(_outputWidget);
            _outputWidget = null;
        }

        if (_cell.isCodeCell() && (_cell.output.length > 0 || _cell.errorOutput.length > 0)) {
            auto outputContainer = new VerticalLayout("output_container");
            outputContainer.margins = Rect(0, 8, 0, 0);

            // Output header
            auto outputHeader = new HorizontalLayout();
            outputHeader.addChild(new TextWidget(null, "Output:"));

            if (_cell.executionCount > 0) {
                auto execCount = new TextWidget(null, format("[%d]", _cell.executionCount));
                execCount.textColor = 0xFF666666;
                outputHeader.addChild(execCount);
            }

            if (_cell.lastExecuted != SysTime.init) {
                auto timestamp = new TextWidget(null, format("(%s)", formatExecutionTime()));
                timestamp.textColor = 0xFF999999;
                timestamp.fontSize = 10;
                outputHeader.addChild(timestamp);
            }

            outputContainer.addChild(outputHeader);

            // Output content
            if (_cell.output.length > 0) {
                auto outputText = new TextWidget(null, _cell.output);
                outputText.fontFace = "Courier New";
                outputText.backgroundColor = 0xFFF8FFF8;
                outputText.padding = Rect(8, 4, 8, 4);
                outputContainer.addChild(outputText);
            }

            // Error output
            if (_cell.errorOutput.length > 0) {
                auto errorText = new TextWidget(null, _cell.errorOutput);
                errorText.fontFace = "Courier New";
                errorText.backgroundColor = 0xFFFFF8F8;
                errorText.textColor = 0xFFCC0000;
                errorText.padding = Rect(8, 4, 8, 4);
                outputContainer.addChild(errorText);
            }

            _outputWidget = outputContainer;
            addChild(_outputWidget);
        }
    }

    private Widget createMarkdownRenderer(string markdown) {
        // Simplified markdown renderer - in practice, you'd want a proper one
        auto renderer = new TextWidget("markdown_content", processMarkdown(markdown));
        renderer.backgroundColor = 0xFFFFFFF8;
        renderer.padding = Rect(12, 8, 12, 8);
        // TODO: TextWidget in dlangui 0.10.8 doesn't have multiline property
        // renderer.multiline = true;

        // Double-click to edit
        renderer.mouseEvent = delegate(Widget source, MouseEvent event) {
            if (event.action == MouseAction.ButtonDown && event.doubleClick) {
                startEditing();
                return true;
            }
            return false;
        };

        return renderer;
    }

    private Widget createCodeDisplay(string code) {
        auto codeWidget = new TextWidget("code_content", code);
        codeWidget.fontFace = "Courier New";
        codeWidget.backgroundColor = 0xFFF8F8F8;
        codeWidget.padding = Rect(12, 8, 12, 8);
        // TODO: TextWidget in dlangui 0.10.8 doesn't have multiline property
        // codeWidget.multiline = true;

        // Double-click to edit
        codeWidget.mouseEvent = delegate(Widget source, MouseEvent event) {
            if (event.action == MouseAction.ButtonDown && event.doubleClick) {
                startEditing();
                return true;
            }
            return false;
        };

        return codeWidget;
    }

    private string processMarkdown(string markdown) {
        // Very basic markdown processing - replace with proper parser
        string processed = markdown;

        // Headers
        import std.regex;
        processed = std.regex.replace(processed, regex(r"^# (.+)$", "gm"), "*** $1 ***");
        processed = std.regex.replace(processed, regex(r"^## (.+)$", "gm"), "** $1 **");
        processed = std.regex.replace(processed, regex(r"^### (.+)$", "gm"), "* $1 *");

        // Bold and italic (simplified)
        import std.string : replace;
        processed = processed.replace("**", ""); // Remove for now
        processed = processed.replace("*", "");  // Remove for now

        return processed;
    }

    private void saveContent() {
        if (_contentWidget !is null) {
            auto editor = cast(EditBox)_contentWidget;
            if (editor !is null && _cell !is null) {
                _cell.source = editor.text.to!string;
            }
        }
    }

    private void updateSelection() {
        if (_isSelected) {
            backgroundColor = 0xFFE8F4FD;
            // TODO: borderColor and borderWidth not available in dlangui 0.10.8
            // borderColor = 0xFF4A90E2;
            // borderWidth = 2;
        } else {
            backgroundColor = 0xFFFFFF;
            // TODO: borderColor and borderWidth not available in dlangui 0.10.8
            // borderColor = 0xFFE0E0E0;
            // borderWidth = 1;
        }
        invalidate();
    }

    private void updateFromCell() {
        if (_cell is null) return;

        _header.updateFromCell();
        updateContentWidget();
    }

    private string formatExecutionTime() {
        auto duration = Clock.currTime() - _cell.lastExecuted;
        if (duration < 1.seconds) {
            return "< 1s";
        } else if (duration < 1.minutes) {
            return format("%ds", duration.total!"seconds");
        } else {
            return format("%dm %ds", duration.total!"minutes", duration.total!"seconds" % 60);
        }
    }

    // Cell event handlers
    private void onCellContentChanged() {
        if (!_isEditing) {
            updateContentWidget();
        }
        onContentChanged.emit();
    }

    private void onCellStateChanged() {
        _header.updateFromCell();
        updateOutputWidget();
    }

    private void onCellOutputChanged(string output) {
        updateOutputWidget();
    }

    override bool onMouseEvent(MouseEvent event) {
        if (event.action == MouseAction.ButtonDown && event.button == MouseButton.Left) {
            setSelected(true);
            return true;
        }
        return super.onMouseEvent(event);
    }

    override bool onKeyEvent(KeyEvent event) {
        if (_isSelected && event.action == KeyAction.KeyDown) {
            switch (event.keyCode) {
                case KeyCode.RETURN:
                    if (event.flags & KeyFlag.Shift) {
                        executeCell();
                    } else {
                        startEditing();
                    }
                    return true;
                case KeyCode.ESCAPE:
                    if (_isEditing) {
                        stopEditing();
                        return true;
                    }
                    break;
                case KeyCode.DEL:
                    if (event.flags & KeyFlag.Control) {
                        onCellDeleted.emit(this);
                        return true;
                    }
                    break;
                default:
                    break;
            }
        }
        return super.onKeyEvent(event);
    }
}

/**
 * Cell header with controls and status
 */
class CellHeaderWidget : HorizontalLayout {
    private NotebookCell _cell;
    private TextWidget _statusText;
    private Button _executeButton;
    private Button _deleteButton;
    private Button _moveUpButton;
    private Button _moveDownButton;
    private ComboBox _cellTypeCombo;

    // Signals
    Signal!() onExecuteClicked;
    Signal!() onDeleteClicked;
    Signal!() onMoveUpClicked;
    Signal!() onMoveDownClicked;

    this(NotebookCell cell) {
        super("cell_header");
        _cell = cell;

        minHeight = 32;
        backgroundColor = 0xFFF0F0F0;
        padding = Rect(8, 4, 8, 4);

        setupUI();
        updateFromCell();
    }

    void updateFromCell() {
        if (_cell is null) return;

        // Update status text
        string statusText = "";
        switch (_cell.state) {
            case CellState.Idle:
                statusText = "Ready";
                break;
            case CellState.Running:
                statusText = "Running...";
                break;
            case CellState.Completed:
                statusText = format("Completed [%d]", _cell.executionCount);
                break;
            case CellState.Error:
                statusText = "Error";
                break;
            case CellState.Stale:
                statusText = "Stale";
                break;
            default:
                statusText = "Unknown";
                break;
        }

        if (_statusText !is null) {
            _statusText.text = statusText.to!dstring;
        }

        // Update execute button
        if (_executeButton !is null) {
            _executeButton.enabled = _cell.isCodeCell() && _cell.state != CellState.Running;
        }

        // Update cell type combo
        if (_cellTypeCombo !is null) {
            string typeName = _cell.type.to!string.toLower;
            for (int i = 0; i < _cellTypeCombo.items.length; i++) {
                if (_cellTypeCombo.items[i].toUTF8 == typeName) {
                    _cellTypeCombo.selectedItemIndex = i;
                    break;
                }
            }
        }
    }

    private void setupUI() {
        // Cell type selector
        _cellTypeCombo = new ComboBox("cell_type_combo");
        _cellTypeCombo.items = ["markdown"d, "code"d, "raw"d];
        _cellTypeCombo.minWidth = 80;
        _cellTypeCombo.itemClick = (Widget source, int itemIndex) {
            if (_cell !is null && itemIndex >= 0) {
                switch (itemIndex) {
                    case 0: _cell.type = CellType.Markdown; break;
                    case 1: _cell.type = CellType.Code; break;
                    case 2: _cell.type = CellType.Raw; break;
                    default: break;
                }
            }
            return true;
        };
        addChild(_cellTypeCombo);

        // Status text
        _statusText = new TextWidget("status_text", "Ready");
        _statusText.minWidth = 100;
        addChild(_statusText);

        // Spacer
        addChild(new HSpacer());

        // Control buttons
        _executeButton = new Button("execute_btn", "▶ Run");
        _executeButton.click = (Widget w) {
            onExecuteClicked.emit();
            return true;
        };
        addChild(_executeButton);

        _moveUpButton = new Button("move_up_btn", "↑");
        _moveUpButton.minWidth = 30;
        _moveUpButton.click = (Widget w) {
            onMoveUpClicked.emit();
            return true;
        };
        addChild(_moveUpButton);

        _moveDownButton = new Button("move_down_btn", "↓");
        _moveDownButton.minWidth = 30;
        _moveDownButton.click = (Widget w) {
            onMoveDownClicked.emit();
            return true;
        };
        addChild(_moveDownButton);

        _deleteButton = new Button("delete_btn", "×");
        _deleteButton.minWidth = 30;
        _deleteButton.backgroundColor = 0xFFFF6B6B;
        _deleteButton.click = (Widget w) {
            onDeleteClicked.emit();
            return true;
        };
        addChild(_deleteButton);
    }
}

/**
 * Notebook outline widget showing sections and navigation
 */
class NotebookOutlineWidget : VerticalLayout {
    private Notebook _notebook;
    private TreeWidget _outlineTree;

    Signal!(NotebookCell) onCellSelected;
    Signal!(NotebookSection) onSectionSelected;

    this(Notebook notebook) {
        super("notebook_outline");
        _notebook = notebook;

        setupUI();
        updateOutline();

        if (_notebook !is null) {
            _notebook.onSectionAdded.connect(&onNotebookChanged);
            _notebook.onSectionRemoved.connect(&onNotebookChanged);
        }
    }

    void updateOutline() {
        if (_outlineTree is null || _notebook is null) return;

        _outlineTree.clearAllItems();

        foreach (sectionIndex, section; _notebook.sections()) {
            auto sectionItem = _outlineTree.items.newChild(format("section_%d", sectionIndex), section.name.to!dstring);

            if (section.isBranching) {
                sectionItem.text = ("🔀 " ~ section.name).to!dstring;
            }

            foreach (cellIndex, cell; section.cells()) {
                string cellText = "";
                switch (cell.type) {
                    case CellType.Markdown:
                        cellText = "📝 " ~ (cell.source.length > 30 ?
                                           cell.source[0..30] ~ "..." : cell.source);
                        break;
                    case CellType.Code:
                        cellText = "⚡ " ~ (cell.source.length > 30 ?
                                          cell.source[0..30] ~ "..." : cell.source);
                        break;
                    default:
                        cellText = "📄 " ~ (cell.source.length > 30 ?
                                          cell.source[0..30] ~ "..." : cell.source);
                        break;
                }

                auto cellItem = sectionItem.newChild(format("cell_%s", cell.id), cellText.replace("\n", " ").to!dstring);
            }
        }
    }

    private void setupUI() {
        addChild(new TextWidget(null, "Notebook Outline"));

        _outlineTree = new TreeWidget("outline_tree");
        // TODO: Connect selection event handler when TreeWidget API is determined
        /*
        _outlineTree.onItemSelected = (TreeItem item) {
            if (item.id.startsWith("section_")) {
                // Navigate to section
            } else if (item.id.startsWith("cell_")) {
                // Navigate to cell
            }
            return true;
        };
        */

        addChild(_outlineTree);
    }

    private void onNotebookChanged(NotebookSection section) {
        updateOutline();
    }
}

/**
 * Main notebook widget with LiveBook-style interface
 */
class NotebookWidget : HorizontalLayout {
    private Notebook _notebook;
    private NotebookExecutor _executor;
    private ScrollWidget _mainScroll;
    private VerticalLayout _cellContainer;
    private NotebookOutlineWidget _outline;
    private CellWidget _selectedCell;
    private ToolBarWidget _toolbar;

    // Signals
    Signal!() onNotebookChanged;
    Signal!(Notebook) onNotebookSaved;

    this(Notebook notebook = null) {
        super("notebook_widget");
        _notebook = notebook;
        _executor = new NotebookExecutor();

        setupUI();

        if (_notebook !is null) {
            loadNotebook();
        }
    }

    @property Notebook notebook() { return _notebook; }

    void setNotebook(Notebook notebook) {
        _notebook = notebook;
        loadNotebook();
    }

    void saveNotebook() {
        if (_notebook !is null) {
            if (_notebook.save()) {
                onNotebookSaved.emit(_notebook);
            }
        }
    }

    void addNewCell(CellType type = CellType.Code) {
        if (_notebook is null) return;

        auto cell = _notebook.createCell(type);
        auto cellWidget = createCellWidget(cell);
        _cellContainer.addChild(cellWidget);

        // Select and start editing the new cell
        selectCell(cellWidget);
        cellWidget.startEditing();

        onNotebookChanged.emit();
    }

    void executeAllCells() {
        if (_notebook is null || _executor is null) return;

        _executor.executeNotebook(_notebook);
    }

    void clearAllOutputs() {
        if (_notebook is null || _executor is null) return;

        _executor.clearAllOutputs(_notebook);
        updateCellWidgets();
    }

    private void setupUI() {
        // Create splitter for main content and outline
        auto splitter = new HSplitter();

        // Main content area
        auto mainArea = new VerticalLayout("main_area");

        // Toolbar
        _toolbar = createToolbar();
        mainArea.addChild(_toolbar);

        // Scrollable cell container
        _mainScroll = new ScrollWidget("cell_scroll", ScrollBarMode.Invisible, ScrollBarMode.Auto);
        _cellContainer = new VerticalLayout("cell_container");
        _cellContainer.padding = Rect(16, 16, 16, 16);
        _mainScroll.contentWidget = _cellContainer;
        mainArea.addChild(_mainScroll);

        splitter.addChild(mainArea);

        // Outline panel
        auto outlinePanel = new VerticalLayout("outline_panel");
        outlinePanel.minWidth = 250;
        outlinePanel.maxWidth = 350;

        if (_notebook !is null) {
            _outline = new NotebookOutlineWidget(_notebook);
            outlinePanel.addChild(_outline);
        }

        splitter.addChild(outlinePanel);
        addChild(splitter);
    }

    private ToolBarWidget createToolbar() {
        auto toolbar = new ToolBarWidget("notebook_toolbar");

        // Add cell buttons
        toolbar.addButton("add_md_cell", "📝 + Markdown", () => addNewCell(CellType.Markdown));
        toolbar.addButton("add_code_cell", "⚡ + Code", () => addNewCell(CellType.Code));
        toolbar.addSeparator();

        // Execution buttons
        toolbar.addButton("run_all", "▶▶ Run All", () => executeAllCells());
        toolbar.addButton("clear_outputs", "🗑 Clear Outputs", () => clearAllOutputs());
        toolbar.addSeparator();

        // File operations
        toolbar.addButton("save_notebook", "💾 Save", () => saveNotebook());

        return toolbar;
    }

    private void loadNotebook() {
        // Clear existing cells
        _cellContainer.removeAllChildren();

        if (_notebook is null) return;

        // Create cell widgets for all sections
        foreach (section; _notebook.sections()) {
            foreach (cell; section.cells()) {
                auto cellWidget = createCellWidget(cell);
                _cellContainer.addChild(cellWidget);
            }
        }

        // Update outline
        if (_outline !is null) {
            _outline.updateOutline();
        }

        requestLayout();
    }

    private CellWidget createCellWidget(NotebookCell cell) {
        auto cellWidget = new CellWidget(cell, _executor);

        // Connect signals
        cellWidget.onCellSelected.connect(&selectCell);
        cellWidget.onCellDeleted.connect(&deleteCell);
        cellWidget.onCellMoveRequest.connect(&moveCell);
        cellWidget.onContentChanged.connect(() => onNotebookChanged.emit());

        return cellWidget;
    }

    private void selectCell(CellWidget cellWidget) {
        // Deselect previous cell
        if (_selectedCell !is null) {
            _selectedCell.setSelected(false);
        }

        // Select new cell
        _selectedCell = cellWidget;
        if (_selectedCell !is null) {
            _selectedCell.setSelected(true);
        }
    }

    private void deleteCell(CellWidget cellWidget) {
        if (cellWidget is null) return;

        // Remove from notebook
        auto cell = cellWidget.cell;
        if (cell !is null && _notebook !is null) {
            foreach (section; _notebook.sections()) {
                if (section.removeCell(cell)) {
                    break;
                }
            }
        }

        // Remove widget
        _cellContainer.removeChild(cellWidget);

        // Update selection
        if (_selectedCell == cellWidget) {
            _selectedCell = null;
        }

        onNotebookChanged.emit();
        requestLayout();
    }

    private void moveCell(CellWidget source, CellWidget target) {
        // Implement cell moving logic
        // This is a simplified version - full implementation would handle
        // moving between sections and proper positioning

        if (source is null) return;

        // For now, just move up or down within the same container
        int sourceIndex = -1;
        for (int i = 0; i < _cellContainer.childCount; i++) {
            if (_cellContainer.child(i) == source) {
                sourceIndex = i;
                break;
            }
        }

        if (sourceIndex >= 0) {
            if (target is null) {
                // Move up or down by 1
                // This would need more context about direction
            }
        }

        onNotebookChanged.emit();
    }

    private void updateCellWidgets() {
        // Refresh all cell widgets to reflect changes
        for (int i = 0; i < _cellContainer.childCount; i++) {
            auto cellWidget = cast(CellWidget)_cellContainer.child(i);
            if (cellWidget !is null) {
                cellWidget.onCellContentChanged(); // Trigger update
            }
        }
    }

    override bool onKeyEvent(KeyEvent event) {
        if (event.action == KeyAction.KeyDown) {
            switch (event.keyCode) {
                case KeyCode.KEY_N:
                    if (event.flags & KeyFlag.Control) {
                        if (event.flags & KeyFlag.Shift) {
                            addNewCell(CellType.Markdown);
                        } else {
                            addNewCell(CellType.Code);
                        }
                        return true;
                    }
                    break;
                case KeyCode.KEY_S:
                    if (event.flags & KeyFlag.Control) {
                        saveNotebook();
                        return true;
                    }
                    break;
                case KeyCode.KEY_R:
                    if (event.flags & KeyFlag.Control) {
                        executeAllCells();
                        return true;
                    }
                    break;
                default:
                    break;
            }
        }

        return super.onKeyEvent(event);
    }
}

/**
 * Simple toolbar widget for notebook operations
 */
class ToolBarWidget : HorizontalLayout {
    this(string id) {
        super(id);
        backgroundColor = 0xFFF5F5F5;
        padding = Rect(8, 4, 8, 4);
        minHeight = 36;
    }

    void addButton(string id, string text, void delegate() onClick) {
        auto button = new Button(id, text);
        button.click = (Widget w) {
            if (onClick !is null) onClick();
            return true;
        };
        addChild(button);
    }

    void addSeparator() {
        auto separator = new Widget("separator");
        separator.minWidth = 1;
        separator.maxWidth = 1;
        separator.backgroundColor = 0xFFCCCCCC;
        addChild(separator);

        // Add some spacing
        addChild(new HSpacer().layoutWidth(8));
    }
}
