module dcore.artifact.kind;

import std.algorithm;
import std.path;
import std.string;

import dcore.artifact.artifact;

/**
 * ArtifactKind — Describes a kind of artifact recognised by the IDE.
 *
 * Mirrors LanguageProfile: one registry, looked up by id or file extension.
 * Unlike languages, kinds are registered at runtime so each kind module can
 * contribute its own factory without a central switch.
 */
struct ArtifactKind {
    string   id;           // canonical short id: "lyrics", "text", …
    string   displayName;  // human-readable:      "Lyrics", "Text", …
    string[] extensions;   // lower-case dotted:   [".lyrics"] …
    bool     textBacked;   // content is held in a Document
    Artifact function(string id, string name, string sourcePath) create;
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

private __gshared ArtifactKind[] g_artifactKinds;

/**
 * Register (or replace, by id) an artifact kind.
 */
void registerArtifactKind(ArtifactKind kind) {
    foreach (ref k; g_artifactKinds) {
        if (k.id == kind.id) {
            k = kind;
            return;
        }
    }
    g_artifactKinds ~= kind;
}

const(ArtifactKind)[] artifactKinds() {
    return g_artifactKinds;
}

// ---------------------------------------------------------------------------
// Free functions
// ---------------------------------------------------------------------------

/**
 * Return the kind whose extensions list contains the lower-cased extension
 * of `filePath`, or null if none matches.
 */
const(ArtifactKind)* findArtifactKind(string filePath) {
    string ext = extension(filePath).toLower();
    if (ext.length == 0)
        return null;

    foreach (ref k; g_artifactKinds) {
        if (k.extensions.canFind(ext))
            return &k;
    }
    return null;
}

/**
 * Return the kind with id `kindId`, or null if not registered.
 */
const(ArtifactKind)* artifactKindById(string kindId) {
    foreach (ref k; g_artifactKinds) {
        if (k.id == kindId)
            return &k;
    }
    return null;
}

/**
 * Register the kinds shipped with the IDE. Safe to call more than once.
 */
void registerBuiltinArtifactKinds() {
    registerArtifactKind(ArtifactKind("text", "Text", [], true,
        (id, name, path) => cast(Artifact)new TextArtifact(id, "text", name, path)));

    import dcore.artifact.lyrics : registerLyricsKind;
    registerLyricsKind();
}
