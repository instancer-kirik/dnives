module dcore.tools.toolmanager;

import std.algorithm;
import std.array;
import std.process;
import std.string;
import std.path;
import std.file;
import std.json;
import std.datetime;
import std.regex;
import std.conv;
import core.thread;
import core.time;
import core.atomic;

import dlangui.core.logger;
// Use dlangui for UI signals
import dlangui.core.signals;

import dcore.core;
import dcore.vault.vault;

/**
 * ToolSignal - Simple signal implementation for tool manager
 * Supports two parameters for tool ID and data
 */
struct ToolSignal(T1, T2) {
    private void delegate(T1, T2)[] _handlers;
    private shared bool _locked;
    
    void connect(void delegate(T1, T2) handler) {
        if (handler is null)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Add handler if not already connected
        bool found = false;
        foreach (h; _handlers) {
            if (h == handler) {
                found = true;
                break;
            }
        }
        
        if (!found)
            _handlers ~= handler;
            
        atomicStore(_locked, false);
    }
    
    void disconnect(void delegate(T1, T2) handler) {
        if (handler is null || _handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Find and remove handler
        void delegate(T1, T2)[] newHandlers;
        foreach (h; _handlers) {
            if (h != handler)
                newHandlers ~= h;
        }
        
        _handlers = newHandlers;
        atomicStore(_locked, false);
    }
    
    void emit(T1 arg1, T2 arg2) {
        if (_handlers.length == 0)
            return;
            
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        // Call all handlers
        foreach (handler; _handlers) {
            if (handler !is null)
                handler(arg1, arg2);
        }
        
        atomicStore(_locked, false);
    }
    
    void clear() {
        while (atomicLoad(_locked)) {}
        atomicStore(_locked, true);
        
        _handlers.length = 0;
        
        atomicStore(_locked, false);
    }
}

/**
 * Tool - Abstract base class for all tools
 */
abstract class Tool {
    private string _id;
    private string _name;
    private string _description;
    private bool _enabled = true;
    private string _workingDirectory;

    // Events
    import dcore.utils.signals;
    Signal!() onStarted;
    Signal!() onFinished;
    Signal!(string) onOutput;
    Signal!(string) onError;
    Signal!(int) onExitCode;

    // Process state
    protected ProcessPipes _pipes;
    protected Pid _pid;
    protected bool _running = false;
    protected Thread _outputThread;
    protected Thread _errorThread;
    protected bool _stopThreads = false;

    /**
     * Constructor
     */
    this(string id, string name, string description = "") {
        _id = id;
        _name = name;
        _description = description;

        // Initialize signals with default values
        onStarted = Signal!().init;
        onFinished = Signal!().init;
        onOutput = Signal!(string).init;
        onError = Signal!(string).init;
        onExitCode = Signal!(int).init;
    }

    /**
     * Get tool ID
     */
    @property string id() { return _id; }

    /**
     * Get tool name
     */
    @property string name() { return _name; }

    /**
     * Get tool description
     */
    @property string description() { return _description; }

    /**
     * Check if tool is enabled
     */
    @property bool enabled() { return _enabled; }
    @property void enabled(bool value) { _enabled = value; }

    /**
     * Get working directory
     */
    @property string workingDirectory() { return _workingDirectory; }
    @property void workingDirectory(string value) { _workingDirectory = value; }

    /**
     * Check if tool is running
     */
    @property bool running() { return _running; }

    /**
     * Execute the tool with arguments
     */
    abstract bool execute(string[] arguments = []);

    /**
     * Stop the tool execution
     */
    bool stop() {
        if (!_running || _pid is null)
            return false;

        try {
            // Kill process
            kill(_pid);
            _running = false;

            // Stop output threads
            _stopThreads = true;
            if (_outputThread !is null && _outputThread.isRunning)
                _outputThread.join(false);
            if (_errorThread !is null && _errorThread.isRunning)
                _errorThread.join(false);

            onFinished.emit();

            return true;
        }
        catch (Exception e) {
            Log.e("Tool: Error stopping: ", _id, " - ", e.msg);
            return false;
        }
    }

