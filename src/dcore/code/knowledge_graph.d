module dcore.code.knowledge_graph;

import std.algorithm;
import std.array;

/**
 * Workspace knowledge graph.
 *
 * Same shape as the Python vault graph: directed links, tags, free
 * references, and the reverse backlink index. Code imports and markdown
 * wiki links both land here so the assistant and the symbol graph share
 * one neighbourhood.
 */
class KnowledgeGraph {
    private string[][string] _links;
    private string[][string] _backlinks;
    private string[][string] _tags;
    private string[][string] _references;

    void clear() {
        _links.clear();
        _backlinks.clear();
        _tags.clear();
        _references.clear();
    }

    void addLink(string source, string target) {
        if (source.length == 0 || target.length == 0 || source == target)
            return;
        addUnique(_links, source, target);
        addUnique(_backlinks, target, source);
    }

    void addTag(string file, string tag) {
        if (file.length && tag.length)
            addUnique(_tags, file, tag);
    }

    void addReference(string file, string reference) {
        if (file.length && reference.length)
            addUnique(_references, file, reference);
    }

    string[] linksFrom(string file) const {
        return copyOf(_links, file);
    }

    string[] backlinks(string file) const {
        return copyOf(_backlinks, file);
    }

    string[] tags(string file) const {
        return copyOf(_tags, file);
    }

    string[] references(string file) const {
        return copyOf(_references, file);
    }

    string[] connected(string file) const {
        string[] out_;
        void take(string[] items) {
            foreach (item; items)
                if (!out_.canFind(item))
                    out_ ~= item;
        }
        take(linksFrom(file));
        take(backlinks(file));
        take(tags(file));
        take(references(file));
        return out_;
    }

    private static void addUnique(ref string[][string] map, string key, string value) {
        auto existing = key in map;
        if (existing is null) {
            map[key] = [value];
            return;
        }
        if (!(*existing).canFind(value))
            *existing ~= value;
    }

    private static string[] copyOf(ref const(string[][string]) map, string key) {
        auto existing = key in map;
        if (existing is null)
            return [];
        return (*existing).dup;
    }
}
