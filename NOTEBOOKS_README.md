# 📓 D Language Interactive Notebooks

## Overview

Dnives IDE now features a powerful **Interactive Notebook System** inspired by Elixir's LiveBook, bringing the best of literate programming to the D language ecosystem. Combine executable D code with rich documentation, AI assistance, and real-time collaboration in a modern notebook environment.

**🎉 INTEGRATION STATUS: COMPLETE**
- ✅ Core notebook system implemented
- ✅ Multi-kernel execution engine (D, Shell, AI)
- ✅ LiveBook-style UI components
- ✅ Workspace management
- ✅ CCCore/DCore integration
- ✅ AI system integration
- ✅ File format support (.notebook, .livemd)

![Notebook Interface](screenshots/notebook-interface.png)

## ✨ Key Features

### 🚀 **LiveBook-Style Interface**
- **Split-view design** with notebook content and outline panel
- **Real-time cell execution** with streaming output
- **Multi-section organization** with branching support
- **Interactive cell editing** with syntax highlighting

### 📝 **Multiple Cell Types**
- **Markdown cells** - Rich documentation with KaTeX math support
- **D code cells** - Executable D code with full language support
- **AI cells** - Natural language prompts for code generation
- **Shell cells** - System command execution
- **Raw cells** - Plain text content

### 🤖 **AI-Powered Development**
- **Code generation** from natural language descriptions
- **Code explanation** and documentation assistance
- **Error analysis** and debugging help
- **Performance optimization** suggestions
- **Interactive learning** with AI tutoring

### ⚡ **Advanced Execution**
- **Multiple kernel support** (D, Shell, AI, Python*)
- **Sequential execution** with dependency tracking
- **Background processing** for long-running computations
- **Context persistence** across cell executions
- **Error isolation** and recovery

### 🏗️ **Workspace Management**
- **Multi-workspace support** for project organization
- **Notebook templates** for common use cases
- **File format compatibility** (.notebook, .livemd, .ipynb*)
- **Export capabilities** to various formats
- **Git integration** for version control

## 🚀 Quick Start

### Creating Your First Notebook

1. **Open Dnives IDE** and navigate to the Notebooks panel
2. **Create a new workspace** or use the default one
3. **Click "New Notebook"** or use `Ctrl+Alt+N`
4. **Choose a template** or start blank

```d
// Your first D notebook cell!
import std.stdio;

void main() {
    writeln("Hello from D Interactive Notebook! 🚀");
    
    // Variables are persistent across cells
    int magicNumber = 42;
    string[] languages = ["D", "Python", "Elixir"];
    
    writefln("Magic number: %s", magicNumber);
    writefln("Supported languages: %s", languages);
}
```

### Basic Operations

| Action | Shortcut | Description |
|--------|----------|-------------|
| **New Cell** | `Ctrl+N` | Add new code cell |
| **New Markdown** | `Ctrl+Shift+N` | Add markdown cell |
| **Execute Cell** | `Shift+Enter` | Run current cell |
| **Execute All** | `Ctrl+R` | Run all cells |
| **Edit Cell** | `Enter` or double-click | Start editing |
| **Save Notebook** | `Ctrl+S` | Save changes |

## 📚 Notebook Structure

### Sections and Organization

```markdown
# Main Section
Primary content and introduction

## Data Loading
<!-- livebook:{"branch_parent_index":0} -->
Branched section for data processing

### Subsection
Further organization within sections
```

### Cell Metadata

Each cell supports metadata for enhanced functionality:

```json
{
  "tags": ["tutorial", "basics"],
  "kernel": "d",
  "ai_generated": false,
  "execution_priority": "normal"
}
```

## 🛠️ Kernel System

### D Language Kernel

The primary kernel with full D language support:

```d
import std.algorithm;
import std.array;
import std.range;

void main() {
    // Full D standard library available
    auto numbers = iota(1, 11)
        .filter!(n => n % 2 == 0)
        .map!(n => n * n)
        .array;
    
    writeln("Even squares: ", numbers);
}
```

**Features:**
- ✅ Full Phobos standard library
- ✅ DUB dependency integration
- ✅ Compile-time features (CTFE, templates)
- ✅ Module definitions across cells
- ✅ Error handling and debugging

### Shell Kernel

Execute system commands and scripts:

```bash
#!/bin/bash
# List D source files in project
find . -name "*.d" -type f | head -10

# Check D compiler version
dmd --version

# Run performance benchmarks
dub test --build=release
```

### AI Kernel

Natural language programming assistance:

