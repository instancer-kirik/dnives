module dcore.code.graph_query;

import std.algorithm;
import std.array;
import std.range;
import std.conv;
import std.format;
import std.path;
import std.string;

import dcore.code.symbol_tracker;
import dcore.lsp.lsptypes;

/**
 * The few questions the assistant and the symbol graph both ask.
 * Facts come from the indexer. This module does not infer new edges.
 */
struct GraphQuery {
    SymbolTracker tracker;

    CodeSymbol[] search(string query, int limit = 8) {
        if (tracker is null)
            return [];
        return tracker.searchSymbols(query, limit);
    }

    SymbolReference[] callers(CodeSymbol symbol, int limit = 12) {
        SymbolReference[] hits;
        if (tracker is null)
            return hits;
        foreach (ref r; tracker.allReferences()) {
            if (r.referenceType != "call")
                continue;
            if (!namesTarget(r, symbol))
                continue;
            hits ~= r;
            if (hits.length >= limit)
                break;
        }
        return hits;
    }

    SymbolReference[] callees(CodeSymbol symbol, int limit = 12) {
        SymbolReference[] hits;
        if (tracker is null)
            return hits;
        foreach (ref r; tracker.outgoingReferences(symbol.filePath)) {
            if (r.referenceType != "call")
                continue;
            if (r.fromName != symbol.fullyQualifiedName && r.fromName != symbol.name)
                continue;
            hits ~= r;
            if (hits.length >= limit)
                break;
        }
        return hits;
    }

    /// One readable block: where the symbol lives, who calls it, what it calls.
    string describe(CodeSymbol symbol) {
        string sig = symbol.signature.length ? symbol.signature : symbol.name;
        string[] lines;
        lines ~= format("%s %s — %s:%d",
            kindName(symbol.kind), sig,
            baseName(symbol.filePath), symbol.location.start.line + 1);

        auto calledBy = callers(symbol);
        if (calledBy.length) {
            lines ~= "  callers:";
            foreach (ref r; calledBy)
                lines ~= format("    %s (%s:%d)",
                    r.fromName.length ? r.fromName : baseName(r.filePath),
                    baseName(r.filePath), r.location.start.line + 1);
        }

        auto calls = callees(symbol);
        if (calls.length) {
            lines ~= "  callees:";
            foreach (ref r; calls)
                lines ~= format("    %s", r.symbol.name);
        }

        if (tracker && tracker.knowledge) {
            auto notes = tracker.knowledge.backlinks(symbol.filePath);
            if (notes.length)
                lines ~= "  linked from: " ~ notes.map!(n => baseName(n)).take(6).join(", ");
        }

        int files = 0;
        bool[string] seenFiles;
        foreach (ref r; calledBy) {
            if (r.filePath !in seenFiles) {
                seenFiles[r.filePath] = true;
                files++;
            }
        }
        if (calledBy.length)
            lines ~= format("  impact: %d call sites in %d files", calledBy.length, files);
        return lines.join("\n");
    }

    /**
     * Answer a chat prompt from symbols it names, plus the open files.
     */
    string answer(string prompt, string[] files) {
        if (tracker is null)
            return "";
        string[] lines;
        bool[string] seen;
        CodeSymbol[] hits;

        void take(CodeSymbol symbol) {
            string id = symbol.fullyQualifiedName.length ? symbol.fullyQualifiedName : symbol.name;
            if (id.length == 0 || id in seen)
                return;
            seen[id] = true;
            hits ~= symbol;
        }

        if (prompt.length) {
            string lowered = prompt.toLower();
            foreach (name; tracker.symbolNames()) {
                if (name.length < 3)
                    continue;
                if (lowered.indexOf(name.toLower()) < 0)
                    continue;
                foreach (symbol; tracker.symbolsNamed(name))
                    take(symbol);
                if (hits.length >= 6)
                    break;
            }
        }

        foreach (filePath; files) {
            if (hits.length >= 8)
                break;
            foreach (symbol; tracker.getFileSymbols(filePath)) {
                if (symbol.kind == SymbolKind.Function || symbol.kind == SymbolKind.Method
                        || symbol.kind == SymbolKind.Class || symbol.kind == SymbolKind.Struct)
                    take(symbol);
                if (hits.length >= 8)
                    break;
            }
        }

        if (hits.length == 0)
            return "";
        lines ~= "Graph:";
        foreach (symbol; hits)
            lines ~= describe(symbol);
        return lines.join("\n");
    }
}

private bool namesTarget(ref SymbolReference r, CodeSymbol symbol) {
    if (symbol.fullyQualifiedName.length && r.symbol.fullyQualifiedName == symbol.fullyQualifiedName)
        return true;
    return r.symbol.name == symbol.name;
}

private string kindName(SymbolKind kind) {
    final switch (kind) {
        case SymbolKind.File: return "file";
        case SymbolKind.Module: return "module";
        case SymbolKind.Namespace: return "namespace";
        case SymbolKind.Package: return "package";
        case SymbolKind.Class: return "class";
        case SymbolKind.Method: return "method";
        case SymbolKind.Property: return "property";
        case SymbolKind.Field: return "field";
        case SymbolKind.Constructor: return "constructor";
        case SymbolKind.Enum: return "enum";
        case SymbolKind.Interface: return "interface";
        case SymbolKind.Function: return "function";
        case SymbolKind.Variable: return "variable";
        case SymbolKind.Constant: return "constant";
        case SymbolKind.String: return "string";
        case SymbolKind.Number: return "number";
        case SymbolKind.Boolean: return "boolean";
        case SymbolKind.Array: return "array";
        case SymbolKind.Object: return "object";
        case SymbolKind.Key: return "key";
        case SymbolKind.Null: return "null";
        case SymbolKind.EnumMember: return "enum member";
        case SymbolKind.Struct: return "struct";
        case SymbolKind.Event: return "event";
        case SymbolKind.Operator: return "operator";
        case SymbolKind.TypeParameter: return "type";
    }
}
