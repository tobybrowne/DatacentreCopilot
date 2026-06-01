#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building ML2 Voice GDExtension (debug + release) ==="
cd "$SCRIPT_DIR"
scons platform=android target=template_debug arch=x86_64
scons platform=android target=template_release arch=x86_64
echo "=== Done - .so files in app/addons/ml2_voice/bin/ ==="