```ai
Please create a generic binary search tree implementation in D with the following features:
- Insert, remove, and search operations
- In-order traversal
- Balanced tree maintenance
- Iterator support

Make it memory-safe and include usage examples.
```

## 🎯 Use Cases

### 1. **Algorithm Development**

Perfect for developing and testing algorithms interactively:

```d
// Binary search implementation with step-by-step testing
import std.stdio;
import std.algorithm;

bool binarySearch(T)(T[] arr, T target) {
    // Implementation here...
    return false; // Placeholder
}

void main() {
    // Test with different datasets
    int[] data = [1, 3, 5, 7, 9, 11, 13];
    writeln("Testing binary search...");
    
    foreach (target; [5, 8, 13]) {
        bool found = binarySearch(data, target);
        writefln("%d: %s", target, found ? "Found" : "Not found");
    }
}
```

### 2. **Data Analysis**

Analyze datasets with interactive visualizations:

```d
import std.csv;
import std.stdio;
import std.algorithm;
import std.array;

void main() {
    // Load CSV data
    auto records = File("sales_data.csv")
        .byLine
        .map!(line => line.splitter(',').array)
        .array;
    
    writefln("Loaded %d records", records.length);
    
    // Calculate statistics
    auto totalSales = records[1..$]
        .map!(row => row[2].to!double)
        .sum;
    
    writefln("Total sales: $%.2f", totalSales);
}
```

### 3. **Learning and Teaching**

Interactive tutorials and educational content:

```markdown
# D Language Tutorial: Ranges

Ranges are one of D's most powerful features. Let's explore them step by step.

## What are Ranges?

A range is an abstraction that allows you to iterate over collections of data...
```

```d
// Interactive examples students can modify and run
import std.range;
import std.algorithm;
import std.stdio;

void main() {
    // Try changing these values!
    auto start = 1;
    auto end = 10;
    
    auto squares = iota(start, end)
        .map!(x => x * x);
    
    writeln("Squares: ", squares);
}
```

### 4. **Prototyping and Experimentation**

Rapid prototyping with immediate feedback:

```d
// Experiment with different sorting algorithms
import std.algorithm;
import std.datetime.stopwatch;
import std.random;

void benchmarkSort(alias sortFunc)(int[] data, string name) {
    auto sw = StopWatch(AutoStart.yes);
    sortFunc(data);
    sw.stop();
    
    writefln("%s: %s ms", name, sw.peek.total!"msecs");
}

void main() {
    // Generate test data
    auto rng = Random(42);
    int[] data = new int[10000];
    foreach (ref x; data) {
        x = uniform(1, 1000, rng);
    }
    
    // Test different algorithms
    benchmarkSort!sort(data.dup, "Standard sort");
    benchmarkSort!schwartzSort(data.dup, "Schwartz sort");
}
```

## 🤖 AI Integration

### Code Generation

Ask the AI to generate code from natural descriptions:

**Prompt:** "Create a thread-safe queue implementation in D"

**Generated Code:**
```d
import std.concurrency;
import std.container;
import core.sync.mutex;

class ThreadSafeQueue(T) {
    private DList!T queue;
    private Mutex mutex;
    
    this() {
        mutex = new Mutex();
    }
    
    void enqueue(T item) {
        synchronized(mutex) {
            queue.insertBack(item);
        }
    }
    
    T dequeue() {
        synchronized(mutex) {
            if (queue.empty) {
                throw new Exception("Queue is empty");
            }
            auto item = queue.front;
            queue.removeFront();
            return item;
        }
    }
    
    bool empty() {
        synchronized(mutex) {
            return queue.empty;
        }
    }
}
```

### Code Explanation

Get detailed explanations of complex code:

**Input:** Complex algorithm implementation
**AI Output:** Step-by-step breakdown with performance analysis and optimization suggestions.

### Learning Assistance

Interactive programming education:

```ai
I'm learning about D's template system. Can you explain the difference between:
1. Function templates
2. Class templates  
3. Mixin templates

Please provide examples of each with practical use cases.
```

## 📁 File Formats

### Native Format (.notebook)

JSON-based format with full feature support:

```json
{
  "notebook_format_version": 1,
  "name": "My D Notebook",
  "kernel_name": "d",
  "sections": [
    {
      "name": "Introduction",
      "cells": [
        {
          "cell_type": "markdown",
          "source": "# Welcome to my notebook"
        }
      ]
    }
  ]
}
```

### LiveMD Export (.livemd)

Elixir LiveBook compatible format:

```markdown
# My D Notebook

Welcome to my notebook

```d
import std.stdio;
writeln("Hello, World!");
```
```

