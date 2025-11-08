module ai_usage_example;

import std.stdio;
import std.string;
import std.path;
import std.file;
import std.json;

import dlangui;
import dlangui.core.logger;

import dcore.core;
import dcore.components.cccore;
import dcore.ui.mainwindow;
import dcore.ai.integration;
import dcore.ai.ai_manager;
import dcore.ai.context_manager;
import dcore.ai.code_action_manager;
import dcore.config;

/**
 * Example of how to integrate and use the AI chat system in Dnives IDE
 */
void main() {
    // Initialize DlangUI
    Platform.instance.initialize();

    // Set up logging
    Log.setLogLevel(LogLevel.Info);

    // Example configuration directory
    string configDir = buildPath(expandTilde("~"), ".dnives_ai_example");
    if (!exists(configDir)) {
        mkdirRecurse(configDir);
    }

    // Create example AI configuration
    createExampleAIConfig(configDir);

    // Initialize DCore
    auto dcore = new DCore(configDir);
    if (!dcore.initialize()) {
        Log.e("Failed to initialize DCore");
        return;
    }

    // Create main window
    auto mainWindow = new MainWindow("Dnives AI Example");

    // Create CCCore and link with DCore
    auto configManager = new ConfigManager(configDir);
    auto ccCore = new CCCore(configManager, dcore);
    ccCore.initialize();

    // Set cross-references
    mainWindow.setCore(ccCore);
    ccCore.setMainWindow(mainWindow);
    dcore.setMainWindow(mainWindow);

    // Initialize AI system if enabled
    if (dcore.isAIEnabled()) {
        Log.i("Initializing AI system...");
        // AI system is automatically initialized in DCore
    }

    // Run the application
    Log.i("Starting AI-enabled Dnives IDE example...");
    Platform.instance.enterMessageLoop();

    // Cleanup
    if (dcore.getAIIntegration()) {
        dcore.getAIIntegration().cleanup();
    }
    dcore.cleanup();

    Platform.instance.closeApp();
}

/**
 * Create an example AI configuration file
 */
void createExampleAIConfig(string configDir) {
    string configPath = buildPath(configDir, "ai_config.json");

    if (exists(configPath)) {
        return; // Don't overwrite existing config
    }

    JSONValue config = JSONValue.emptyObject;

    // Basic settings
    config["default_backend"] = "ollama"; // Use local Ollama for example
    config["enable_streaming"] = true;
    config["ai_enabled"] = true;
    config["max_context_tokens"] = 4000;
    config["temperature"] = 0.7;
    config["system_prompt"] = "You are an expert D programming language assistant. Help with code analysis, debugging, and improvement suggestions.";

    // Ollama configuration (local, no API key needed)
    config["ollama"] = JSONValue.emptyObject;
    config["ollama"]["model"] = "codellama:7b";
    config["ollama"]["base_url"] = "http://localhost:11434";
    config["ollama"]["timeout_seconds"] = 60;

    // OpenAI configuration (requires API key)
    config["openai"] = JSONValue.emptyObject;
    config["openai"]["api_key"] = "your_openai_api_key_here";
    config["openai"]["model"] = "gpt-4-turbo-preview";

    // Context management settings
    config["context_manager"] = JSONValue.emptyObject;
    config["context_manager"]["max_context_files"] = 5;
    config["context_manager"]["max_file_lines"] = 200;
    config["context_manager"]["auto_include_imports"] = true;

    // UI preferences
    config["ui_preferences"] = JSONValue.emptyObject;
    config["ui_preferences"]["chat_dock_width"] = 400;
    config["ui_preferences"]["auto_scroll_chat"] = true;
    config["ui_preferences"]["show_line_numbers"] = true;

    // Code action settings
    config["code_actions"] = JSONValue.emptyObject;
    config["code_actions"]["validate_changes"] = true;
    config["code_actions"]["create_auto_backups"] = true;
    config["code_actions"]["conflict_resolution"] = "manual";

    // Write configuration
    try {
        std.file.write(configPath, config.toPrettyString());
        Log.i("Created example AI configuration: ", configPath);
        Log.i("Edit this file to configure your AI backend settings.");
    } catch (Exception e) {
        Log.e("Failed to create AI config: ", e.msg);
    }
}

/**
 * Example of programmatic AI usage
 */
void demonstrateAIUsage(DCore dcore) {
    auto aiIntegration = dcore.getAIIntegration();
    if (!aiIntegration || !aiIntegration.isInitialized()) {
        Log.w("AI system not available");
        return;
    }

    auto aiManager = aiIntegration.getAIManager();
    auto contextManager = aiIntegration.getContextManager();
    auto codeActionManager = aiIntegration.getCodeActionManager();

    // Example 1: Get code suggestions for current workspace
    Log.i("=== Example 1: Code Analysis ===");
    try {
        // This would normally be the current workspace files
        string[] exampleFiles = ["src/example.d"];
        aiManager.generateCodeSuggestions(exampleFiles, "Please analyze this D code and suggest improvements.");
    } catch (Exception e) {
        Log.e("Code analysis failed: ", e.msg);
    }

    // Example 2: Create a conversation context
    Log.i("=== Example 2: Context Management ===");
    try {
        auto workspace = dcore.getCurrentWorkspace();
        if (workspace) {
            auto conversation = contextManager.createConversation(workspace.path, ["src/main.d"]);
            string context = contextManager.getConversationContext(conversation.conversationId);
            Log.i("Generated context length: ", context.length);
        }
    } catch (Exception e) {
        Log.e("Context management failed: ", e.msg);
    }

    // Example 3: Create a rollback point
    Log.i("=== Example 3: Code Action Management ===");
    try {
        string rollbackId = codeActionManager.createRollbackPoint("Before AI changes", ["src/main.d"]);
        Log.i("Created rollback point: ", rollbackId);
    } catch (Exception e) {
        Log.e("Rollback point creation failed: ", e.msg);
    }
}

