module dcore.ai.ai_backend;

import std.stdio;
import std.string;
import std.json;
import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.exception;
import std.net.curl;
import std.uri;
import std.uuid;
import core.time;

import dlangui.core.logger;

/**
 * AIMessage - Represents a single message in a conversation
 */
struct AIMessage {
    enum Role {
        System,
        User,
        Assistant,
        Tool
    }

    Role role;
    string content;
    string toolCallId;
    JSONValue metadata;
    DateTime timestamp;

    this(Role role, string content) {
        this.role = role;
        this.content = content;
        this.timestamp = cast(DateTime)Clock.currTime();
        this.metadata = JSONValue.emptyObject;
    }

    JSONValue toJSON() const {
        JSONValue json = JSONValue.emptyObject;
        json["role"] = roleToString(role);
        json["content"] = content;
        json["timestamp"] = timestamp.toISOExtString();
        if (!toolCallId.empty)
            json["tool_call_id"] = toolCallId;
        if (metadata.type != JSONType.null_)
            json["metadata"] = metadata;
        return json;
    }

    private string roleToString(Role role) const {
        switch (role) {
            case Role.System: return "system";
            case Role.User: return "user";
            case Role.Assistant: return "assistant";
            case Role.Tool: return "tool";
            default: return "user";
        }
    }
}

/**
 * AIToolCall - Represents a tool/function call from the AI
 */
struct AIToolCall {
    string id;
    string name;
    JSONValue arguments;

    this(string name, JSONValue arguments) {
        this.id = randomUUID().toString();
        this.name = name;
        this.arguments = arguments;
    }
}

/**
 * AIResponse - Response from AI model
 */
struct AIResponse {
    string content;
    AIToolCall[] toolCalls;
    bool isComplete;
    string finishReason;
    JSONValue usage;
    DateTime timestamp;

    this(string content, bool isComplete = true) {
        this.content = content;
        this.isComplete = isComplete;
        this.timestamp = cast(DateTime)Clock.currTime();
        this.usage = JSONValue.emptyObject;
    }
}

/**
 * AIStreamChunk - Streaming response chunk
 */
struct AIStreamChunk {
    string content;
    bool isComplete;
    AIToolCall[] toolCalls;
    string finishReason;

    this(string content, bool isComplete = false) {
        this.content = content;
        this.isComplete = isComplete;
    }
}

/**
 * AICapabilities - What the AI backend supports
 */
struct AICapabilities {
    bool supportsStreaming;
    bool supportsToolCalls;
    bool supportsVision;
    bool supportsCodeExecution;
    int maxTokens;
    string[] supportedLanguages;

    // Default initialization - structs in D automatically have default constructors
}

/**
 * AIBackend - Abstract interface for AI providers
 */
abstract class AIBackend {
    protected string _name;
    protected string _apiKey;
    protected string _baseUrl;
    protected AICapabilities _capabilities;
    protected Duration _timeout = 30.seconds;

    this(string name) {
        _name = name;
        _capabilities = AICapabilities();
    }

    @property string name() { return _name; }
    @property AICapabilities capabilities() { return _capabilities; }

    /**
     * Initialize the backend with configuration
     */
    abstract void initialize(JSONValue config);

    /**
     * Send a chat completion request
     */
    abstract AIResponse chat(AIMessage[] messages, JSONValue options = JSONValue.emptyObject);

    /**
     * Send a streaming chat completion request
     */
    abstract void chatStream(AIMessage[] messages,
                           void delegate(AIStreamChunk) onChunk,
                           JSONValue options = JSONValue.emptyObject);

    /**
     * Test if the backend is available
     */
    abstract bool isAvailable();

    /**
     * Get model information
     */
    abstract JSONValue getModelInfo();

    /**
     * Cleanup resources
     */
    void cleanup() {}
}

/**
 * OpenAIBackend - OpenAI API implementation
 */
class OpenAIBackend : AIBackend {
    private string _model = "gpt-4";

    this() {
        super("OpenAI");
        _baseUrl = "https://api.openai.com/v1";
        _capabilities.supportsStreaming = true;
        _capabilities.supportsToolCalls = true;
        _capabilities.supportsVision = true;
        _capabilities.maxTokens = 128000;
        _capabilities.supportedLanguages = ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh"];
    }

