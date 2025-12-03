module dlangide.ui.inlinediffeditor;

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
import dlangui.graphics.drawbuf;
import dlangui.graphics.colors;

import std.algorithm;
import std.array;
import std.string;
import std.conv;
import std.file;
import std.path;
import std.utf;
import std.json;
import std.stdio;
import std.datetime;
import std.format;
import std.math;

import dcore.editor.document;
import dcore.ai.code_action_manager;
import dlangide.ui.diffanalyzer;
import dlangide.ui.aimerger;
import dlangide.ui.dsourceedit;

/// Inline diff mode for the editor
enum InlineDiffMode {
    None,           // Normal editor mode
    SideBySide,     // Side-by-side comparison
    Unified,        // Unified diff view
    Overlay         // Changes overlaid on original
}

/// Represents an inline change suggestion
struct InlineChange {
    int startLine;
    int endLine;
    string originalText;
    string suggestedText;
    string reason;          // Why this change was suggested
    double confidence;      // AI confidence score
    bool isAccepted;        // User has accepted this change
    bool isRejected;        // User has rejected this change
    string changeId;        // Unique identifier
    ChangeType type;        // Type of change
}

/// Type of change
enum ChangeType {
    Insert,
    Delete,
    Replace,
    Move,
    Format
}

/// Widget for displaying inline change suggestions with accept/reject buttons
class InlineChangeWidget : HorizontalLayout {
    private {
        InlineChange _change;
        Button _acceptBtn;
        Button _rejectBtn;
        Button _previewBtn;
        TextWidget _reasonLabel;
        TextWidget _confidenceLabel;
        Widget _changePreview;
        bool _expanded = false;
    }

    Signal!(InlineChange, bool) onChangeAction; // emitted with (change, accepted)
    Signal!(InlineChange) onPreviewRequested;

    this(InlineChange change) {
        super("inlineChange_" ~ change.changeId);
        _change = change;
        createUI();
    }

    private void createUI() {
        layoutWidth = FILL_PARENT;
        layoutHeight = WRAP_CONTENT;
        margins = Rect(2, 2, 2, 2);
        padding = Rect(4, 4, 4, 4);
        backgroundColor = 0xFFFFF8DC; // Light yellow background

        // Change type indicator
        TextWidget typeLabel = new TextWidget();
        typeLabel.text = getChangeTypeIcon(_change.type);
        typeLabel.textColor = getChangeTypeColor(_change.type);
        typeLabel.fontSize = 12;
        typeLabel.minWidth = 20;
        addChild(typeLabel);

        // Reason text
        _reasonLabel = new TextWidget();
        _reasonLabel.text = _change.reason.toUTF32();
        _reasonLabel.textColor = 0xFF333333;
        _reasonLabel.fontSize = 10;
        _reasonLabel.layoutWidth = FILL_PARENT;
        addChild(_reasonLabel);

        // Confidence score
        _confidenceLabel = new TextWidget();
        _confidenceLabel.text = format("%.0f%%", _change.confidence * 100).toUTF32();
        _confidenceLabel.textColor = getConfidenceColor(_change.confidence);
        _confidenceLabel.fontSize = 10;
        _confidenceLabel.minWidth = 40;
        addChild(_confidenceLabel);

        // Action buttons
        _previewBtn = new Button("preview", "👁"d);
        _previewBtn.tooltipText = "Preview change"d;
        _previewBtn.minWidth = 30;
        _previewBtn.click = delegate(Widget source) {
            togglePreview();
            return true;
        };
        addChild(_previewBtn);

        _acceptBtn = new Button("accept", "✓"d);
        _acceptBtn.tooltipText = "Accept change"d;
        _acceptBtn.backgroundColor = 0xFF90EE90;
        _acceptBtn.minWidth = 30;
        _acceptBtn.click = delegate(Widget source) {
            acceptChange();
            return true;
        };
        addChild(_acceptBtn);

        _rejectBtn = new Button("reject", "✗"d);
        _rejectBtn.tooltipText = "Reject change"d;
        _rejectBtn.backgroundColor = 0xFFFFB6C1;
        _rejectBtn.minWidth = 30;
        _rejectBtn.click = delegate(Widget source) {
            rejectChange();
            return true;
        };
        addChild(_rejectBtn);
    }

