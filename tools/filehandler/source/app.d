module filehandler.app;

import std.stdio;
import std.file;
import std.path;
import std.string;
import std.array;
import std.algorithm;
import std.process;
import std.conv;
import core.thread;
import std.uuid;
import std.file : tempDir, mkdirRecurse, copy, exists, dirEntries, SpanMode;
import std.file : writeFile = write;
import std.path : absolutePath;

struct FileInfo
{
    string path;
    string extension;
    string basename;
    string content;
    bool isText;
    ulong size;
}

class FileHandler
{
    private string[] supportedTextExtensions = [
        ".md", ".markdown", ".txt", ".d", ".c", ".cpp", ".h", ".hpp",
        ".java", ".py", ".js", ".ts", ".html", ".xml", ".css", ".json",
        ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".log",
        ".sh", ".bash", ".zsh", ".fish", ".ps1", ".bat", ".cmd",
        ".rs", ".go", ".swift", ".kt", ".scala", ".rb", ".php",
        ".sql", ".r", ".m", ".mm", ".cs", ".fs", ".vb", ".pl",
        ".lua", ".tcl", ".awk", ".sed", ".vim", ".emacs",
        ".dockerfile", ".makefile", ".cmake", ".gradle", ".sbt",
        ".gitignore", ".gitattributes", ".editorconfig"
    ];

    FileInfo analyzeFile(string filePath)
    {
        FileInfo info;
        info.path = filePath;
        info.basename = baseName(filePath);
        info.extension = extension(filePath).toLower();

        if (exists(filePath) && isFile(filePath))
        {
            info.size = getSize(filePath);
            info.isText = isTextFile(info.extension, info.basename);

            if (info.isText && info.size < 10_000_000)
            { // Read files smaller than 10MB
                try
                {
                    info.content = readText(filePath);
                }
                catch (Exception e)
                {
                    writefln("Warning: Could not read file content: %s", e.msg);
                    info.isText = false;
                }
            }
        }

        return info;
    }

    bool isTextFile(string ext, string basename)
    {
        // Check by extension
        if (supportedTextExtensions.canFind(ext))
        {
            return true;
        }

        // Check by common filenames without extensions
        string lowerBasename = basename.toLower();
        if (lowerBasename.among("readme", "license", "changelog", "makefile",
                "dockerfile", "rakefile", "gemfile", "procfile", "cmakelists.txt"))
        {
            return true;
        }

        return false;
    }

    void handleFiles(string[] filePaths, string action = "auto")
    {
        if (filePaths.empty)
        {
            writeln("Dnives - Command-line tool for handling files from Dolphin");
            writeln("");
            writeln("Usage: dnives [options] <file1> [file2] ...");
            writeln("");
            writeln("Options:");
            writeln("  --action=<action>  Specify action: view, edit, info, auto (default)");
            writeln("  --help            Show this help");
            writeln("");
            writeln("Actions:");
            writeln("  auto   - Automatically determine best action for file type");
            writeln("  view   - Display file content in terminal");
            writeln("  edit   - Open file in suitable editor");
            writeln("  info   - Show file information");
            writeln("");
            writeln("Examples:");
            writeln("  dnives README.md");
            writeln("  dnives --action=view script.py");
            writeln("  dnives --action=edit main.d");
            writeln("  dnives --action=info image.png");
            return;
        }

        foreach (filePath; filePaths)
        {
            handleSingleFile(filePath, action);
            if (filePaths.length > 1)
                writeln(); // Separator between files
        }
    }

    void handleSingleFile(string filePath, string action)
    {
        writefln("Processing: %s", filePath);

        if (!exists(filePath))
        {
            writefln("Error: File does not exist: %s", filePath);
            return;
        }

        FileInfo info = analyzeFile(filePath);

        switch (action)
        {
        case "info":
            showFileInfo(info);
            break;
        case "view":
            viewFile(info);
            break;
        case "edit":
            editFile(info);
            break;
        case "auto":
        default:
            autoHandle(info);
            break;
        }
    }

    void showFileInfo(FileInfo info)
    {
        writefln("File Information:");
        writefln("  Path: %s", info.path);
        writefln("  Name: %s", info.basename);
        writefln("  Extension: %s", info.extension.empty ? "(none)" : info.extension);
        writefln("  Size: %s bytes", info.size);
        writefln("  Type: %s", info.isText ? "Text" : "Binary");

        if (info.isText && !info.content.empty)
        {
            auto lines = info.content.splitLines();
            writefln("  Lines: %s", lines.length);
            writefln("  Characters: %s", info.content.length);

            // Show first few lines as preview
            if (lines.length > 0)
            {
                writeln("  Preview:");
                foreach (i, line; lines[0 .. min(3, lines.length)])
                {
                    writefln("    %s: %s", i + 1, line.length > 80 ? line[0 .. 80] ~ "..." : line);
                }
                if (lines.length > 3)
                {
                    writefln("    ... (%s more lines)", lines.length - 3);
                }
            }
        }
    }

