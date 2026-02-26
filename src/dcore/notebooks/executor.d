module dcore.notebooks.executor;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.file;
import std.json;
import std.path;
import std.process;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;
import std.uuid;

import dlangui.core.logger;
import dlangui.core.signals;
import dcore.utils.signals : Signal;
import dcore.notebooks.notebook;

/**
 * Kernel types supported by the notebook executor
 */
enum KernelType {
    D,           // D language
    Shell,       // Shell commands
    Python,      // Python (if available)
    JavaScript,  // JavaScript/Node.js
    SQL,         // SQL queries
    Markdown,    // Markdown rendering
    AI           // AI-powered code generation
}

/**
 * Execution context for code cells
 */
class ExecutionContext {
    private string[string] _variables;
    private string[] _imports;
    private string[] _moduleDefinitions;
    private string _workingDirectory;
    private JSONValue _metadata;

    this() {
        _workingDirectory = getcwd();
        _metadata = JSONValue.emptyObject;
    }

    @property string[string] variables() { return _variables; }
    @property string[] imports() { return _imports.dup; }
    @property string[] moduleDefinitions() { return _moduleDefinitions.dup; }
    @property string workingDirectory() const { return _workingDirectory; }
    @property void workingDirectory(string path) { _workingDirectory = path; }

    void setVariable(string name, string value) {
        _variables[name] = value;
    }

    string getVariable(string name) {
        return _variables.get(name, "");
    }

    void addImport(string importStatement) {
        if (!_imports.canFind(importStatement)) {
            _imports ~= importStatement;
        }
    }

    void addModuleDefinition(string moduleCode) {
        _moduleDefinitions ~= moduleCode;
    }

    void reset() {
        _variables.clear();
        _imports.length = 0;
        _moduleDefinitions.length = 0;
    }
}

/**
 * Execution result for a single cell
 */
struct ExecutionResult {
    bool success;
    string output;
    string errorOutput;
    Duration executionTime;
    JSONValue metadata;
    string[] warnings;

    this(bool success, string output = "", string errorOutput = "") {
        this.success = success;
        this.output = output;
        this.errorOutput = errorOutput;
        this.executionTime = Duration.zero;
        this.metadata = JSONValue.emptyObject;
    }
}

/**
 * Base kernel interface
 */
abstract class NotebookKernel {
    protected ExecutionContext _context;
    protected string _name;
    protected string _version;

    this(string name, string ver = "1.0") {
        _name = name;
        _version = ver;
        _context = new ExecutionContext();
    }

    @property string name() const { return _name; }
    @property string kernelVersion() const { return _version; }
    @property ExecutionContext context() { return _context; }

    abstract ExecutionResult execute(string code);
    abstract bool isAvailable();
    abstract string[] getSupportedLanguages();

    void reset() {
        _context.reset();
    }
}

/**
 * D language kernel
 */
class DKernel : NotebookKernel {
    private string _dmdPath;
    private string _dubPath;
    private string _tempDir;
    private int _executionCounter;

    this() {
        super("D", "1.0");
        _dmdPath = findExecutable("dmd");
        _dubPath = findExecutable("dub");
        _tempDir = buildPath(tempDir(), "dnives_notebook_" ~ randomUUID().toString()[0..8]);
        _executionCounter = 0;

        // Create temp directory
        if (!exists(_tempDir)) {
            mkdirRecurse(_tempDir);
        }

        // Set up basic D environment
        _context.addImport("import std.stdio;");
        _context.addImport("import std.algorithm;");
        _context.addImport("import std.array;");
        _context.addImport("import std.conv;");
        _context.addImport("import std.range;");
    }

    ~this() {
        // Cleanup temp directory
        if (exists(_tempDir)) {
            try {
                rmdirRecurse(_tempDir);
            } catch (Exception e) {
                Log.w("Failed to cleanup temp directory: ", e.msg);
            }
        }
    }

    override bool isAvailable() {
        return _dmdPath.length > 0;
    }

    override string[] getSupportedLanguages() {
        return ["d", "dlang"];
    }

