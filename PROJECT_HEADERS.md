# Dnives IDE Project Structure

This document outlines the file structure and component organization for the Dnives IDE project. Each file is listed with its path and a brief description of its purpose and responsibilities.

## Core System

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/core/cccore.d` | Central coordinator for all IDE components. Manages initialization, communication between components, and lifecycle. |
| `dnives/src/dlangide/core/config.d` | Configuration management with support for user preferences, workspace settings, and system configurations. |
| `dnives/src/dlangide/core/event_manager.d` | Event system for inter-component communication with support for event registration, dispatch, and handling. |
| `dnives/src/dlangide/core/thread_controller.d` | Thread management for background tasks with priority handling and cancellation support. |
| `dnives/src/dlangide/core/manager_interfaces.d` | Base interfaces for all manager components to ensure consistent API. |
| `dnives/src/dlangide/core/plugin_system.d` | Plugin loading and management system with lifecycle hooks and dependency resolution. |

## UI Components

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/ui/frame.d` | Main application window frame with docking support and layout management. |
| `dnives/src/dlangide/ui/radialmenu.d` | Circular contextual menu for quick access to commands and tools. |
| `dnives/src/dlangide/ui/terminal.d` | Terminal emulator with command history, syntax highlighting, and AI integration. |
| `dnives/src/dlangide/ui/searchpanel.d` | Advanced search and replace with regex support and multi-file capabilities. |
| `dnives/src/dlangide/ui/commands.d` | Command system with keyboard shortcuts and action handlers. |
| `dnives/src/dlangide/ui/toolbar_manager.d` | Customizable toolbar management with icon and action support. |
| `dnives/src/dlangide/ui/menu_manager.d` | Menu system with dynamic menu generation and context sensitivity. |
| `dnives/src/dlangide/ui/theme_manager.d` | Theme management with support for light/dark modes and custom color schemes. |
| `dnives/src/dlangide/ui/widget_manager.d` | Central registry for UI widgets with lifecycle management. |
| `dnives/src/dlangide/ui/statusbar.d` | Status bar with support for progress indicators, notifications, and contextual information. |
| `dnives/src/dlangide/ui/notification.d` | Notification system for alerts, warnings, and information messages. |
| `dnives/src/dlangide/ui/dialogs/preferences.d` | Application preferences dialog with categorized settings. |
| `dnives/src/dlangide/ui/dialogs/project_settings.d` | Project configuration dialog for build settings and properties. |

## AI Subsystem

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/ai/manager.d` | AI service management with multiple model support and provider abstraction. |
| `dnives/src/dlangide/ai/backends/openai.d` | OpenAI API integration for GPT models. |
| `dnives/src/dlangide/ai/backends/anthropic.d` | Anthropic API integration for Claude models. |
| `dnives/src/dlangide/ai/backends/ollama.d` | Local Ollama integration for self-hosted models. |
| `dnives/src/dlangide/ai/backends/local.d` | Direct local model integration using GGML/GGUF formats. |
| `dnives/src/dlangide/ai/context.d` | Context management for AI with code snippets, file references, and conversation history. |
| `dnives/src/dlangide/ai/tools.d` | Tool calling framework for AI with file, search, and LSP integration. |
| `dnives/src/dlangide/ai/chat.d` | AI chat interface with streaming responses and code block handling. |
| `dnives/src/dlangide/ai/completion.d` | Code completion using AI with context-aware suggestions. |
| `dnives/src/dlangide/ai/model_downloader.d` | Model download and management for local models. |

## Editor Components

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/editor/dsourceedit.d` | D language source editor with syntax highlighting and code completion. |
| `dnives/src/dlangide/editor/code_intelligence.d` | Code intelligence features including symbol navigation and documentation. |
| `dnives/src/dlangide/editor/highlighter.d` | Syntax highlighting engine with support for multiple languages. |
| `dnives/src/dlangide/editor/completion.d` | Code completion system with LSP integration and AI enhancement. |
| `dnives/src/dlangide/editor/formatting.d` | Code formatting with language-specific rules and preferences. |
| `dnives/src/dlangide/editor/refactoring.d` | Refactoring tools for code transformation and cleanup. |
| `dnives/src/dlangide/editor/find_replace.d` | Advanced find and replace functionality within editor. |
| `dnives/src/dlangide/editor/bookmark.d` | Bookmark system for code navigation and annotation. |
| `dnives/src/dlangide/editor/macro_manager.d` | Macro recording and playback for editor actions. |

