#!/usr/bin/env bash
set -euo pipefail

echo "Starting Cloudflare tunnels..."
echo "  room-finder.tobybrowne.co.uk -> localhost:8000"
echo "  supabase.tobybrowne.co.uk    -> localhost:64321"

cloudflared tunnel run entangl