    override ExecutionResult execute(string code) {
        auto startTime = MonoTime.currTime();
        _executionCounter++;

        try {
            // Analyze code to extract imports and module definitions
            analyzeCode(code);

            // Generate complete D program
            string fullProgram = generateProgram(code);

            // Write to temp file
            string tempFile = buildPath(_tempDir, format("cell_%d.d", _executionCounter));
            std.file.write(tempFile, fullProgram);

            // Compile and run
            auto result = compileAndRun(tempFile);
            result.executionTime = MonoTime.currTime() - startTime;

            return result;
        } catch (Exception e) {
            auto result = ExecutionResult(false, "", e.msg);
            result.executionTime = MonoTime.currTime() - startTime;
            return result;
        }
    }

    private void analyzeCode(string code) {
        // Extract import statements
        auto importRegex = regex(r"import\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s*;");
        foreach (match; matchAll(code, importRegex)) {
            _context.addImport(match.hit);
        }

        // Extract module definitions (classes, structs, functions)
        auto moduleRegex = regex(r"(class|struct|enum|interface)\s+([a-zA-Z_][a-zA-Z0-9_]*)", "g");
        foreach (match; matchAll(code, moduleRegex)) {
            // This is a simplified approach - in practice, we'd need a proper D parser
            // For now, we'll just track that module-level constructs exist
        }
    }

    private string generateProgram(string code) {
        string program = "";

        // Add imports
        foreach (importStmt; _context.imports) {
            program ~= importStmt ~ "\n";
        }

        program ~= "\n";

        // Add previous module definitions
        foreach (moduleDef; _context.moduleDefinitions) {
            program ~= moduleDef ~ "\n\n";
        }

        // Wrap user code in main function if not already a complete program
        if (!code.canFind("void main") && !code.canFind("int main")) {
            program ~= "void main() {\n";
            program ~= "    try {\n";
            program ~= indentCode(code, "        ");
            program ~= "\n    } catch (Exception e) {\n";
            program ~= "        stderr.writeln(\"Error: \", e.msg);\n";
            program ~= "    }\n";
            program ~= "}\n";
        } else {
            program ~= code;
        }

        return program;
    }

    private ExecutionResult compileAndRun(string sourceFile) {
        string execFile = sourceFile.setExtension("exe");

        // Compile
        auto compileResult = executeCommand([_dmdPath, "-of=" ~ execFile, sourceFile]);
        if (!compileResult.success) {
            return ExecutionResult(false, "", compileResult.output);
        }

        // Run
        auto runResult = executeCommand([execFile]);

        // Clean up executable
        if (exists(execFile)) {
            remove(execFile);
        }

        return runResult;
    }

    private string indentCode(string code, string indent) {
        return code.splitLines().map!(line => indent ~ line).join("\n");
    }
}

/**
 * Shell kernel for system commands
 */
class ShellKernel : NotebookKernel {
    this() {
        super("Shell", "1.0");
    }

    override bool isAvailable() {
        return true; // Shell is always available
    }

    override string[] getSupportedLanguages() {
        return ["sh", "bash", "shell", "cmd"];
    }

    override ExecutionResult execute(string code) {
        auto startTime = MonoTime.currTime();

        try {
            auto result = executeCommand(["sh", "-c", code], _context.workingDirectory);
            result.executionTime = MonoTime.currTime() - startTime;
            return result;
        } catch (Exception e) {
            auto result = ExecutionResult(false, "", e.msg);
            result.executionTime = MonoTime.currTime() - startTime;
            return result;
        }
    }
}

/**
 * AI kernel for AI-powered code generation and assistance
 */
class AIKernel : NotebookKernel {
    // This would integrate with the existing AI system in dnives
    private bool _aiAvailable;

    this() {
        super("AI", "1.0");
        // Check if AI system is available
        _aiAvailable = checkAIAvailability();
    }

    override bool isAvailable() {
        return _aiAvailable;
    }

    override string[] getSupportedLanguages() {
        return ["ai", "assistant"];
    }

    override ExecutionResult execute(string code) {
        auto startTime = MonoTime.currTime();

        try {
            // This would integrate with the existing AI chat system
            // For now, return a placeholder response
            string aiResponse = processAIRequest(code);

            auto result = ExecutionResult(true, aiResponse, "");
            result.executionTime = MonoTime.currTime() - startTime;
            return result;
        } catch (Exception e) {
            auto result = ExecutionResult(false, "", e.msg);
            result.executionTime = MonoTime.currTime() - startTime;
            return result;
        }
    }

