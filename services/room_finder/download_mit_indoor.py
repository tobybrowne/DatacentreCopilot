"""
Downloads and unpacks the MIT Indoor Scenes dataset (67 categories, ~2.4 GB).

Usage:
    python download_mit_indoor.py <dest_dir>

The extracted structure will be:
    <dest_dir>/train/<category>/
    <dest_dir>/test/<category>/

The official train/test split from the dataset is used (80/20 approx).
"""

import argparse
import os
import tarfile
import urllib.request
import shutil
from pathlib import Path

DATASET_URL = "http://groups.csail.mit.edu/vision/LabelMe/NewImages/indoorCVPR_09.tar"
SPLITS_URL = "http://web.mit.edu/torralba/www/TrainImages.txt"
SPLITS_TEST_URL = "http://web.mit.edu/torralba/www/TestImages.txt"

TAR_NAME = "indoorCVPR_09.tar"


def download(url: str, dest: str):
    if os.path.exists(dest):
        print(f"  Already downloaded: {dest}")
        return
    print(f"  Downloading {url} ...")
    tmp = dest + ".part"
    def progress(count, block_size, total):
        mb_done = count * block_size / 1e6
        mb_total = total / 1e6
        print(f"\r  {mb_done:.1f} / {mb_total:.1f} MB", end="", flush=True)
    urllib.request.urlretrieve(url, tmp, reporthook=progress)
    print()
    os.rename(tmp, dest)


def fetch_split_list(url: str) -> list[str]:
    print(f"  Fetching split list from {url} ...")
    with urllib.request.urlopen(url) as r:
        lines = r.read().decode().splitlines()
    # lines look like: /airport_inside/image_0001.jpg
    return [l.strip().lstrip("/") for l in lines if l.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dest_dir", help="Directory to extract the dataset into")
    args = parser.parse_args()

    dest = Path(args.dest_dir)
    dest.mkdir(parents=True, exist_ok=True)

    tar_path = dest / TAR_NAME

    print("Step 1: Download archive")
    download(DATASET_URL, str(tar_path))

    print("Step 2: Extract archive")
    images_dir = dest / "Images"
    if not images_dir.exists():
        print(f"  Extracting {tar_path} ...")
        with tarfile.open(tar_path) as tf:
            tf.extractall(dest)
        print("  Done.")
    else:
        print("  Already extracted.")

    print("Step 3: Fetch train/test splits")
    train_files = fetch_split_list(SPLITS_URL)
    test_files = fetch_split_list(SPLITS_TEST_URL)

    print(f"  {len(train_files)} train, {len(test_files)} test images")

    print("Step 4: Organise into train/ and test/ dirs")
    for split_name, file_list in [("train", train_files), ("test", test_files)]:
        split_dir = dest / split_name
        for rel_path in file_list:
            # rel_path: airport_inside/image_0001.jpg
            src = images_dir / rel_path
            if not src.exists():
                continue
            category = Path(rel_path).parts[0]
            category_dir = split_dir / category
            category_dir.mkdir(parents=True, exist_ok=True)
            dst = category_dir / src.name
            if not dst.exists():
                shutil.copy2(src, dst)
        print(f"  {split_name}/ done")

    print(f"\nDataset ready at {dest}")
    print(f"  Train: {dest / 'train'}")
    print(f"  Test:  {dest / 'test'}")
    print(f"\nUsage:")
    print(f"  python main.py train <output_dir> {dest / 'train'}")
    print(f"  python main.py test  <output_dir> {dest / 'test'}")


if __name__ == "__main__":
    main()
