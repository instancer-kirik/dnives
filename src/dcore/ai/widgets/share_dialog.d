module dcore.ai.widgets.share_dialog;

import std.string, std.conv, std.format, std.datetime, std.file,
       std.path, std.array, std.algorithm, std.uuid;

import dlangui;
import dlangui.dialogs.dialog;
import dlangui.core.logger;
import dcore.ai.share_portal;

// ─────────────────────────────────────────────────────────────────────────────
// Result
// ─────────────────────────────────────────────────────────────────────────────

/// Returned to the caller after the dialog closes.
struct ShareDialogResult
{
    /// true when the user confirmed (saved or copied), false on cancel.
    bool   confirmed;
    /// Absolute file path the HTML was written to; empty when only copied.
    string outputPath;
    /// The full generated HTML string (populated whenever confirmed == true).
    string htmlContent;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog
// ─────────────────────────────────────────────────────────────────────────────

/**
 * ShareDialog
 *
 * A modal dialog that lets the user review and configure a shareable
 * conversation HTML page produced by `SharePortalGenerator`.
 *
 * Usage:
 * ---
 *   auto dlg = new ShareDialog(window, myConv);
 *   dlg.show();
 *   // inspect dlg.result after the dialog closes via its callback
 * ---
 */
class ShareDialog : Dialog
{
public:

    // ── Result ───────────────────────────────────────────────────────────────

    /// Populated when the dialog closes.
    ShareDialogResult result;

    // ── Constructor ──────────────────────────────────────────────────────────

    this(Window window, SharedConversation conv)
    {
        // Modal, resizable dialog – no built-in OK/Cancel button strip.
        super(UIString.fromRaw("Share Conversation"d),
              window,
              DialogFlag.Modal | DialogFlag.Resizable);

        _conv    = conv;
        _window  = window;
    }

    // ── Dialog initialisation ─────────────────────────────────────────────────

    override void initialize()
    {
        super.initialize();

        // ── Root layout ───────────────────────────────────────────────────────
        auto root = new VerticalLayout("share_root");
        root.layoutWidth(FILL_PARENT);
        root.layoutHeight(FILL_PARENT);
        root.padding(Rect(12, 12, 12, 12));
        root.backgroundColor(0x252526);

        // ── Title field ───────────────────────────────────────────────────────
        auto titleLabel = new TextWidget("lbl_title", "Title:"d);
        titleLabel.fontSize(13);
        titleLabel.textColor(0xCCCCCC);
        root.addChild(titleLabel);

        _titleEdit = new EditLine("fld_title");
        _titleEdit.text       = _conv.title.to!dstring;
        _titleEdit.layoutWidth(FILL_PARENT);
        _titleEdit.margins(Rect(0, 4, 0, 8));
        root.addChild(_titleEdit);

        // ── Description field ─────────────────────────────────────────────────
        auto descLabel = new TextWidget("lbl_desc", "Description:"d);
        descLabel.fontSize(13);
        descLabel.textColor(0xCCCCCC);
        root.addChild(descLabel);

        _descEdit = new EditLine("fld_desc");
        _descEdit.text       = _conv.description.to!dstring;
        _descEdit.layoutWidth(FILL_PARENT);
        _descEdit.margins(Rect(0, 4, 0, 12));
        root.addChild(_descEdit);

        // ── Generate initial HTML & fill preview ──────────────────────────────
        _generatedHtml = new SharePortalGenerator().generate(_conv);

        auto previewLabel = new TextWidget("lbl_preview", "HTML Preview (first 3000 chars):"d);
        previewLabel.fontSize(13);
        previewLabel.textColor(0xCCCCCC);
        root.addChild(previewLabel);

        _previewBox = new EditBox("preview_box");
        _previewBox.readOnly(true);
        _previewBox.layoutWidth(FILL_PARENT);
        _previewBox.layoutHeight(200);
        _previewBox.minHeight(200);
        _previewBox.margins(Rect(0, 4, 0, 8));
        _previewBox.backgroundColor(0x1E1E1E);
        _previewBox.textColor(0xD4D4D4);
        _updatePreview();
        root.addChild(_previewBox);

        // ── Button row ────────────────────────────────────────────────────────
        auto btnRow = new HorizontalLayout("btn_row");
        btnRow.layoutWidth(FILL_PARENT);
        btnRow.margins(Rect(0, 4, 0, 8));

        auto btnRegenerate = new Button("btn_regen", "Regenerate Preview"d);
        btnRegenerate.click = delegate(Widget src) {
            regenerate();
            return true;
        };

        auto btnSave = new Button("btn_save", "Save to File..."d);
        btnSave.click = delegate(Widget src) {
            saveToFile();
            return true;
        };

        auto btnCopy = new Button("btn_copy", "Copy HTML"d);
        btnCopy.click = delegate(Widget src) {
            if (_generatedHtml.length > 0)
            {
                platform.setClipboardText(_generatedHtml.to!dstring);
                _setStatus("HTML copied to clipboard."d);
                result.confirmed   = true;
                result.htmlContent = _generatedHtml;
            }
            return true;
        };

        auto btnClose = new Button("btn_close", "Close"d);
        btnClose.click = delegate(Widget src) {
            close(ACTION_CANCEL);
            return true;
        };

        btnRow.addChild(btnRegenerate);
        btnRow.addChild(new HSpacer());
        btnRow.addChild(btnSave);
        btnRow.addChild(btnCopy);
        btnRow.addChild(btnClose);
        root.addChild(btnRow);

        // ── Status label ──────────────────────────────────────────────────────
        _statusLabel = new TextWidget("lbl_status", ""d);
        _statusLabel.fontSize(12);
        _statusLabel.textColor(0x9CDCFE);
        _statusLabel.layoutWidth(FILL_PARENT);
        root.addChild(_statusLabel);

        // ── Attach to dialog content ──────────────────────────────────────────
        addChild(root);
    }

private:

