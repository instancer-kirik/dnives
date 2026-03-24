# AI Assistance Implementation Plan

## Overview

This document outlines the concrete implementation plan for AI assistance features in the Dnives IDE. It bridges the high-level roadmap with specific development tasks, prioritizing features based on impact and implementation complexity.

**Status**: Phase 2 (AI Integration Core) - In Progress  
**Last Updated**: March 2026  
**Target Completion**: Q2 2026

---

## Current State Assessment

### ✅ Completed Components

| Component | File | Status | Lines |
|-----------|------|--------|-------|
| AI Manager | `src/dcore/ai/ai_manager.d` | Implemented | ~700 |
| AI Backend | `src/dcore/ai/ai_backend.d` | Implemented | ~600 |
| Context Manager | `src/dcore/ai/context_manager.d` | Implemented | ~800 |
| Code Action Manager | `src/dcore/ai/code_action_manager.d` | Implemented | ~900 |
| Integration Layer | `src/dcore/ai/integration.d` | Implemented | ~700 |
| Chat Widget | `src/dcore/ai/widgets/chat_widget.d` | Implemented | ~1100 |
| Symbol Tracker | `src/dcore/code/symbol_tracker.d` | Implemented | ~500 |
| ChatGPT Import | `src/dcore/ai/chatgpt_importer.d` | Implemented | ~500 |

**Total**: ~5,800 lines of implemented D code

### 📋 Existing Features

- [x] Multiple AI backend support (OpenAI, Anthropic, Ollama)
- [x] Streaming response handling
- [x] Context management with file tracking
- [x] Symbol tracking with LSP integration
- [x] Code action management with rollback
- [x] Chat widget with split-pane UI
- [x] Thread/conversation management
- [x] Configuration system (JSON-based)
- [x] Keyboard shortcuts integration
- [x] Menu integration

---

## Phase 1: Stabilization & Hardening (Immediate - 2 weeks)

### 1.1 Core Stability Tasks

| Priority | Task | Complexity | Owner |
|----------|------|------------|-------|
| **P0** | Fix memory leaks in streaming response handling | Medium | TBD |
| **P0** | Add error recovery for failed AI backend connections | Low | TBD |
| **P0** | Implement proper cancellation for long-running AI requests | Medium | TBD |
| **P1** | Add comprehensive logging for debugging | Low | TBD |
| **P1** | Create unit tests for AI backend interfaces | High | TBD |

### 1.2 Configuration & Setup

```d
// Tasks:
- [ ] Create configuration UI dialog
- [ ] Add API key validation on startup
- [ ] Implement config migration from older versions
- [ ] Add config file watching for hot-reload
```

### 1.3 Documentation

- [ ] Generate API documentation from source
- [ ] Create troubleshooting guide
- [ ] Add architecture diagrams to docs/

---

## Phase 2: Enhanced Context Management (2-4 weeks)

### 2.1 Smart Context Gathering

**Goal**: Improve context relevance and reduce token usage

| Feature | Description | Status |
|---------|-------------|--------|
| Semantic Search | Use embeddings to find relevant code | Not Started |
| Import Tree Analysis | Deep analysis of module dependencies | Partial |
| Call Graph Tracking | Track function call relationships | Not Started |
| Type-Aware Context | Include type definitions automatically | Planned |

**Implementation Tasks**:

```d
// File: src/dcore/ai/context_manager.d

// TODO: Add semantic search using embeddings
class SemanticContextSearcher {
    // - Index codebase using local embeddings
    // - Query with user prompt for relevance
    // - Cache embeddings for performance
}

// TODO: Implement call graph analysis
class CallGraphAnalyzer {
    // - Build call graph from LSP data
    // - Traverse for transitive dependencies
    // - Prune irrelevant branches
}
```

### 2.2 Conversation Memory

| Task | Description | Priority |
|------|-------------|----------|
| Conversation Persistence | Save/load conversation history | P1 |
| Conversation Search | Search through past conversations | P2 |
| Smart Summarization | Auto-summarize long conversations | P2 |
| Cross-Conversation Context | Link related conversations | P3 |

### 2.3 Context UI Improvements

- [ ] Visual context tree showing included files
- [ ] Drag-and-drop context reordering
- [ ] Context size indicator with token count
- [ ] Quick toggle for context types

---

## Phase 3: Code Intelligence Features (4-6 weeks)

### 3.1 Inline Suggestions

**Architecture**:

