# AI Chat System for Dnives IDE

An advanced AI-powered chat system integrated into the Dnives D language IDE, providing intelligent code assistance, analysis, and automated refactoring capabilities.

## Features

### 🤖 AI Chat Interface
- **Split-pane chat widget** with conversation threads
- **Real-time streaming responses** from AI models
- **Context-aware conversations** with automatic code context inclusion
- **Multiple AI backend support** (OpenAI, Anthropic, Ollama)
- **Thread management** for organizing different conversations
- **Export/import conversations** for sharing and archiving

### 🔍 Symbol Tracking & Context Management
- **Intelligent symbol tracking** across the entire codebase
- **LSP integration** for real-time code intelligence
- **Automatic context gathering** from relevant files and symbols
- **Smart context prioritization** based on relevance and recency
- **File reference management** with pinning capabilities
- **Import/dependency tracking** for comprehensive context

### 🛠️ Automated Code Actions
- **AI-generated code suggestions** with validation
- **Automated refactoring** with rollback capabilities  
- **Code change tracking** and session management
- **Conflict detection and resolution** for safe code modifications
- **LSP validation** of proposed changes before application
- **Rollback points** for reverting changes

### 🎯 Advanced Features
- **Multi-file context analysis** for complex refactoring
- **Code block extraction and application** from AI responses
- **Intelligent merge conflict resolution**
- **Session-based change tracking** with full audit trail
- **Real-time file monitoring** for context updates

## Architecture

### Core Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   ChatWidget    │    │   AIManager      │    │ ContextManager  │
│                 │◄──►│                  │◄──►│                 │
│ - UI Interface  │    │ - Coordination   │    │ - Context       │
│ - Thread Mgmt   │    │ - Session Mgmt   │    │ - File Analysis │
│ - Streaming     │    │ - Event Handling │    │ - Symbol Data   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  AIBackend      │    │CodeActionManager │    │ SymbolTracker   │
│                 │    │                  │    │                 │
│ - OpenAI        │    │ - Change Mgmt    │    │ - LSP Integ.    │
│ - Anthropic     │    │ - Rollback       │    │ - File Monitor  │
│ - Ollama        │    │ - Validation     │    │ - Ref. Tracking │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Integration with DCore

The AI chat system integrates seamlessly with the existing DCore architecture:

- **CCCore Integration**: Managed as a core component alongside other IDE managers
- **MainWindow Integration**: Dock panel integration with keyboard shortcuts
- **LSP Integration**: Real-time symbol and diagnostic information
- **File System Integration**: Automatic file watching and context updates
- **Event System**: Coordinated event handling across components

## Installation & Setup

### 1. Configuration

Copy `ai_config_example.json` to your config directory and rename to `ai_config.json`:

```bash
cp ai_config_example.json ~/.dlangide/ai_config.json
```

### 2. API Keys

Configure your preferred AI backend in `ai_config.json`:

**For OpenAI:**
```json
{
  "default_backend": "openai",
  "openai": {
    "api_key": "sk-your-openai-api-key-here",
    "model": "gpt-4-turbo-preview"
  }
}
```

**For Anthropic Claude:**
```json
{
  "default_backend": "anthropic", 
  "anthropic": {
    "api_key": "your-anthropic-api-key-here",
    "model": "claude-3-sonnet-20240229"
  }
}
```

**For Local Ollama:**
```json
{
  "default_backend": "ollama",
  "ollama": {
    "model": "codellama:13b",
    "base_url": "http://localhost:11434"
  }
}
```

### 3. Build Integration

The AI chat system is built as part of the main DCore build process. The components are automatically included when building the IDE.

## Usage

### Opening the AI Chat

- **Keyboard Shortcut**: Press `F4` to toggle the AI chat panel
- **Menu**: Navigate to `AI > Toggle AI Chat`
- **First Time**: The chat dock will appear on the right side of the IDE

### Basic Chat Operations

1. **New Conversation**: `Ctrl+Shift+N` or click the "+" tab
2. **Type your question** in the input box at the bottom
3. **Send**: Press `Ctrl+Enter` or click the "Send" button
4. **Streaming Response**: Watch the AI response appear in real-time

### Adding Context

#### Automatic Context
- The AI automatically includes context from:
  - Currently open files
  - Symbols referenced in your question
  - Related files through imports/dependencies

#### Manual Context
- **File Tree**: Use the "Files" tab to browse and select files
- **Symbol Search**: Use the "Symbols" tab to search and add specific symbols
- **Attach Button**: Click 📎 to attach current file, selection, or symbols

### Code Actions

#### Getting Code Suggestions
1. Open a file you want to analyze
2. Press `Ctrl+Shift+S` or use `AI > Get Code Suggestions`
3. The AI will analyze your code and provide specific suggestions

