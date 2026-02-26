module dcore.utils.process;

import std.process;
import std.stdio;
import std.array;
import std.string;
import std.algorithm;
import std.datetime;
import std.path;
import std.file;
import std.conv;
import core.thread;
import core.time;

import dlangui.core.logger;

import dcore.utils.signals;

/**
 * Process wrapper utility for the CompyutinatorCode D implementation
 * 
 * Provides a convenient interface for spawning and managing external processes
 * with support for asynchronous execution, output capturing, and command building.
 */
class Process {
    private {
        string _executable;           // Process executable
        string[] _arguments;          // Process arguments
        string _workingDir;           // Working directory
        string[string] _environment;  // Environment variables
        
        std.process.Pid _pid;         // Process ID
        
        string _stdoutData;           // Standard output data
        string _stderrData;           // Standard error data
        int _exitCode;                // Exit code
        
        bool _running;                // Is process running?
        bool _captureOutput;          // Capture output?
        bool _mergeOutput;            // Merge stdout and stderr?
        
        Thread _monitorThread;        // Thread to monitor process execution
    }
    
    // Signals
    Signal!() onStarted;              // Process started
    Signal!() onStopped;              // Process stopped
    Signal!() onStdoutReceived;       // Data received on stdout
    Signal!() onStderrReceived;       // Data received on stderr
    
    /**
     * Create a new process
     */
    this(string executable) {
        _executable = executable;
        _arguments = [];
        _workingDir = getcwd();
        _captureOutput = true;
        _mergeOutput = false;
        _running = false;
    }
    
    /**
     * Set process arguments
     */
    Process setArguments(string[] args) {
        _arguments = args;
        return this;
    }
    
    /**
     * Add an argument to the process
     */
    Process addArgument(string arg) {
        _arguments ~= arg;
        return this;
    }
    
    /**
     * Set working directory
     */
    Process setWorkingDir(string dir) {
        _workingDir = dir;
        return this;
    }
    
    /**
     * Set environment variable
     */
    Process setEnvironment(string key, string value) {
        _environment[key] = value;
        return this;
    }
    
    /**
     * Set whether to capture output
     */
    Process setCaptureOutput(bool capture) {
        _captureOutput = capture;
        return this;
    }
    
    /**
     * Set whether to merge stdout and stderr
     */
    Process setMergeOutput(bool merge) {
        _mergeOutput = merge;
        return this;
    }
    
    /**
     * Start the process
     */
    bool start() {
        if (_running)
            return false;
            
        try {
            // Prepare process configuration
            auto config = std.process.Config.none;
            
            // Start process with appropriate redirection
            std.process.ProcessPipes pipes;
            if (_captureOutput) {
                pipes = pipeProcess([_executable] ~ _arguments, 
                                   std.process.Redirect.all, 
                                   _environment, 
                                   config, 
                                   _workingDir);
            } else {
                pipes = pipeProcess([_executable] ~ _arguments, 
                                   std.process.Redirect.stdin, 
                                   _environment, 
                                   config, 
                                   _workingDir);
            }
            _pid = pipes.pid;
            _running = true;
            
            // Signal process started
            onStarted.emit();
                
            // Start monitor thread if capturing output
            if (_captureOutput) {
                _monitorThread = new Thread({
                    _stdoutData = "";
                    _stderrData = "";
                    
                    // Read stdout
                    foreach (line; pipes.stdout.byLine) {
                        _stdoutData ~= line.to!string ~ "\n";
                        onStdoutReceived.emit();
                    }
                    
                    // Read stderr if not merged
                    if (!_mergeOutput) {
                        foreach (line; pipes.stderr.byLine) {
                            _stderrData ~= line.to!string ~ "\n";
                            onStderrReceived.emit();
                        }
                    }
                    
                    // Wait for process to exit
                    auto result = pipes.pid.wait();
                    _exitCode = result;
                    _running = false;
                    
                    // Signal process stopped
                    onStopped.emit();
                });
                
                _monitorThread.isDaemon = true;
                _monitorThread.start();
            }
            
            return true;
        } catch (Exception e) {
            Log.e("Failed to start process: ", e.msg);
            return false;
        }
    }
    
    /**
     * Execute process synchronously and return exit code
     */
    int execute() {
        if (!start())
            return -1;
            
        // If we're capturing output, wait for monitor thread
        if (_captureOutput && _monitorThread) {
            _monitorThread.join();
            return _exitCode;
        }
        
        // Otherwise wait directly
        auto result = _pid.wait();
        _running = false;
        _exitCode = result;
        
        onStopped.emit();
            
        return _exitCode;
    }
    
    /**
     * Kill the process
     */
    bool kill() {
        if (!_running)
            return false;
            
        try {
            std.process.kill(_pid);
            _running = false;
            
            onStopped.emit();
                
            return true;
        } catch (Exception e) {
            Log.e("Failed to kill process: ", e.msg);
            return false;
        }
    }
    
    /**
     * Check if process is running
     */
    bool isRunning() {
        if (!_running)
            return false;
            
        try {
            auto result = _pid.tryWait();
            if (result.terminated) {
                _running = false;
                _exitCode = result.status;
                
                onStopped.emit();
            }
            
            return !result.terminated;
        } catch (Exception e) {
            Log.e("Failed to check process status: ", e.msg);
            return false;
        }
    }
    
    /**
     * Get standard output data
     */
    string getStdout() {
        return _stdoutData;
    }
    
    /**
     * Get standard error data
     */
    string getStderr() {
        return _stderrData;
    }
    
    /**
     * Get exit code
     */
    int getExitCode() {
        return _exitCode;
    }
    
    /**
     * Get command line for logging
     */
    string getCommandLine() {
        return _executable ~ " " ~ _arguments.join(" ");
    }
}

/**
 * Helper function to create a process
 */
Process createProcess(string executable) {
    return new Process(executable);
}