module dlangide.ui.artifactpanel;

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.string;
import std.utf;

import dlangui;
import dlangui.widgets.tree;
import dlangui.widgets.popup;
import dlangui.core.logger;

import dcore.core;
import dcore.artifact.artifact;
import dcore.artifact.element;
import dcore.artifact.transform;
import dlangide.ui.commands;

/// Tree that lets the panel intercept clipboard keys before navigation.
private class ElementTree : TreeWidget {
    bool delegate(KeyEvent) keyHook;

    this(string id) {
        super(id);
    }

    override bool onKey(Widget source, KeyEvent event) {
        if (keyHook !is null && keyHook(event))
            return true;
        return super.onKey(source, event);
    }
}

/**
 * ArtifactPanel - Shows the active artifact's context elements as a tree with
 * a text preview, and offers copy / transform / pipe / AI-context actions.
 */
class ArtifactPanel : VerticalLayout {
    private DCore _core;
    private Artifact _artifact;
    private string _wsDir;
    private TextWidget _title;
    private ElementTree _tree;
    private EditBox _preview;
    private string _lastCommand = "wc -l";

    /// Called by the Refresh button so the host can re-sync editor content.
    void delegate() refreshRequested;

    this(DCore core) {
        super("artifactPanel");
        _core = core;
        layoutWidth  = FILL_PARENT;
        layoutHeight = FILL_PARENT;

        // ── Toolbar ──────────────────────────────────────────────────────────
        auto toolbar = new HorizontalLayout("artifactToolbar");
        toolbar.layoutWidth  = FILL_PARENT;
        toolbar.layoutHeight = WRAP_CONTENT;
        toolbar.padding(Rect(4, 2, 4, 2));

        _title = new TextWidget("artifactTitle", "No artifact"d);
        _title.fontSize = 11;
        _title.layoutWidth = FILL_PARENT;
        toolbar.addChild(_title);

        toolbar.addChild(toolButton("artifactBtnCopy", "Copy"d, ACTION_ARTIFACT_COPY_TEXT));
        toolbar.addChild(toolButton("artifactBtnJson", "JSON"d, ACTION_ARTIFACT_COPY_JSON));
        toolbar.addChild(toolButton("artifactBtnTransform", "Transform"d, ACTION_ARTIFACT_RUN_TRANSFORM));
        toolbar.addChild(toolButton("artifactBtnSend", "Send"d, ACTION_ARTIFACT_SEND_TO_PROGRAM));
        toolbar.addChild(toolButton("artifactBtnAI", "AI+"d, ACTION_ARTIFACT_ADD_TO_AI));
        toolbar.addChild(toolButton("artifactBtnPaste", "Paste"d, ACTION_ARTIFACT_PASTE));

        auto btnRefresh = new Button("artifactBtnRefresh", "\u21bb"d);
        btnRefresh.fontSize = 11;
        btnRefresh.click = delegate(Widget src) {
            if (refreshRequested !is null)
                refreshRequested();
            else
                refresh();
            return true;
        };
        toolbar.addChild(btnRefresh);
        addChild(toolbar);

        // ── Element tree ─────────────────────────────────────────────────────
        _tree = new ElementTree("artifactTree");
        _tree.layoutWidth  = FILL_PARENT;
        _tree.layoutHeight = FILL_PARENT;
        _tree.layoutWeight = 3;
        _tree.selectionChange = delegate(TreeItems source, TreeItem item, bool activated) {
            updatePreview();
        };
        _tree.popupMenu = &elementPopupMenu;
        _tree.keyHook = &handleTreeKey;
        addChild(_tree);

        addChild(new ResizerWidget("artifactResizer"));

        // ── Preview ──────────────────────────────────────────────────────────
        _preview = new EditBox("artifactPreview");
        _preview.layoutWidth  = FILL_PARENT;
        _preview.layoutHeight = FILL_PARENT;
        _preview.layoutWeight = 2;
        _preview.readOnly = true;
        addChild(_preview);
    }

