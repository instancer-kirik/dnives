module dlangide.ui.diffmerger;

import dlangui;
import dlangui.widgets.widget;
import dlangui.widgets.layouts;
import dlangui.widgets.controls;
import dlangui.widgets.editors;
import dlangui.widgets.menu;
import dlangui.widgets.popup;
import dlangui.widgets.scrollbar;
import dlangui.widgets.splitter;
import dlangui.core.events;
import dlangui.core.signals;
import dlangui.dialogs.dialog;
import dlangui.dialogs.filedlg;
import dlangui.platforms.common.platform;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.utf;
import std.json;
import std.stdio;
import core.thread;

import dcore.editor.document;
import dcore.ai.code_action_manager;

/// Represents a difference between two text blocks
struct DiffBlock {
    string key;           // Unique identifier (function name, class name, etc.)
    string originalContent;
    string suggestedContent;
    int originalStartLine;
    int originalEndLine;
    int suggestedStartLine;
    int suggestedEndLine;
    bool isConflict;      // True if there's a meaningful difference
    bool isResolved;      // True if user has made a choice
    string resolvedContent; // Content chosen by user
}

/// Diff merge strategies
enum MergeStrategy {
    TakeOriginal,
    TakeSuggested,
    Manual,
    AIAssisted
}

/// Code block extraction configuration
struct BlockExtractionConfig {
    string[] keySymbols = ["def", "class", "function", "struct", "interface", "enum"];
    bool preserveOrder = true;
    bool includeComments = true;
    bool includeImports = true;
}

/// Event args for diff resolution
class DiffResolvedEventArgs : EventArgs {
    DiffBlock[] resolvedBlocks;
    string mergedContent;

    this(DiffBlock[] blocks, string content) {
        resolvedBlocks = blocks.dup;
        mergedContent = content;
    }
}

/// Main diff merger widget providing side-by-side comparison and merge capabilities
class DiffMergerWidget : Dialog {
    private {
        // UI Components
        SourceEdit _originalEditor;
        SourceEdit _suggestedEditor;
        SourceEdit _resultEditor;
        VScrollBar _syncScrollbar;

        // Control widgets
        Button _showDiffBtn;
        Button _clearResultBtn;
        Button _saveResultBtn;
        Button _applyChangesBtn;
        CheckBox _preserveOrderCheck;
        CheckBox _autoMergeCheck;
        ComboBox _strategyCombo;

        // Diff navigation
        Button _prevDiffBtn;
        Button _nextDiffBtn;
        TextWidget _diffCounterLabel;

        // AI integration
        Button _aiSuggestBtn;
        CheckBox _enableAICheck;

        // Layout containers
        HorizontalLayout _editorsLayout;
        VirtualLayout _diffsLayout;
        ScrollWidget _diffsScroll;
        VSplitter _mainSplitter;

        // Data
        DiffBlock[] _diffBlocks;
        BlockExtractionConfig _config;
        int _currentDiffIndex = -1;
        string _filePath;

        // State
        bool _isFullscreen = false;
        bool _syncScrolling = true;
    }

    // Events
    Signal!(DiffResolvedEventArgs) onDiffResolved;

    this(string originalText = "", string suggestedText = "", string filePath = null) {
        super(UIString.fromRaw("Diff Merger"), Platform.instance.mainWindow,
              DialogFlag.Modal | DialogFlag.Resizable, 1200, 800);

        _filePath = filePath;
        _config = BlockExtractionConfig();

        createUI();
        loadTexts(originalText, suggestedText);

        if (_filePath) {
            windowCaption = UIString.fromRaw("Diff Merger - " ~ baseName(_filePath));
        }
    }