    private bool checkAIAvailability() {
        // This would check if AI configuration exists and is valid
        // For now, assume it's available
        return true;
    }

    private string processAIRequest(string request) {
        // This would integrate with the AI backend system
        // For now, return a placeholder
        return "AI Response: " ~ request ~ "\n\n(This would be processed by the AI system)";
    }
}

/**
 * Main notebook executor
 */
class NotebookExecutor {
    private NotebookKernel[KernelType] _kernels;
    private KernelType _defaultKernel;
    private ExecutionContext _globalContext;

    // Signals
    Signal!(NotebookCell, ExecutionResult) onCellExecuted;
    Signal!(NotebookCell) onExecutionStarted;
    Signal!(string) onExecutionError;

    this() {
        _defaultKernel = KernelType.D;
        _globalContext = new ExecutionContext();

        // Initialize kernels
        _kernels[KernelType.D] = new DKernel();
        _kernels[KernelType.Shell] = new ShellKernel();
        _kernels[KernelType.AI] = new AIKernel();

        Log.i("NotebookExecutor initialized with ", _kernels.length, " kernels");
    }

    /**
     * Execute a single cell
     */
    ExecutionResult executeCell(NotebookCell cell, KernelType kernelType = KernelType.D) {
        if (cell is null) {
            return ExecutionResult(false, "", "Invalid cell");
        }

        if (!cell.isCodeCell()) {
            return ExecutionResult(false, "", "Cell is not executable");
        }

        onExecutionStarted.emit(cell);
        cell.state = CellState.Running;

        try {
            auto kernel = getKernel(kernelType);
            if (kernel is null) {
                auto errorMsg = format("Kernel not available: %s", kernelType);
                onExecutionError.emit(errorMsg);
                return ExecutionResult(false, "", errorMsg);
            }

            auto result = kernel.execute(cell.source);

            // Update cell with results
            if (result.success) {
                cell.output = result.output;
                cell.errorOutput = "";
                cell.markExecuted();
            } else {
                cell.output = "";
                cell.errorOutput = result.errorOutput;
                cell.markFailed(result.errorOutput);
            }

            onCellExecuted.emit(cell, result);
            return result;

        } catch (Exception e) {
            string errorMsg = "Execution failed: " ~ e.msg;
            cell.markFailed(errorMsg);
            onExecutionError.emit(errorMsg);
            return ExecutionResult(false, "", errorMsg);
        }
    }

    /**
     * Execute all cells in a notebook
     */
    ExecutionResult[] executeNotebook(Notebook notebook, KernelType kernelType = KernelType.D) {
        ExecutionResult[] results;

        if (notebook is null) {
            return results;
        }

        // Reset kernel context for clean execution
        auto kernel = getKernel(kernelType);
        if (kernel !is null) {
            kernel.reset();
        }

        // Execute all code cells in order
        auto codeCells = notebook.getCodeCells();
        foreach (cell; codeCells) {
            auto result = executeCell(cell, kernelType);
            results ~= result;

            // Stop execution if a cell fails (optional behavior)
            if (!result.success) {
                Log.w("Cell execution failed, stopping notebook execution");
                break;
            }
        }

        return results;
    }

    /**
     * Execute cells in a specific section
     */
    ExecutionResult[] executeSection(NotebookSection section, KernelType kernelType = KernelType.D) {
        ExecutionResult[] results;

        if (section is null) {
            return results;
        }

        foreach (cell; section.cells()) {
            if (cell.isCodeCell()) {
                auto result = executeCell(cell, kernelType);
                results ~= result;
            }
        }

        return results;
    }

    /**
     * Get available kernels
     */
    KernelType[] getAvailableKernels() {
        KernelType[] available;
        foreach (type, kernel; _kernels) {
            if (kernel.isAvailable()) {
                available ~= type;
            }
        }
        return available;
    }

    /**
     * Get kernel by type
     */
    NotebookKernel getKernel(KernelType type) {
        return _kernels.get(type, null);
    }

