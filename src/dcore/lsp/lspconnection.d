module dcore.lsp.lspconnection;

import dlangui.core.logger;
import std.process;
import std.json;
import std.stdio;
import std.string;
import std.format;
import std.conv;
import std.concurrency;
import std.datetime;
import core.thread;
import core.sync.mutex;

import dcore.lsp.lsptypes;

/**
 * LSPConnection - Handles communication with a Language Server Protocol server
 *
 * Responsible for:
 * - Starting/stopping the LSP server process
 * - Sending/receiving JSON-RPC messages
 * - Managing request IDs and responses
 * - Handling notifications and events
 */
class LSPConnection {
    private string _language;
    private ProcessPipes _pipes;
    import dcore.utils.process : Process;
    private std.process.Pid _processId;
    private bool _connected = false;
    private int _nextId = 1;
    private JSONValue _serverCapabilities;
    
    // Thread for reading responses
    private Thread _readThread;
    private bool _stopThread = false;
    
    // Synchronization for request responses
    private Mutex _responseMutex;
    private JSONValue[int] _pendingResponses;
    private bool[int] _responseReceived;
    
    /**
     * Constructor
     */
    this(string language) {
        _language = language;
        _responseMutex = new Mutex();
        Log.i("LSPConnection: Created for language: ", language);
    }
    
    /**
     * Start the language server process
     */
    bool startServer(string command, string[] args) {
        try {
            // Combine command and args
            string[] cmdArgs = [command] ~ args;
            
            // Start the process
            _pipes = pipeProcess(cmdArgs, Redirect.stdin | Redirect.stdout | Redirect.stderr);
            _processId = _pipes.pid;
            
            // Check if process started successfully
            if (_processId.processID == 0) {
                Log.e("LSPConnection: Failed to start server process");
                return false;
            }
            
            // Start read thread
            _stopThread = false;
            _readThread = new Thread(&readThreadFunc);
            _readThread.isDaemon = true;
            _readThread.start();
            
            _connected = true;
            
            Log.i("LSPConnection: Server process started. PID: ", _processId.processID);
            return true;
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error starting server: ", e.msg);
            return false;
        }
    }
    
    /**
     * Read thread function - reads responses from the server
     */
    private void readThreadFunc() {
        File stdout = _pipes.stdout;
        stdout.setvbuf(4096, _IOLBF);
        
        try {
            while (!_stopThread) {
                // Check for available data
                if (stdout.eof()) {
                    Log.e("LSPConnection: Server stdout closed unexpectedly");
                    _connected = false;
                    break;
                }
                
                // Parse the Content-Length header
                string line = stdout.readln().chomp();
                if (line.empty) continue;
                
                int contentLength = 0;
                if (line.startsWith("Content-Length: ")) {
                    contentLength = to!int(line["Content-Length: ".length .. $]);
                } else {
                    Log.w("LSPConnection: Invalid header: ", line);
                    continue;
                }
                
                // Skip empty line
                stdout.readln();
                
                // Read message content
                char[] buffer = new char[contentLength];
                auto bytesRead = stdout.rawRead(buffer);
                
                if (bytesRead.length < contentLength) {
                    Log.w("LSPConnection: Incomplete message received");
                    continue;
                }
                
                string content = buffer.idup;
                
                // Parse JSON
                JSONValue message = parseJSON(content);
                handleMessage(message);
            }
        }
        catch (Exception e) {
            Log.e("LSPConnection: Read thread error: ", e.msg);
            _connected = false;
        }
    }
    
    /**
     * Handle received message
     */
    private void handleMessage(JSONValue message) {
        try {
            if (message.type != JSONType.object) {
                Log.w("LSPConnection: Received non-object message");
                return;
            }
            
            // Check if it's a response
            if ("id" in message && "result" in message) {
                // It's a response to a request
                int id = cast(int)message["id"].integer;
                
                synchronized(_responseMutex) {
                    _pendingResponses[id] = message["result"];
                    _responseReceived[id] = true;
                }
                
                Log.i("LSPConnection: Received response for request ID: ", id);
            }
            // Check if it's an error response
            else if ("id" in message && "error" in message) {
                int id = cast(int)message["id"].integer;
                
                Log.e("LSPConnection: Received error response for request ID: ", id, 
                    " Error: ", message["error"].toString());
                
                synchronized(_responseMutex) {
                    _pendingResponses[id] = message["error"];
                    _responseReceived[id] = true;
                }
            }
            // Check if it's a notification
            else if ("method" in message && "params" in message && "id" !in message) {
                string method = message["method"].str;
                JSONValue params = message["params"];
                
                handleNotification(method, params);
            }
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error handling message: ", e.msg);
        }
    }
    
