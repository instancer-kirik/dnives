module dcore.artifact.element;

import std.json;

/**
 * ContextElement - A viewable/copyable/passable part of an artifact.
 *
 * Elements form a tree: the whole document, structural parts (e.g. lyric
 * sections and their lines), metadata, and transform outputs.
 */
class ContextElement {
    string id;          // unique within the artifact, e.g. "lyrics:/a.lyrics#section/2"
    string label;       // tree label
    string kind;        // "document", "section", "line", "metadata", "output", …
    string text;        // plain-text payload used for copy / pipe / AI context
    JSONValue data;     // optional structured payload
    ContextElement[] children;

    this(string id, string label, string kind, string text = null) {
        this.id = id;
        this.label = label;
        this.kind = kind;
        this.text = text;
        this.data = JSONValue(null);
    }

    ContextElement add(ContextElement child) {
        children ~= child;
        return child;
    }

    JSONValue toJSON() {
        JSONValue j = parseJSON("{}");
        j["id"] = id;
        j["label"] = label;
        j["kind"] = kind;
        j["text"] = text;
        if (!data.isNull)
            j["data"] = data;
        if (children.length) {
            JSONValue[] arr;
            foreach (c; children)
                arr ~= c.toJSON();
            j["children"] = JSONValue(arr);
        }
        return j;
    }
}