    void viewFile(FileInfo info)
    {
        if (!info.isText)
        {
            writefln("Cannot view binary file: %s", info.path);
            writeln("File type: Binary");
            writefln("Size: %s bytes", info.size);
            writeln("Use appropriate application to view this file.");
            return;
        }

        writeln("=" ~ "=".replicate(info.basename.length + 16) ~ "=");
        writefln("=== Content of %s ===", info.basename);
        writeln("=" ~ "=".replicate(info.basename.length + 16) ~ "=");
        writeln();

        if (info.content.length > 100_000)
        {
            writeln("File is large. Showing first 100,000 characters...");
            writeln();
            write(info.content[0 .. 100_000]);
            writeln();
            writeln("... [File truncated - use a proper editor to view complete content] ...");
        }
        else
        {
            write(info.content);
        }

        writeln();
        writeln("=" ~ "=".replicate(15) ~ "=");
        writeln("=== End of file ===");
        writeln("=" ~ "=".replicate(15) ~ "=");
    }

    void editFile(FileInfo info)
    {
        writefln("Attempting to open '%s' with dnives or another editor...", info.basename);

        // For edit action, try DlangIDE first for all file types
        if (openWithDlangide(info))
        {
            return;
        }

        // Try to open with other editors
        string[] editors = [
            "code", // VS Code
            "codium", // VS Codium
            "kate", // KDE Kate
            "gedit", // GNOME Text Editor
            "mousepad", // XFCE Mousepad
            "leafpad", // Leafpad
            "nano", // Nano
            "vim", // Vim
            "nvim", // Neovim
            "emacs" // Emacs
        ];

        foreach (editor; editors)
        {
            try
            {
                writefln("Trying to launch: %s", editor);
                spawnProcess([editor, info.path]);
                writefln("Successfully opened with %s", editor);
                return;
            }
            catch (Exception e)
            {
                writefln("Failed to launch %s: %s", editor, e.msg);
                continue;
            }
        }

        writeln("Could not find or launch a suitable editor.");
        writeln("Please install one of the following editors:");
        writeln("  - code (Visual Studio Code)");
        writeln("  - kate (KDE Kate)");
        writeln("  - gedit (GNOME Text Editor)");
        writeln("  - nano (console editor)");
        writeln();
        writefln("Or open manually: <editor> '%s'", info.path);
    }

    bool openWithDlangide(FileInfo info)
    {
        try
        {
            string dlangidePath = "/home/kirik/Code/dnives/bin/dlangide";

            // Always create a smart temporary workspace that auto-opens the target file
            string tempWorkspace = createSmartWorkspace(info);
            if (tempWorkspace !is null)
            {
                writefln("Created smart workspace: %s", tempWorkspace);
                spawnProcess([dlangidePath, tempWorkspace]);
                writefln("✓ Opened with smart workspace in DlangIDE - file should auto-open");
                return true;
            }

            return false;
        }
        catch (Exception e)
        {
            writefln("Failed to open with DlangIDE: %s", e.msg);
            return false;
        }
    }

    string findExistingProject(string filePath)
    {
        string dir = isFile(filePath) ? dirName(filePath) : filePath;
        dir = absolutePath(dir);

        // Walk up the directory tree looking for project files
        while (dir != "/" && dir.length > 1)
        {

            // Check for DUB project files
            string dubJson = buildPath(dir, "dub.json");
            string dubSdl = buildPath(dir, "dub.sdl");

            if (exists(dubJson))
            {

                return dubJson;
            }
            if (exists(dubSdl))
            {

                return dubSdl;
            }

            // Check for .dlangidews files
            try
            {
                foreach (entry; dirEntries(dir, "*.dlangidews", SpanMode.shallow))
                {

                    return entry.name;
                }
            }
            catch (Exception e)
            {
                // Ignore permission errors, continue searching
            }

            string parent = dirName(dir);
            if (parent == dir)
                break; // Reached root
            dir = parent;
        }

        return null;
    }

