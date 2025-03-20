{ pkgs ? import <nixpkgs> {} }:
let
  logFile = "shell_log.txt";
  python = pkgs.python311;
in pkgs.mkShell {
  packages = [
    python
    pkgs.uv
    pkgs.stdenv.cc.cc.lib
  ];
  env = {
    PYTHONUNBUFFERED = 1;
    PYTHONDONTWRITEBYTECODE = 1;
    LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH";
    PORT = 20250;
  };
  shellHook = ''

    # Start with a fresh log file
    echo "=== avante.nvim RAG service setup log $(date '+%Y-%m-%d %H:%M:%S') ===" > "${logFile}"

    # Function to run commands and log their output
    run_and_log() {
      echo "$ $1" >> "${logFile}"
      eval "$1" 2>&1 | tee -a "${logFile}"
      echo "" >> "${logFile}"
    }

    # Log environment info
    run_and_log "echo 'Environment: $(uname -a)'"
    run_and_log "echo 'Python version: $(python --version)'"
    run_and_log "echo 'UV version: $(uv --version)'"


    if [ ! -d ".venv" ]; then
      run_and_log "uv venv"
    else
      echo "Using existing virtual environment"  tee -a "${logFile}"
    fi

    run_and_log source ".venv/bin/activate"

    run_and_log "uv pip install -r requirements.txt"

    run_and_log "uv run fastapi run src/main.py --port $PORT --workers 3"
    '';
}
