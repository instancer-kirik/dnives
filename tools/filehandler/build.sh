#!/bin/bash

# Build script for File Handler tool
# This script builds the console version of dnives file handler

set -e

echo "Building Dnives file handler tool..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create bin directory if it doesn't exist
mkdir -p ../../bin

echo "Building console version..."
dub build --build=release

echo "Build completed successfully!"
echo ""
echo "Executable created: ../../bin/dnives"
echo ""
echo "Installation instructions:"
echo "1. Copy the binary to your PATH:"
echo "   sudo cp ../../bin/dnives /usr/local/bin/"
echo ""
echo "2. To use with Dolphin file manager:"
echo "   - Right-click on a file in Dolphin"
echo "   - Select 'Open With' -> 'Other Application'"
echo "   - Browse to /usr/local/bin/dnives"
echo "   - Check 'Remember application association for all files of this type'"
echo ""
echo "3. To create a custom action in Dolphin:"
echo "   - Copy the service file:"
echo "     mkdir -p ~/.local/share/kservices5/ServiceMenus/"
echo "     cp filehandler.desktop ~/.local/share/kservices5/ServiceMenus/"
echo ""
echo "Usage examples:"
echo "  dnives file.md                    # Auto-handle markdown file"
echo "  dnives --action=view file.txt     # View text file content"
echo "  dnives --action=edit file.d       # Open file in editor"
echo "  dnives --action=info file.bin     # Show file information"
echo ""
echo "Test the build:"
echo "  ../../bin/dnives --help           # Show help"
echo "  ../../bin/dnives README.md        # Test with this README"
