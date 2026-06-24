#!/usr/bin/env bash

# Set the target directory (use the first argument or default to a local state directory)
TARGET_DIR="${1:$HOME/.local/state/avante-rag-service}"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"


# Change to the target directory
cd "$TARGET_DIR" || exit 2
echo "Files have been copied to $TARGET_DIR"

# Run the RAG service using nix-shell
# The environment variables (PORT, DATA_DIR, OPENAI_API_KEY, OPENAI_BASE_URL) are passed from the parent process
nix run ../..#ragService
