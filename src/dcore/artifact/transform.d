module dcore.artifact.transform;

import dlangui.core.logger;

import std.algorithm;
import std.array;
import std.conv;

import dcore.artifact.artifact;
import dcore.tools.toolmanager;

/**
 * Transform - Turns input artifact(s) into output artifact(s).
 *
 * In-process transforms return their outputs from apply(). External
 * transforms run asynchronously and deliver outputs through onCompleted;
 * apply() returns an empty array for them.
 */
interface Transform {
    @property string id();
    @property string name();

    /// Whether this transform can take an artifact of `kind` as input.
    bool accepts(string kind);

    Artifact[] apply(Artifact[] inputs);
}

/**
 * InProcessTransform - Transform implemented by a D delegate.
 */
class InProcessTransform : Transform {
    private string _id;
    private string _name;
    private string[] _kinds;
    private Artifact[] delegate(Artifact[]) _fn;

    this(string id, string name, string[] kinds, Artifact[] delegate(Artifact[]) fn) {
        _id = id;
        _name = name;
        _kinds = kinds;
        _fn = fn;
    }

    @property string id() { return _id; }
    @property string name() { return _name; }

    bool accepts(string kind) {
        return _kinds.length == 0 || _kinds.canFind(kind);
    }

    Artifact[] apply(Artifact[] inputs) {
        try {
            return _fn(inputs);
        } catch (Exception e) {
            Log.e("Transform: ", _id, " failed: ", e.msg);
            return [];
        }
    }
}

/**
 * ExternalToolTransform - Runs a command through ToolManager with the input
 * artifacts' source paths appended as arguments. Stdout becomes a single
 * text artifact of `outputKind`, delivered via onCompleted.
 */
class ExternalToolTransform : Transform {
    import dcore.utils.signals : Signal;
    Signal!(Artifact[]) onCompleted;

    private string _id;
    private string _name;
    private string[] _kinds;
    private string _command;
    private string[] _args;
    private string _outputKind;
    private ToolManager _toolManager;
    private CommandTool _tool;
    private string _output;
    private int _exitCode;

    this(ToolManager toolManager, string id, string name, string[] kinds,
         string command, string[] args = [], string outputKind = "text") {
        _toolManager = toolManager;
        _id = id;
        _name = name;
        _kinds = kinds;
        _command = command;
        _args = args;
        _outputKind = outputKind;
    }

    @property string id() { return _id; }
    @property string name() { return _name; }

    bool accepts(string kind) {
        return _kinds.length == 0 || _kinds.canFind(kind);
    }

    Artifact[] apply(Artifact[] inputs) {
        if (_toolManager is null) {
            Log.e("ExternalToolTransform: No ToolManager for ", _id);
            return [];
        }

        string toolId = "transform." ~ _id;
        if (_tool is null) {
            _tool = new CommandTool(toolId, _name, _command, _args, "Artifact transform");
            _tool.onOutput.connect((string s) { _output ~= s; });
            _tool.onExitCode.connect((int code) { _exitCode = code; });
            _tool.onFinished.connect(&handleFinished);
            _toolManager.registerTool(_tool);
        }

        _output = null;
        _exitCode = 0;
        string[] paths = inputs.map!(a => a.sourcePath).filter!(p => p.length > 0).array;
        if (!_toolManager.executeTool(toolId, paths))
            Log.e("ExternalToolTransform: Failed to start ", _command);
        return [];
    }

    private void handleFinished() {
        if (_exitCode != 0) {
            Log.w("ExternalToolTransform: ", _id, " exited with ", _exitCode);
            onCompleted.emit([]);
            return;
        }
        auto result = new TextArtifact(_id ~ ":out", _outputKind, _name ~ " output");
        result.setText(_output);
        onCompleted.emit([cast(Artifact)result]);
    }
}