    private void togglePreview() {
        _expanded = !_expanded;

        if (_expanded) {
            showPreview();
            _previewBtn.text = "🔼"d;
        } else {
            hidePreview();
            _previewBtn.text = "👁"d;
        }
    }

    private void showPreview() {
        if (_changePreview) return;

        _changePreview = new VerticalLayout();
        _changePreview.layoutWidth = FILL_PARENT;
        _changePreview.layoutHeight = WRAP_CONTENT;
        _changePreview.backgroundColor = 0xFFF5F5F5;
        _changePreview.margins = Rect(20, 4, 4, 4);

        // Original text
        if (_change.originalText.length > 0) {
            TextWidget originalLabel = new TextWidget();
            originalLabel.text = "- " ~ _change.originalText.toUTF32();
            originalLabel.textColor = 0xFFDC143C;
            originalLabel.fontSize = 9;
            _changePreview.addChild(originalLabel);
        }

        // Suggested text
        if (_change.suggestedText.length > 0) {
            TextWidget suggestedLabel = new TextWidget();
            suggestedLabel.text = "+ " ~ _change.suggestedText.toUTF32();
            suggestedLabel.textColor = 0xFF228B22;
            suggestedLabel.fontSize = 9;
            _changePreview.addChild(suggestedLabel);
        }

        // Insert after current layout
        if (parent) {
            auto parentLayout = cast(LinearLayout)parent;
            if (parentLayout) {
                int myIndex = parentLayout.childIndex(this);
                parentLayout.insertChild(_changePreview, myIndex + 1);
            }
        }
    }

    private void hidePreview() {
        if (_changePreview && _changePreview.parent) {
            _changePreview.parent.removeChild(_changePreview);
            _changePreview = null;
        }
    }

    private void acceptChange() {
        _change.isAccepted = true;
        backgroundColor = 0xFF90EE90; // Light green
        _acceptBtn.enabled = false;
        _rejectBtn.enabled = false;

        if (onChangeAction.assigned) {
            onChangeAction(_change, true);
        }
    }

    private void rejectChange() {
        _change.isRejected = true;
        backgroundColor = 0xFFFFB6C1; // Light red
        _acceptBtn.enabled = false;
        _rejectBtn.enabled = false;

        if (onChangeAction.assigned) {
            onChangeAction(_change, false);
        }
    }

    private dstring getChangeTypeIcon(ChangeType type) {
        final switch (type) {
            case ChangeType.Insert: return "+"d;
            case ChangeType.Delete: return "-"d;
            case ChangeType.Replace: return "~"d;
            case ChangeType.Move: return "↕"d;
            case ChangeType.Format: return "⚡"d;
        }
    }

    private uint getChangeTypeColor(ChangeType type) {
        final switch (type) {
            case ChangeType.Insert: return 0xFF228B22;   // Forest green
            case ChangeType.Delete: return 0xFFDC143C;   // Crimson
            case ChangeType.Replace: return 0xFF4169E1;  // Royal blue
            case ChangeType.Move: return 0xFF9932CC;     // Dark orchid
            case ChangeType.Format: return 0xFFFF8C00;   // Dark orange
        }
    }

    private uint getConfidenceColor(double confidence) {
        if (confidence >= 0.9) return 0xFF008000;      // Green
        if (confidence >= 0.7) return 0xFFFFA500;      // Orange
        if (confidence >= 0.5) return 0xFFFF4500;      // Orange red
        return 0xFFDC143C;                              // Crimson
    }

    @property InlineChange change() { return _change; }
}

/// Main editor with inline diff capabilities
class InlineDiffEditor : VerticalLayout {
    private {
        // Main editor
        SourceEdit _editor;

        // Diff state
        InlineDiffMode _diffMode = InlineDiffMode.None;
        InlineChange[] _pendingChanges;
        InlineChangeWidget[] _changeWidgets;

        // Side-by-side comparison
        HorizontalLayout _comparisonLayout;
        SourceEdit _originalEditor;
        SourceEdit _suggestedEditor;

        // Unified diff view
        ScrollWidget _unifiedScroll;
        VerticalLayout _unifiedLayout;

        // AI integration
        AIAssistedMerger _aiMerger;
        DiffAnalyzer _diffAnalyzer;

        // UI controls
        HorizontalLayout _diffToolbar;
        Button _showSideBySideBtn;
        Button _showUnifiedBtn;
        Button _showOverlayBtn;
        Button _acceptAllBtn;
        Button _rejectAllBtn;
        Button _aiSuggestBtn;
        CheckBox _autoApplyCheck;
        TextWidget _statusLabel;

        // State
        string _filePath;
        string _originalContent;
        bool _hasUnsavedChanges = false;
        int _activeChangeIndex = -1;
    }

