#!/bin/bash

# File Handler Installation Script
# This script installs the File Handler tool system-wide and sets up Dolphin integration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/../../bin/filehandler"
INSTALL_PATH="/usr/local/bin/filehandler"
SERVICE_FILE="$SCRIPT_DIR/filehandler.desktop"
SERVICE_DIR="$HOME/.local/share/kservices5/ServiceMenus"

echo "File Handler Installation Script"
echo "================================"

# Check if binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    echo "Please run './build.sh' first to build the binary."
    exit 1
fi

echo "Found binary at: $BINARY_PATH"

# Install binary
echo ""
echo "1. Installing binary..."
if [ -w "/usr/local/bin" ]; then
    cp "$BINARY_PATH" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "   ✓ Binary installed to $INSTALL_PATH"
else
    echo "   Need sudo privileges to install to /usr/local/bin"
    sudo cp "$BINARY_PATH" "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
    echo "   ✓ Binary installed to $INSTALL_PATH"
fi

# Verify installation
if command -v filehandler >/dev/null 2>&1; then
    echo "   ✓ filehandler is now available in PATH"
else
    echo "   ⚠ Warning: filehandler not found in PATH"
    echo "     You may need to add /usr/local/bin to your PATH"
    echo "     Add this line to your ~/.bashrc or ~/.zshrc:"
    echo "     export PATH=\"/usr/local/bin:\$PATH\""
fi

# Set up Dolphin service menu
echo ""
echo "2. Setting up Dolphin integration..."
if [ -f "$SERVICE_FILE" ]; then
    mkdir -p "$SERVICE_DIR"
    cp "$SERVICE_FILE" "$SERVICE_DIR/"
    echo "   ✓ Service menu installed to $SERVICE_DIR/filehandler.desktop"
    echo "   ✓ Right-click context menu will be available in Dolphin"
else
    echo "   ⚠ Warning: Service file not found at $SERVICE_FILE"
fi

# Test installation
echo ""
echo "3. Testing installation..."
if filehandler --help >/dev/null 2>&1; then
    echo "   ✓ Installation successful!"
else
    echo "   ✗ Installation test failed"
    exit 1
fi

echo ""
echo "Installation Complete!"
echo "======================"
echo ""
echo "Usage:"
echo "  filehandler <file>                    # Auto-handle any file"
echo "  filehandler --action=view <file>     # View file content"
echo "  filehandler --action=edit <file>     # Open in editor"
echo "  filehandler --action=info <file>     # Show file info"
echo ""
echo "Dolphin Integration:"
echo "  Right-click any file in Dolphin and look for 'File Handler' submenu"
echo ""
echo "To set as default application:"
echo "  1. Right-click a file in Dolphin"
echo "  2. Select 'Open With' → 'Other Application'"
echo "  3. Type 'filehandler' or browse to $INSTALL_PATH"
echo "  4. Check 'Remember application association'"
echo ""
echo "To uninstall:"
echo "  sudo rm $INSTALL_PATH"
echo "  rm $SERVICE_DIR/filehandler.desktop"
echo ""
echo "Test with: filehandler README.md"
