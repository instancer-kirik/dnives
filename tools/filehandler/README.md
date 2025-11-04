# Dnives File Handler

A command-line tool for handling files opened from Dolphin file manager or terminal. This tool can automatically detect file types and handle them appropriately, whether they are markdown files, code files, or other text-based documents. It prioritizes opening files with your customized Dnives IDE.

## Features

- **Auto-detection** of file types based on extension and content
- **Multiple handling modes**: view, edit, info, or auto
- **Support for many file types**: Markdown, D, C/C++, Java, Python, JavaScript, TypeScript, and many more
- **GUI and console modes** available
- **Integration with Dolphin** file manager
- **Smart editor selection** - prioritizes Dnives, then tries VS Code, Kate, Gedit, etc.

## Supported File Types

### Text Files
- Markdown (`.md`, `.markdown`)
- Code files (`.d`, `.c`, `.cpp`, `.h`, `.hpp`, `.java`, `.py`, `.js`, `.ts`, `.rs`, `.go`, etc.)
- Web files (`.html`, `.xml`, `.css`, `.json`)
- Configuration files (`.yaml`, `.yml`, `.toml`, `.ini`, `.cfg`, `.conf`)
- Scripts (`.sh`, `.bash`, `.zsh`, `.fish`, `.ps1`, `.bat`, `.cmd`)
- Documentation (`.txt`, `.log`)
- Special files (`README`, `LICENSE`, `CHANGELOG`, `Makefile`, `Dockerfile`, etc.)

### Binary Files
- Automatically opens with system default application using `xdg-open`

## Building

### Prerequisites
- D compiler (DMD, LDC, or GDC)
- DUB (D package manager)
- DlangUI library (automatically downloaded by DUB)

### Build Instructions

```bash
cd dnives/tools/filehandler
./build.sh
```

This will create the executable in `../../bin/dnives`.

### Manual Build
```bash
# Console version only
dub build --config=console --build=release

# GUI version (can also run in console mode)
dub build --config=gui --build=release
```

## Installation

1. **Copy to system PATH**:
   ```bash
   sudo cp bin/dnives /usr/local/bin/
   ```

2. **Make executable** (if needed):
   ```bash
   chmod +x /usr/local/bin/dnives
   ```

## Usage

### Command Line

```bash
# Auto-handle files (recommended)
dnives file.md document.txt script.py

# View file content in terminal
dnives --action=view README.md

# Open file in an editor
dnives --action=edit main.d

# Show file information
dnives --action=info image.png

# Show help
dnives --help
```

### Integration with Dolphin File Manager

#### Method 1: Default Application
1. Right-click on a file in Dolphin
2. Select "Open With" → "Other Application"
3. Browse to `/usr/local/bin/dnives` or type `dnives`
4. Check "Remember application association for all files of this type"

#### Method 2: Service Menu (Recommended)
1. Copy the service file:
   ```bash
   mkdir -p ~/.local/share/kservices5/ServiceMenus/
   cp filehandler.desktop ~/.local/share/kservices5/ServiceMenus/
   ```

2. Right-click on any file in Dolphin
3. You'll see "Dnives File Handler" submenu with options:
   - Handle with Dnives (Auto)
   - View File Content
   - Edit File
   - Show File Information

#### Method 3: Custom Action
1. Open Dolphin
2. Go to Settings → Configure Dolphin → Services
3. Click "Download New Services" or create manually
4. Add the provided `filehandler.desktop` file

## Behavior by File Type

### Markdown Files (`.md`, `.markdown`)
- Shows file information
- Tries to open with markdown editors: Dnives, Typora, MarkText, Ghostwriter, VS Code
- Falls back to showing content in terminal

### Code Files (`.d`, `.c`, `.cpp`, `.java`, `.py`, `.js`, `.ts`, etc.)
- Shows file information
- Tries to open with code editors: Dnives (prioritized), VS Code, Atom, Kate, Gedit
- Falls back to showing content in terminal with syntax awareness

### Text Files
- Shows file information
- Displays content in terminal
- Handles large files by truncating display

### Binary Files
- Shows file information only
- Opens with system default application (`xdg-open`)

## Configuration

The tool uses smart defaults but can be customized by modifying the source code:

- **Supported extensions**: Edit `supportedTextExtensions` in `app.d`
- **Editor preferences**: Modify editor arrays for different file types
- **File size limits**: Adjust the 10MB limit for text file reading

## Examples

### Basic Usage
```bash
# Handle a markdown file
dnives README.md

# View multiple files
dnives --action=view *.txt

# Get info about a binary
dnives --action=info /usr/bin/ls
```

### Integration Examples
After installing the service menu, you can:
- Right-click any text file → Dnives File Handler → View File Content
- Right-click code files → Dnives File Handler → Edit File
- Right-click any file → Dnives File Handler → Show File Information

## Troubleshooting

### Build Issues
- Ensure DMD/LDC and DUB are installed
- Try `dub clean && dub build --force`
- Check that DlangUI dependencies are satisfied

### Runtime Issues
- **"No editor found"**: Ensure Dnives is in PATH, or install VS Code, Kate, or Gedit
- **"File not found"**: Check file path and permissions
- **Binary files not opening**: Ensure `xdg-open` is available

### Dolphin Integration
- **Service menu not appearing**: Check file location and restart Dolphin
- **"Command not found"**: Ensure dnives is in PATH
- **Permissions**: Make sure the binary is executable

## Development

### Adding New File Types
1. Add extensions to `supportedTextExtensions`
2. Add handling logic in `autoHandle()` method
3. Rebuild and test

### Contributing
This tool is part of the Dnives project (customized DlangIDE). Contributions welcome!

## License

Same as Dnives/DlangIDE project (Boost License).