    private void createUI() {
        // Main vertical layout
        VerticalLayout mainLayout = new VerticalLayout("mainLayout");
        mainLayout.layoutWidth = FILL_PARENT;
        mainLayout.layoutHeight = FILL_PARENT;
        mainLayout.margins = Rect(8, 8, 8, 8);

        // Toolbar
        mainLayout.addChild(createToolbar());

        // Main content splitter
        _mainSplitter = new VSplitter("mainSplitter");
        _mainSplitter.layoutWidth = FILL_PARENT;
        _mainSplitter.layoutHeight = FILL_PARENT;

        // Top section: editors
        Widget editorsSection = createEditorsSection();
        editorsSection.layoutHeight = WRAP_CONTENT;
        editorsSection.minHeight = 300;
        _mainSplitter.addChild(editorsSection);

        // Bottom section: diff details
        Widget diffsSection = createDiffsSection();
        diffsSection.layoutHeight = WRAP_CONTENT;
        diffsSection.minHeight = 200;
        _mainSplitter.addChild(diffsSection);

        mainLayout.addChild(_mainSplitter);

        // Status bar
        mainLayout.addChild(createStatusBar());

        // Action buttons
        mainLayout.addChild(createActionButtons());

        addChild(mainLayout);
        setupEventHandlers();
    }

    private Widget createToolbar() {
        HorizontalLayout toolbar = new HorizontalLayout("toolbar");
        toolbar.layoutWidth = FILL_PARENT;
        toolbar.layoutHeight = WRAP_CONTENT;
        toolbar.margins = Rect(0, 0, 0, 8);

        _showDiffBtn = new Button("showDiff", "Show Diff"d);
        _clearResultBtn = new Button("clearResult", "Clear Result"d);
        _saveResultBtn = new Button("saveResult", "Save Result"d);

        toolbar.addChild(_showDiffBtn);
        toolbar.addChild(_clearResultBtn);
        toolbar.addChild(_saveResultBtn);

        // Spacer
        Widget spacer = new Widget("spacer");
        spacer.layoutWidth = FILL_PARENT;
        toolbar.addChild(spacer);

        // Options
        _preserveOrderCheck = new CheckBox("preserveOrder", "Preserve Original Order"d);
        _preserveOrderCheck.checked = _config.preserveOrder;
        toolbar.addChild(_preserveOrderCheck);

        _autoMergeCheck = new CheckBox("autoMerge", "Auto-merge Non-conflicts"d);
        toolbar.addChild(_autoMergeCheck);

        return toolbar;
    }

    private Widget createEditorsSection() {
        HorizontalLayout editorsContainer = new HorizontalLayout("editorsContainer");
        editorsContainer.layoutWidth = FILL_PARENT;
        editorsContainer.layoutHeight = FILL_PARENT;

        // Original text editor
        VerticalLayout originalSection = new VerticalLayout();
        originalSection.layoutWidth = FILL_PARENT;
        originalSection.layoutHeight = FILL_PARENT;

        TextWidget originalLabel = new TextWidget("originalLabel", "Original"d);
        originalSection.addChild(originalLabel);

        _originalEditor = new SourceEdit("originalEditor");
        _originalEditor.layoutWidth = FILL_PARENT;
        _originalEditor.layoutHeight = FILL_PARENT;
        _originalEditor.readOnly = true;
        originalSection.addChild(_originalEditor);

        Button takeOriginalBtn = new Button("takeOriginal", "← Take Original"d);
        originalSection.addChild(takeOriginalBtn);

        editorsContainer.addChild(originalSection);

        // Control column
        VerticalLayout controlColumn = new VerticalLayout();
        controlColumn.layoutWidth = WRAP_CONTENT;
        controlColumn.layoutHeight = FILL_PARENT;
        controlColumn.minWidth = 120;
        controlColumn.margins = Rect(8, 0, 8, 0);

        // Navigation controls
        _prevDiffBtn = new Button("prevDiff", "↑ Prev"d);
        _nextDiffBtn = new Button("nextDiff", "↓ Next"d);
        _diffCounterLabel = new TextWidget("diffCounter", "0/0"d);

        controlColumn.addChild(_prevDiffBtn);
        controlColumn.addChild(_nextDiffBtn);
        controlColumn.addChild(_diffCounterLabel);

        // Strategy selection
        TextWidget strategyLabel = new TextWidget("strategyLabel", "Strategy:"d);
        controlColumn.addChild(strategyLabel);

        _strategyCombo = new ComboBox("strategyCombo",
            ["Take Original"d, "Take Suggested"d, "Manual"d, "AI Assisted"d]);
        _strategyCombo.selectedItemIndex = 2; // Manual by default
        controlColumn.addChild(_strategyCombo);

        // AI controls
        _enableAICheck = new CheckBox("enableAI", "Enable AI"d);
        _aiSuggestBtn = new Button("aiSuggest", "AI Suggest"d);
        _aiSuggestBtn.enabled = false;

        controlColumn.addChild(_enableAICheck);
        controlColumn.addChild(_aiSuggestBtn);

        editorsContainer.addChild(controlColumn);

        // Suggested text editor
        VerticalLayout suggestedSection = new VerticalLayout();
        suggestedSection.layoutWidth = FILL_PARENT;
        suggestedSection.layoutHeight = FILL_PARENT;

        TextWidget suggestedLabel = new TextWidget("suggestedLabel", "Suggested"d);
        suggestedSection.addChild(suggestedLabel);

        _suggestedEditor = new SourceEdit("suggestedEditor");
        _suggestedEditor.layoutWidth = FILL_PARENT;
        _suggestedEditor.layoutHeight = FILL_PARENT;
        _suggestedEditor.readOnly = true;
        suggestedSection.addChild(_suggestedEditor);

        Button takeSuggestedBtn = new Button("takeSuggested", "Take Suggested →"d);
        suggestedSection.addChild(takeSuggestedBtn);

        editorsContainer.addChild(suggestedSection);

        return editorsContainer;
    }

