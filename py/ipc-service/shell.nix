{ pkgs ? import <nixpkgs> {} }:
let
  python = pkgs.python311;
in pkgs.mkShell {
  packages = [
    python
    pkgs.uv
  ];
  env = {
    PYTHONUNBUFFERED = 1;
    PYTHONDONTWRITEBYTECODE = 1;
    PORT = 20251;
  };
  shellHook = ''
    if [ ! -d ".venv" ]; then
      uv venv
    fi
    source ".venv/bin/activate"
    uv pip install -r requirements.txt
    uv run fastapi run src/main.py --port $PORT --workers 1
  '';
}

