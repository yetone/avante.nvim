#!/usr/bin/env bash

REPO_OWNER="yetone"
REPO_NAME="avante.nvim"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set the target directory to clone the artifact
TARGET_DIR="${SCRIPT_DIR}/build"

# Get the artifact download URL based on the platform and Lua version
case "$(uname -s)" in
Linux*)
  PLATFORM="ubuntu"
  ;;
Darwin*)
  PLATFORM="macos"
  ;;
CYGWIN* | MINGW* | MSYS*)
  PLATFORM="windows"
  ;;
*)
  echo "Unsupported platform"
  exit 1
  ;;
esac

# Set the Lua version (lua54 or luajit)
LUA_VERSION="${LUA_VERSION:-luajit}"

# Set the artifact name pattern
ARTIFACT_NAME_PATTERN="avante_lib-$PLATFORM-latest-$LUA_VERSION"

# Get the artifact download URL
ARTIFACT_URL=$(curl -s "https://api.github.com/repos/yetone/avante.nvim/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4 | grep $ARTIFACT_NAME_PATTERN)

mkdir -p "$TARGET_DIR"

curl -L "$ARTIFACT_URL" | tar -zxv -C "$TARGET_DIR"