    string createTempWorkspace(FileInfo info)
    {
        try
        {
            // Create temp directory for workspace
            string tempDir = buildPath(tempDir(), "dnives-workspace-" ~ randomUUID()
                    .toString()[0 .. 8]);
            mkdirRecurse(tempDir);

            // Create a minimal dub.json
            string dubContent = `{
    "name": "temp-workspace",
    "description": "Temporary workspace for file editing",
    "targetType": "executable",
    "sourcePaths": ["."],
    "dependencies": {}
}`;
            string dubFile = buildPath(tempDir, "dub.json");
            writeFile(dubFile, dubContent);

            // Copy the source file to temp directory
            string targetFile = buildPath(tempDir, info.basename);
            copy(info.path, targetFile);

            // Create a .dlangidews workspace file
            string workspaceContent = `{
    "name": "temp-workspace",
    "description": "Temporary workspace for `
                ~ info.basename ~ `",
    "projects": {
        "temp-workspace": "dub.json"
    }
}`;
            string workspaceFile = buildPath(tempDir, "temp-workspace.dlangidews");
            writeFile(workspaceFile, workspaceContent);

            // Create workspace settings file to auto-open the target file
            string settingsContent = `{
    "files": [
        {
            "file": "`
                ~ targetFile ~ `",
            "column": 0,
            "row": 0
        }
    ]
}`;
            string settingsFile = buildPath(tempDir, "temp-workspace.dlangidews.wssettings");
            writeFile(settingsFile, settingsContent);

            writefln("Note: Temporary workspace created at %s", tempDir);
            writefln("You can delete it manually when done: rm -rf %s", tempDir);

            return workspaceFile;
        }
        catch (Exception e)
        {
            writefln("Failed to create temporary workspace: %s", e.msg);
            return null;
        }
    }

    string createSmartWorkspace(FileInfo info)
    {
        try
        {
            // Create temp directory for workspace
            string tempDir = buildPath(tempDir(), "dnives-workspace-" ~ randomUUID()
                    .toString()[0 .. 8]);
            mkdirRecurse(tempDir);

            // Check if file is part of an existing project
            string projectFile = findExistingProject(info.path);

            string workspaceContent;
            if (projectFile !is null)
            {
                writefln("Found existing project: %s", projectFile);

                // Create workspace that references the existing project
                string projectName = baseName(dirName(projectFile));
                string relativeProjectPath = relativePath(projectFile, tempDir);

                workspaceContent = `{
    "name": "smart-workspace-`
                    ~ projectName ~ `",
    "description": "Smart workspace for `
                    ~ info.basename ~ ` (from project ` ~ projectName ~ `)",
    "projects": {
        "`
                    ~ projectName ~ `": "` ~ relativeProjectPath ~ `"
    }
}`;
            }
            else
            {
                // Create minimal standalone project
                string dubContent = `{
    "name": "temp-workspace",
    "description": "Temporary workspace for file editing",
    "targetType": "executable",
    "sourcePaths": ["."],
    "dependencies": {}
}`;
                string dubFile = buildPath(tempDir, "dub.json");
                writeFile(dubFile, dubContent);

                // Copy the source file to temp directory
                string targetFile = buildPath(tempDir, info.basename);
                copy(info.path, targetFile);

                workspaceContent = `{
    "name": "temp-workspace",
    "description": "Temporary workspace for `
                    ~ info.basename ~ `",
    "projects": {
        "temp-workspace": "dub.json"
    }
}`;
            }

            // Create the .dlangidews workspace file
            string workspaceFile = buildPath(tempDir, "smart-workspace.dlangidews");
            writeFile(workspaceFile, workspaceContent);

            // Create workspace settings file to auto-open the target file
            // Always use absolute path for reliable file opening
            string absoluteFilePath = isAbsolute(info.path) ? info.path : absolutePath(info.path);
            string settingsContent = `{
    "files": [
        {
            "file": "`
                ~ absoluteFilePath ~ `",
            "column": 0,
            "row": 0
        }
    ]
}`;
            string settingsFile = buildPath(tempDir, "smart-workspace.dlangidews.wssettings");
            writeFile(settingsFile, settingsContent);

            writefln("Note: Smart workspace created at %s", tempDir);
            writefln("Target file: %s", info.path);
            writefln("You can delete workspace when done: rm -rf %s", tempDir);

            return workspaceFile;
        }
        catch (Exception e)
        {
            writefln("Failed to create smart workspace: %s", e.msg);
            return null;
        }
    }

