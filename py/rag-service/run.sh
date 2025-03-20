#!/usr/bin/env bash

# Set the target directory (use the first argument or default to a local state directory)
TARGET_DIR=$1
if [ -z "$TARGET_DIR" ]; then
  TARGET_DIR="$HOME/.local/state/avante-rag-service"
fi
# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Copy the required files to the target directory
cp -r src/ "$TARGET_DIR"
cp requirements.txt "$TARGET_DIR"
cp shell.nix "$TARGET_DIR"

echo "Files have been copied to $TARGET_DIR"

# Change to the target directory
cd "$TARGET_DIR"

# Run the RAG service using nix-shell
# The environment variables (PORT, DATA_DIR, OPENAI_API_KEY, OPENAI_BASE_URL) are passed from the parent process
nix-shell