    /**
     * Read output stream
     */
    protected void readOutput() {
        try {
            while (!_stopThreads && _running) {
                char[4096] buffer;
                auto bytesRead = _pipes.stdout.rawRead(buffer);

                if (bytesRead.length > 0) {
                    string output = cast(string)bytesRead;
                    onOutput.emit(output);
                } else {
                    // No more output
                    break;
                }

                // Short sleep to avoid CPU hogging
                Thread.sleep(dur!"msecs"(10));
            }
        }
        catch (Exception e) {
            Log.e("Tool: Error reading output: ", _id, " - ", e.msg);
        }
    }

    /**
     * Read error stream
     */
    protected void readError() {
        try {
            while (!_stopThreads && _running) {
                char[4096] buffer;
                auto bytesRead = _pipes.stderr.rawRead(buffer);

                if (bytesRead.length > 0) {
                    string error = cast(string)bytesRead;
                    onError.emit(error);
                } else {
                    // No more output
                    break;
                }

                // Short sleep to avoid CPU hogging
                Thread.sleep(dur!"msecs"(10));
            }
        }
        catch (Exception e) {
            Log.e("Tool: Error reading error stream: ", _id, " - ", e.msg);
        }
    }

    /**
     * Wait for process to complete
     */
    protected void waitForCompletion() {
        try {
            // Wait for process to exit
            auto exitCode = wait(_pid);

            // Wait for output threads to finish
            if (_outputThread !is null && _outputThread.isRunning)
                _outputThread.join(true);
            if (_errorThread !is null && _errorThread.isRunning)
                _errorThread.join(true);

            // Signal completion
            _running = false;
            onExitCode.emit(exitCode);
            onFinished.emit();
        }
        catch (Exception e) {
            Log.e("Tool: Error waiting for completion: ", _id, " - ", e.msg);
            _running = false;
            onFinished.emit();
        }
    }

    /**
     * Get tool configuration as JSON
     */
    JSONValue getConfig() {
        JSONValue config = parseJSON("{}");
        config["id"] = _id;
        config["name"] = _name;
        config["description"] = _description;
        config["enabled"] = _enabled;
        return config;
    }

    /**
     * Set tool configuration from JSON
     */
    void setConfig(JSONValue config) {
        if ("name" in config) _name = config["name"].str;
        if ("description" in config) _description = config["description"].str;
        if ("enabled" in config) _enabled = config["enabled"].boolean;
    }
}

/**
 * CommandTool - Tool that executes a command line
 */
class CommandTool : Tool {
    private string _command;
    private string[] _defaultArgs;
    private string _workspaceDir;

    /**
     * Constructor
     */
    this(string id, string name, string command, string[] defaultArgs = [], string description = "") {
        super(id, name, description);
        _command = command;
        _defaultArgs = defaultArgs;
    }

    /**
     * Get command
     */
    @property string command() { return _command; }
    @property void command(string value) { _command = value; }

    /**
     * Get default arguments
     */
    @property string[] defaultArgs() { return _defaultArgs; }
    @property void defaultArgs(string[] value) { _defaultArgs = value; }