    private Widget createDiffsSection() {
        VerticalLayout diffsContainer = new VerticalLayout("diffsContainer");
        diffsContainer.layoutWidth = FILL_PARENT;
        diffsContainer.layoutHeight = FILL_PARENT;

        TextWidget diffsLabel = new TextWidget("diffsLabel", "Diff Details"d);
        diffsContainer.addChild(diffsLabel);

        _diffsScroll = new ScrollWidget("diffsScroll");
        _diffsScroll.layoutWidth = FILL_PARENT;
        _diffsScroll.layoutHeight = FILL_PARENT;

        _diffsLayout = new VirtualLayout("diffsLayout");
        _diffsLayout.layoutWidth = FILL_PARENT;
        _diffsLayout.layoutHeight = WRAP_CONTENT;

        _diffsScroll.contentWidget = _diffsLayout;
        diffsContainer.addChild(_diffsScroll);

        return diffsContainer;
    }

    private Widget createStatusBar() {
        HorizontalLayout statusBar = new HorizontalLayout("statusBar");
        statusBar.layoutWidth = FILL_PARENT;
        statusBar.layoutHeight = WRAP_CONTENT;
        statusBar.margins = Rect(0, 8, 0, 0);

        TextWidget statusText = new TextWidget("statusText", "Ready"d);
        statusBar.addChild(statusText);

        return statusBar;
    }

    private Widget createActionButtons() {
        HorizontalLayout buttonLayout = new HorizontalLayout("actionButtons");
        buttonLayout.layoutWidth = FILL_PARENT;
        buttonLayout.layoutHeight = WRAP_CONTENT;
        buttonLayout.margins = Rect(0, 8, 0, 0);

        // Spacer to push buttons to the right
        Widget spacer = new Widget("spacer");
        spacer.layoutWidth = FILL_PARENT;
        buttonLayout.addChild(spacer);

        Button cancelBtn = new Button("cancel", "Cancel"d);
        Button okBtn = new Button("ok", "Apply Changes"d);

        buttonLayout.addChild(cancelBtn);
        buttonLayout.addChild(okBtn);

        return buttonLayout;
    }

