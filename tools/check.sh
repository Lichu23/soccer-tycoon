#!/usr/bin/env bash
# Runs every check: sourcemap, type check, format check, lint and unit tests.
# Usage from the project root: tools/check.sh
set -euo pipefail

cd "$(dirname "$0")/.."

ROJO="${ROJO:-$HOME/.rojo/bin/rojo.exe}"
GLOBAL_TYPES="${GLOBAL_TYPES:-$HOME/.local/share/luau/globalTypes.d.luau}"

echo "== sourcemap"
"$ROJO" sourcemap default.project.json -o sourcemap.json

echo "== type check (luau-lsp)"
luau-lsp analyze --definitions="$GLOBAL_TYPES" --sourcemap=sourcemap.json --ignore="**/vendor/**" src

echo "== format check (stylua)"
stylua --check src tests

echo "== lint (selene)"
selene src

echo "== unit tests (lune)"
lune run tests/run

echo "All checks passed."