```
┌─────────────────────────────────────┐
│  InlineSuggestionWidget             │
├─────────────────────────────────────┤
│  - Ghost text rendering             │
│  - Debounced trigger (300ms)        │
│  - Partial acceptance (Tab/→)       │
│  - Full acceptance (Ctrl+→)         │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  InlineSuggestionProvider           │
├─────────────────────────────────────┤
│  - Cursor position context          │
│  - AST-based trigger points         │
│  - Caching for common patterns      │
└─────────────────────────────────────┘
```

**Tasks**:
- [ ] Create `src/dcore/ai/inline_suggestion.d`
- [ ] Implement ghost text widget
- [ ] Add debounced trigger system
- [ ] Cache common completion patterns
- [ ] Create acceptance/rejection handlers

### 3.2 AI-Powered Refactoring

| Refactoring Type | Description | Priority |
|------------------|-------------|----------|
| Extract Method | Extract selection to new function | P1 |
| Rename Symbol | AI-assisted symbol renaming | P1 |
| Move Method | Move methods between classes | P2 |
| Inline Variable | Replace variable with expression | P2 |
| Convert to Struct/Class | Type conversion assistance | P3 |

**Implementation**:

```d
// File: src/dcore/ai/refactoring_provider.d

class AIRefactoringProvider {
    // TODO: Implement extract method
    // - Analyze selected code
    // - Determine parameters/return type
    // - Generate method signature
    // - Apply LSP refactoring
    
    // TODO: Implement rename with AI validation
    // - Check for naming conventions
    // - Suggest better names based on usage
    // - Preview all references
}
```

### 3.3 Code Review Mode

**Features**:
- [ ] Request review for current file
- [ ] Review for entire PR/branch
- [ ] Highlight issues inline
- [ ] Generate fix suggestions
- [ ] Create review summary document

---

## Phase 4: Tool Calling & Actions (6-8 weeks)

### 4.1 Tool System Architecture

```d
// File: src/dcore/ai/tools/tool_registry.d

interface AITool {
    string name();
    string description();
    JSONValue parameters();
    JSONValue execute(JSONValue args);
}

class ToolRegistry {
    // TODO: Register built-in tools
    // TODO: Load custom tools from plugins
    // TODO: Validate tool schemas
}
```

### 4.2 Built-in Tools

| Tool | Purpose | Priority | Status |
|------|---------|----------|--------|
| `read_file` | Read file contents | P0 | Implemented |
| `list_files` | List directory contents | P0 | Implemented |
| `search_code` | Search codebase | P1 | Partial |
| `run_terminal` | Execute terminal commands | P1 | Not Started |
| `edit_file` | Apply file edits | P0 | Implemented |
| `get_diagnostics` | Fetch LSP diagnostics | P1 | Not Started |
| `find_symbol` | Locate symbol definitions | P1 | Partial |
| `git_status` | Get git repository status | P2 | Not Started |
| `web_search` | Search the web | P2 | Not Started |

### 4.3 Tool Call UI

- [ ] Tool call visualization in chat
- [ ] Approval dialog for destructive operations
- [ ] Tool execution progress indicator
- [ ] Tool result rendering (diffs, file trees, etc.)

---

## Phase 5: Advanced Features (8-12 weeks)

### 5.1 Multi-Modal Support

| Feature | Description | Priority |
|---------|-------------|----------|
| Image Input | Send screenshots to AI | P2 |
| Diagram Generation | Generate architecture diagrams | P3 |
| Voice Commands | Speech-to-text input | P3 |

### 5.2 Agent Mode

**Concept**: Autonomous AI agent for complex tasks

```
User: "Refactor all string concatenations to use format()"

Agent Loop:
1. Search for all string concatenation patterns
2. Analyze each occurrence for context
3. Plan refactoring steps
4. Execute with validation after each step
5. Report results
```

**Components**:
- [ ] Agent loop implementation
- [ ] Task planning system
- [ ] Progress tracking UI
- [ ] Human-in-the-loop checkpoints

### 5.3 Custom AI Tools

- [ ] Tool definition format (JSON/D code)
- [ ] Tool marketplace/registry
- [ ] User-defined tool creation UI
- [ ] Tool testing framework

---

## Implementation Milestones

### Milestone 1: Stable Core (Week 2)
- [ ] All P0 stability tasks complete
- [ ] Configuration UI working
- [ ] Error handling robust
- [ ] Basic tests passing

**Success Criteria**:
- No crashes during normal usage
- Graceful degradation when AI unavailable
- Config changes apply without restart

### Milestone 2: Smart Context (Week 6)
- [ ] Semantic search working
- [ ] Conversation persistence
- [ ] Context UI improvements
- [ ] Token usage optimization

**Success Criteria**:
- 30% reduction in token usage
- Relevant context found in <100ms
- Conversations survive IDE restart

