#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export OUTPUT_DIR="${OUTPUT_DIR:=../../room_finder/HouseTrain}"
export METHOD="${METHOD:=kmeans}"
export HOST="${HOST:=0.0.0.0}"
export PORT="${PORT:=8000}"

echo "Syncing dependencies..."
uv sync

echo "Starting room-finder-service on ${HOST}:${PORT} (method=${METHOD}, output_dir=${OUTPUT_DIR})"
exec uv run uvicorn app:app --host "$HOST" --port "$PORT"

