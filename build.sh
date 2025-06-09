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

latest_tag="$(git describe --tags --abbrev=0 || true)" # will be empty in clone repos
built_tag="$(cat build/.tag 2>/dev/null || true)"

save_tag() {
  echo "$latest_tag" >build/.tag
}

if [[ "$latest_tag" = "$built_tag" && -n "$latest_tag" ]]; then
  echo "Local build is up to date. No download needed."
elif [[ "$latest_tag" != "$built_tag" && -n "$latest_tag" ]]; then
  if test_command "gh" && test_gh_auth; then
    gh release download "$latest_tag" --repo "github.com/$REPO_OWNER/$REPO_NAME" --pattern "*$ARTIFACT_NAME_PATTERN*" --clobber --output - | tar -zxv -C "$TARGET_DIR"
    save_tag
  else
    # Get the artifact download URL
    ARTIFACT_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$latest_tag" | grep "browser_download_url" | cut -d '"' -f 4 | grep $ARTIFACT_NAME_PATTERN)

    set -x

    mkdir -p "$TARGET_DIR"

    curl -L "$ARTIFACT_URL" | tar -zxv -C "$TARGET_DIR"
    save_tag
  fi
else
  cargo build --release --features=$LUA_VERSION
  for f in target/release/lib*.so; do
    cp "$f" "build/$(echo $f | sed 's#.*/lib##')"
  done
fi