### Jupyter Compatibility (.ipynb)*

Basic compatibility with Jupyter notebooks:
- Import existing Jupyter notebooks
- Export to Jupyter format (limited features)

## 🏗️ Workspace Management

### Creating Workspaces

```bash
# Default workspace location
~/.dnives/notebooks/
├── Default/
│   ├── .workspace.json
│   └── example.notebook
└── DataScience/
    ├── .workspace.json
    ├── analysis.notebook
    └── visualization.notebook
```

### Workspace Configuration

```json
{
  "id": "workspace-uuid",
  "name": "Data Science",
  "description": "Notebooks for data analysis projects",
  "notebooks": [
    {
      "name": "Market Analysis",
      "file_path": "analysis.notebook",
      "last_accessed": "2024-01-15T10:30:00Z"
    }
  ],
  "settings": {
    "default_kernel": "d",
    "auto_save": true,
    "execution_timeout": 30000
  }
}
```

## ⚙️ Configuration

### IDE Settings

Configure notebooks through Dnives IDE settings:

```json
{
  "notebooks": {
    "workspaces_path": "~/.dnives/notebooks",
    "default_kernel": "d",
    "auto_save_interval": 60,
    "max_output_lines": 1000,
    "execution_timeout": 30000,
    "ai": {
      "enabled": true,
      "provider": "openai",
      "model": "gpt-4"
    }
  }
}
```

### Kernel Configuration

Customize kernel behavior:

```json
{
  "kernels": {
    "d": {
      "compiler": "dmd",
      "flags": ["-O", "-release"],
      "libraries": ["phobos"],
      "timeout": 30000
    },
    "shell": {
      "shell": "/bin/bash",
      "timeout": 60000,
      "allowed_commands": ["ls", "find", "grep"]
    }
  }
}
```

## 🔧 Advanced Features

### Custom Kernels

Create custom kernels for specialized workflows:

```d
class CustomKernel : NotebookKernel {
    this() {
        super("custom", "1.0");
    }
    
    override ExecutionResult execute(string code) {
        // Custom execution logic
        return ExecutionResult(true, "Custom output");
    }
    
    override bool isAvailable() {
        return true;
    }
}

// Register kernel
executor.registerKernel(KernelType.Custom, new CustomKernel());
```

### Notebook Templates

Create reusable templates:

```d
class DataAnalysisTemplate {
    static Notebook create() {
        auto notebook = new Notebook("Data Analysis");
        
        // Add standard sections
        notebook.addSection("Data Loading");
        notebook.addSection("Exploration");
        notebook.addSection("Analysis");
        notebook.addSection("Visualization");
        
        return notebook;
    }
}
```

### Extension Points

Extend notebook functionality:

```d
interface NotebookExtension {
    string name();
    void onCellExecuted(NotebookCell cell);
    void onNotebookSaved(Notebook notebook);
    Widget createCustomWidget();
}
```

## 🔍 Troubleshooting

### Common Issues

**Kernel Not Starting**
```bash
# Check D compiler availability
which dmd
dmd --version

# Verify dependencies
dub list
```

**Execution Timeout**
```json
// Increase timeout in settings
{
  "notebooks": {
    "execution_timeout": 60000  // 60 seconds
  }
}
```

**Memory Issues**
```d
// Monitor memory usage in notebooks
import std.process;
writeln("Memory usage: ", environment.get("MEMORY_LIMIT", "Unknown"));
```

### Performance Optimization

1. **Use compiled modules** for heavy computations
2. **Limit output size** to prevent UI slowdown
3. **Clear outputs** regularly for large notebooks
4. **Use background execution** for long-running tasks

## 🚀 Future Enhancements

### Planned Features

- [ ] **Real-time collaboration** with multiple users
- [ ] **Notebook sharing** and publishing platform
- [ ] **Advanced visualizations** with D plotting libraries
- [ ] **Database integration** with SQL cells
- [ ] **Package management** with DUB integration
- [ ] **Cloud execution** for resource-intensive tasks
- [ ] **Mobile companion** app for viewing notebooks

### Community

- **GitHub**: [dnives/notebooks](https://github.com/dnives/notebooks)
- **Discord**: #notebooks channel
- **Documentation**: [notebooks.dnives.dev](https://notebooks.dnives.dev)
- **Examples**: [github.com/dnives/notebook-examples](https://github.com/dnives/notebook-examples)

## 📄 License

This notebook system is part of Dnives IDE and is licensed under the same terms.

---

**Happy coding with D Interactive Notebooks! 📓✨**

*Bringing the power of literate programming to the D ecosystem.*