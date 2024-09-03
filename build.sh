#!/bin/bash

set -eo pipefail

# Check if jq is installed
if ! command -v jq &>/dev/null; then
  echo "Error: jq is not installed. Please install jq."
  exit 1
fi

# Check if GITHUB_TOKEN is set
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GITHUB_TOKEN is not set. Please provide a valid GitHub token."
  exit 1
fi

REPO_OWNER="yetone"
REPO_NAME="avante.nvim"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set the target directory to clone the artifact
TARGET_DIR="${SCRIPT_DIR}/build"

# Get the latest successful run ID of the workflow
RUN_ID=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/workflows/build.yaml/runs?status=success&branch=main&per_page=1" | jq ".workflow_runs[0].id")

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
ARTIFACT_URL=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID/artifacts" |
  jq -r '.artifacts[] | select(.name | test("'"$ARTIFACT_NAME_PATTERN"'")) | .archive_download_url')

mkdir -p "$TARGET_DIR"

curl -L -H "Authorization: Bearer $GITHUB_TOKEN" "$ARTIFACT_URL" | tar -x -C "$TARGET_DIR"