    /**
     * Execute the command
     */
    override bool execute(string[] arguments = []) {
        if (!enabled)
            return false;

        if (running)
            return false;

        try {
            // Combine default args with provided args
            string[] args = _defaultArgs ~ arguments;

            // Determine working directory
            string cwd = workingDirectory;
            if (cwd.length == 0 && _workspaceDir.length > 0)
                cwd = _workspaceDir;

            // Start process
            _pipes = pipeProcess([_command] ~ args,
                Redirect.stdin | Redirect.stdout | Redirect.stderr,
                null, // environment
                Config.none,
                cwd.length > 0 ? cwd : null);

            _pid = _pipes.pid;
            _running = true;
            _stopThreads = false;

            Log.i("CommandTool: Executing: ", _command, " ", args.join(" "));

            // Start output reading threads
            _outputThread = new Thread(&readOutput);
            _errorThread = new Thread(&readError);

            _outputThread.isDaemon = true;
            _errorThread.isDaemon = true;

            _outputThread.start();
            _errorThread.start();

            // Signal started
            onStarted.emit();

            // Start wait thread
            Thread waitThread = new Thread(&waitForCompletion);
            waitThread.isDaemon = true;
            waitThread.start();

            return true;
        }
        catch (Exception e) {
            Log.e("CommandTool: Error executing: ", _id, " - ", e.msg);
            return false;
        }
    }

    /**
     * Set workspace directory
     */
    void setWorkspaceDir(string dir) {
        _workspaceDir = dir;
    }

    /**
     * Get tool configuration as JSON
     */
    override JSONValue getConfig() {
        JSONValue config = super.getConfig();
        config["command"] = _command;

        JSONValue argsArray = parseJSON("[]");
        foreach (arg; _defaultArgs)
            argsArray.array ~= JSONValue(arg);

        config["defaultArgs"] = argsArray;
        return config;
    }

    /**
     * Set tool configuration from JSON
     */
    override void setConfig(JSONValue config) {
        super.setConfig(config);

        if ("command" in config)
            _command = config["command"].str;

        if ("defaultArgs" in config && config["defaultArgs"].type == JSONType.array) {
            _defaultArgs.length = 0;
            foreach (arg; config["defaultArgs"].array)
                _defaultArgs ~= arg.str;
        }
    }
}

/**
 * BuildTool - Tool for building projects
 */
class BuildTool : CommandTool {
    // Build-specific properties
    private string _buildFile;
    private string _target = "all";
    private string _buildType = "debug"; // debug, release, etc.

    /**
     * Constructor
     */
    this(string id, string name, string command, string[] defaultArgs = [], string description = "") {
        super(id, name, command, defaultArgs, description);
    }

    /**
     * Get build file
     */
    @property string buildFile() { return _buildFile; }
    @property void buildFile(string value) { _buildFile = value; }

    /**
     * Get target
     */
    @property string target() { return _target; }
    @property void target(string value) { _target = value; }

    /**
     * Get build type
     */
    @property string buildType() { return _buildType; }
    @property void buildType(string value) { _buildType = value; }

    /**
     * Execute build with specific target and build type
     */
    bool build(string target = null, string buildType = null) {
        string actualTarget = target ? target : _target;
        string actualBuildType = buildType ? buildType : _buildType;

        // Add target and build type to arguments
        return execute([actualTarget, "--type=" ~ actualBuildType]);
    }

    /**
     * Get tool configuration as JSON
     */
    override JSONValue getConfig() {
        JSONValue config = super.getConfig();
        config["buildFile"] = _buildFile;
        config["target"] = _target;
        config["buildType"] = _buildType;
        return config;
    }

    /**
     * Set tool configuration from JSON
     */
    override void setConfig(JSONValue config) {
        super.setConfig(config);

        if ("buildFile" in config) _buildFile = config["buildFile"].str;
        if ("target" in config) _target = config["target"].str;
        if ("buildType" in config) _buildType = config["buildType"].str;
    }
}

/**
 * DebugTool - Tool for debugging projects
 */
class DebugTool : CommandTool {
    // Debug-specific properties
    private string _program;
    private string[] _programArgs;
    private string _breakpointsFile;

    /**
     * Constructor
     */
    this(string id, string name, string command, string[] defaultArgs = [], string description = "") {
        super(id, name, command, defaultArgs, description);
    }

    /**
     * Get program to debug
     */
    @property string program() { return _program; }
    @property void program(string value) { _program = value; }

    /**
     * Get program arguments
     */
    @property string[] programArgs() { return _programArgs; }
    @property void programArgs(string[] value) { _programArgs = value; }

