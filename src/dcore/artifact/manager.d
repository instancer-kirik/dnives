module dcore.artifact.manager;

import dlangui.core.logger;

import std.algorithm;
import std.array;
import std.format;
import std.path;
import std.string;

import dcore.artifact.artifact;
import dcore.artifact.kind;
import dcore.artifact.transform;
import dcore.tools.toolmanager;

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
    private ExternalToolTransform[string] _pipes; // command line -> transform
    private int _scratchCounter;

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

    /**
     * Create an in-memory text artifact (e.g. from pasted text) in `workspaceDir`.
     */
    TextArtifact createScratch(string text, string workspaceDir = null) {
        string ws = workspaceDir.length ? buildNormalizedPath(workspaceDir) : "";
        string id = format("scratch:%d", ++_scratchCounter);
        auto a = new TextArtifact(id, "text", format("Scratch %d", _scratchCounter));
        a.setText(text);
        _artifacts[ws][id] = a;
        onArtifactOpened.emit(a);
        return a;
    }

    /// Scratch artifacts of `workspaceDir`, oldest first.
    Artifact[] scratchArtifacts(string workspaceDir) {
        return artifacts(workspaceDir).filter!(a => a.id.startsWith("scratch:"))
                                      .array.sort!((a, b) => a.id < b.id).release;
    }

    /**
     * Run a registered transform; outputs are attached to the first input.
     */
    Artifact[] runTransform(string transformId, Artifact[] inputs) {
        auto t = getTransform(transformId);
        if (t is null) {
            Log.w("ArtifactManager: Unknown transform ", transformId);
            return [];
        }
        auto outputs = t.apply(inputs);
        if (inputs.length && outputs.length)
            inputs[0].addDerived(outputs);
        return outputs;
    }

    /**
     * Pipe `text` to a shell command line through ToolManager. Stdout is
     * delivered asynchronously to `done` (on the tool's thread).
     */
    void pipeToCommand(ToolManager toolManager, string commandLine, string text,
                       void delegate(Artifact[]) done) {
        auto p = commandLine in _pipes;
        ExternalToolTransform t = p ? *p : null;
        if (t is null) {
            t = ExternalToolTransform.shellPipe(toolManager, commandLine);
            _pipes[commandLine] = t;
        }
        if (t.running) {
            Log.w("ArtifactManager: Command still running: ", commandLine);
            return;
        }
        t.onCompleted.clear();
        t.onCompleted.connect(done);
        t.run([], text);
    }

    void cleanup() {
        _artifacts = null;
    }
}