    // Events
    Signal!(string) onContentChanged;
    Signal!(InlineChange[]) onChangesApplied;
    Signal!(InlineDiffMode) onDiffModeChanged;

    this(string filePath = null) {
        super("inlineDiffEditor");
        _filePath = filePath;
        _diffAnalyzer = new DiffAnalyzer();

        createUI();
        setupEventHandlers();

        if (_filePath && exists(_filePath)) {
            loadFile(_filePath);
        }
    }

    private void createUI() {
        layoutWidth = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        // Create diff toolbar
        createDiffToolbar();
        addChild(_diffToolbar);

        // Main editor (default view)
        _editor = new SourceEdit("mainEditor");
        _editor.layoutWidth = FILL_PARENT;
        _editor.layoutHeight = FILL_PARENT;
        addChild(_editor);

        // Initially hidden comparison layout
        createComparisonLayout();

        // Initially hidden unified diff layout
        createUnifiedDiffLayout();
    }

    private void createDiffToolbar() {
        _diffToolbar = new HorizontalLayout("diffToolbar");
        _diffToolbar.layoutWidth = FILL_PARENT;
        _diffToolbar.layoutHeight = WRAP_CONTENT;
        _diffToolbar.backgroundColor = 0xFFF0F0F0;
        _diffToolbar.margins = Rect(0, 0, 0, 4);
        _diffToolbar.padding = Rect(4, 4, 4, 4);
        _diffToolbar.visibility = Visibility.Gone; // Hidden by default

        // Mode buttons
        _showSideBySideBtn = new Button("sideBySide", "Side by Side"d);
        _showUnifiedBtn = new Button("unified", "Unified"d);
        _showOverlayBtn = new Button("overlay", "Overlay"d);

        _diffToolbar.addChild(_showSideBySideBtn);
        _diffToolbar.addChild(_showUnifiedBtn);
        _diffToolbar.addChild(_showOverlayBtn);

        // Separator
        _diffToolbar.addChild(new VSpacer());

        // Action buttons
        _acceptAllBtn = new Button("acceptAll", "✓ Accept All"d);
        _rejectAllBtn = new Button("rejectAll", "✗ Reject All"d);
        _aiSuggestBtn = new Button("aiSuggest", "🤖 AI Suggest"d);

        _diffToolbar.addChild(_acceptAllBtn);
        _diffToolbar.addChild(_rejectAllBtn);
        _diffToolbar.addChild(_aiSuggestBtn);

        // Options
        _autoApplyCheck = new CheckBox("autoApply", "Auto-apply high confidence changes"d);
        _diffToolbar.addChild(_autoApplyCheck);

        // Status
        _statusLabel = new TextWidget("status", "Ready"d);
        _statusLabel.layoutWidth = FILL_PARENT;
        _statusLabel.textColor = 0xFF666666;
        _diffToolbar.addChild(_statusLabel);
    }

    private void createComparisonLayout() {
        _comparisonLayout = new HorizontalLayout("comparison");
        _comparisonLayout.layoutWidth = FILL_PARENT;
        _comparisonLayout.layoutHeight = FILL_PARENT;
        _comparisonLayout.visibility = Visibility.Gone;

        // Original editor
        VerticalLayout originalSection = new VerticalLayout();
        originalSection.layoutWidth = FILL_PARENT;
        originalSection.layoutHeight = FILL_PARENT;

        TextWidget originalLabel = new TextWidget("originalLabel", "Original"d);
        originalLabel.backgroundColor = 0xFFFFE0E0;
        originalSection.addChild(originalLabel);

        _originalEditor = new SourceEdit("originalEditor");
        _originalEditor.layoutWidth = FILL_PARENT;
        _originalEditor.layoutHeight = FILL_PARENT;
        _originalEditor.readOnly = true;
        originalSection.addChild(_originalEditor);

        _comparisonLayout.addChild(originalSection);

        // Suggested editor
        VerticalLayout suggestedSection = new VerticalLayout();
        suggestedSection.layoutWidth = FILL_PARENT;
        suggestedSection.layoutHeight = FILL_PARENT;

        TextWidget suggestedLabel = new TextWidget("suggestedLabel", "Suggested"d);
        suggestedLabel.backgroundColor = 0xFFE0FFE0;
        suggestedSection.addChild(suggestedLabel);

        _suggestedEditor = new SourceEdit("suggestedEditor");
        _suggestedEditor.layoutWidth = FILL_PARENT;
        _suggestedEditor.layoutHeight = FILL_PARENT;
        _suggestedEditor.readOnly = true;
        suggestedSection.addChild(_suggestedEditor);

        _comparisonLayout.addChild(suggestedSection);
        addChild(_comparisonLayout);
    }