    override void initialize(JSONValue config) {
        if ("api_key" in config && config["api_key"].type == JSONType.string)
            _apiKey = config["api_key"].str;

        if ("model" in config && config["model"].type == JSONType.string)
            _model = config["model"].str;

        if ("base_url" in config && config["base_url"].type == JSONType.string)
            _baseUrl = config["base_url"].str;
    }

    override AIResponse chat(AIMessage[] messages, JSONValue options = JSONValue.emptyObject) {
        if (_apiKey.empty)
            throw new Exception("OpenAI API key not configured");

        JSONValue request = buildChatRequest(messages, options);

        try {
            auto http = HTTP();
            http.addRequestHeader("Authorization", "Bearer " ~ _apiKey);
            http.addRequestHeader("Content-Type", "application/json");
            http.connectTimeout = _timeout;

            string url = _baseUrl ~ "/chat/completions";
            string responseData = post(url, request.toString(), http).to!string;

            JSONValue response = parseJSON(responseData);
            return parseChatResponse(response);

        } catch (Exception e) {
            Log.e("OpenAI API error: ", e.msg);
            throw new Exception("OpenAI API request failed: " ~ e.msg);
        }
    }

    override void chatStream(AIMessage[] messages,
                           void delegate(AIStreamChunk) onChunk,
                           JSONValue options = JSONValue.emptyObject) {
        if (_apiKey.empty)
            throw new Exception("OpenAI API key not configured");

        JSONValue request = buildChatRequest(messages, options);
        request["stream"] = true;

        try {
            auto http = HTTP();
            http.addRequestHeader("Authorization", "Bearer " ~ _apiKey);
            http.addRequestHeader("Content-Type", "application/json");
            http.addRequestHeader("Accept", "text/event-stream");
            http.connectTimeout = _timeout;

            string url = _baseUrl ~ "/chat/completions";

            // Set up streaming callback
            http.onReceive = (ubyte[] data) {
                string chunk = cast(string)data;
                processStreamChunk(chunk, onChunk);
                return data.length;
            };

            http.method = HTTP.Method.post;
            http.url = url;
            http.postData = request.toString();
            http.perform();

        } catch (Exception e) {
            Log.e("OpenAI streaming error: ", e.msg);
            throw new Exception("OpenAI streaming request failed: " ~ e.msg);
        }
    }

    override bool isAvailable() {
        if (_apiKey.empty)
            return false;

        try {
            // Test with a simple request
            JSONValue testRequest = JSONValue.emptyObject;
            testRequest["model"] = _model;
            testRequest["messages"] = [JSONValue(["role": "user", "content": "test"])];
            testRequest["max_tokens"] = 1;

            auto http = HTTP();
            http.addRequestHeader("Authorization", "Bearer " ~ _apiKey);
            http.addRequestHeader("Content-Type", "application/json");
            http.connectTimeout = 5.seconds;

            string url = _baseUrl ~ "/chat/completions";
            post(url, testRequest.toString(), http);

            return true;
        } catch (Exception e) {
            return false;
        }
    }

    override JSONValue getModelInfo() {
        JSONValue info = JSONValue.emptyObject;
        info["provider"] = "OpenAI";
        info["model"] = _model;
        info["capabilities"] = capabilitiesToJSON(_capabilities);
        return info;
    }

    private JSONValue buildChatRequest(AIMessage[] messages, JSONValue options) {
        JSONValue request = JSONValue.emptyObject;
        request["model"] = _model;
        request["messages"] = JSONValue.emptyArray;

        foreach (msg; messages) {
            request["messages"].array ~= msg.toJSON();
        }

        // Apply options
        if ("temperature" in options)
            request["temperature"] = options["temperature"];
        if ("max_tokens" in options)
            request["max_tokens"] = options["max_tokens"];
        if ("top_p" in options)
            request["top_p"] = options["top_p"];

        return request;
    }