    /**
     * Get breakpoints file
     */
    @property string breakpointsFile() { return _breakpointsFile; }
    @property void breakpointsFile(string value) { _breakpointsFile = value; }

    /**
     * Start debugging
     */
    bool debug_(string program = null, string[] programArgs = null) {
        string actualProgram = program ? program : _program;
        string[] actualProgramArgs = programArgs ? programArgs : _programArgs;

        // Add program and args to command arguments
        string[] args = [actualProgram] ~ actualProgramArgs;
        return execute(args);
    }

    /**
     * Send command to debugger
     */
    bool sendCommand(string command) {
        if (!running)
            return false;

        try {
            _pipes.stdin.writeln(command);
            _pipes.stdin.flush();
            return true;
        }
        catch (Exception e) {
            Log.e("DebugTool: Error sending command: ", e.msg);
            return false;
        }
    }

    /**
     * Get tool configuration as JSON
     */
    override JSONValue getConfig() {
        JSONValue config = super.getConfig();
        config["program"] = _program;

        JSONValue argsArray = parseJSON("[]");
        foreach (arg; _programArgs)
            argsArray.array ~= JSONValue(arg);

        config["programArgs"] = argsArray;
        config["breakpointsFile"] = _breakpointsFile;
        return config;
    }

    /**
     * Set tool configuration from JSON
     */
    override void setConfig(JSONValue config) {
        super.setConfig(config);

        if ("program" in config) _program = config["program"].str;

        if ("programArgs" in config && config["programArgs"].type == JSONType.array) {
            _programArgs.length = 0;
            foreach (arg; config["programArgs"].array)
                _programArgs ~= arg.str;
        }

        if ("breakpointsFile" in config) _breakpointsFile = config["breakpointsFile"].str;
    }
}

/**
 * ToolManager - Manages tools for the IDE
 */
class ToolManager {
    private DCore _core;
    private Tool[string] _tools;
    private string _configPath;

    // Default tools
    private BuildTool _buildTool;
    private DebugTool _debugTool;
    private CommandTool _formatTool;
    private CommandTool _runTool;

    // Output handlers using custom tool signals
    ToolSignal!(string, string) onToolOutput; // (tool_id, output_text)
    ToolSignal!(string, string) onToolError;  // (tool_id, error_text)
    ToolSignal!(string, int) onToolExited;    // (tool_id, exit_code)

    /**
     * Constructor
     */
    this(DCore core, string configPath) {
        _core = core;
        _configPath = configPath;

        // Initialize signals - as they are structs, no initialization needed
        // The signals are ready to use by default

        Log.i("ToolManager: Initializing");
    }

    /**
     * Initialize tool manager
     */
    void initialize() {
        Log.i("ToolManager: Starting initialization");

        // Create default tools
        createDefaultTools();

        // Load tool configurations
        loadConfig();

        Log.i("ToolManager: Initialization complete");
    }

    /**
     * Create default tools
     */
    private void createDefaultTools() {
        // D build tool (DUB)
        _buildTool = new BuildTool("dub_build", "DUB Build", "dub", ["build"], "Build D projects with DUB");
        registerTool(_buildTool);

        // D debugger
        _debugTool = new DebugTool("gdb", "GDB", "gdb", ["-q"], "Debug with GDB");
        registerTool(_debugTool);

        // D formatter
        _formatTool = new CommandTool("dfmt", "DFMT", "dfmt", [], "Format D code");
        registerTool(_formatTool);

        // Run tool
        _runTool = new CommandTool("run", "Run", "", [], "Run executable");
        registerTool(_runTool);
    }