    private void createUnifiedDiffLayout() {
        _unifiedScroll = new ScrollWidget("unifiedScroll");
        _unifiedScroll.layoutWidth = FILL_PARENT;
        _unifiedScroll.layoutHeight = FILL_PARENT;
        _unifiedScroll.visibility = Visibility.Gone;

        _unifiedLayout = new VerticalLayout("unifiedLayout");
        _unifiedLayout.layoutWidth = FILL_PARENT;
        _unifiedLayout.layoutHeight = WRAP_CONTENT;

        _unifiedScroll.contentWidget = _unifiedLayout;
        addChild(_unifiedScroll);
    }

    private void setupEventHandlers() {
        // Mode switching
        _showSideBySideBtn.click = delegate(Widget source) {
            setDiffMode(InlineDiffMode.SideBySide);
            return true;
        };

        _showUnifiedBtn.click = delegate(Widget source) {
            setDiffMode(InlineDiffMode.Unified);
            return true;
        };

        _showOverlayBtn.click = delegate(Widget source) {
            setDiffMode(InlineDiffMode.Overlay);
            return true;
        };

        // Action buttons
        _acceptAllBtn.click = delegate(Widget source) {
            acceptAllChanges();
            return true;
        };

        _rejectAllBtn.click = delegate(Widget source) {
            rejectAllChanges();
            return true;
        };

        _aiSuggestBtn.click = delegate(Widget source) {
            generateAISuggestions();
            return true;
        };

        // Editor content changes
        _editor.onContentChange = delegate(EditableContent source) {
            _hasUnsavedChanges = true;
            if (onContentChanged.assigned) {
                onContentChanged(_editor.text.toUTF8());
            }
            return true;
        };
    }

    /// Load file into editor
    void loadFile(string filePath) {
        try {
            _filePath = filePath;
            string content = readText(filePath);
            _originalContent = content;
            _editor.text = content.toUTF32();
            _hasUnsavedChanges = false;

            updateStatus("File loaded: " ~ baseName(filePath));
        } catch (Exception e) {
            updateStatus("Error loading file: " ~ e.msg);
        }
    }

    /// Save current editor content
    void saveFile(string filePath = null) {
        string targetPath = filePath ? filePath : _filePath;
        if (targetPath.empty) return;

        try {
            string content = _editor.text.toUTF8();
            std.file.write(targetPath, content);
            _hasUnsavedChanges = false;
            _originalContent = content;

            updateStatus("File saved: " ~ baseName(targetPath));
        } catch (Exception e) {
            updateStatus("Error saving file: " ~ e.msg);
        }
    }

    /// Show inline suggestions for code changes
    void showInlineSuggestions(InlineChange[] changes) {
        clearInlineSuggestions();

        _pendingChanges = changes.dup;

        if (changes.empty) {
            updateStatus("No changes to suggest");
            return;
        }

        // Show diff toolbar
        _diffToolbar.visibility = Visibility.Visible;

        // Create change widgets and insert them inline
        foreach (change; changes) {
            auto widget = new InlineChangeWidget(change);

            widget.onChangeAction.connect((InlineChange ch, bool accepted) {
                handleChangeAction(ch, accepted);
            });

            _changeWidgets ~= widget;
        }

        setDiffMode(InlineDiffMode.Overlay);
        updateStatus(format("Showing %d suggested changes", changes.length));

        // Auto-apply high confidence changes if enabled
        if (_autoApplyCheck.checked) {
            autoApplyHighConfidenceChanges();
        }
    }