    private AIResponse parseChatResponse(JSONValue response) {
        if ("error" in response)
            throw new Exception("OpenAI API error: " ~ response["error"]["message"].str);

        auto choice = response["choices"].array[0];
        auto message = choice["message"];

        AIResponse result = AIResponse(message["content"].str, true);
        result.finishReason = choice["finish_reason"].str;

        if ("usage" in response)
            result.usage = response["usage"];

        return result;
    }

    private void processStreamChunk(string data, void delegate(AIStreamChunk) onChunk) {
        auto lines = data.split("\n");

        foreach (line; lines) {
            line = line.strip();
            if (line.empty || !line.startsWith("data: "))
                continue;

            string jsonStr = line[6..$];
            if (jsonStr == "[DONE]") {
                onChunk(AIStreamChunk("", true));
                return;
            }

            try {
                JSONValue chunk = parseJSON(jsonStr);
                if ("choices" in chunk && chunk["choices"].array.length > 0) {
                    auto choice = chunk["choices"].array[0];
                    if ("delta" in choice && "content" in choice["delta"]) {
                        string content = choice["delta"]["content"].str;
                        bool isComplete = "finish_reason" in choice &&
                                        choice["finish_reason"].type != JSONType.null_;
                        onChunk(AIStreamChunk(content, isComplete));
                    }
                }
            } catch (Exception e) {
                Log.w("Failed to parse stream chunk: ", e.msg);
            }
        }
    }
}

/**
 * AnthropicBackend - Anthropic Claude API implementation
 */
class AnthropicBackend : AIBackend {
    private string _model = "claude-3-sonnet-20240229";

    this() {
        super("Anthropic");
        _baseUrl = "https://api.anthropic.com/v1";
        _capabilities.supportsStreaming = true;
        _capabilities.supportsToolCalls = true;
        _capabilities.supportsVision = true;
        _capabilities.maxTokens = 200000;
        _capabilities.supportedLanguages = ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh"];
    }

    override void initialize(JSONValue config) {
        if ("api_key" in config && config["api_key"].type == JSONType.string)
            _apiKey = config["api_key"].str;

        if ("model" in config && config["model"].type == JSONType.string)
            _model = config["model"].str;
    }

    override AIResponse chat(AIMessage[] messages, JSONValue options = JSONValue.emptyObject) {
        // Simplified implementation - would need full Anthropic API support
        throw new Exception("Anthropic backend not yet implemented");
    }

    override void chatStream(AIMessage[] messages,
                           void delegate(AIStreamChunk) onChunk,
                           JSONValue options = JSONValue.emptyObject) {
        throw new Exception("Anthropic streaming not yet implemented");
    }

    override bool isAvailable() {
        return !_apiKey.empty;
    }

    override JSONValue getModelInfo() {
        JSONValue info = JSONValue.emptyObject;
        info["provider"] = "Anthropic";
        info["model"] = _model;
        info["capabilities"] = capabilitiesToJSON(_capabilities);
        return info;
    }
}

/**
 * OllamaBackend - Local Ollama implementation
 */
class OllamaBackend : AIBackend {
    private string _model = "llama2";

    this() {
        super("Ollama");
        _baseUrl = "http://localhost:11434";
        _capabilities.supportsStreaming = true;
        _capabilities.supportsToolCalls = false;
        _capabilities.supportsVision = false;
        _capabilities.maxTokens = 4096;
        _capabilities.supportedLanguages = ["en"];
    }

    override void initialize(JSONValue config) {
        if ("model" in config && config["model"].type == JSONType.string)
            _model = config["model"].str;

        if ("base_url" in config && config["base_url"].type == JSONType.string)
            _baseUrl = config["base_url"].str;
    }

    override AIResponse chat(AIMessage[] messages, JSONValue options = JSONValue.emptyObject) {
        JSONValue request = JSONValue.emptyObject;
        request["model"] = _model;
        request["messages"] = JSONValue.emptyArray;

        foreach (msg; messages) {
            request["messages"].array ~= msg.toJSON();
        }

        if ("temperature" in options)
            request["options"]["temperature"] = options["temperature"];

        try {
            auto http = HTTP();
            http.addRequestHeader("Content-Type", "application/json");
            http.connectTimeout = _timeout;

            string url = _baseUrl ~ "/api/chat";
            string responseData = post(url, request.toString(), http).to!string;

            JSONValue response = parseJSON(responseData);
            return AIResponse(response["message"]["content"].str, true);

        } catch (Exception e) {
            Log.e("Ollama API error: ", e.msg);
            throw new Exception("Ollama API request failed: " ~ e.msg);
        }
    }

