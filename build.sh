#!/usr/bin/env bash

set -e

REPO_REMOTE="${1:-origin}"
remote_url=$(git config --get remote.${REPO_REMOTE}.url 2>/dev/null || true)
if [[ "$remote_url" == *"github.com"* ]]; then
  tmp="${remote_url#*github.com[:/]}"
  tmp="${tmp%.git}"
  REPO_OWNER="${tmp%/*}"
  REPO_NAME="${tmp#*/}"
else
  REPO_OWNER="yetone"
  REPO_NAME="avante.nvim"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set the target directory to clone the artifact
TARGET_DIR="${SCRIPT_DIR}/lua"

# Get the artifact download URL based on the platform and Lua version
case "$(uname -s)" in
Linux*)
  PLATFORM="linux"
  CARGO_EXT="so"
  LIB_EXT="so"
  ARCHIVE_EXT="tar.gz"
  ;;
Darwin*)
  PLATFORM="darwin"
  CARGO_EXT="dylib"
  LIB_EXT="so"
  ARCHIVE_EXT="tar.gz"
  ;;
CYGWIN* | MINGW* | MSYS*)
  PLATFORM="windows"
  CARGO_EXT="dll"
  LIB_EXT="dll"
  ARCHIVE_EXT="zip"
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

fetch_remote_tags() {
  git ls-remote --tags "$REPO_REMOTE" | cut -f2 | sed 's|refs/tags/||' | while read -r tag; do
    if ! git rev-parse "$tag" >/dev/null 2>&1; then
      git fetch "$REPO_REMOTE" "refs/tags/$tag:refs/tags/$tag"
    fi
  done
}

if [ ! -d "$TARGET_DIR" ]; then
  mkdir -p "$TARGET_DIR"
fi

fetch_remote_tags
latest_tag="$(git describe --tags --abbrev=0 --match "v*" || true)" # will be empty in clone repos
built_tag="$(cat "${TARGET_DIR}/.tag" 2>/dev/null || true)"

save_tag() {
  echo "$latest_tag" > "${TARGET_DIR}/.tag"
}

build_from_source() {
  echo "Building from source."
  cargo build --release --features="$LUA_VERSION"
  for f in target/release/lib*."$CARGO_EXT"; do
    filename=$(basename "$f" | sed 's/^lib//' | sed "s/\.$CARGO_EXT$/.$LIB_EXT/")
    cp "$f" "${TARGET_DIR}/${filename}"
  done
}

download_and_extract() {
  local url="$1"
  local tmpfile
  tmpfile=$(mktemp -t avante_lib.XXXXXX)

  if ! curl -fL "$url" -o "$tmpfile"; then
    rm -f "$tmpfile"
    return 1
  fi

  if [[ "$url" == *.zip ]]; then
    unzip -o "$tmpfile" -d "$TARGET_DIR"
  else
    tar -zxv -f "$tmpfile" -C "$TARGET_DIR"
  fi
  local status=$?
  rm -f "$tmpfile"
  return $status
}

download_with_gh() {
  local tmpdir
  tmpdir=$(mktemp -d -t avante_lib.XXXXXX)

  if ! gh release download "$latest_tag" --repo "github.com/$REPO_OWNER/$REPO_NAME" --pattern "*$ARTIFACT_NAME_PATTERN*" --clobber --dir "$tmpdir"; then
    rm -rf "$tmpdir"
    return 1
  fi

  local artifacts=("$tmpdir"/*)
  if [[ ${#artifacts[@]} -ne 1 || ! -f "${artifacts[0]}" ]]; then
    rm -rf "$tmpdir"
    return 1
  fi

  if [[ "${artifacts[0]}" == *.zip ]]; then
    unzip -o "${artifacts[0]}" -d "$TARGET_DIR"
  else
    tar -zxv -f "${artifacts[0]}" -C "$TARGET_DIR"
  fi
  local status=$?
  rm -rf "$tmpdir"
  return $status
}

if [[ "$latest_tag" = "$built_tag" && -n "$latest_tag" ]]; then
  echo "Local build is up to date $latest_tag. No download needed."
elif [[ "$latest_tag" != "$built_tag" && -n "$latest_tag" ]]; then
  echo "Local build is out of date $built_tag. Downloading latest $latest_tag."

  set -x
  if test_command "gh" && test_gh_auth; then
    if download_with_gh; then
      save_tag
    else
      build_from_source
    fi
  else
    # Get the artifact download URL
    ARTIFACT_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$latest_tag" | grep "browser_download_url" | cut -d '"' -f 4 | grep "$ARTIFACT_NAME_PATTERN" || true)

  mkdir -p "$TARGET_DIR"

    if [[ -z "$ARTIFACT_URL" ]]; then
      ARTIFACT_URL="https://github.com/$REPO_OWNER/$REPO_NAME/releases/download/$latest_tag/$ARTIFACT_NAME_PATTERN.$ARCHIVE_EXT"
    fi

    if download_and_extract "$ARTIFACT_URL"; then
      save_tag
    else
      build_from_source
    fi
  fi
else
  echo "No latest tag found. Building from source."
  build_from_source
fi