    /// Set the diff viewing mode
    void setDiffMode(InlineDiffMode mode) {
        if (_diffMode == mode) return;

        // Hide current mode
        hideCurrentMode();

        _diffMode = mode;

        // Show new mode
        showCurrentMode();

        // Update button states
        updateModeButtons();

        if (onDiffModeChanged.assigned) {
            onDiffModeChanged(mode);
        }
    }

    private void hideCurrentMode() {
        _editor.visibility = Visibility.Gone;
        _comparisonLayout.visibility = Visibility.Gone;
        _unifiedScroll.visibility = Visibility.Gone;

        // Clear overlay widgets
        clearOverlayWidgets();
    }

    private void showCurrentMode() {
        final switch (_diffMode) {
            case InlineDiffMode.None:
                _editor.visibility = Visibility.Visible;
                _diffToolbar.visibility = Visibility.Gone;
                break;

            case InlineDiffMode.SideBySide:
                _comparisonLayout.visibility = Visibility.Visible;
                _diffToolbar.visibility = Visibility.Visible;
                updateComparisonEditors();
                break;

            case InlineDiffMode.Unified:
                _unifiedScroll.visibility = Visibility.Visible;
                _diffToolbar.visibility = Visibility.Visible;
                updateUnifiedDiffView();
                break;

            case InlineDiffMode.Overlay:
                _editor.visibility = Visibility.Visible;
                _diffToolbar.visibility = Visibility.Visible;
                showOverlayWidgets();
                break;
        }
    }

    private void updateComparisonEditors() {
        if (_originalEditor && _suggestedEditor) {
            _originalEditor.text = _originalContent.toUTF32();

            string suggestedContent = applyPendingChanges(_originalContent, _pendingChanges);
            _suggestedEditor.text = suggestedContent.toUTF32();
        }
    }

    private void updateUnifiedDiffView() {
        _unifiedLayout.removeAllChildren();

        auto hunks = _diffAnalyzer.analyzeDiff(_originalContent,
                                             applyPendingChanges(_originalContent, _pendingChanges));

        foreach (hunk; hunks) {
            Widget hunkWidget = createUnifiedHunkWidget(hunk);
            _unifiedLayout.addChild(hunkWidget);
        }
    }

    private Widget createUnifiedHunkWidget(DiffHunk hunk) {
        VerticalLayout hunkLayout = new VerticalLayout();
        hunkLayout.layoutWidth = FILL_PARENT;
        hunkLayout.layoutHeight = WRAP_CONTENT;
        hunkLayout.backgroundColor = 0xFFF8F8F8;
        hunkLayout.margins = Rect(0, 2, 0, 2);
        hunkLayout.padding = Rect(4, 4, 4, 4);

        // Hunk header
        TextWidget header = new TextWidget();
        header.text = format("@@ -%d,%d +%d,%d @@",
                            hunk.originalStart, hunk.originalLength,
                            hunk.suggestedStart, hunk.suggestedLength).toUTF32();
        header.textColor = 0xFF0066CC;
        header.fontSize = 10;
        hunkLayout.addChild(header);

        // Diff lines
        foreach (diff; hunk.diffs) {
            TextWidget lineWidget = new TextWidget();

            final switch (diff.type) {
                case LineDiff.Type.Equal:
                    lineWidget.text = (" " ~ diff.originalText).toUTF32();
                    lineWidget.textColor = 0xFF000000;
                    break;
                case LineDiff.Type.Delete:
                    lineWidget.text = ("-" ~ diff.originalText).toUTF32();
                    lineWidget.textColor = 0xFFDC143C;
                    lineWidget.backgroundColor = 0xFFFFE0E0;
                    break;
                case LineDiff.Type.Insert:
                    lineWidget.text = ("+" ~ diff.suggestedText).toUTF32();
                    lineWidget.textColor = 0xFF228B22;
                    lineWidget.backgroundColor = 0xFFE0FFE0;
                    break;
                case LineDiff.Type.Change:
                    lineWidget.text = ("~" ~ diff.suggestedText).toUTF32();
                    lineWidget.textColor = 0xFF4169E1;
                    lineWidget.backgroundColor = 0xFFE0E0FF;
                    break;
            }

            lineWidget.fontSize = 10;
            hunkLayout.addChild(lineWidget);
        }

        return hunkLayout;
    }

