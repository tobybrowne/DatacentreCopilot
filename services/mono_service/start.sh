#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export HOST="${HOST:=0.0.0.0}"
export PORT="${PORT:=8000}"

echo "Installing Node dependencies..."
npm install --silent --prefix nav/detour_js

echo "Syncing dependencies..."
uv sync

echo "Starting mono-service on ${HOST}:${PORT}"
exec uv run uvicorn app:app --host "$HOST" --port "$PORT"

