name: pre-commit

on:
  pull_request:
    types: [labeled, opened, reopened, synchronize]
  push:
    branches: [main, test-me-*]

jobs:
  pre-commit:
    if: "github.event.action != 'labeled' || github.event.label.name == 'pre-commit ci run'"
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - run: gh pr edit ${{ github.event.number }} --remove-label 'pre-commit ci run'
      if: github.event.action == 'labeled' && github.event.label.name == 'pre-commit ci run'
      env:
        GH_TOKEN: ${{ github.token }}
    - uses: actions/setup-python@v3
      with:
        python-version: '3.11'
    - name: Install uv
      uses: astral-sh/setup-uv@v5
    - run: |
        uv venv
        source .venv/bin/activate
        uv pip install -r py/rag-service/requirements.txt
    - uses: leafo/gh-actions-lua@v11
    - uses: leafo/gh-actions-luarocks@v5
    - run: luarocks install luacheck
    - name: Install stylua from crates.io
      uses: baptiste0928/cargo-install@v3
      with:
        crate: stylua
        args: --features lua54
    - uses: pre-commit/action@v3.0.1
    - uses: pre-commit-ci/lite-action@v1.1.0
      if: always()