    private void showOverlayWidgets() {
        // Insert change widgets at appropriate positions in the editor
        foreach (widget; _changeWidgets) {
            // This would need custom integration with the editor's line rendering
            // For now, we'll add them to a side panel or overlay area
        }
    }

    private void clearOverlayWidgets() {
        foreach (widget; _changeWidgets) {
            if (widget.parent) {
                widget.parent.removeChild(widget);
            }
        }
    }

    private void updateModeButtons() {
        _showSideBySideBtn.checked = _diffMode == InlineDiffMode.SideBySide;
        _showUnifiedBtn.checked = _diffMode == InlineDiffMode.Unified;
        _showOverlayBtn.checked = _diffMode == InlineDiffMode.Overlay;
    }

    private void handleChangeAction(InlineChange change, bool accepted) {
        if (accepted) {
            applyChange(change);
        } else {
            rejectChange(change);
        }

        updateChangeCounters();
    }

    private void applyChange(InlineChange change) {
        // Apply the change to the editor content
        string currentContent = _editor.text.toUTF8();
        string newContent = applyChangeToContent(currentContent, change);
        _editor.text = newContent.toUTF32();
        _hasUnsavedChanges = true;

        updateStatus("Change applied: " ~ change.reason);
    }

    private void rejectChange(InlineChange change) {
        updateStatus("Change rejected: " ~ change.reason);
    }

    private string applyChangeToContent(string content, InlineChange change) {
        auto lines = content.splitLines();

        final switch (change.type) {
            case ChangeType.Replace:
                if (change.startLine < lines.length) {
                    lines[change.startLine] = change.suggestedText;
                }
                break;
            case ChangeType.Insert:
                if (change.startLine <= lines.length) {
                    lines = lines[0..change.startLine] ~ [change.suggestedText] ~ lines[change.startLine..$];
                }
                break;
            case ChangeType.Delete:
                if (change.startLine < lines.length) {
                    lines = lines[0..change.startLine] ~ lines[change.endLine+1..$];
                }
                break;
            case ChangeType.Move:
            case ChangeType.Format:
                // More complex operations would be handled here
                break;
        }

        return lines.join("\n");
    }

    private string applyPendingChanges(string content, InlineChange[] changes) {
        string result = content;
        foreach (change; changes) {
            if (change.isAccepted) {
                result = applyChangeToContent(result, change);
            }
        }
        return result;
    }

    private void acceptAllChanges() {
        foreach (ref change; _pendingChanges) {
            if (!change.isRejected) {
                change.isAccepted = true;
            }
        }

        // Update all widgets
        foreach (widget; _changeWidgets) {
            if (!widget.change.isRejected) {
                // widget.acceptChange(); // Would need to implement
            }
        }

        // Apply all accepted changes
        string newContent = applyPendingChanges(_originalContent, _pendingChanges);
        _editor.text = newContent.toUTF32();
        _hasUnsavedChanges = true;

        updateStatus("All changes accepted");
        updateChangeCounters();
    }

    private void rejectAllChanges() {
        foreach (ref change; _pendingChanges) {
            if (!change.isAccepted) {
                change.isRejected = true;
            }
        }

        // Update all widgets
        foreach (widget; _changeWidgets) {
            if (!widget.change.isAccepted) {
                // widget.rejectChange(); // Would need to implement
            }
        }

        updateStatus("All changes rejected");
        updateChangeCounters();
    }

    private void autoApplyHighConfidenceChanges() {
        int autoAppliedCount = 0;

        foreach (ref change; _pendingChanges) {
            if (change.confidence >= 0.9 && !change.isRejected) {
                change.isAccepted = true;
                autoAppliedCount++;
            }
        }

        if (autoAppliedCount > 0) {
            string newContent = applyPendingChanges(_originalContent, _pendingChanges);
            _editor.text = newContent.toUTF32();
            _hasUnsavedChanges = true;

            updateStatus(format("Auto-applied %d high confidence changes", autoAppliedCount));
        }
    }