    private void setupEventHandlers() {
        // Button click handlers
        _showDiffBtn.click = delegate(Widget source) {
            showDiff();
            return true;
        };

        _clearResultBtn.click = delegate(Widget source) {
            clearResult();
            return true;
        };

        _nextDiffBtn.click = delegate(Widget source) {
            navigateToNextDiff();
            return true;
        };

        _prevDiffBtn.click = delegate(Widget source) {
            navigateToPreviousDiff();
            return true;
        };

        _enableAICheck.checkChange = delegate(Widget source, bool checked) {
            _aiSuggestBtn.enabled = checked;
            return true;
        };

        // Scroll synchronization
        _originalEditor.onScrollPosChange = delegate(AbstractSlider source, ScrollEvent event) {
            if (_syncScrolling) {
                syncEditorScrolling(_originalEditor);
            }
            return true;
        };

        _suggestedEditor.onScrollPosChange = delegate(AbstractSlider source, ScrollEvent event) {
            if (_syncScrolling) {
                syncEditorScrolling(_suggestedEditor);
            }
            return true;
        };
    }

    private void loadTexts(string originalText, string suggestedText) {
        if (originalText.length > 0) {
            _originalEditor.text = originalText.toUTF32();
        }
        if (suggestedText.length > 0) {
            _suggestedEditor.text = suggestedText.toUTF32();
        }
    }

    private void showDiff() {
        string originalText = _originalEditor.text.toUTF8();
        string suggestedText = _suggestedEditor.text.toUTF8();

        if (originalText.empty && suggestedText.empty) {
            showMessageBox("Warning"d, "Both editors are empty"d);
            return;
        }

        // Extract code blocks and analyze differences
        _diffBlocks = analyzeDifferences(originalText, suggestedText);

        // Update diff display
        updateDiffDisplay();
        updateNavigationState();

        // Auto-navigate to first conflict if any
        if (_diffBlocks.length > 0) {
            _currentDiffIndex = 0;
            navigateToCurrentDiff();
        }
    }

    private DiffBlock[] analyzeDifferences(string originalText, string suggestedText) {
        DiffBlock[] blocks;

        auto originalBlocks = extractCodeBlocks(originalText, "original");
        auto suggestedBlocks = extractCodeBlocks(suggestedText, "suggested");

        // Determine block order
        string[] allKeys;
        if (_config.preserveOrder) {
            allKeys = originalBlocks.keys;
            foreach (key; suggestedBlocks.keys) {
                if (!allKeys.canFind(key)) {
                    allKeys ~= key;
                }
            }
        } else {
            allKeys = suggestedBlocks.keys;
            foreach (key; originalBlocks.keys) {
                if (!allKeys.canFind(key)) {
                    allKeys ~= key;
                }
            }
        }

        foreach (key; allKeys) {
            DiffBlock block;
            block.key = key;

            if (key in originalBlocks) {
                auto orig = originalBlocks[key];
                block.originalContent = orig.content;
                block.originalStartLine = orig.startLine;
                block.originalEndLine = orig.endLine;
            }

            if (key in suggestedBlocks) {
                auto sugg = suggestedBlocks[key];
                block.suggestedContent = sugg.content;
                block.suggestedStartLine = sugg.startLine;
                block.suggestedEndLine = sugg.endLine;
            }

            // Determine if this is a conflict
            block.isConflict = isContentDifferent(block.originalContent, block.suggestedContent);

            blocks ~= block;
        }

        return blocks;
    }

    private auto extractCodeBlocks(string text, string source) {
        struct CodeBlock {
            string content;
            int startLine;
            int endLine;
        }

        CodeBlock[string] blocks;
        string[] lines = text.splitLines();

        string currentKey = "global";
        string[] currentBlock;
        int startLine = 0;

        foreach (i, line; lines) {
            string trimmedLine = line.strip();

            // Check if line starts with a key symbol
            bool isKeyLine = false;
            foreach (symbol; _config.keySymbols) {
                if (trimmedLine.startsWith(symbol ~ " ") ||
                    trimmedLine.startsWith(symbol ~ "\t") ||
                    (trimmedLine.length > symbol.length &&
                     trimmedLine.startsWith(symbol) &&
                     !trimmedLine[symbol.length].isAlphaNum())) {
                    isKeyLine = true;
                    break;
                }
            }

            if (isKeyLine) {
                // Save previous block
                if (currentBlock.length > 0) {
                    blocks[currentKey] = CodeBlock(
                        currentBlock.join("\n"),
                        startLine,
                        cast(int)i - 1
                    );
                }

                // Start new block
                currentKey = trimmedLine;
                currentBlock = [line];
                startLine = cast(int)i;
            } else {
                currentBlock ~= line;
            }
        }

        // Save final block
        if (currentBlock.length > 0) {
            blocks[currentKey] = CodeBlock(
                currentBlock.join("\n"),
                startLine,
                cast(int)lines.length - 1
            );
        }

        return blocks;
    }