/**
 * Example of creating a simple D file for testing AI features
 */
void createExampleDFile(string workspaceDir) {
    string srcDir = buildPath(workspaceDir, "src");
    if (!exists(srcDir)) {
        mkdirRecurse(srcDir);
    }

    string exampleFile = buildPath(srcDir, "example.d");
    if (exists(exampleFile)) {
        return; // Don't overwrite
    }

    string exampleCode = `module example;

import std.stdio;
import std.algorithm;
import std.array;

/**
 * A simple example class for AI analysis
 */
class Calculator {
    private double[] history;

    this() {
        history = [];
    }

    // This function could be improved - AI might suggest better error handling
    double add(double a, double b) {
        double result = a + b;
        history ~= result;
        return result;
    }

    // This function has a potential bug - division by zero
    double divide(double a, double b) {
        double result = a / b;
        history ~= result;
        return result;
    }

    // This could be optimized
    double[] getHistory() {
        double[] copy;
        foreach(val; history) {
            copy ~= val;
        }
        return copy;
    }

    // Missing documentation
    void clearHistory() {
        history.length = 0;
    }
}

void main() {
    auto calc = new Calculator();

    // Some example usage
    writeln("5 + 3 = ", calc.add(5, 3));
    writeln("10 / 2 = ", calc.divide(10, 2));

    // This will cause division by zero!
    // writeln("10 / 0 = ", calc.divide(10, 0));

    writeln("History: ", calc.getHistory());
    calc.clearHistory();
    writeln("After clear: ", calc.getHistory());
}
`;

    try {
        std.file.write(exampleFile, exampleCode);
        Log.i("Created example D file: ", exampleFile);
        Log.i("This file contains code that the AI can analyze and improve.");
    } catch (Exception e) {
        Log.e("Failed to create example file: ", e.msg);
    }
}

/**
 * Example keyboard shortcuts demonstration
 */
void demonstrateKeyboardShortcuts() {
    Log.i("=== AI Chat Keyboard Shortcuts ===");
    Log.i("F4                  - Toggle AI Chat");
    Log.i("Ctrl+Shift+N        - New Conversation");
    Log.i("Ctrl+Shift+S        - Get Code Suggestions");
    Log.i("Ctrl+Shift+A        - Ask About Selection");
    Log.i("Ctrl+Shift+R        - Start Refactoring");
    Log.i("Ctrl+Shift+Z        - Rollback Changes");
    Log.i("Ctrl+Enter          - Send Chat Message");
}

/**
 * Example AI prompts for different use cases
 */
void demonstrateAIPrompts() {
    Log.i("=== Example AI Prompts ===");

    writeln("Code Review:");
    writeln("  'Please review this code and suggest improvements for readability, performance, and best practices.'");
    writeln();

    writeln("Bug Finding:");
    writeln("  'Can you identify any potential bugs or issues in this code?'");
    writeln();

    writeln("Refactoring:");
    writeln("  'How can I refactor this code to make it more maintainable and follow D language idioms?'");
    writeln();

    writeln("Documentation:");
    writeln("  'Please help me add proper documentation and comments to this code.'");
    writeln();

    writeln("Testing:");
    writeln("  'Generate unit tests for this class/function.'");
    writeln();

    writeln("Optimization:");
    writeln("  'How can I optimize this code for better performance?'");
    writeln();

    writeln("Architecture:");
    writeln("  'Review the architecture of these classes and suggest improvements.'");
}

/**
 * Example of setting up AI configuration for different backends
 */
void demonstrateBackendSetup() {
    Log.i("=== AI Backend Setup Examples ===");

    writeln("For OpenAI GPT-4:");
    writeln(`{
  "default_backend": "openai",
  "openai": {
    "api_key": "sk-your-key-here",
    "model": "gpt-4-turbo-preview"
  }
}`);
    writeln();

    writeln("For Anthropic Claude:");
    writeln(`{
  "default_backend": "anthropic",
  "anthropic": {
    "api_key": "your-anthropic-key-here",
    "model": "claude-3-sonnet-20240229"
  }
}`);
    writeln();

    writeln("For Local Ollama:");
    writeln(`{
  "default_backend": "ollama",
  "ollama": {
    "model": "codellama:7b",
    "base_url": "http://localhost:11434"
  }
}`);
    writeln();

    writeln("Make sure to:");
    writeln("1. Install and run Ollama for local models");
    writeln("2. Pull the desired model: 'ollama pull codellama:7b'");
    writeln("3. Set up API keys for cloud providers");
}