## Workspace Management

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/workspace/workspace.d` | Workspace management with multi-project support and configuration. |
| `dnives/src/dlangide/workspace/project.d` | Project representation with source files, build settings, and dependencies. |
| `dnives/src/dlangide/workspace/file_manager.d` | File operations including creation, modification, and deletion. |
| `dnives/src/dlangide/workspace/build_manager.d` | Build system integration with configuration and dependency handling. |
| `dnives/src/dlangide/workspace/vault_manager.d` | Secure storage for sensitive project information and credentials. |
| `dnives/src/dlangide/workspace/file_explorer.d` | File explorer with tree view and file operations. |
| `dnives/src/dlangide/workspace/project_templates.d` | Project templates and wizards for new project creation. |
| `dnives/src/dlangide/workspace/history_manager.d` | History tracking for file changes and project navigation. |

## LSP Integration

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/lsp/manager.d` | Language Server Protocol manager with server lifecycle handling. |
| `dnives/src/dlangide/lsp/client.d` | LSP client implementation for communication with language servers. |
| `dnives/src/dlangide/lsp/protocol.d` | LSP protocol definitions and message handling. |
| `dnives/src/dlangide/lsp/diagnostics.d` | Diagnostic handling for errors, warnings, and information. |
| `dnives/src/dlangide/lsp/symbols.d` | Symbol management for code navigation and outline. |
| `dnives/src/dlangide/lsp/completion.d` | Completion request handling and result processing. |
| `dnives/src/dlangide/lsp/dcd_integration.d` | D Completion Daemon integration for D language support. |

## Debugging

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/debug/manager.d` | Debug session management with breakpoints and variables. |
| `dnives/src/dlangide/debug/variables.d` | Variable watching and modification during debugging. |
| `dnives/src/dlangide/debug/breakpoints.d` | Breakpoint management with conditional breakpoints. |
| `dnives/src/dlangide/debug/callstack.d` | Call stack visualization and navigation. |
| `dnives/src/dlangide/debug/watches.d` | Watch expressions for monitoring values during debugging. |
| `dnives/src/dlangide/debug/console.d` | Debug console for command input and output viewing. |
| `dnives/src/dlangide/debug/visualizers.d` | Data visualizers for complex data structures. |

## Tools and Utilities

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/tools/dub.d` | DUB package manager integration. |
| `dnives/src/dlangide/tools/profiler.d` | Performance profiling tools for D applications. |
| `dnives/src/dlangide/tools/documentation.d` | Documentation generation and viewing. |
| `dnives/src/dlangide/tools/code_analysis.d` | Static code analysis and metrics. |
| `dnives/src/dlangide/tools/testing.d` | Unit testing framework integration. |
| `dnives/src/dlangide/tools/task_runner.d` | Custom task definition and execution. |
| `dnives/src/dlangide/tools/git.d` | Git integration for version control. |
| `dnives/src/dlangide/tools/simulator.d` | Code simulation and visualization. |
| `dnives/src/dlangide/tools/risk_manager.d` | Risk assessment and management for projects. |

## Multi-Modal Features

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/multimodal/voice_commands.d` | Voice command recognition and processing. |
| `dnives/src/dlangide/multimodal/speech_recognition.d` | Speech-to-text integration for dictation. |
| `dnives/src/dlangide/multimodal/tts.d` | Text-to-speech for documentation reading and feedback. |
| `dnives/src/dlangide/multimodal/transcriptor.d` | Audio transcription for meetings and notes. |
| `dnives/src/dlangide/multimodal/gesture.d` | Gesture recognition for UI interaction. |

## Plugin System

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/plugins/interface.d` | Plugin interface definitions and base classes. |
| `dnives/src/dlangide/plugins/loader.d` | Plugin discovery, loading, and initialization. |
| `dnives/src/dlangide/plugins/manager.d` | Plugin lifecycle management and dependency resolution. |
| `dnives/src/dlangide/plugins/extension_points.d` | Extension point system for plugin integration. |
| `dnives/src/dlangide/plugins/marketplace.d` | Plugin discovery and installation from repositories. |

## Utils

| File Path | Description |
|-----------|-------------|
| `dnives/src/dlangide/utils/logging.d` | Logging system with categories and levels. |
| `dnives/src/dlangide/utils/i18n.d` | Internationalization and localization support. |
| `dnives/src/dlangide/utils/signals.d` | Signal and slot system for event handling. |
| `dnives/src/dlangide/utils/timer.d` | Timer utilities for delayed and periodic execution. |
| `dnives/src/dlangide/utils/path.d` | Path handling and manipulation utilities. |
| `dnives/src/dlangide/utils/json.d` | JSON parsing and generation utilities. |
| `dnives/src/dlangide/utils/xml.d` | XML processing utilities for configuration and data. |
| `dnives/src/dlangide/utils/process.d` | Process execution and management. |
| `dnives/src/dlangide/utils/platform.d` | Platform-specific functionality and detection. |

## Implementation Notes

This file structure follows a modular design approach with clear separation of concerns. Each component is designed to:

1. Have a single responsibility
2. Be testable independently
3. Use interfaces for dependency injection
4. Support extensibility through plugins
5. Follow consistent naming and organization

When implementing a new feature, consider:
- Which existing module it should belong to
- Whether it warrants creating a new module
- How it interacts with other components
- What interfaces it should implement or extend

The goal is to maintain a clean, maintainable codebase with minimal coupling between components.