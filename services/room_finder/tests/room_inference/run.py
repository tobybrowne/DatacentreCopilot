"""
Submit images to the room inference endpoint and print results.

Usage:
    python run.py <image_or_dir> [<image_or_dir> ...] [--url http://localhost:8000]

Examples:
    python run.py photo.jpg
    python run.py ./test_images/
    python run.py ./kitchen/ ./bedroom/ --url http://localhost:8000
"""

import argparse
import os
import sys
import time

import requests

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
BASE_URL  = "http://localhost:8000"


def collect_images(paths: list[str]) -> list[str]:
    images = []
    for p in paths:
        if os.path.isfile(p):
            images.append(p)
        elif os.path.isdir(p):
            for root, _, files in os.walk(p):
                for f in sorted(files):
                    if os.path.splitext(f)[1].lower() in IMG_EXTS:
                        images.append(os.path.join(root, f))
        else:
            print(f"Warning: {p} not found, skipping")
    return images


def submit(image_path: str, base_url: str) -> str:
    with open(image_path, "rb") as f:
        resp = requests.post(
            f"{base_url}/jobs/room-inference",
            files={"file": (os.path.basename(image_path), f)},
        )
    resp.raise_for_status()
    return resp.json()["job_id"]


def fetch_result(job_id: str, base_url: str) -> dict:
    resp = requests.get(f"{base_url}/jobs/{job_id}")
    resp.raise_for_status()
    return resp.json()


def print_result(image_path: str, data: dict):
    r = data["result"]
    timing = r["timing_ms"]
    top5   = r["top5"]

    print(f"\n{'─'*60}")
    print(f"  Image   : {image_path}")
    print(f"  Method  : {r['method']}")
    print(f"  Result  : {r['predicted_room']}  (confidence {r['confidence']:.3f})")
    print(f"  Timing  : embed={timing['embed']}ms  search={timing['search']}ms  total={timing['total']}ms")
    print(f"  Top 5   :")
    for room, score in top5.items():
        marker = " ←" if room == r["predicted_room"] else ""
        print(f"            {score:.3f}  {room}{marker}")
    print(f"  Job     : {data['id']}  ({data['queued_at']} → {data['finished_at']})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="Image files or directories")
    parser.add_argument("--url", default=BASE_URL, help=f"Service base URL (default: {BASE_URL})")
    parser.add_argument("--sequential", action="store_true",
                        help="Submit one at a time instead of all at once")
    args = parser.parse_args()

    images = collect_images(args.paths)
    if not images:
        print("No images found.")
        sys.exit(1)

    print(f"Submitting {len(images)} image(s) to {args.url} ...")

    if args.sequential:
        for path in images:
            t0 = time.perf_counter()
            job_id = submit(path, args.url)
            data   = fetch_result(job_id, args.url)
            elapsed = (time.perf_counter() - t0) * 1000
            print_result(path, data)
            print(f"  Round-trip: {elapsed:.0f}ms")
    else:
        # submit all, then collect results
        jobs = []
        for path in images:
            job_id = submit(path, args.url)
            jobs.append((path, job_id))
            print(f"  Submitted {os.path.basename(path)} → {job_id}")

        print("\nWaiting for results ...")
        for path, job_id in jobs:
            data = fetch_result(job_id, args.url)
            print_result(path, data)

    print(f"\n{'─'*60}")
    print(f"Done. {len(images)} image(s) processed.")


if __name__ == "__main__":
    main()
