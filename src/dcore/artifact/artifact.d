module dcore.artifact.artifact;

import dlangui.core.logger;

import std.file;
import std.json;
import std.path;
import std.utf;

import dcore.editor.document;

/**
 * Artifact - A workspace item the IDE can reason about beyond "a file".
 *
 * An artifact has:
 * - an id (stable within a workspace; the normalized source path for file-backed artifacts)
 * - a kind (see dcore.artifact.kind)
 * - a metadata bag (JSON object, kind-specific keys)
 * - a source reference (file path, may be empty for derived artifacts)
 * - optional text content exposed as a Document for text-backed kinds
 */
class Artifact {
    import dcore.utils.signals : Signal;
    Signal!() onMetadataChanged;

    private string _id;
    private string _kind;
    private string _name;
    private string _sourcePath;
    private JSONValue _metadata;
    protected Document _document;

    this(string id, string kind, string name, string sourcePath = null) {
        _id = id;
        _kind = kind;
        _name = name;
        _sourcePath = sourcePath;
        _metadata = parseJSON("{}");
    }

    @property string id() const { return _id; }
    @property string kind() const { return _kind; }
    @property string name() const { return _name; }
    @property string sourcePath() const { return _sourcePath; }
    @property ref JSONValue metadata() { return _metadata; }

    /// True when the artifact's content is plain text held in a Document.
    @property bool textBacked() const { return false; }

    /**
     * Content document for text-backed kinds, loaded lazily from sourcePath.
     * Returns null for non-text kinds.
     */
    Document document() {
        if (!textBacked)
            return null;
        if (_document is null) {
            _document = new Document();
            if (_sourcePath.length && exists(_sourcePath)) {
                try {
                    _document.setText(readText(_sourcePath));
                } catch (Exception e) {
                    Log.e("Artifact: Failed to read ", _sourcePath, ": ", e.msg);
                }
            }
            _document.onTextChanged.connect(&refreshMetadata);
            refreshMetadata();
        }
        return _document;
    }

    /// Replace content from an external source (e.g. the editor buffer).
    void setText(string text) {
        auto doc = document();
        if (doc !is null)
            doc.setText(text);
    }

    /// Recompute kind-specific metadata from content. Base does nothing.
    void refreshMetadata() {
    }

    protected void metadataChanged() {
        onMetadataChanged.emit();
    }
}

/**
 * TextArtifact - Generic text-backed artifact used for derived/plain outputs.
 */
class TextArtifact : Artifact {
    this(string id, string kind, string name, string sourcePath = null) {
        super(id, kind, name, sourcePath);
    }

    override @property bool textBacked() const { return true; }
}
