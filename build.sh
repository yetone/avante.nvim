#!/bin/bash

set -eo pipefail

REPO_OWNER="yetone"
REPO_NAME="avante.nvim"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set the target directory to clone the artifact
TARGET_DIR="${SCRIPT_DIR}/build"

# Get the latest successful run ID of the workflow
RUN_ID=$(curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/build.yaml/runs?status=success&branch=main" |
  \grep -oP '(?<="id": )\d+' | head -1)

# Get the artifact download URL based on the platform and Lua version
case "$(uname -s)" in
Linux*)
  PLATFORM="linux"
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
ARTIFACT_URL=$(curl -s -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID/artifacts" |
  \grep -oP "(?<=\"archive_download_url\": \")https://[^\"]+/$ARTIFACT_NAME_PATTERN[^\"]+")

mkdir -p "$TARGET_DIR"
curl -L "$ARTIFACT_URL" | tar -xz -C "$TARGET_DIR" --strip-components=1
