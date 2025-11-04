#!/bin/bash

# Simple Installation Script for Dnives File Handler
# This creates a symlink to make installation and updates easier

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY_PATH="$SCRIPT_DIR/../../bin/dnives"
INSTALL_PATH="/usr/local/bin/dnives"
SERVICE_FILE="$SCRIPT_DIR/filehandler.desktop"
SERVICE_DIR="$HOME/.local/share/kservices5/ServiceMenus"

echo "Dnives File Handler - Simple Installation"
echo "========================================"

# Check if binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    echo "Please run './build.sh' first to build the binary."
    exit 1
fi

echo "Found binary at: $BINARY_PATH"

# Create symlink instead of copying
echo ""
echo "1. Creating symlink to dnives binary..."
if [ -L "$INSTALL_PATH" ]; then
    echo "   Removing existing symlink..."
    sudo rm "$INSTALL_PATH"
elif [ -f "$INSTALL_PATH" ]; then
    echo "   Backing up existing binary to ${INSTALL_PATH}.backup"
    sudo mv "$INSTALL_PATH" "${INSTALL_PATH}.backup"
fi

sudo ln -sf "$BINARY_PATH" "$INSTALL_PATH"
echo "   ✓ Created symlink: $INSTALL_PATH -> $BINARY_PATH"

# Verify installation
if command -v dnives >/dev/null 2>&1; then
    echo "   ✓ dnives is now available in PATH"
else
    echo "   ⚠ Warning: dnives not found in PATH"
    echo "     You may need to add /usr/local/bin to your PATH"
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
if dnives --help >/dev/null 2>&1; then
    echo "   ✓ Installation successful!"
else
    echo "   ✗ Installation test failed"
    exit 1
fi

echo ""
echo "Installation Complete!"
echo "====================="
echo ""
echo "Benefits of symlink installation:"
echo "  - Updates automatically when you rebuild dnives"
echo "  - No need to reinstall after changes"
echo "  - Easy to remove: sudo rm $INSTALL_PATH"
echo ""
echo "Usage:"
echo "  dnives <file>                    # Auto-handle any file with your IDE"
echo "  dnives --action=view <file>      # View file content"
echo "  dnives --action=edit <file>      # Open in editor"
echo "  dnives --action=info <file>      # Show file info"
echo ""
echo "Dolphin Integration:"
echo "  Right-click any file → 'Dnives File Handler' submenu"
echo ""
echo "Now when you rebuild dnives, the file handler will automatically"
echo "use the latest version without needing to reinstall!"
echo ""
echo "Test with: dnives README.md"
