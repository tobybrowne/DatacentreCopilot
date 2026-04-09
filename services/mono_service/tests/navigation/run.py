"""
Test the nav/path-image endpoint.

Usage:
    python run.py <anchor_a_id> <anchor_b_id> [--url http://localhost:8000] [--out path.png]

Examples:
    python run.py abc123 def456
    python run.py abc123 def456 --out debug.png
    python run.py abc123 def456 --url http://localhost:8000 --out result.png
"""

import argparse
import sys
import time
from pathlib import Path

import requests

BASE_URL = "http://localhost:8000"


def request_path_image(anchor_a_id: str, anchor_b_id: str, base_url: str) -> bytes:
    resp = requests.post(
        f"{base_url}/nav/path-image",
        json={"anchor_a_id": anchor_a_id, "anchor_b_id": anchor_b_id},
    )
    if resp.status_code != 200:
        print(f"Error {resp.status_code}: {resp.text}", file=sys.stderr)
        resp.raise_for_status()
    return resp.content


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("anchor_a_id", help="UUID of the start anchor")
    parser.add_argument("anchor_b_id", help="UUID of the end anchor")
    parser.add_argument("--url", default=BASE_URL, help=f"Service base URL (default: {BASE_URL})")
    parser.add_argument("--out", default="path.png", help="Output PNG file (default: path.png)")
    args = parser.parse_args()

    print(f"Requesting path image: {args.anchor_a_id} → {args.anchor_b_id}")
    t0 = time.perf_counter()
    image_bytes = request_path_image(args.anchor_a_id, args.anchor_b_id, args.url)
    elapsed = (time.perf_counter() - t0) * 1000

    out = Path(args.out)
    out.write_bytes(image_bytes)

    print(f"{'─'*60}")
    print(f"  Start   : {args.anchor_a_id}")
    print(f"  End     : {args.anchor_b_id}")
    print(f"  Output  : {out.resolve()}")
    print(f"  Size    : {len(image_bytes) / 1024:.1f} KB")
    print(f"  Time    : {elapsed:.0f}ms")
    print(f"{'─'*60}")


if __name__ == "__main__":
    main()