    private void generateAISuggestions() {
        if (!_aiMerger) {
            _aiMerger = new AIAssistedMerger(null); // Would need proper initialization
        }

        string currentContent = _editor.text.toUTF8();

        // This would integrate with your AI system
        updateStatus("Generating AI suggestions...");

        // Mock AI suggestions for demonstration
        InlineChange[] aiSuggestions = generateMockAISuggestions(currentContent);

        if (aiSuggestions.length > 0) {
            showInlineSuggestions(aiSuggestions);
        } else {
            updateStatus("No AI suggestions available");
        }
    }

    private InlineChange[] generateMockAISuggestions(string content) {
        InlineChange[] suggestions;
        auto lines = content.splitLines();

        foreach (i, line; lines) {
            // Mock suggestion: add documentation comments
            if (line.strip().startsWith("def ") || line.strip().startsWith("function ")) {
                InlineChange suggestion;
                suggestion.changeId = format("ai_doc_%d", i);
                suggestion.startLine = cast(int)i;
                suggestion.endLine = cast(int)i;
                suggestion.originalText = "";
                suggestion.suggestedText = "    /// TODO: Add function documentation";
                suggestion.reason = "AI suggests adding documentation";
                suggestion.confidence = 0.8;
                suggestion.type = ChangeType.Insert;

                suggestions ~= suggestion;
            }
        }

        return suggestions;
    }

    private void clearInlineSuggestions() {
        foreach (widget; _changeWidgets) {
            if (widget.parent) {
                widget.parent.removeChild(widget);
            }
        }
        _changeWidgets.length = 0;
        _pendingChanges.length = 0;

        if (_pendingChanges.empty) {
            setDiffMode(InlineDiffMode.None);
        }
    }

    private void updateChangeCounters() {
        int accepted = 0, rejected = 0, pending = 0;

        foreach (change; _pendingChanges) {
            if (change.isAccepted) accepted++;
            else if (change.isRejected) rejected++;
            else pending++;
        }

        updateStatus(format("Changes: %d accepted, %d rejected, %d pending",
                          accepted, rejected, pending));
    }

    private void updateStatus(string message) {
        if (_statusLabel) {
            _statusLabel.text = message.toUTF32();
        }
        writeln("InlineDiffEditor: ", message);
    }

    /// Get current editor content
    @property string content() {
        return _editor ? _editor.text.toUTF8() : "";
    }

    /// Set editor content
    @property void content(string value) {
        if (_editor) {
            _editor.text = value.toUTF32();
            _hasUnsavedChanges = true;
        }
    }

    /// Get file path
    @property string filePath() {
        return _filePath;
    }

    /// Check if there are unsaved changes
    @property bool hasUnsavedChanges() {
        return _hasUnsavedChanges;
    }

    /// Get pending changes count
    @property int pendingChangesCount() {
        return cast(int)_pendingChanges.length;
    }

    /// Get current diff mode
    @property InlineDiffMode diffMode() {
        return _diffMode;
    }

    /// Check if AI merger is available
    @property bool hasAIMerger() {
        return _aiMerger !is null;
    }

    /// Set AI merger instance
    void setAIMerger(AIAssistedMerger aiMerger) {
        _aiMerger = aiMerger;
        if (_aiSuggestBtn) {
            _aiSuggestBtn.enabled = (_aiMerger !is null);
        }
    }

    /// Navigate to specific change
    void navigateToChange(int changeIndex) {
        if (changeIndex < 0 || changeIndex >= _pendingChanges.length) return;

        _activeChangeIndex = changeIndex;
        auto change = _pendingChanges[changeIndex];

        // Scroll editor to the change location
        if (_editor && change.startLine >= 0) {
            // Would need to implement line-based scrolling in the editor
            // _editor.scrollToLine(change.startLine);
        }

        updateStatus(format("Change %d/%d: %s", changeIndex + 1,
                          _pendingChanges.length, change.reason));
    }

    /// Navigate to next change
    void nextChange() {
        if (_activeChangeIndex < _pendingChanges.length - 1) {
            navigateToChange(_activeChangeIndex + 1);
        }
    }

    /// Navigate to previous change
    void previousChange() {
        if (_activeChangeIndex > 0) {
            navigateToChange(_activeChangeIndex - 1);
        }
    }