    void autoHandle(FileInfo info)
    {
        writeln();

        if (info.isText)
        {
            if (info.extension == ".md" || info.extension == ".markdown")
            {
                writefln("📝 Markdown file detected: %s", info.basename);
                showFileInfo(info);
                writeln();

                // First try to open with DlangIDE
                if (openWithDlangide(info))
                {
                    return;
                }

                // Try to open with markdown-specific viewers/editors
                string[] mdApps = [
                    "typora", // Typora
                    "marktext", // MarkText
                    "ghostwriter", // Ghostwriter
                    "code", // VS Code
                    "kate", // Kate
                    "gedit" // Gedit
                ];

                foreach (app; mdApps)
                {
                    try
                    {
                        writefln("Trying to launch: %s", app);
                        spawnProcess([app, info.path]);
                        writefln("✓ Opened markdown file with %s", app);
                        return;
                    }
                    catch (Exception e)
                    {
                        writefln("Failed to launch %s: %s", app, e.msg);
                        continue;
                    }
                }

                writeln("No markdown viewer found. Showing content:");
                writeln();
                viewFile(info);
            }
            else if (info.extension.among(".d", ".c", ".cpp", ".h", ".hpp", ".java", ".py",
                    ".js", ".ts", ".rs", ".go", ".swift", ".kt"))
            {
                writefln("💻 Code file detected: %s", info.basename);
                showFileInfo(info);
                writeln();

                // First try to open with DlangIDE
                if (openWithDlangide(info))
                {
                    return;
                }

                // Try to open with other code editors
                string[] codeEditors = [
                    "code", // VS Code
                    "codium", // VS Codium
                    "atom", // Atom
                    "sublime_text", // Sublime Text
                    "kate", // Kate
                    "gedit" // Gedit
                ];

                foreach (editor; codeEditors)
                {
                    try
                    {
                        writefln("Trying to launch: %s", editor);
                        spawnProcess([editor, info.path]);
                        writefln("✓ Opened code file with %s", editor);
                        return;
                    }
                    catch (Exception e)
                    {
                        writefln("Failed to launch %s: %s", editor, e.msg);
                        continue;
                    }
                }

                writeln("No code editor found. Showing content:");
                writeln();
                viewFile(info);
            }
            else if (info.extension.among(".html", ".xml", ".svg"))
            {
                writefln("🌐 Web/Markup file detected: %s", info.basename);
                showFileInfo(info);
                writeln();

                // Try to open with web browsers or specialized editors
                string[] webApps = [
                    "firefox",
                    "chromium",
                    "google-chrome",
                    "/home/kirik/Code/dnives/bin/dlangide",
                    "code",
                    "kate"
                ];

                foreach (app; webApps)
                {
                    try
                    {
                        spawnProcess([app, info.path]);
                        writefln("✓ Opened web file with %s", app);
                        return;
                    }
                    catch (Exception e)
                    {
                        continue;
                    }
                }

                viewFile(info);
            }
            else
            {
                writefln("📄 Text file detected: %s", info.basename);
                showFileInfo(info);
                writeln();
                viewFile(info);
            }
        }
        else
        {
            writefln("🗃️  Binary file detected: %s", info.basename);
            showFileInfo(info);
            writeln();

            writeln("Attempting to open with system default application...");

            // Try to open with system default application
            try
            {
                version (linux)
                {
                    spawnProcess(["xdg-open", info.path]);
                    writeln("✓ Opened with system default application");
                }
                else version (OSX)
                {
                    spawnProcess(["open", info.path]);
                    writeln("✓ Opened with system default application");
                }
                else version (Windows)
                {
                    spawnProcess(["start", info.path]);
                    writeln("✓ Opened with system default application");
                }
                else
                {
                    writeln("Cannot open binary file on this platform.");
                }
            }
            catch (Exception e)
            {
                writefln("Could not open with system default: %s", e.msg);
                writeln("Please open the file manually with an appropriate application.");
            }
        }
    }
}

int main(string[] args)
{
    FileHandler handler = new FileHandler();

    if (args.length <= 1)
    {
        handler.handleFiles([]);
        return 0;
    }

    string action = "auto";
    string[] files;

    foreach (arg; args[1 .. $])
    {
        if (arg.startsWith("--action="))
        {
            action = arg[9 .. $];
        }
        else if (arg == "--help")
        {
            handler.handleFiles([]);
            return 0;
        }
        else
        {
            files ~= arg;
        }
    }

    if (files.empty)
    {
        handler.handleFiles([]);
        return 0;
    }

    handler.handleFiles(files, action);
    return 0;
}