    /**
     * Register a tool
     */
    void registerTool(Tool tool) {
        if (tool.id in _tools) {
            Log.w("ToolManager: Tool already registered: ", tool.id);
            return;
        }

        // Connect signals
        tool.onOutput.connect(delegate(string output) {
            // Pass both tool ID and output
            onToolOutput.emit(tool.id, output);
        });

        tool.onError.connect(delegate(string error) {
            // Pass both tool ID and error
            onToolError.emit(tool.id, error);
        });

        tool.onExitCode.connect(delegate(int exitCode) {
            // Pass both tool ID and exit code
            onToolExited.emit(tool.id, exitCode);
        });

        // Add to tools map
        _tools[tool.id] = tool;

        Log.i("ToolManager: Registered tool: ", tool.id);
    }

    /**
     * Get tool by ID
     */
    Tool getTool(string id) {
        if (id in _tools)
            return _tools[id];
        return null;
    }

    /**
     * Get all registered tools
     */
    Tool[] getAllTools() {
        Tool[] result;
        foreach (id, tool; _tools)
            result ~= tool;
        return result;
    }

    /**
     * Execute a tool by ID
     */
    bool executeTool(string id, string[] arguments = []) {
        if (id !in _tools) {
            Log.e("ToolManager: Tool not found: ", id);
            return false;
        }

        Tool tool = _tools[id];
        return tool.execute(arguments);
    }

    /**
     * Stop a running tool
     */
    bool stopTool(string id) {
        if (id !in _tools) {
            Log.e("ToolManager: Tool not found: ", id);
            return false;
        }

        Tool tool = _tools[id];
        return tool.stop();
    }

    /**
     * Build a project
     */
    bool build(string target = null, string buildType = null) {
        if (!_buildTool) {
            Log.e("ToolManager: Build tool not initialized");
            return false;
        }

        return _buildTool.build(target, buildType);
    }

    /**
     * Debug a program
     */
    bool debug_(string program = null, string[] programArgs = null) {
        if (!_debugTool) {
            Log.e("ToolManager: Debug tool not initialized");
            return false;
        }

        return _debugTool.debug_(program, programArgs);
    }

    /**
     * Format a file
     */
    bool formatFile(string filePath) {
        if (!_formatTool) {
            Log.e("ToolManager: Format tool not initialized");
            return false;
        }

        return _formatTool.execute([filePath]);
    }

    /**
     * Run a program
     */
    bool run(string program, string[] programArgs = []) {
        if (!_runTool) {
            Log.e("ToolManager: Run tool not initialized");
            return false;
        }

        // Set the program as the command
        _runTool.command = program;
        return _runTool.execute(programArgs);
    }

    /**
     * Set workspace directory for tools
     */
    void setWorkspaceDir(string dir) {
        if (!exists(dir)) {
            Log.e("ToolManager: Workspace directory does not exist: ", dir);
            return;
        }

        // Set working directory for all tools
        foreach (id, tool; _tools) {
            CommandTool cmdTool = cast(CommandTool)tool;
            if (cmdTool)
                cmdTool.setWorkspaceDir(dir);
        }

        Log.i("ToolManager: Set workspace directory: ", dir);
    }

    /**
     * Workspace changed event handler
     */
    void onWorkspaceChanged(Workspace workspace) {
        if (!workspace)
            return;

        string workspacePath = workspace.path;

        // Set workspace directory for tools
        setWorkspaceDir(workspacePath);

        // Check for project files
        detectProjectType(workspacePath);

        Log.i("ToolManager: Workspace changed to: ", workspace.name);
    }

