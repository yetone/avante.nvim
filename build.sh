#!/usr/bin/env bash

set -e

REPO_OWNER="yetone"
REPO_NAME="avante.nvim"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set the target directory to clone the artifact
TARGET_DIR="${SCRIPT_DIR}/build"

# Get the artifact download URL based on the platform and Lua version
case "$(uname -s)" in
Linux*)
  PLATFORM="linux"
  ;;
Darwin*)
  PLATFORM="darwin"
  ;;
CYGWIN* | MINGW* | MSYS*)
  PLATFORM="windows"
  ;;
*)
  echo "Unsupported platform"
  exit 1
  ;;
esac

# Get the architecture (x86_64 or aarch64)
case "$(uname -m)" in
x86_64)
  ARCH="x86_64"
  ;;
aarch64)
  ARCH="aarch64"
  ;;
arm64)
  ARCH="aarch64"
  ;;
*)
  echo "Unsupported architecture"
  exit 1
  ;;
esac

# Set the Lua version (lua54 or luajit)
LUA_VERSION="${LUA_VERSION:-luajit}"

# Set the artifact name pattern
ARTIFACT_NAME_PATTERN="avante_lib-$PLATFORM-$ARCH-$LUA_VERSION"

test_command() {
    command -v "$1" >/dev/null 2>&1
}

test_gh_auth() {
    if gh api user >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

if test_command "gh" && test_gh_auth; then
  latest_release_time=$(gh release view "$(git describe --tags --abbrev=0)" --repo "$REPO_OWNER/$REPO_NAME" --json assets -q '.assets[] | "\(.name) - \(.createdAt)"' | awk "/$ARTIFACT_NAME_PATTERN/{print \$3}" | xargs date -u +%s -d)
  current_build_time=$(stat -c %Y build/avante_html2md* 2>/dev/null || echo "$latest_release_time")
  if [ "$latest_release_time" -gt "$current_build_time" ]; then
    gh release download --repo "github.com/$REPO_OWNER/$REPO_NAME" --pattern "*$ARTIFACT_NAME_PATTERN*" --clobber --output - | tar -zxv -C "$TARGET_DIR"
  fi
else
  latest_release_time=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | grep "$ARTIFACT_NAME_PATTERN.*[^,]$" -B2 | awk -F\" '/created_at/{print $4}' | xargs date -u +%s -d)
  current_build_time=$(stat -c %Y build/avante_html2md* 2>/dev/null || echo "$latest_release_time")
  if [ "$latest_release_time" -gt "$current_build_time" ]; then
    # Get the artifact download URL
    ARTIFACT_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4 | grep $ARTIFACT_NAME_PATTERN)

    set -x

    mkdir -p "$TARGET_DIR"

    curl -L "$ARTIFACT_URL" | tar -zxv -C "$TARGET_DIR"
  fi
fi
