#!/bin/bash
set -e

# Path to this repository
REPO_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$HOME/.local/bin}"

echo "🍏 Installing LocalGit..."
echo "📦 Compiling Swift packages..."
(cd "$REPO_DIR" && swift build -c debug)

mkdir -p "$TARGET_DIR"
ln -sf "$REPO_DIR/localgit" "$TARGET_DIR/localgit"

echo "✔ Successfully linked localgit to $TARGET_DIR/localgit"

# Check if target directory is in user's PATH
if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
    echo "⚠️  Note: $TARGET_DIR is not in your current \$PATH."
    echo "To access 'localgit' from anywhere, add this to your ~/.zshrc or ~/.bashrc:"
    echo "  export PATH=\"$TARGET_DIR:\$PATH\""
else
    echo "✔ $TARGET_DIR is in your \$PATH. You can now run 'localgit' from anywhere in terminal!"
fi