    /**
     * Detect project type and configure tools
     */
    private void detectProjectType(string workspacePath) {
        // Check for DUB project
        string dubFile = buildPath(workspacePath, "dub.json");
        string dubSdlFile = buildPath(workspacePath, "dub.sdl");

        if (exists(dubFile) || exists(dubSdlFile)) {
            Log.i("ToolManager: Detected DUB project");

            // Configure build tool
            _buildTool.workingDirectory = workspacePath;
            _buildTool.buildFile = exists(dubFile) ? dubFile : dubSdlFile;

            // Find executable
            string dubDesc = execute(["dub", "describe", "--root=" ~ workspacePath]).output;
            try {
                auto json = parseJSON(dubDesc);
                string mainSourceFile = json["mainSourceFile"].str;
                string targetPath = json["targetPath"].str;
                string targetName = json["targetName"].str;

                string targetExecutable = buildPath(workspacePath, targetPath, targetName);

                // Configure debug tool
                _debugTool.workingDirectory = workspacePath;
                _debugTool.program = targetExecutable;

                // Configure run tool
                _runTool.workingDirectory = workspacePath;
                _runTool.command = targetExecutable;

                Log.i("ToolManager: Configured tools for DUB project");
            } catch (Exception e) {
                Log.w("ToolManager: Error parsing DUB description: ", e.msg);
            }

            return;
        }

        // Check for Make project
        string makeFile = buildPath(workspacePath, "Makefile");
        if (exists(makeFile)) {
            Log.i("ToolManager: Detected Make project");

            // Configure build tool
            auto makeTool = cast(BuildTool)getTool("make_build");
            if (!makeTool) {
                makeTool = new BuildTool("make_build", "Make", "make", [], "Build with Make");
                registerTool(makeTool);
            }

            makeTool.workingDirectory = workspacePath;
            makeTool.buildFile = makeFile;

            // Use make tool as default build tool
            _buildTool = makeTool;

            return;
        }

        // Check for CMake project
        string cmakeFile = buildPath(workspacePath, "CMakeLists.txt");
        if (exists(cmakeFile)) {
            Log.i("ToolManager: Detected CMake project");

            // Configure build tool
            auto cmakeTool = cast(BuildTool)getTool("cmake_build");
            if (!cmakeTool) {
                cmakeTool = new BuildTool("cmake_build", "CMake", "cmake", ["--build", "."], "Build with CMake");
                registerTool(cmakeTool);
            }

            cmakeTool.workingDirectory = workspacePath;
            cmakeTool.buildFile = cmakeFile;

            // Use cmake tool as default build tool
            _buildTool = cmakeTool;

            return;
        }
    }

    /**
     * Load tool configurations
     */
    void loadConfig() {
        if (!exists(_configPath)) {
            Log.i("ToolManager: Config file does not exist, using defaults: ", _configPath);
            return;
        }

        try {
            string content = readText(_configPath);
            JSONValue config = parseJSON(content);

            if ("tools" !in config || config["tools"].type != JSONType.array) {
                Log.w("ToolManager: Invalid config file, using defaults");
                return;
            }

            // Configure tools
            foreach (toolConfig; config["tools"].array) {
                string id = toolConfig["id"].str;

                if (id in _tools) {
                    // Configure existing tool
                    _tools[id].setConfig(toolConfig);
                    Log.i("ToolManager: Configured tool: ", id);
                }
            }
        } catch (Exception e) {
            Log.e("ToolManager: Error loading config: ", e.msg);
        }
    }

    /**
     * Save tool configurations
     */
    void saveConfig() {
        try {
            JSONValue config = parseJSON("{}");
            JSONValue toolsArray = parseJSON("[]");

            // Add each tool's config
            foreach (id, tool; _tools)
                toolsArray.array ~= tool.getConfig();

            config["tools"] = toolsArray;

            // Create directory if it doesn't exist
            string dir = dirName(_configPath);
            if (!exists(dir))
                mkdirRecurse(dir);

            // Save to file
            std.file.write(_configPath, config.toPrettyString());

            Log.i("ToolManager: Config saved: ", _configPath);
        } catch (Exception e) {
            Log.e("ToolManager: Error saving config: ", e.msg);
        }
    }

    /**
     * Cleanup resources
     */
    void cleanup() {
        Log.i("ToolManager: Cleaning up");

        // Stop all running tools
        foreach (id, tool; _tools) {
            if (tool.running) {
                Log.i("ToolManager: Stopping tool: ", id);
                tool.stop();
            }
        }

        // Save configuration
        saveConfig();
    }
}