    private Button toolButton(string id, dstring label, const Action action) {
        auto b = new Button(id, label);
        b.fontSize = 11;
        b.click = delegate(Widget src) {
            if (action.id == IDEActions.ArtifactRunTransform)
                showTransformMenu(src);
            else
                handleArtifactAction(action);
            return true;
        };
        return b;
    }

    @property Artifact artifact() { return _artifact; }

    /// Show `a` (may be null) as the active artifact of workspace `wsDir`.
    void setArtifact(Artifact a, string wsDir) {
        _artifact = a;
        _wsDir = wsDir;
        refresh();
    }

    /// Rebuild the tree from the active artifact and workspace scratch artifacts.
    void refresh() {
        string selectedId;
        if (auto sel = selectedElement())
            selectedId = sel.id;

        _tree.clearAllItems();
        _title.text = _artifact ? toUTF32(_artifact.name ~ "  [" ~ _artifact.kind ~ "]") : "No artifact"d;

        if (_artifact !is null)
            foreach (e; _artifact.contextElements())
                addElement(_tree.items, e);

        auto manager = _core ? _core.artifactManager : null;
        if (manager !is null) {
            auto scratch = manager.scratchArtifacts(_wsDir);
            if (scratch.length) {
                auto root = _tree.items.newChild("#scratch", "Scratch"d);
                foreach (s; scratch) {
                    auto e = new ContextElement(s.id, s.name, "scratch", s.text());
                    foreach (d; s.derived)
                        e.add(new ContextElement(d.id, d.name, "output", d.text()));
                    addElement(root, e);
                }
            }
        }

        if (selectedId.length)
            _tree.selectItem(selectedId);
        updatePreview();
    }

    private void addElement(TreeItem parent, ContextElement e) {
        string label = e.label.length > 80 ? e.label[0 .. 80] ~ "\u2026" : e.label;
        auto item = parent.newChild(e.id, toUTF32(label));
        item.objectParam = e;
        foreach (c; e.children)
            addElement(item, c);
        if (e.kind == "section" || e.kind == "outputs" || e.kind == "scratch")
            item.collapse();
    }

    ContextElement selectedElement() {
        auto item = _tree.items.selectedItem;
        return item ? cast(ContextElement)item.objectParam : null;
    }

