#!/bin/bash

DEPS=(
  "folke/neodev.nvim"
  "nvim-lua/plenary.nvim"
  "MunifTanjim/nui.nvim"
  "stevearc/dressing.nvim"
  "folke/snacks.nvim"
  "echasnovski/mini.nvim"
  "nvim-telescope/telescope.nvim"
  "hrsh7th/nvim-cmp"
  "ibhagwan/fzf-lua"
  "nvim-tree/nvim-web-devicons"
  "zbirenbaum/copilot.lua"
  "folke/lazy.nvim"
)

LUALS_VERSION="3.13.6"

verbose=false

log() {
    echo "$1" >&2
}

log_verbose() {
    if [ "$verbose" = "true" ]; then
        echo "$1" >&2
    fi
}

# Process a single dependency (used for parallel execution)
process_single_dep() {
    local dep="$1"
    local deps_dir="$2"
    local repo_name="$(echo "$dep" | cut -d'/' -f2)"
    local repo_path="$deps_dir/$repo_name"

    if [ -d "$repo_path/.git" ]; then
        log_verbose "Updating existing repository: $repo_path"
        (
            cd "$repo_path"
            git fetch -q
            if git show-ref --verify --quiet refs/remotes/origin/main; then
                git reset -q --hard origin/main
            elif git show-ref --verify --quiet refs/remotes/origin/master; then
                git reset -q --hard origin/master
            else
                log "Could not find main or master branch for $repo_name"
                return 1
            fi
        )
    else
        if [ -d "$repo_path" ]; then
            log_verbose "Directory '$repo_path' exists but is not a git repository. Removing and re-cloning."
            rm -rf "$repo_path"
        fi
        log_verbose "Cloning new repository: $dep to $repo_path"
        git clone -q --depth 1 "https://github.com/${dep}.git" "$repo_path"
    fi
}

clone_deps() {
    local deps_dir=${1:-"$PWD/deps"}
    log_verbose "Cloning dependencies into: $deps_dir (parallel mode)"
    mkdir -p "$deps_dir"

    # Array to store background process PIDs
    local pids=()

    # Start all dependency processes in parallel
    for dep in "${DEPS[@]}"; do
        process_single_dep "$dep" "$deps_dir" &
        pids+=($!)
    done

    # Wait for all background processes to complete and check their exit status
    local failed_count=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed_count++))
        fi
    done

    if [ "$failed_count" -gt 0 ]; then
        log "Warning: $failed_count dependencies failed to process"
        return 1
    fi

    log_verbose "All dependencies processed successfully"
}

install_luals() {
    local dest_dir=${1:-"$PWD/target/tests"}

    # Detect operating system and architecture
    local os_name=""
    local arch=""
    local file_ext=""
    local extract_cmd=""

    case "$(uname -s)" in
        Linux*)
            os_name="linux"
            file_ext="tar.gz"
            ;;
        Darwin*)
            os_name="darwin"
            file_ext="tar.gz"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            os_name="win32"
            file_ext="zip"
            ;;
        *)
            log "Unsupported operating system: $(uname -s)"
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)
            arch="x64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        *)
            log "Unsupported architecture: $(uname -m), falling back to x64"
            arch="x64"
            ;;
    esac

    # Set up extraction command based on file type
    if [ "$file_ext" = "tar.gz" ]; then
        extract_cmd="tar zx --directory"
    else
        extract_cmd="unzip -q -d"
    fi

    local platform="${os_name}-${arch}"
    local luals_url_template="https://github.com/LuaLS/lua-language-server/releases/download/__VERSION__/lua-language-server-__VERSION__-__PLATFORM__.__EXT__"
    local luals_download_url="${luals_url_template//__VERSION__/$LUALS_VERSION}"
    luals_download_url="${luals_download_url//__PLATFORM__/$platform}"
    luals_download_url="${luals_download_url//__EXT__/$file_ext}"

    local luals_dir="$dest_dir/lua-language-server-${LUALS_VERSION}-${platform}"

    if [ ! -d "$luals_dir" ]; then
        log "Installing lua-language-server ${LUALS_VERSION} for ${platform}..."
        mkdir -p "$luals_dir"

        if [ "$file_ext" = "tar.gz" ]; then
            curl -sSL "${luals_download_url}" | tar zx --directory "$luals_dir"
        else
            # For zip files, download first then extract
            local temp_file="/tmp/luals-${LUALS_VERSION}.zip"
            curl -sSL "${luals_download_url}" -o "$temp_file"
            unzip -q "$temp_file" -d "$luals_dir"
            rm -f "$temp_file"
        fi
    else
        log_verbose "lua-language-server is already installed in $luals_dir"
    fi
    echo "$luals_dir/bin"
}