    // ── Fields ────────────────────────────────────────────────────────────────

    Window             _window;
    SharedConversation _conv;

    EditLine   _titleEdit;
    EditLine   _descEdit;
    EditBox    _previewBox;
    TextWidget _statusLabel;

    string _generatedHtml;
    string _savedPath;

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Update the preview widget from `_generatedHtml`.
    void _updatePreview()
    {
        immutable size_t maxPreview = 3_000;
        auto snippet = _generatedHtml.length > maxPreview
                       ? _generatedHtml[0 .. maxPreview] ~ "\n… (truncated)"
                       : _generatedHtml;
        _previewBox.text = snippet.to!dstring;
    }

    void _setStatus(dstring msg)
    {
        _statusLabel.text = msg;
    }

    // ── Private methods ───────────────────────────────────────────────────────

    /**
     * Reads the current values of the title / description edit fields back
     * into `_conv`, regenerates the HTML, and refreshes the preview.
     */
    void regenerate()
    {
        _conv.title       = _titleEdit.text.to!string;
        _conv.description = _descEdit.text.to!string;

        try
        {
            _generatedHtml = new SharePortalGenerator().generate(_conv);
            _updatePreview();
            _setStatus("Preview regenerated."d);
            Log.i("ShareDialog: HTML regenerated (", _generatedHtml.length, " bytes)");
        }
        catch (Exception e)
        {
            _setStatus(("Regeneration failed: " ~ e.msg).to!dstring);
            Log.e("ShareDialog: regeneration error: ", e.msg);
        }
    }

    /**
     * Saves `_generatedHtml` to ~/Downloads/dnives_share_<timestamp>.html.
     * Updates the status label with the resulting path.
     */
    void saveToFile()
    {
        if (_generatedHtml.length == 0)
        {
            _setStatus("Nothing to save — generate a preview first."d);
            return;
        }

        try
        {
            // Build destination path.
            immutable string downloadsDir =
                buildPath(expandTilde("~"), "Downloads");

            if (!exists(downloadsDir))
                mkdirRecurse(downloadsDir);

            // Timestamp token: 20240601T143200
            immutable string ts = Clock.currTime()
                                       .toISOString()
                                       .replace(":", "")
                                       .replace("-", "")
                                       .replace(".", "_");

            immutable string filename = format("dnives_share_%s.html", ts);
            immutable string fullPath = buildPath(downloadsDir, filename);

            std.file.write(fullPath, _generatedHtml);

            _savedPath         = fullPath;
            result.confirmed   = true;
            result.outputPath  = fullPath;
            result.htmlContent = _generatedHtml;

            immutable dstring msg = ("Saved to: " ~ fullPath).to!dstring;
            _setStatus(msg);
            Log.i("ShareDialog: HTML saved to ", fullPath);
        }
        catch (Exception e)
        {
            _setStatus(("Save failed: " ~ e.msg).to!dstring);
            Log.e("ShareDialog: save error: ", e.msg);
        }
    }
}