    private bool isContentDifferent(string content1, string content2) {
        // Simple content comparison - could be enhanced with more sophisticated diff
        return content1.strip() != content2.strip();
    }

    private void updateDiffDisplay() {
        // Clear existing diff widgets
        _diffsLayout.removeAllChildren();

        foreach (i, ref block; _diffBlocks) {
            Widget diffWidget = createDiffBlockWidget(i, block);
            _diffsLayout.addChild(diffWidget);
        }
    }

    private Widget createDiffBlockWidget(int index, ref DiffBlock block) {
        VerticalLayout container = new VerticalLayout();
        container.layoutWidth = FILL_PARENT;
        container.layoutHeight = WRAP_CONTENT;
        container.margins = Rect(4, 4, 4, 4);
        container.backgroundColor = block.isConflict ? 0xFFFFE0E0 : 0xFFE0FFE0;

        // Header
        HorizontalLayout header = new HorizontalLayout();
        header.layoutWidth = FILL_PARENT;
        header.layoutHeight = WRAP_CONTENT;

        TextWidget keyLabel = new TextWidget();
        keyLabel.text = (block.key ~ " " ~ (block.isConflict ? "[CONFLICT]" : "[OK]")).toUTF32();
        keyLabel.textColor = block.isConflict ? 0xFF800000 : 0xFF008000;
        header.addChild(keyLabel);

        // Action buttons for conflicts
        if (block.isConflict) {
            Button takeOrigBtn = new Button();
            takeOrigBtn.text = "Take Original"d;
            takeOrigBtn.click = delegate(Widget source) {
                resolveBlock(index, MergeStrategy.TakeOriginal);
                return true;
            };

            Button takeSuggBtn = new Button();
            takeSuggBtn.text = "Take Suggested"d;
            takeSuggBtn.click = delegate(Widget source) {
                resolveBlock(index, MergeStrategy.TakeSuggested);
                return true;
            };

            header.addChild(takeOrigBtn);
            header.addChild(takeSuggBtn);
        }

        container.addChild(header);

        // Content preview (truncated)
        if (block.isConflict) {
            TextWidget contentPreview = new TextWidget();
            string preview = block.originalContent;
            if (preview.length > 100) {
                preview = preview[0..100] ~ "...";
            }
            contentPreview.text = preview.toUTF32();
            contentPreview.textColor = 0xFF666666;
            container.addChild(contentPreview);
        }

        return container;
    }

    private void resolveBlock(int index, MergeStrategy strategy) {
        if (index < 0 || index >= _diffBlocks.length) return;

        auto block = &_diffBlocks[index];

        final switch (strategy) {
            case MergeStrategy.TakeOriginal:
                block.resolvedContent = block.originalContent;
                break;
            case MergeStrategy.TakeSuggested:
                block.resolvedContent = block.suggestedContent;
                break;
            case MergeStrategy.Manual:
                // Open manual editor - would need implementation
                break;
            case MergeStrategy.AIAssisted:
                // Request AI assistance - would integrate with AI system
                break;
        }

        block.isResolved = true;

        // Update display
        updateDiffDisplay();
        updateResult();
    }

    private void updateResult() {
        string[] resultLines;

        foreach (ref block; _diffBlocks) {
            if (block.isResolved) {
                resultLines ~= block.resolvedContent.splitLines();
            } else if (!block.isConflict) {
                // Non-conflict blocks use suggested content by default
                resultLines ~= block.suggestedContent.splitLines();
            } else {
                // Unresolved conflict - mark it
                resultLines ~= ["// UNRESOLVED CONFLICT: " ~ block.key];
                resultLines ~= block.originalContent.splitLines();
                resultLines ~= ["// --- VS ---"];
                resultLines ~= block.suggestedContent.splitLines();
                resultLines ~= ["// END CONFLICT"];
            }
        }

        if (_resultEditor is null) {
            // Create result editor if it doesn't exist
            _resultEditor = new SourceEdit("resultEditor");
            _resultEditor.layoutWidth = FILL_PARENT;
            _resultEditor.layoutHeight = FILL_PARENT;
        }

        _resultEditor.text = resultLines.join("\n").toUTF32();
    }