install_nvim_runtime() {
    local dest_dir=${1:-"$PWD/target/tests"}

    command -v yq &>/dev/null || die "yq is not installed for parsing GitHub API responses."

    local nvim_version
    nvim_version="$(yq -r '.jobs.typecheck.strategy.matrix.nvim_version[0]' .github/workflows/lua.yaml)"
    log_verbose "Parsed nvim version from workflow: $nvim_version"

    log_verbose "Resolving ${nvim_version} Neovim release from GitHub API..."
    local api_url="https://api.github.com/repos/neovim/neovim/releases"
    if [ "$nvim_version" == "stable" ]; then
        api_url="$api_url/latest"
    else
        api_url="$api_url/tags/${nvim_version}"
    fi

    local release_data
    release_data="$(curl -s "$api_url")"
    if [ -z "$release_data" ] || echo "$release_data" | yq -e '.message == "Not Found"' > /dev/null; then
        die "Failed to fetch release data from GitHub API for version '${nvim_version}'."
    fi

    # Find the correct asset by regex and extract its name and download URL.
    local asset_info
    asset_info="$(echo "$release_data" | \
      yq -r '.assets[] | select(.name | test("nvim-linux(64|-x86_64)\\.tar\\.gz$")) | .name + " " + .browser_download_url')"

    if [ -z "$asset_info" ]; then
        die "Could not find a suitable linux tarball asset for version '${nvim_version}'."
    fi

    local asset_name
    local download_url
    read -r asset_name download_url <<< "$asset_info"

    local actual_version
    actual_version="$(echo "$download_url" | grep -E -o 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
    if [ -z "$actual_version" ]; then
        die "Could not resolve a version tag from URL: $download_url"
    fi
    log_verbose "Resolved Neovim version is ${actual_version}"

    local runtime_dir="$dest_dir/nvim-${actual_version}-runtime"
    if [ ! -d "$runtime_dir" ]; then
        log "Installing Neovim runtime (${actual_version})..."
        mkdir -p "$runtime_dir"
        curl -sSL "${download_url}" | \
            tar xzf - -C "$runtime_dir" --strip-components=4 \
                "${asset_name%.tar.gz}/share/nvim/runtime"
    else
        log_verbose "Neovim runtime (${actual_version}) is already installed"
    fi
    echo "$runtime_dir"
}

generate_luarc() {
    local luarc_path=${1:-"$PWD/target/tests/luarc.json"}
    local luarc_template="luarc.json.template"

    log_verbose "Generating luarc file at: $luarc_path"
    mkdir -p "$(dirname "$luarc_path")"

    local lua_deps=""
    for dep in "${DEPS[@]}"; do
        repo_name="$(echo "$dep" | cut -d'/' -f2)"
        lua_deps="${lua_deps},\n      \"\$DEPS_PATH/${repo_name}/lua\""
    done
    sed "s#{{DEPS}}#${lua_deps}#" "$luarc_template" > "$luarc_path"
}

main() {
    local command=""
    local args=()

    # Manual parsing for flags and command
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
            verbose=true
            shift
            ;;
            *)
            if [ -z "$command" ]; then
                command=$1
            else
                args+=("$1")
            fi
            shift
            ;;
        esac
    done

    if [ "$command" == "clone" ]; then
        clone_deps "${args[@]}"
    elif [ "$command" == "generate-luarc" ]; then
        generate_luarc "${args[@]}"
    elif [ "$command" == "install-luals" ]; then
        install_luals "${args[@]}"
    elif [ "$command" == "install-nvim" ]; then
        install_nvim_runtime "${args[@]}"
    else
        echo "Usage: $0 [-v|--verbose] {clone [dir]|generate-luarc [path]|install-luals [dir]|install-nvim [dir]}"
        exit 1
    fi
}

main "$@"
