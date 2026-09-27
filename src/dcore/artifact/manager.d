module dcore.artifact.manager;

import dlangui.core.logger;

import std.algorithm;
import std.array;
import std.path;

import dcore.artifact.artifact;
import dcore.artifact.kind;
import dcore.artifact.transform;

/**
 * ArtifactManager - Tracks artifacts per workspace and the available transforms.
 *
 * Workspaces are keyed by directory so both the dlangide Workspace and the
 * vault Workspace can use it. Files whose extension has no registered kind
 * are not artifacts; existing code tooling handles them as before.
 */
class ArtifactManager {
    import dcore.utils.signals : Signal;
    Signal!(Artifact) onArtifactOpened;

    private Artifact[string][string] _artifacts; // workspace dir -> id -> artifact
    private Transform[string] _transforms;

    this() {
        Log.i("ArtifactManager: Initializing");
    }

    void initialize() {
        registerBuiltinArtifactKinds();

        import dcore.artifact.lyrics : lyricsTransforms;
        foreach (t; lyricsTransforms())
            registerTransform(t);

        Log.i("ArtifactManager: ", artifactKinds.length, " kinds, ",
              _transforms.length, " transforms registered");
    }

    void registerTransform(Transform t) {
        _transforms[t.id] = t;
    }

    Transform getTransform(string id) {
        auto p = id in _transforms;
        return p ? *p : null;
    }

    /// Transforms that accept artifacts of `kind`.
    Transform[] transformsFor(string kind) {
        return _transforms.values.filter!(t => t.accepts(kind)).array;
    }

    /**
     * Return the artifact for `filePath` in `workspaceDir`, creating it if its
     * extension maps to a registered kind. Returns null for non-artifact files.
     */
    Artifact resolve(string filePath, string workspaceDir = null) {
        string id = buildNormalizedPath(filePath);
        string ws = workspaceDir.length ? buildNormalizedPath(workspaceDir) : "";

        if (auto wsMap = ws in _artifacts)
            if (auto a = id in *wsMap)
                return *a;

        auto kind = findArtifactKind(id);
        if (kind is null || kind.create is null)
            return null;

        Artifact a = kind.create(id, baseName(id), id);
        _artifacts[ws][id] = a;
        Log.i("ArtifactManager: Opened ", kind.id, " artifact: ", id);
        onArtifactOpened.emit(a);
        return a;
    }

    Artifact[] artifacts(string workspaceDir) {
        string ws = workspaceDir.length ? buildNormalizedPath(workspaceDir) : "";
        if (auto wsMap = ws in _artifacts)
            return wsMap.values;
        return [];
    }

    void closeArtifact(string filePath, string workspaceDir = null) {
        string ws = workspaceDir.length ? buildNormalizedPath(workspaceDir) : "";
        if (auto wsMap = ws in _artifacts)
            (*wsMap).remove(buildNormalizedPath(filePath));
    }

    void closeWorkspace(string workspaceDir) {
        _artifacts.remove(workspaceDir.length ? buildNormalizedPath(workspaceDir) : "");
    }

    Artifact[] runTransform(string transformId, Artifact[] inputs) {
        auto t = getTransform(transformId);
        if (t is null) {
            Log.w("ArtifactManager: Unknown transform ", transformId);
            return [];
        }
        return t.apply(inputs);
    }

    void cleanup() {
        _artifacts = null;
    }
}