    private void updatePreview() {
        auto e = selectedElement();
        _preview.text = e ? toUTF32(e.text) : ""d;
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    private MenuItem elementPopupMenu(TreeItems source, TreeItem item) {
        if (item !is null)
            _tree.selectItem(item);
        auto menu = new MenuItem();
        menu.add(ACTION_ARTIFACT_COPY_TEXT, ACTION_ARTIFACT_COPY_JSON);
        menu.addSeparator();
        auto transforms = transformMenu();
        if (transforms !is null)
            menu.add(transforms);
        menu.add(ACTION_ARTIFACT_SEND_TO_PROGRAM, ACTION_ARTIFACT_ADD_TO_AI);
        menu.addSeparator();
        menu.add(ACTION_ARTIFACT_PASTE);
        menu.menuItemAction = &handleArtifactAction;
        return menu;
    }

    private MenuItem transformMenu() {
        if (_artifact is null || _core is null || _core.artifactManager is null)
            return null;
        auto transforms = _core.artifactManager.transformsFor(_artifact.kind);
        if (!transforms.length)
            return null;
        auto sub = new MenuItem(ACTION_ARTIFACT_RUN_TRANSFORM.clone());
        foreach (t; transforms.sort!((a, b) => a.name < b.name)) {
            auto a = new Action(IDEActions.ArtifactRunTransform, toUTF32(t.name));
            a.stringParam = t.id;
            sub.add(a);
        }
        return sub;
    }

    private void showTransformMenu(Widget anchor) {
        auto sub = transformMenu();
        if (sub is null) {
            showMessage("Run Transform"d, "No transforms available for this artifact."d);
            return;
        }
        auto menu = new MenuItem();
        foreach (i; 0 .. sub.subitemCount)
            menu.add(sub.subitem(i).action);
        menu.menuItemAction = &handleArtifactAction;
        auto popup = window.showPopup(new PopupMenu(menu), anchor, PopupAlign.Below);
        popup.flags = PopupFlags.CloseOnClickOutside;
    }

    private bool handleTreeKey(KeyEvent event) {
        if (event.action != KeyAction.KeyDown || !(event.flags & KeyFlag.Control))
            return false;
        if (event.keyCode == KeyCode.KEY_C)
            return handleArtifactAction((event.flags & KeyFlag.Shift) ? ACTION_ARTIFACT_COPY_JSON : ACTION_ARTIFACT_COPY_TEXT);
        if (event.keyCode == KeyCode.KEY_V)
            return handleArtifactAction(ACTION_ARTIFACT_PASTE);
        return false;
    }

    /// Handle an Artifact* action; returns true if handled.
    bool handleArtifactAction(const Action a) {
        switch (a.id) {
            case IDEActions.ArtifactCopyText:
                if (auto e = selectedElement())
                    platform.setClipboardText(toUTF32(e.text));
                return true;
            case IDEActions.ArtifactCopyJson:
                if (auto e = selectedElement())
                    platform.setClipboardText(toUTF32(e.toJSON().toPrettyString()));
                return true;
            case IDEActions.ArtifactRunTransform:
                if (a.stringParam.length)
                    runTransform(a.stringParam);
                else
                    showTransformMenu(_tree);
                return true;
            case IDEActions.ArtifactSendToProgram:
                sendToProgram();
                return true;
            case IDEActions.ArtifactAddToAI:
                addToAIContext();
                return true;
            case IDEActions.ArtifactPaste:
                pasteScratch();
                return true;
            default:
                return false;
        }
    }

    private void runTransform(string transformId) {
        if (_artifact is null || _core is null || _core.artifactManager is null)
            return;
        auto outputs = _core.artifactManager.runTransform(transformId, [_artifact]);
        refresh();
        if (outputs.length)
            _tree.selectItem(outputs[0].id);
        updatePreview();
    }

    private void sendToProgram() {
        auto e = selectedElement();
        if (e is null || _core is null || _core.artifactManager is null || _core.toolManager is null) {
            showMessage("Send to Program"d, "Select an element first."d);
            return;
        }
        auto w = window;
        if (w is null)
            return;
        string text = e.text;
        w.showInputBox("Send to Program"d, "Shell command (element text is piped to stdin):"d,
            toUTF32(_lastCommand), delegate(dstring result) {
                string cmd = result.to!string.strip;
                if (!cmd.length)
                    return;
                _lastCommand = cmd;
                Artifact target = _artifact;
                if (target is null)
                    target = _core.artifactManager.createScratch(text, _wsDir);
                _core.artifactManager.pipeToCommand(_core.toolManager, cmd, text,
                    delegate(Artifact[] outputs) {
                        w.executeInUiThread(delegate() {
                            target.addDerived(outputs);
                            refresh();
                            if (outputs.length) {
                                _tree.selectItem(outputs[0].id);
                                updatePreview();
                            }
                        });
                    });
            });
    }

    private void addToAIContext() {
        auto e = selectedElement();
        if (e is null || _core is null)
            return;
        import dcore.ai.context_manager : ContextManager, ContextPriority;
        auto ai = _core.getAIIntegration();
        auto aiManager = ai ? ai.getAIManager() : null;
        ContextManager cm = aiManager ? aiManager.getContextManager() : null;
        if (cm is null) {
            showMessage("Add to AI Context"d, "AI context is not available."d);
            return;
        }
        string header = format("--- %s: %s (%s) ---\n",
                               _artifact ? _artifact.name : "scratch", e.label, e.kind);
        cm.addGlobalContext("artifact:" ~ e.id, header ~ e.text, ContextPriority.High, "artifact");
        Log.i("ArtifactPanel: Added to AI context: ", e.id);
    }

    private void pasteScratch() {
        if (_core is null || _core.artifactManager is null || !platform.hasClipboardText())
            return;
        string text = platform.getClipboardText().to!string;
        if (!text.length)
            return;
        auto s = _core.artifactManager.createScratch(text, _wsDir);
        refresh();
        _tree.selectItem(s.id);
        updatePreview();
    }

    private void showMessage(dstring title, dstring msg) {
        if (window)
            window.showMessageBox(title, msg);
    }
}
