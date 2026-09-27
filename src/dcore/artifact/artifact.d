module dcore.artifact.artifact;

import dlangui.core.logger;

import std.file;
import std.json;
import std.path;
import std.utf;

import dcore.editor.document;
import dcore.artifact.element;

/**
 * Artifact - A workspace item the IDE can reason about beyond "a file".
 *
 * An artifact has:
 * - an id (stable within a workspace; the normalized source path for file-backed artifacts)
 * - a kind (see dcore.artifact.kind)
 * - a metadata bag (JSON object, kind-specific keys)
 * - a source reference (file path, may be empty for derived artifacts)
 * - optional text content exposed as a Document for text-backed kinds
 * - derived artifacts produced by transforms run on it
 */
class Artifact {
    import dcore.utils.signals : Signal;
    Signal!() onMetadataChanged;
    Signal!() onElementsChanged;

    private string _id;
    private string _kind;
    private string _name;
    private string _sourcePath;
    private JSONValue _metadata;
    private Artifact[] _derived;
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
    @property ref JSONValue metadata() {
        if (textBacked && _document is null)
            document();
        return _metadata;
    }
    @property Artifact[] derived() { return _derived; }

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

    /// Full text content, or "" for non-text kinds.
    string text() {
        auto doc = document();
        return doc ? doc.getText().toUTF8 : "";
    }

    /// Recompute kind-specific metadata from content. Base does nothing.
    void refreshMetadata() {
    }

    /// Attach transform outputs, replacing earlier outputs with the same id.
    void addDerived(Artifact[] outputs) {
        foreach (o; outputs) {
            bool replaced = false;
            foreach (ref d; _derived) {
                if (d.id == o.id) {
                    d = o;
                    replaced = true;
                    break;
                }
            }
            if (!replaced)
                _derived ~= o;
        }
        onElementsChanged.emit();
    }

    /**
     * Element tree for viewing / copying / passing on. Kinds override
     * structureElements() to add their parts; document, metadata and
     * outputs are provided here.
     */
    ContextElement[] contextElements() {
        ContextElement[] result;
        if (textBacked)
            result ~= new ContextElement(_id ~ "#document", _name, "document", text());
        result ~= structureElements();

        auto meta = new ContextElement(_id ~ "#metadata", "Metadata", "metadata",
                                       _metadata.toPrettyString());
        meta.data = _metadata;
        result ~= meta;

        if (_derived.length) {
            auto outputs = new ContextElement(_id ~ "#outputs", "Outputs", "outputs");
            foreach (d; _derived) {
                auto e = outputs.add(new ContextElement(d.id, d.name, "output", d.text()));
                e.data = d.metadata;
            }
            result ~= outputs;
        }
        return result;
    }

    protected ContextElement[] structureElements() {
        return [];
    }

    protected void metadataChanged() {
        onMetadataChanged.emit();
        onElementsChanged.emit();
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