### Milestone 3: Code Intelligence (Week 10)
- [ ] Inline suggestions working
- [ ] AI refactoring tools available
- [ ] Code review mode functional
- [ ] LSP integration complete

**Success Criteria**:
- Suggestions appear within 500ms
- 80% acceptance rate on suggestions
- Refactorings apply without errors

### Milestone 4: Tool Ecosystem (Week 14)
- [ ] All P1 tools implemented
- [ ] Tool UI polished
- [ ] Custom tool support
- [ ] Agent mode prototype

**Success Criteria**:
- Tools execute reliably
- Users can create custom tools
- Agent handles 5-step tasks autonomously

### Milestone 5: Release Ready (Week 16)
- [ ] All features integrated
- [ ] Documentation complete
- [ ] Performance optimized
- [ ] Bug fixes resolved

**Success Criteria**:
- Feature parity with target competitors
- <1% crash rate
- Positive user feedback

---

## Technical Debt & Refactoring

### Code Quality Tasks

| Task | File(s) | Priority |
|------|---------|----------|
| Extract common JSON handling | `ai_backend.d`, `integration.d` | P2 |
| Unify error handling patterns | All AI modules | P1 |
| Reduce module dependencies | `ai_manager.d` | P2 |
| Add comprehensive comments | All public APIs | P1 |

### Performance Optimizations

```d
// TODO: Implement request batching
// Current: One request per operation
// Target: Batch related requests

// TODO: Add response caching
// Cache: Common AI responses
// TTL: 1 hour for code explanations

// TODO: Optimize context gathering
// Current: Rescan all files
// Target: Incremental updates only
```

---

## Testing Strategy

### Unit Tests

```d
// File: tests/ai/test_ai_backend.d

unittest {
    // Test backend switching
    auto manager = new AIManager();
    manager.setBackend("openai");
    assert(manager.currentBackend.name == "openai");
    
    // Test streaming
    auto stream = manager.streamCompletion("test");
    assert(stream !is null);
}
```

### Integration Tests

- [ ] End-to-end chat workflow
- [ ] Context gathering accuracy
- [ ] Code action application
- [ ] Configuration persistence

### Manual Testing Checklist

- [ ] OpenAI backend works
- [ ] Anthropic backend works
- [ ] Ollama backend works
- [ ] Streaming responses smooth
- [ ] Large file handling (>1000 lines)
- [ ] Network failure recovery
- [ ] Multi-workspace support

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| API rate limits | High | Implement request queuing and caching |
| Token costs | High | Optimize context, add spending limits |
| Model deprecation | Medium | Abstract backend, easy provider switching |
| Performance issues | Medium | Lazy loading, background processing |
| User privacy concerns | Medium | Local model support, data handling docs |

---

## Dependencies & External Integrations

### Required

- [x] LSP manager for symbol information
- [x] DCD for D language symbols
- [x] HTTP client for API calls
- [x] JSON library for configuration

### Optional Enhancements

- [ ] Embedding model for semantic search
- [ ] Local LLM (Llama.cpp/Ollama)
- [ ] Vector database for code indexing
- [ ] Git integration for PR reviews

---

## Appendix: File Organization

```
src/dcore/ai/
├── ai_manager.d              # Central coordinator (existing)
├── ai_backend.d                # Backend interfaces (existing)
├── context_manager.d           # Context handling (existing)
├── code_action_manager.d       # Code actions (existing)
├── refactoring_provider.d      # NEW: Refactoring tools
├── inline_suggestion.d         # NEW: Ghost text suggestions
├── tool/
│   ├── tool_registry.d         # NEW: Tool registration
│   ├── file_tools.d            # NEW: File operation tools
│   ├── search_tools.d          # NEW: Code search tools
│   ├── terminal_tools.d        # NEW: Terminal integration
│   └── lsp_tools.d             # NEW: LSP-based tools
├── agent/
│   ├── agent_loop.d            # NEW: Autonomous agent
│   ├── task_planner.d          # NEW: Task planning
│   └── checkpoint.d            # NEW: Human checkpoints
└── widgets/
    ├── chat_widget.d           # Existing
    ├── inline_widget.d         # NEW: Suggestion widget
    ├── tool_call_widget.d      # NEW: Tool visualization
    └── review_panel.d          # NEW: Code review UI
```

---

## Next Actions (This Week)

1. [ ] Review current implementation for stability issues
2. [ ] Create GitHub issues for P0 tasks
3. [ ] Set up testing framework for AI modules
4. [ ] Draft configuration UI mockup
5. [ ] Profile token usage for optimization

---

*This plan is a living document. Update priorities and status as development progresses.*