    override void chatStream(AIMessage[] messages,
                           void delegate(AIStreamChunk) onChunk,
                           JSONValue options = JSONValue.emptyObject) {
        // Similar to chat but with streaming
        throw new Exception("Ollama streaming not yet implemented");
    }

    override bool isAvailable() {
        try {
            auto http = HTTP();
            http.connectTimeout = 2.seconds;
            string response = get(_baseUrl ~ "/api/version", http).to!string;
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    override JSONValue getModelInfo() {
        JSONValue info = JSONValue.emptyObject;
        info["provider"] = "Ollama";
        info["model"] = _model;
        info["capabilities"] = capabilitiesToJSON(_capabilities);
        return info;
    }
}

/**
 * AIBackendManager - Manages multiple AI backends
 */
class AIBackendManager {
    private AIBackend[string] _backends;
    private string _defaultBackend;
    private JSONValue _config;

    this() {
        // Register available backends
        _backends["openai"] = new OpenAIBackend();
        _backends["anthropic"] = new AnthropicBackend();
        _backends["ollama"] = new OllamaBackend();

        _defaultBackend = "openai";
    }

    /**
     * Initialize with configuration
     */
    void initialize(JSONValue config) {
        _config = config;

        if ("default_backend" in config)
            _defaultBackend = config["default_backend"].str;

        // Initialize each backend
        foreach (name, backend; _backends) {
            if (name in config && config[name].type == JSONType.object) {
                try {
                    backend.initialize(config[name]);
                    Log.i("Initialized AI backend: ", name);
                } catch (Exception e) {
                    Log.w("Failed to initialize AI backend ", name, ": ", e.msg);
                }
            }
        }
    }

    /**
     * Get the default backend
     */
    AIBackend getDefaultBackend() {
        return getBackend(_defaultBackend);
    }

    /**
     * Get a specific backend
     */
    AIBackend getBackend(string name) {
        if (name in _backends)
            return _backends[name];
        return null;
    }

    /**
     * Get available backends
     */
    string[] getAvailableBackends() {
        string[] available;
        foreach (name, backend; _backends) {
            if (backend.isAvailable()) {
                available ~= name;
            }
        }
        return available;
    }

    /**
     * Send chat to default backend
     */
    AIResponse chat(AIMessage[] messages, JSONValue options = JSONValue.emptyObject) {
        auto backend = getDefaultBackend();
        if (!backend)
            throw new Exception("No default AI backend available");
        return backend.chat(messages, options);
    }

    /**
     * Send streaming chat to default backend
     */
    void chatStream(AIMessage[] messages,
                   void delegate(AIStreamChunk) onChunk,
                   JSONValue options = JSONValue.emptyObject) {
        auto backend = getDefaultBackend();
        if (!backend)
            throw new Exception("No default AI backend available");
        backend.chatStream(messages, onChunk, options);
    }

    /**
     * Cleanup all backends
     */
    void cleanup() {
        foreach (backend; _backends.values) {
            backend.cleanup();
        }
        _backends.clear();
    }
}

/**
 * Extension methods for capabilities
 */
/**
 * Convert AICapabilities to JSON
 */
JSONValue capabilitiesToJSON(AICapabilities capabilities) {
    JSONValue json = JSONValue.emptyObject;
    json["supports_streaming"] = capabilities.supportsStreaming;
    json["supports_tool_calls"] = capabilities.supportsToolCalls;
    json["supports_vision"] = capabilities.supportsVision;
    json["supports_code_execution"] = capabilities.supportsCodeExecution;
    json["max_tokens"] = capabilities.maxTokens;
    json["supported_languages"] = JSONValue(capabilities.supportedLanguages);
    return json;
}