    /// Export changes as JSON for external processing
    JSONValue exportChanges() {
        JSONValue result = JSONValue.emptyObject;
        JSONValue[] changesArray;

        foreach (change; _pendingChanges) {
            JSONValue changeJson = JSONValue.emptyObject;
            changeJson["id"] = JSONValue(change.changeId);
            changeJson["startLine"] = JSONValue(change.startLine);
            changeJson["endLine"] = JSONValue(change.endLine);
            changeJson["originalText"] = JSONValue(change.originalText);
            changeJson["suggestedText"] = JSONValue(change.suggestedText);
            changeJson["reason"] = JSONValue(change.reason);
            changeJson["confidence"] = JSONValue(change.confidence);
            changeJson["type"] = JSONValue(to!string(change.type));
            changeJson["isAccepted"] = JSONValue(change.isAccepted);
            changeJson["isRejected"] = JSONValue(change.isRejected);

            changesArray ~= changeJson;
        }

        result["changes"] = JSONValue(changesArray);
        result["filePath"] = JSONValue(_filePath);
        result["diffMode"] = JSONValue(to!string(_diffMode));
        result["hasUnsavedChanges"] = JSONValue(_hasUnsavedChanges);

        return result;
    }

    /// Import changes from JSON
    void importChanges(JSONValue data) {
        clearInlineSuggestions();

        if ("changes" in data && data["changes"].type == JSONType.array) {
            InlineChange[] newChanges;

            foreach (changeJson; data["changes"].array) {
                InlineChange change;
                change.changeId = changeJson["id"].str;
                change.startLine = cast(int)changeJson["startLine"].integer;
                change.endLine = cast(int)changeJson["endLine"].integer;
                change.originalText = changeJson["originalText"].str;
                change.suggestedText = changeJson["suggestedText"].str;
                change.reason = changeJson["reason"].str;
                change.confidence = changeJson["confidence"].floating;
                change.type = to!ChangeType(changeJson["type"].str);
                change.isAccepted = changeJson["isAccepted"].boolean;
                change.isRejected = changeJson["isRejected"].boolean;

                newChanges ~= change;
            }

            if (newChanges.length > 0) {
                showInlineSuggestions(newChanges);
            }
        }
    }

    /// Compare with another file
    void compareWithFile(string otherFilePath) {
        try {
            if (!exists(otherFilePath)) {
                updateStatus("File not found: " ~ otherFilePath);
                return;
            }

            string otherContent = readText(otherFilePath);
            string currentContent = _editor.text.toUTF8();

            auto hunks = _diffAnalyzer.analyzeDiff(currentContent, otherContent);

            // Convert hunks to inline changes
            InlineChange[] changes = convertHunksToChanges(hunks,
                                    baseName(otherFilePath) ~ " comparison");

            if (changes.length > 0) {
                showInlineSuggestions(changes);
                updateStatus(format("Comparing with %s - %d differences found",
                                  baseName(otherFilePath), changes.length));
            } else {
                updateStatus("No differences found with " ~ baseName(otherFilePath));
            }

        } catch (Exception e) {
            updateStatus("Error comparing files: " ~ e.msg);
        }
    }

    private InlineChange[] convertHunksToChanges(DiffHunk[] hunks, string reason) {
        InlineChange[] changes;
        int changeId = 0;

        foreach (hunk; hunks) {
            foreach (diff; hunk.diffs) {
                if (diff.type == LineDiff.Type.Equal) continue;

                InlineChange change;
                change.changeId = format("hunk_%d", changeId++);
                change.startLine = diff.originalLine >= 0 ? diff.originalLine : diff.suggestedLine;
                change.endLine = change.startLine;
                change.originalText = diff.originalText;
                change.suggestedText = diff.suggestedText;
                change.reason = reason;
                change.confidence = diff.similarity;

                final switch (diff.type) {
                    case LineDiff.Type.Insert:
                        change.type = ChangeType.Insert;
                        break;
                    case LineDiff.Type.Delete:
                        change.type = ChangeType.Delete;
                        break;
                    case LineDiff.Type.Change:
                        change.type = ChangeType.Replace;
                        break;
                    case LineDiff.Type.Equal:
                        break; // Already handled above
                }

                changes ~= change;
            }
        }

        return changes;
    }

    /// Cleanup resources
    void cleanup() {
        clearInlineSuggestions();
        if (_aiMerger) {
            _aiMerger.clearCache();
        }
    }
}

/// Factory function to create inline diff editor
InlineDiffEditor createInlineDiffEditor(string filePath = null) {
    return new InlineDiffEditor(filePath);
}