    private void clearResult() {
        if (_resultEditor) {
            _resultEditor.text = ""d;
        }
        _diffBlocks.length = 0;
        updateDiffDisplay();
        updateNavigationState();
    }

    private void navigateToNextDiff() {
        if (_diffBlocks.length == 0) return;

        _currentDiffIndex++;
        if (_currentDiffIndex >= _diffBlocks.length) {
            _currentDiffIndex = 0;
        }
        navigateToCurrentDiff();
    }

    private void navigateToPreviousDiff() {
        if (_diffBlocks.length == 0) return;

        _currentDiffIndex--;
        if (_currentDiffIndex < 0) {
            _currentDiffIndex = cast(int)_diffBlocks.length - 1;
        }
        navigateToCurrentDiff();
    }

    private void navigateToCurrentDiff() {
        if (_currentDiffIndex < 0 || _currentDiffIndex >= _diffBlocks.length) return;

        auto block = _diffBlocks[_currentDiffIndex];

        // Scroll editors to show the current diff
        if (block.originalStartLine >= 0) {
            // Would need to implement line-based scrolling
            // _originalEditor.scrollToLine(block.originalStartLine);
        }
        if (block.suggestedStartLine >= 0) {
            // _suggestedEditor.scrollToLine(block.suggestedStartLine);
        }

        updateNavigationState();
    }

    private void updateNavigationState() {
        if (_diffCounterLabel) {
            string text = format("%d/%d", _currentDiffIndex + 1, _diffBlocks.length);
            _diffCounterLabel.text = text.toUTF32();
        }

        if (_prevDiffBtn) _prevDiffBtn.enabled = _diffBlocks.length > 0;
        if (_nextDiffBtn) _nextDiffBtn.enabled = _diffBlocks.length > 0;
    }

    private void syncEditorScrolling(SourceEdit sourceEditor) {
        if (!_syncScrolling) return;

        // Get scroll position from source editor
        // Sync other editors to same position
        // This would need proper implementation with DlangUI scroll handling
    }

    /// Get the merged content result
    string getMergedContent() {
        if (_resultEditor) {
            return _resultEditor.text.toUTF8();
        }
        return "";
    }

    /// Check if there are unresolved conflicts
    bool hasUnresolvedConflicts() {
        foreach (ref block; _diffBlocks) {
            if (block.isConflict && !block.isResolved) {
                return true;
            }
        }
        return false;
    }

    /// Get statistics about the diff
    auto getDiffStats() {
        struct DiffStats {
            int totalBlocks;
            int conflicts;
            int resolved;
            int autoMerged;
        }

        DiffStats stats;
        stats.totalBlocks = cast(int)_diffBlocks.length;

        foreach (ref block; _diffBlocks) {
            if (block.isConflict) {
                stats.conflicts++;
                if (block.isResolved) {
                    stats.resolved++;
                }
            } else {
                stats.autoMerged++;
            }
        }

        return stats;
    }

    override void close(const Action action) {
        if (action.id == StandardAction.Ok) {
            if (hasUnresolvedConflicts()) {
                showMessageBox("Unresolved Conflicts"d,
                             "There are still unresolved conflicts. Please resolve them first."d);
                return;
            }

            // Emit resolved event
            if (onDiffResolved.assigned) {
                onDiffResolved(new DiffResolvedEventArgs(_diffBlocks, getMergedContent()));
            }
        }

        super.close(action);
    }
}

/// Factory function to create and show diff merger dialog
DiffMergerWidget createDiffMerger(string originalText, string suggestedText,
                                 string filePath = null) {
    auto merger = new DiffMergerWidget(originalText, suggestedText, filePath);
    return merger;
}