    /**
     * Handle notification from server
     */
    private void handleNotification(string method, JSONValue params) {
        Log.i("LSPConnection: Received notification: ", method);
        
        // TODO: Handle specific notifications based on method
        // Examples:
        //  - textDocument/publishDiagnostics
        //  - window/showMessage
        //  - window/logMessage
    }
    
    /**
     * Send a request to the language server and wait for response
     */
    JSONValue sendRequest(string method, JSONValue params) {
        if (!_connected) {
            Log.e("LSPConnection: Cannot send request, not connected");
            return JSONValue(null);
        }
        
        int id = _nextId++;
        
        try {
            // Create request object
            JSONValue request = parseJSON("{}");
            request["jsonrpc"] = "2.0";
            request["id"] = id;
            request["method"] = method;
            request["params"] = params;
            
            string requestStr = request.toString();
            
            // Send with proper headers
            string message = format("Content-Length: %d\r\n\r\n%s", requestStr.length, requestStr);
            _pipes.stdin.write(message);
            _pipes.stdin.flush();
            
            Log.i("LSPConnection: Sent request ID: ", id, " Method: ", method);
            
            // Wait for response
            return waitForResponse(id);
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error sending request: ", e.msg);
            return JSONValue(null);
        }
    }
    
    /**
     * Send a notification to the language server (no response expected)
     */
    void sendNotification(string method, JSONValue params) {
        if (!_connected) {
            Log.e("LSPConnection: Cannot send notification, not connected");
            return;
        }
        
        try {
            // Create notification object
            JSONValue notification = parseJSON("{}");
            notification["jsonrpc"] = "2.0";
            notification["method"] = method;
            notification["params"] = params;
            
            string notificationStr = notification.toString();
            
            // Send with proper headers
            string message = format("Content-Length: %d\r\n\r\n%s", notificationStr.length, notificationStr);
            _pipes.stdin.write(message);
            _pipes.stdin.flush();
            
            Log.i("LSPConnection: Sent notification. Method: ", method);
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error sending notification: ", e.msg);
        }
    }
    
    /**
     * Wait for response to a request
     */
    private JSONValue waitForResponse(int id) {
        // Wait for response with timeout
        SysTime startTime = Clock.currTime();
        Duration timeout = dur!"seconds"(5);
        
        while (true) {
            // Check if response received
            synchronized(_responseMutex) {
                if (id in _responseReceived && _responseReceived[id]) {
                    JSONValue response = _pendingResponses[id];
                    
                    // Clean up
                    _pendingResponses.remove(id);
                    _responseReceived.remove(id);
                    
                    return response;
                }
            }
            
            // Check timeout
            Duration elapsed = Clock.currTime() - startTime;
            if (elapsed > timeout) {
                Log.e("LSPConnection: Timeout waiting for response ID: ", id);
                break;
            }
            
            // Sleep a bit to avoid busy waiting
            Thread.sleep(dur!"msecs"(10));
        }
        
        return JSONValue(null);
    }
    
    /**
     * Shutdown the language server
     */
    void shutdown() {
        if (!_connected)
            return;
            
        try {
            // Send shutdown request
            JSONValue params = parseJSON("{}");
            sendRequest("shutdown", params);
            
            // Send exit notification
            sendNotification("exit", params);
            
            // Stop read thread
            _stopThread = true;
            if (_readThread && _readThread.isRunning()) {
                _readThread.join(false);
            }
            
            // Kill process if still running
            if (_processId.processID != 0) {
                _processId.kill();
            }
            
            // Close pipes
            _pipes.stdin.close();
            _pipes.stdout.close();
            _pipes.stderr.close();
            
            _connected = false;
            
            Log.i("LSPConnection: Server shutdown complete for ", _language);
        }
        catch (Exception e) {
            Log.e("LSPConnection: Error shutting down server: ", e.msg);
        }
    }
    
    /**
     * Check if connected to server
     */
    bool isConnected() {
        return _connected;
    }
    
    /**
     * Get language
     */
    string getLanguage() {
        return _language;
    }
    
    /**
     * Set server capabilities
     */
    void setServerCapabilities(JSONValue capabilities) {
        _serverCapabilities = capabilities;
    }
    
    /**
     * Get server capabilities
     */
    JSONValue getServerCapabilities() {
        return _serverCapabilities;
    }
    
    /**
     * Destructor - ensure server is shut down
     */
    ~this() {
        shutdown();
    }
}