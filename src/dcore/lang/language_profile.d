module dcore.lang.language_profile;

import std.path;
import std.string;
import std.algorithm;
import std.array;

/**
 * LanguageProfile — Describes a programming / markup language recognised by the IDE.
 *
 * This struct is the single source of truth for language detection and file
 * classification.  Every component that needs to know "what language is this
 * file?" should call the free functions below instead of maintaining its own
 * switch-case table.
 */
struct LanguageProfile {
    string   id;           // canonical short id: "d", "python", "rust", …
    string   displayName;  // human-readable:      "D",  "Python",  "Rust", …
    string[] extensions;   // lower-case dotted:   [".d", ".di"] …
    string   lspId;        // LSP languageId string
    uint     graphColour;  // base colour for symbol-graph nodes (RGB, no alpha)
    string   lineComment;  // single-line comment token, e.g. "//" or "#"
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

immutable LanguageProfile[] LANGUAGE_PROFILES = [
    {
        id: "d", displayName: "D",
        extensions: [".d", ".di", ".dt"],
        lspId: "d", graphColour: 0x1A5276, lineComment: "//"
    },
    {
        id: "c", displayName: "C",
        extensions: [".c", ".h"],
        lspId: "c", graphColour: 0x1E8449, lineComment: "//"
    },
    {
        id: "cpp", displayName: "C++",
        extensions: [".cpp", ".cxx", ".cc", ".hpp", ".hxx"],
        lspId: "cpp", graphColour: 0x196F3D, lineComment: "//"
    },
    {
        id: "python", displayName: "Python",
        extensions: [".py", ".pyw", ".pyi"],
        lspId: "python", graphColour: 0x6C3483, lineComment: "#"
    },
    {
        id: "javascript", displayName: "JavaScript",
        extensions: [".js", ".mjs", ".cjs"],
        lspId: "javascript", graphColour: 0x7D6608, lineComment: "//"
    },
    {
        id: "typescript", displayName: "TypeScript",
        extensions: [".ts", ".tsx", ".mts"],
        lspId: "typescript", graphColour: 0x154360, lineComment: "//"
    },
    {
        id: "rust", displayName: "Rust",
        extensions: [".rs"],
        lspId: "rust", graphColour: 0x784212, lineComment: "//"
    },
    {
        id: "go", displayName: "Go",
        extensions: [".go"],
        lspId: "go", graphColour: 0x0E6655, lineComment: "//"
    },
    {
        id: "ruby", displayName: "Ruby",
        extensions: [".rb", ".rake"],
        lspId: "ruby", graphColour: 0x6E2C00, lineComment: "#"
    },
    {
        id: "java", displayName: "Java",
        extensions: [".java"],
        lspId: "java", graphColour: 0x1A237E, lineComment: "//"
    },
    {
        id: "kotlin", displayName: "Kotlin",
        extensions: [".kt", ".kts"],
        lspId: "kotlin", graphColour: 0x4A148C, lineComment: "//"
    },
    {
        id: "swift", displayName: "Swift",
        extensions: [".swift"],
        lspId: "swift", graphColour: 0x0D47A1, lineComment: "//"
    },
    {
        id: "csharp", displayName: "C#",
        extensions: [".cs"],
        lspId: "csharp", graphColour: 0x1B5E20, lineComment: "//"
    },
    {
        id: "elixir", displayName: "Elixir",
        extensions: [".ex", ".exs"],
        lspId: "elixir", graphColour: 0x4A235A, lineComment: "#"
    },
    {
        id: "lua", displayName: "Lua",
        extensions: [".lua"],
        lspId: "lua", graphColour: 0x0B3D91, lineComment: "--"
    },
    {
        id: "shellscript", displayName: "Shell",
        extensions: [".sh", ".bash", ".zsh", ".fish"],
        lspId: "shellscript", graphColour: 0x2E4053, lineComment: "#"
    },
    {
        id: "html", displayName: "HTML",
        extensions: [".html", ".htm"],
        lspId: "html", graphColour: 0x4E342E, lineComment: ""
    },
    {
        id: "css", displayName: "CSS",
        extensions: [".css", ".scss", ".sass", ".less"],
        lspId: "css", graphColour: 0x37474F, lineComment: "//"
    },
    {
        id: "json", displayName: "JSON",
        extensions: [".json"],
        lspId: "json", graphColour: 0x263238, lineComment: ""
    },
    {
        id: "toml", displayName: "TOML",
        extensions: [".toml"],
        lspId: "toml", graphColour: 0x212121, lineComment: "#"
    },
    {
        id: "markdown", displayName: "Markdown",
        extensions: [".md", ".markdown"],
        lspId: "markdown", graphColour: 0x1A237E, lineComment: ""
    },
    {
        id: "dml", displayName: "DML",
        extensions: [".dml"],
        lspId: "dml", graphColour: 0x1A5276, lineComment: "//"
    },
];

// ---------------------------------------------------------------------------
// Free functions
// ---------------------------------------------------------------------------

/**
 * Return a pointer to the LanguageProfile whose extensions list contains the
 * lower-cased extension of `filePath`, or null if none matches.
 */
const(LanguageProfile)* findProfile(string filePath) {
    string ext = extension(filePath).toLower();
    if (ext.empty)
        return null;

    foreach (ref p; LANGUAGE_PROFILES) {
        if (p.extensions.canFind(ext))
            return &p;
    }
    return null;
}

/**
 * Return the LSP language identifier for `filePath`, or `""` if unknown.
 */
string detectLanguage(string filePath) {
    auto p = findProfile(filePath);
    return p ? p.lspId : "";
}

/**
 * Return true when `filePath` has a recognised language profile.
 * Callers that wish to exclude config/doc files (JSON, TOML, Markdown…) may
 * filter on `detectLanguage` themselves.
 */
bool isSourceFile(string filePath) {
    return findProfile(filePath) !is null;
}

/**
 * Return the human-readable display name for the language with id `langId`,
 * or `langId` itself if the id is not found.
 */
string languageDisplayName(string langId) {
    foreach (ref p; LANGUAGE_PROFILES) {
        if (p.id == langId)
            return p.displayName;
    }
    return langId;
}

/**
 * Return the graph node colour for the language with id `langId`,
 * or a neutral grey `0x3A3A3A` if the id is not found.
 */
uint languageGraphColour(string langId) {
    foreach (ref p; LANGUAGE_PROFILES) {
        if (p.id == langId)
            return p.graphColour;
    }
    return 0x3A3A3A;
}

/**
 * Return the graph node colour appropriate for `filePath` (by extension).
 */
uint fileGraphColour(string filePath) {
    return languageGraphColour(detectLanguage(filePath));
}
