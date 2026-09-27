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
 * PipedCommandTool - CommandTool that writes `input` to the process stdin.
 */
class PipedCommandTool : CommandTool {
    string input;

    this(string id, string name, string command, string[] defaultArgs = [], string description = "") {
        super(id, name, command, defaultArgs, description);
    }

    override bool execute(string[] arguments = []) {
        if (!super.execute(arguments))
            return false;
        try {
            if (input.length)
                _pipes.stdin.write(input);
            _pipes.stdin.close();
        } catch (Exception e) {
            Log.e("PipedCommandTool: Error writing stdin: ", id, " - ", e.msg);
        }
        return true;
    }
}

/**
 * ExternalToolTransform - Runs a command through ToolManager. By default the
 * input artifacts' source paths are appended as arguments; with `pipeText`
 * their text is written to stdin instead. Stdout becomes a single text
 * artifact of `outputKind`, delivered via onCompleted.
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
    private bool _pipeText;
    private ToolManager _toolManager;
    private PipedCommandTool _tool;
    private string _output;
    private string _errors;
    private int _exitCode;

    this(ToolManager toolManager, string id, string name, string[] kinds,
         string command, string[] args = [], string outputKind = "text", bool pipeText = false) {
        _toolManager = toolManager;
        _id = id;
        _name = name;
        _kinds = kinds;
        _command = command;
        _args = args;
        _outputKind = outputKind;
        _pipeText = pipeText;
    }

    /// Shell command line run via `sh -c`, with element text piped to stdin.
    static ExternalToolTransform shellPipe(ToolManager toolManager, string commandLine) {
        import std.digest.crc : crc32Of, toHexString;
        string id = "pipe." ~ toHexString(crc32Of(commandLine)).idup;
        return new ExternalToolTransform(toolManager, id, commandLine, [],
                                         "sh", ["-c", commandLine], "text", true);
    }

    @property bool running() { return _tool !is null && _tool.running; }

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

        return run(inputs, null);
    }

    /// Run with explicit stdin text (used when piping a single context element).
    Artifact[] run(Artifact[] inputs, string stdinText) {
        if (_toolManager is null) {
            Log.e("ExternalToolTransform: No ToolManager for ", _id);
            return [];
        }

        string toolId = "transform." ~ _id;
        if (_tool is null) {
            _tool = new PipedCommandTool(toolId, _name, _command, _args, "Artifact transform");
            _tool.onOutput.connect((string s) { _output ~= s; });
            _tool.onError.connect((string s) { _errors ~= s; });
            _tool.onExitCode.connect((int code) { _exitCode = code; });
            _tool.onFinished.connect(&handleFinished);
            _toolManager.registerTool(_tool);
        }

        _output = null;
        _errors = null;
        _exitCode = 0;
        string[] args;
        if (_pipeText) {
            if (stdinText is null)
                stdinText = inputs.map!(a => a.text()).join("\n");
            _tool.input = stdinText;
        } else {
            _tool.input = null;
            args = inputs.map!(a => a.sourcePath).filter!(p => p.length > 0).array;
        }
        if (!_toolManager.executeTool(toolId, args))
            Log.e("ExternalToolTransform: Failed to start ", _command);
        return [];
    }

    private void handleFinished() {
        string text = _output;
        if (_exitCode != 0) {
            Log.w("ExternalToolTransform: ", _id, " exited with ", _exitCode);
            text ~= "\n[exit " ~ _exitCode.to!string ~ "]\n" ~ _errors;
        }
        auto result = new TextArtifact(_id ~ ":out", _outputKind, "$ " ~ _name);
        result.setText(text);
        onCompleted.emit([cast(Artifact)result]);
    }
}
