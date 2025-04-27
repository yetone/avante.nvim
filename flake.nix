{
  description = "avante.nvim flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

    forEachSupportedSystem = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system: let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [fenix.overlays.default];
          };
          rustToolchain = pkgs.fenix.complete.toolchain;
          # We no longer build individual crates as packages here

          # Parse requirements.txt for devShell
          pythonDeps = pkgs.python3.withPackages (
            ps: let
              reqs = pkgs.lib.splitString "\n" (builtins.readFile ./py/rag-service/requirements.txt);
              cleanedReqs = pkgs.lib.filter (line: line != "" && !pkgs.lib.hasPrefix "#" line) reqs;
              packageNames = pkgs.lib.map (line: pkgs.lib.elemAt (pkgs.lib.splitString "==" line) 0) cleanedReqs;
              getPythonPackage = name: let
                pname = pkgs.lib.replaceStrings ["-"] ["_"] (pkgs.lib.toLower name);
              in
                if builtins.hasAttr pname ps
                then builtins.getAttr pname ps
                else null;
              resolvedPackages = pkgs.lib.filter (p: p != null) (pkgs.lib.map getPythonPackage packageNames);
            in
              resolvedPackages
              ++ [
                ps.python-dotenv
                ps.uvicorn
              ]
          );
          uv = pkgs.uv; # Add uv package
          stdenv = pkgs.stdenv; # Add stdenv for libraries
        in
          f {
            inherit pkgs rustToolchain pythonDeps system;
            # No crate packages inherited here anymore
            inherit uv stdenv; # Pass uv and stdenv
          }
      );

    # Updated script to perform cargo build AND copy to ./build
    appBuildScript = pkgs: luaFeature: rustToolchain: ''
      #!${pkgs.runtimeShell}
      set -e
      echo "Building avante libraries with cargo for ${luaFeature} on ${pkgs.system}..."

      # Ensure Cargo.lock exists, might need generation step if not checked in
      if [ ! -f Cargo.lock ]; then
        echo "Cargo.lock not found, attempting to generate..."
        ${rustToolchain}/bin/cargo generate-lockfile
      fi

      # Build all workspace members with the specified feature
      ${rustToolchain}/bin/cargo build --release --features ${luaFeature} --workspace

      echo "Successfully built libraries in ./target/release/"

      # Now copy to ./build with the old naming convention
      echo "Copying built libraries to ./build/ for compatibility..."

      ext=""
      BUILD_SYSTEM="${pkgs.system}"
      case "''${BUILD_SYSTEM}" in
        *-darwin*)
          ext="dylib"
          ;;
        *-linux*)
          ext="so"
          ;;
        *-mingw*|*-cygwin*) # Handle Windows systems
          ext="dll"
          ;;
        *)
          echo "Warning: Unknown system type ${pkgs.system}. Cannot determine library extension." >&2
          ;;
      esac

      # Create build directory
      mkdir -p ./build

      # Define source and destination names
      crates=("tokenizers" "templates" "repo_map" "html2md")

      # Copy libraries by iterating over elements
      for crate_name in "''${crates[@]}"; do
        src_name="libavante_$crate_name.$ext"
        dst_name="avante_''${crate_name//-/_}.$ext"
        src_path="./target/release/$src_name"
        dst_path="./build/$dst_name"

        if [ -f "$src_path" ]; then
          echo "Copying $src_path to $dst_path"
          cp "$src_path" "$dst_path"
        else
          echo "Warning: Expected library $src_path not found in target/release/"
        fi
      done

      echo "Libraries copied to ./build/"
    '';
  in {
    # Packages output might be minimal now, or just dev tools
    packages = forEachSupportedSystem (attrs: {
      # You could expose the toolchain or other utilities if needed
      default = attrs.rustToolchain; # Example
    });

    # Development shell remains largely the same
    devShells = forEachSupportedSystem (attrs: {
      default = attrs.pkgs.mkShell {
        name = "avante-dev";
        packages = [
          attrs.rustToolchain
          attrs.pythonDeps
          attrs.pkgs.cargo-watch
          attrs.pkgs.luajit
          attrs.pkgs.lua5_1
          attrs.pkgs.stylua
          attrs.pkgs.luacheck
        ];
      };
    });

    # Updated app definitions using the new build script
    apps = forEachSupportedSystem (attrs: let
      pluginBuildScript = attrs.pkgs.writeShellApplication {
        name = "build-avante-plugin";
        # Add rustToolchain to runtimeInputs for cargo command
        runtimeInputs = [attrs.rustToolchain];
        text = appBuildScript attrs.pkgs "luajit" attrs.rustToolchain;
      };
      pluginLua51BuildScript = attrs.pkgs.writeShellApplication {
        name = "build-avante-plugin-lua51";
        runtimeInputs = [attrs.rustToolchain];
        text = appBuildScript attrs.pkgs "lua51" attrs.rustToolchain;
      };
      ragServiceScript = attrs.pkgs.writeShellApplication {
        name = "avante-rag-service";
        runtimeInputs = [attrs.pythonDeps attrs.uv attrs.stdenv.cc.cc.lib];
        text = ''
          #!${attrs.pkgs.runtimeShell}
          set -e

          # Define log file path within DATA_DIR
          logFile="''${DATA_DIR}/runtime.log"

          # Set Python environment variables
          export PYTHONUNBUFFERED=1
          export PYTHONDONTWRITEBYTECODE=1

          # cd into the service directory
          pushd "''${SOURCE}/py/rag-service" &>/dev/null

          # Start with a fresh log file
          echo "=== avante.nvim RAG service setup log $(date '+%Y-%m-%d %H:%M:%S') ===" > "''${logFile}"

          # Function to run commands and log their output
          run_and_log() {
            echo "$ $1" >> "''${logFile}"
            eval "$1" 2>&1 | tee -a "''${logFile}"
            # Add an empty line for readability in the log
            echo "" >> "''${logFile}"
          }

          # Log environment info using Nix paths for tools
          run_and_log "echo 'Environment: $(uname -a)'"
          run_and_log "echo 'Python version: $(${attrs.pythonDeps}/bin/python --version)'"
          run_and_log "echo 'UV version: $(${attrs.uv}/bin/uv --version)'"

          # Setup virtual environment using uv
          if [ ! -d ".venv" ]; then
            run_and_log "${attrs.uv}/bin/uv venv -p ${attrs.pythonDeps}/bin/python"
          else
            echo "Using existing virtual environment" | tee -a "''${logFile}"
          fi

          # Install dependencies using uv
          run_and_log "${attrs.uv}/bin/uv pip install -r requirements.txt"

          # Log and run the service using uv run
          ${attrs.uv}/bin/uv run fastapi run src/main.py --port "''${PORT}" --workers 3 2>&1 | tee -a "''${logFile}"
        '';
      };
    in {
      plugin = {
        type = "app";
        program = "${pluginBuildScript}/bin/build-avante-plugin";
      };
      plugin-lua51 = {
        type = "app";
        program = "${pluginLua51BuildScript}/bin/build-avante-plugin-lua51";
      };
      # Expose the rag-service app
      rag-service = {
        type = "app";
        program = "${ragServiceScript}/bin/avante-rag-service";
      };
    });

    # Default app points to the luajit version
    defaultApp = self.apps."${builtins.currentSystem}".plugin;
  };
}