    /**
     * Register a custom kernel
     */
    void registerKernel(KernelType type, NotebookKernel kernel) {
        _kernels[type] = kernel;
        Log.i("Registered custom kernel: ", type);
    }

    /**
     * Interrupt execution (placeholder for future implementation)
     */
    void interruptExecution() {
        Log.i("Execution interrupt requested (not yet implemented)");
        // This would require process management and threading
    }

    /**
     * Clear all outputs from notebook
     */
    void clearAllOutputs(Notebook notebook) {
        if (notebook is null) return;

        foreach (cell; notebook.getAllCells()) {
            if (cell.isCodeCell()) {
                cell.clearOutput();
            }
        }

        Log.i("Cleared all outputs for notebook: ", notebook.name);
    }

    /**
     * Restart kernel and clear outputs
     */
    void restartKernel(KernelType kernelType = KernelType.D) {
        auto kernel = getKernel(kernelType);
        if (kernel !is null) {
            kernel.reset();
            Log.i("Restarted kernel: ", kernelType);
        }
    }
}

/**
 * Utility functions
 */

/**
 * Find executable in system PATH
 */
string findExecutable(string name) {
    version(Windows) {
        string[] extensions = ["", ".exe", ".cmd", ".bat"];
    } else {
        string[] extensions = [""];
    }

    // Check current directory first
    foreach (ext; extensions) {
        string path = name ~ ext;
        if (exists(path) && isFile(path)) {
            return absolutePath(path);
        }
    }

    // Check PATH environment
    string pathEnv = environment.get("PATH", "");
    foreach (pathDir; pathEnv.split(pathSeparator)) {
        if (pathDir.length == 0) continue;

        foreach (ext; extensions) {
            string fullPath = buildPath(pathDir, name ~ ext);
            if (exists(fullPath) && isFile(fullPath)) {
                return fullPath;
            }
        }
    }

    return "";
}

/**
 * Execute a command and capture output
 */
ExecutionResult executeCommand(string[] args, string workingDir = "") {
    try {
        string[string] env = workingDir.length > 0 ? ["PWD": workingDir] : null;
        auto pipes = pipeProcess(args, Redirect.all, env, Config.none, workingDir);

        // Read output
        string output = "";
        string errorOutput = "";

        foreach (line; pipes.stdout.byLine) {
            output ~= line ~ "\n";
        }

        foreach (line; pipes.stderr.byLine) {
            errorOutput ~= line ~ "\n";
        }

        auto exitCode = wait(pipes.pid);
        bool success = (exitCode == 0);

        return ExecutionResult(success, output, errorOutput);

    } catch (Exception e) {
        return ExecutionResult(false, "", "Command execution failed: " ~ e.msg);
    }
}

/**
 * Detect kernel type from cell metadata or content
 */
KernelType detectKernelType(NotebookCell cell) {
    if (cell is null || !cell.isCodeCell()) {
        return KernelType.D;
    }

    // Check metadata first
    auto metadata = cell.metadata;
    if (metadata.type == JSONType.object && "kernel" in metadata) {
        string kernelStr = metadata["kernel"].str.toLower;
        switch (kernelStr) {
            case "d": case "dlang": return KernelType.D;
            case "sh": case "shell": case "bash": return KernelType.Shell;
            case "python": case "py": return KernelType.Python;
            case "js": case "javascript": case "node": return KernelType.JavaScript;
            case "sql": return KernelType.SQL;
            case "ai": case "assistant": return KernelType.AI;
            default: break;
        }
    }

    // Try to detect from content
    string source = cell.source.strip().toLower;

    if (source.startsWith("import ") && source.canFind("std.")) {
        return KernelType.D;
    } else if (source.startsWith("#!/bin/sh") || source.startsWith("#!/bin/bash")) {
        return KernelType.Shell;
    } else if (source.startsWith("select ") || source.startsWith("insert ") ||
               source.startsWith("update ") || source.startsWith("delete ")) {
        return KernelType.SQL;
    } else if (source.startsWith("please ") || source.startsWith("can you ") ||
               source.startsWith("help me ")) {
        return KernelType.AI;
    }

    // Default to D kernel
    return KernelType.D;
}