#### Applying Code Changes
1. When the AI provides code in response, look for the "Apply Code" button
2. Click to review and apply the suggested changes
3. Changes are tracked and can be rolled back

#### Starting a Refactoring Session
1. Press `Ctrl+Shift+R` or use `AI > Start Refactoring`
2. Describe what you want to refactor
3. The AI will suggest changes and create a tracked session
4. Apply changes incrementally with full rollback capability

### Session Management

#### Rollback Changes
- **Latest Changes**: Press `Ctrl+Shift+Z` to rollback the last AI session
- **Specific Session**: Use `AI > Manage Sessions` to select what to rollback
- **Rollback Points**: Automatic snapshots are created before major changes

#### Change Tracking
- All AI-suggested changes are tracked in sessions
- View applied changes in the session manager
- Full audit trail of what was changed and when

## Advanced Features

### Context Configuration

Customize how context is gathered in `ai_config.json`:

```json
{
  "context_manager": {
    "max_context_files": 10,
    "max_file_lines": 500, 
    "auto_include_imports": true,
    "auto_include_references": true,
    "prioritize_recent_files": true
  }
}
```

### Code Action Settings

Control how code changes are handled:

```json
{
  "code_actions": {
    "validate_changes": true,
    "create_auto_backups": true,
    "auto_apply_safe_changes": false,
    "conflict_resolution": "manual"
  }
}
```

### Custom Keyboard Shortcuts

Modify shortcuts in the configuration:

```json
{
  "keyboard_shortcuts": {
    "toggle_ai_chat": "F4",
    "ask_about_selection": "Ctrl+Shift+A",
    "code_suggestions": "Ctrl+Shift+S"
  }
}
```

## Example Workflows

### 1. Code Review and Improvement
```
1. Open the file you want to review
2. Press F4 to open AI chat
3. Type: "Please review this code and suggest improvements"
4. The AI analyzes the file and provides specific suggestions
5. Apply suggestions using the "Apply Code" buttons
6. Changes are automatically tracked for rollback if needed
```

### 2. Understanding Complex Code
```
1. Select the code section you don't understand
2. Press Ctrl+Shift+A to ask about selection
3. The AI explains the code with context from your project
4. Ask follow-up questions about related concepts
```

### 3. Refactoring with AI Assistance
```
1. Press Ctrl+Shift+R to start a refactoring session
2. Describe what you want to change: "Extract this logic into a separate class"
3. The AI suggests a refactoring plan with specific steps
4. Apply changes step by step with validation
5. Use Ctrl+Shift+Z to rollback if needed
```

### 4. Multi-file Analysis
```
1. Use the Files tab to select related files
2. Ask: "How do these components interact with each other?"
3. The AI provides architectural insights across multiple files
4. Get suggestions for improving the overall design
```

## Troubleshooting

### Common Issues

**AI Chat Won't Open**
- Check that LSP manager is initialized
- Verify AI backend configuration is valid
- Check logs for initialization errors

**No Context in Responses** 
- Ensure files are saved (unsaved changes aren't tracked)
- Check that symbol tracker is running
- Verify LSP server is connected for your language

**Code Changes Not Applying**
- Check file permissions (must be writable)
- Verify no external changes conflict
- Look for validation errors in logs

**API Key Issues**
- Ensure API key is correctly formatted in config
- Check API key has sufficient credits/permissions
- Verify network connectivity to AI service

### Debug Information

Enable debug logging in `ai_config.json`:

```json
{
  "logging": {
    "log_ai_requests": true,
    "log_code_changes": true, 
    "log_level": "debug"
  }
}
```

Logs are written to `~/.dlangide/logs/ai_system.log`

## Development

### Building from Source

The AI chat system is built as part of the main DCore build:

```bash
cd dnives
dub build --config=release
```

### Architecture Notes

- **Modular Design**: Each component can be used independently
- **Event-Driven**: Loose coupling through event system
- **Extensible**: New AI backends can be added easily
- **Safe**: All code changes go through validation and can be rolled back

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request with clear description

## Future Enhancements

- **Voice Commands**: Voice-to-text for hands-free coding assistance
- **AI Pair Programming**: Real-time coding collaboration with AI
- **Automatic Testing**: AI-generated unit tests for code changes
- **Performance Analysis**: AI-driven performance optimization suggestions
- **Documentation Generation**: Automatic code documentation and comments

## License

This AI chat system is part of the Dnives IDE project and follows the same license terms.

## Support

For issues and questions:
- Check the troubleshooting section above
- Review the configuration examples
- File issues on the project repository
- Join the community discussions for tips and best practices