#!/usr/bin/env bash

TARGET_DIR=$1
if [ -z "$TARGET_DIR" ]; then
  TARGET_DIR="$HOME/.local/state/avante-ipc-service"
fi

mkdir -p "$TARGET_DIR"
cp -r src/ "$TARGET_DIR"
cp requirements.txt "$TARGET_DIR"
cp shell.nix "$TARGET_DIR"

echo "Files have been copied to $TARGET_DIR"
cd "$TARGET_DIR"
nix-shell

