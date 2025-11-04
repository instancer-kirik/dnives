module dcore.lsp.lsptypes;

import std.json;
import std.algorithm : startsWith;

/**
 * LSP Types - Definitions for Language Server Protocol data types
 */

/**
 * Completion item kind
 */
enum CompletionItemKind {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25
}

/**
 * Symbol kind
 */
enum SymbolKind {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26
}

/**
 * Diagnostic severity
 */
enum DiagnosticSeverity {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4
}

/**
 * Position in a text document
 */
struct Position {
    int line;
    int character;
}

/**
 * Range in a text document
 */
struct Range {
    Position start;
    Position end;
}

/**
 * Location information
 */
struct LocationInfo {
    string uri;
    int line;
    int character;
    int endLine;
    int endCharacter;
}

/**
 * Diagnostic information
 */
struct DiagnosticInfo {
    Range range;
    DiagnosticSeverity severity;
    string code;
    string source;
    string message;
}

/**
 * Completion item
 */
struct CompletionItem {
    string label;
    CompletionItemKind kind;
    string detail;
    string documentation;
    string insertText;
    JSONValue data;
}

/**
 * Symbol information
 */
struct SymbolInfo {
    string name;
    SymbolKind kind;
    Range range;
    LocationInfo location;
    string containerName;
}

/**
 * Document symbol
 */
struct DocumentSymbol {
    string name;
    string detail;
    SymbolKind kind;
    Range range;
    Range selectionRange;
    DocumentSymbol[] children;
}

/**
 * Text edit
 */
struct TextEdit {
    Range range;
    string newText;
}

/**
 * Workspace edit
 */
struct WorkspaceEdit {
    TextEdit[string] changes;
}

/**
 * Format options
 */
struct FormattingOptions {
    int tabSize;
    bool insertSpaces;
}

/**
 * Command
 */
struct Command {
    string title;
    string command;
    JSONValue[] arguments;
}

/**
 * Code action
 */
struct CodeAction {
    string title;
    string kind;
    DiagnosticInfo[] diagnostics;
    WorkspaceEdit edit;
    Command command;
}

/**
 * Signature information
 */
struct SignatureInformation {
    string label;
    string documentation;
    ParameterInformation[] parameters;
}

/**
 * Parameter information
 */
struct ParameterInformation {
    string label;
    string documentation;
}

/**
 * Signature help
 */
struct SignatureHelp {
    SignatureInformation[] signatures;
    int activeSignature;
    int activeParameter;
}

/**
 * Convert from LSP URI to file path
 */
string uriToPath(string uri) {
    import std.uri : decode;
    
    if (uri.startsWith("file://")) {
        version (Windows) {
            // Windows file URIs either have a drive letter or are UNC paths
            if (uri.startsWith("file:///")) {
                // Regular drive letter path
                return decode(uri[8..$]);
            } else if (uri.startsWith("file://")) {
                // UNC path
                return "\\\\" ~ decode(uri[7..$]);
            }
        } else {
            // Unix-like systems
            return decode(uri[7..$]);
        }
    }
    
    return uri;
}

/**
 * Convert from file path to LSP URI
 */
string pathToUri(string path) {
    import std.uri : encode;
    
    version (Windows) {
        // Handle Windows paths
        if (path.startsWith("\\\\")) {
            // UNC path
            return "file://" ~ encode(path[2..$]);
        } else if (path.length >= 2 && path[1] == ':') {
            // Drive letter path
            return "file:///" ~ encode(path);
        }
    }
    
    // Unix-like path
    return "file://" ~ encode(path);
}