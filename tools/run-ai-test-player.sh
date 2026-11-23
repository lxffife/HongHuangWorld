#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
: "${HH_API_BASE:=http://127.0.0.1:8787}"
export HH_API_BASE
if ! command -v godot >/dev/null 2>&1; then
  echo "Godot 4.6 was not found in PATH." >&2
  exit 1
fi
echo "Starting HongHuang headless AI companion..."
echo "API: $HH_API_BASE"
exec godot --headless --path "$PROJECT_DIR" --script res://scripts/ai_test_player.gd
