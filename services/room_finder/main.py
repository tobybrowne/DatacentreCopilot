import argparse
import os
import json
import time
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay
from room_finder_core import *
import pickle
from enum import Enum
from datetime import datetime

IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

class Model(Enum):
    dinov2_vits14 = "dinov2_vits14"
    dinov2_vitl14 = "dinov2_vitl14"
    dinov2_vits16 = "dinov2_vits16"
    dinov2_vits32 = "dinov2_vits32"
    dinov2_vits64 = "dinov2_vits64"

# DEFAULTS
SAMPLE_FPS = 2.0
MODEL = Model.dinov2_vits14.value
TSNE_PERPLEXITY = 30.0
PCA_DIMS = 50

def cmd_train(args):
    os.makedirs(args.output_dir, exist_ok=True)
    index_file   = os.path.join(args.output_dir, "rooms_index.npz")
    frames_file  = os.path.join(args.output_dir, "rooms_index_frames.pkl")
    cluster_file = os.path.join(args.output_dir, "rooms_clusters.npz")
    crep_file    = os.path.join(args.output_dir, "rooms_clusters_frames.pkl")
    tsne_file    = os.path.join(args.output_dir, "tsne.png")

    device = get_device()
    model = load_fb_model(args.model, device)
    transform = get_norm_transform()

    t_index_start = time.perf_counter()
    X, labels, frames = build_index(args.rooms_dir, args.sample_fps, model, transform, device)
    t_index = time.perf_counter() - t_index_start

    np.savez(index_file, embeddings=X, labels=np.array(labels))
    with open(frames_file, "wb") as f:
        pickle.dump(frames, f)
    print(f"Index saved to {index_file}")

    print(f"Building clusters ({args.clusters} per room) ...")
    t_cluster_start = time.perf_counter()
    centroids, centroid_labels, rep_indices = build_clusters(X, labels, args.clusters)
    t_cluster = time.perf_counter() - t_cluster_start
    np.savez(cluster_file, embeddings=centroids, labels=np.array(centroid_labels))
    rep_frames = [frames[i] for i in rep_indices]
    with open(crep_file, "wb") as f:
        pickle.dump(rep_frames, f)
    print(f"Clusters saved to {cluster_file} ({len(centroids)} centroids)")

    t_tsne_start = time.perf_counter()
    create_tsne(X, labels, args, tsne_file, centroids=centroids, centroid_labels=centroid_labels)
    t_tsne = time.perf_counter() - t_tsne_start
    print(f"t-SNE saved to {tsne_file}")

    n_frames = len(labels)
    meta = {
        "trained_at": datetime.now().isoformat(),
        "model": args.model,
        "rooms_dir": os.path.realpath(args.rooms_dir),
        "sample_fps": args.sample_fps,
        "clusters_per_room": args.clusters,
        "tsne_perplexity": args.tsne_perplexity,
        "pca_dims": args.pca_dims,
        "n_rooms": len(set(labels)),
        "rooms": sorted(set(labels)),
        "n_frames": n_frames,
        "n_centroids": len(centroids),
        "timing_s": {
            "index":   round(t_index,   2),
            "cluster": round(t_cluster, 2),
            "tsne":    round(t_tsne,    2),
            "total":   round(t_index + t_cluster + t_tsne, 2),
            "ms_per_frame": round(t_index / n_frames * 1000, 2),
        },
    }
    meta_file = os.path.join(args.output_dir, "metadata.json")
    with open(meta_file, "w") as f:
        json.dump(meta, f, indent=2)
    print(f"Metadata saved to {meta_file}")
    print(f"Timing: index={t_index:.1f}s  cluster={t_cluster:.1f}s  tsne={t_tsne:.1f}s  ({meta['timing_s']['ms_per_frame']}ms/frame)")

def load_test_images(test_dir: str) -> tuple[list, list, list]:
    """Load images from labelled subdirs. Returns (pil_images, true_labels, paths)."""
    images, true_labels, paths = [], [], []
    for room_name in sorted(os.listdir(test_dir)):
        subdir = os.path.join(test_dir, room_name)
        if not os.path.isdir(subdir):
            continue
        for fname in sorted(os.listdir(subdir)):
            if os.path.splitext(fname)[1].lower() not in IMG_EXTS:
                continue
            path = os.path.join(subdir, fname)
            images.append(Image.open(path).convert("RGB"))
            true_labels.append(room_name)
            paths.append(path)
    return images, true_labels, paths

def cmd_test(args):
    output_dir = args.output_dir

    meta_file = os.path.join(output_dir, "metadata.json")
    train_meta = {}
    if os.path.isfile(meta_file):
        with open(meta_file) as f:
            train_meta = json.load(f)
        print("Training metadata:")
        for k, v in train_meta.items():
            print(f"  {k}: {v}")
    else:
        print("Warning: no metadata.json found in output_dir")

    if args.method == "kmeans":
        index_file  = os.path.join(output_dir, "rooms_clusters.npz")
        frames_file = os.path.join(output_dir, "rooms_clusters_frames.pkl")
        if not os.path.isfile(index_file):
            raise RuntimeError(f"Clusters not found: {index_file}\nRun 'train' first.")
        print(f"Using K-means centroids from {index_file}")
    else:
        index_file  = os.path.join(output_dir, "rooms_index.npz")
        frames_file = os.path.join(output_dir, "rooms_index_frames.pkl")
        if not os.path.isfile(index_file):
            raise RuntimeError(f"Index not found: {index_file}\nRun 'train' first.")
        print(f"Using nearest-neighbour index from {index_file}")

    data = np.load(index_file, allow_pickle=True)
    X_index, index_labels = data["embeddings"], list(data["labels"])

    if os.path.isfile(frames_file):
        with open(frames_file, "rb") as f:
            index_frames = pickle.load(f)
    else:
        print("Warning: no frames file found — representative image will not be shown")
        index_frames = None

    device = get_device()
    model = load_fb_model(args.model, device)
    transform = get_norm_transform()

    test_dir = os.path.realpath(args.test_dir)
    query_imgs, true_labels, img_paths = load_test_images(test_dir)
    if not query_imgs:
        raise RuntimeError(f"No labelled images found in {test_dir}")
    print(f"Testing {len(query_imgs)} images across {len(set(true_labels))} rooms ...")

    t_embed_start = time.perf_counter()
    Q = embed_pil(query_imgs, model, transform, device)
    t_embed = time.perf_counter() - t_embed_start

    t_search_start = time.perf_counter()
    sims = Q @ X_index.T
    nn_indices = sims.argmax(axis=1)
    predicted = [index_labels[i] for i in nn_indices]
    confidences = sims.max(axis=1)
    t_search = time.perf_counter() - t_search_start

    for path, true, pred, conf in zip(img_paths, true_labels, predicted, confidences):
        correct = "✓" if true == pred else "✗"
        print(f"  {correct} {os.path.basename(path):30s} true={true:15s} pred={pred:15s} sim={conf:.3f}")

    n_queries = len(query_imgs)
    accuracy = sum(t == p for t, p in zip(true_labels, predicted)) / len(predicted)
    print(f"\nAccuracy: {accuracy*100:.1f}%")
    print(f"Timing: embed={t_embed:.2f}s  search={t_search:.3f}s  ({t_embed/n_queries*1000:.1f}ms/image embed, {t_search/n_queries*1000:.2f}ms/image search)")

    # timestamped results subdir
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = os.path.join(output_dir, timestamp)
    os.makedirs(run_dir, exist_ok=True)

    run_meta = {
        "tested_at": datetime.now().isoformat(),
        "method": args.method,
        "model": args.model,
        "test_dir": os.path.realpath(args.test_dir),
        "n_test_images": n_queries,
        "n_test_rooms": len(set(true_labels)),
        "accuracy": round(accuracy, 4),
        "timing_s": {
            "embed":  round(t_embed,  3),
            "search": round(t_search, 3),
            "total":  round(t_embed + t_search, 3),
            "ms_per_image_embed":  round(t_embed  / n_queries * 1000, 2),
            "ms_per_image_search": round(t_search / n_queries * 1000, 3),
        },
        "train": train_meta,
    }
    with open(os.path.join(run_dir, "metadata.json"), "w") as f:
        json.dump(run_meta, f, indent=2)

    # predictions panel — random sample capped at PANEL_LIMIT
    PANEL_LIMIT = 32
    panel_indices = list(range(len(img_paths)))
    if len(panel_indices) > PANEL_LIMIT:
        import random
        panel_indices = random.sample(panel_indices, PANEL_LIMIT)
        panel_indices.sort()

    panel_imgs    = [query_imgs[i]  for i in panel_indices]
    panel_true    = [true_labels[i] for i in panel_indices]
    panel_pred    = [predicted[i]   for i in panel_indices]
    panel_conf    = [confidences[i] for i in panel_indices]
    panel_nn      = [nn_indices[i]  for i in panel_indices]
    panel_paths   = [img_paths[i]   for i in panel_indices]

    n = len(panel_indices)
    show_nn = index_frames is not None
    imgs_per_pair = 2 if show_nn else 1
    pairs_per_row = 3
    n_rows = (n + pairs_per_row - 1) // pairs_per_row
    n_cols = pairs_per_row * imgs_per_pair
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(n_cols * 2.5, n_rows * 3.0))
    axes = np.array(axes).reshape(n_rows, n_cols)

    for i, (img, true, pred, conf, nn_idx, path) in enumerate(zip(panel_imgs, panel_true, panel_pred, panel_conf, panel_nn, panel_paths)):
        row = i // pairs_per_row
        col = (i % pairs_per_row) * imgs_per_pair
        correct = true == pred
        axes[row, col].imshow(img)
        axes[row, col].set_title(f"true: {true}\n{os.path.basename(path)}", fontsize=7)
        axes[row, col].axis("off")
        for spine in axes[row, col].spines.values():
            spine.set_edgecolor("green" if correct else "red")
            spine.set_linewidth(2)
            spine.set_visible(True)
        if show_nn:
            axes[row, col + 1].imshow(index_frames[nn_idx])
            axes[row, col + 1].set_title(f"pred: {pred}\nsim={conf:.2f}", fontsize=7, fontweight="bold")
            axes[row, col + 1].axis("off")

    for i in range(n, n_rows * pairs_per_row):
        row = i // pairs_per_row
        col = (i % pairs_per_row) * imgs_per_pair
        for k in range(imgs_per_pair):
            axes[row, col + k].axis("off")

    plt.suptitle(f"Room predictions [{args.method}] — accuracy {accuracy*100:.1f}%", fontsize=12, fontweight="bold")
    plt.tight_layout()
    predictions_file = os.path.join(run_dir, "predictions.png")
    plt.savefig(predictions_file, dpi=150, bbox_inches="tight")
    print(f"Predictions panel saved to {predictions_file}")
    plt.close()

    # confusion matrix
    all_rooms = sorted(set(index_labels))
    cm = confusion_matrix(true_labels, predicted, labels=all_rooms)
    fig, ax = plt.subplots(figsize=(max(6, len(all_rooms)), max(5, len(all_rooms) - 1)))
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=all_rooms)
    disp.plot(ax=ax, colorbar=False, xticks_rotation=45)
    ax.set_title(f"Confusion matrix — accuracy {accuracy*100:.1f}%")
    plt.tight_layout()
    cm_file = os.path.join(run_dir, "confusion_matrix.png")
    plt.savefig(cm_file, dpi=150, bbox_inches="tight")
    print(f"Confusion matrix saved to {cm_file}")
    plt.close()

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="mode", required=True)

    p_train = sub.add_parser("train", help="Build embedding index and save t-SNE")
    p_train.add_argument("output_dir", help="Directory to store all training outputs")
    p_train.add_argument("rooms_dir", help="Directory of room subdirs containing .mp4 files")
    p_train.add_argument("--sample-fps", type=float, default=SAMPLE_FPS)
    p_train.add_argument("--model", default=MODEL, choices=[m.value for m in Model])
    p_train.add_argument("--tsne-perplexity", type=float, default=TSNE_PERPLEXITY)
    p_train.add_argument("--pca-dims", type=int, default=PCA_DIMS)
    p_train.add_argument("--clusters", type=int, default=10,
                         help="Number of K-means centroids per room (default: 10)")

    p_test = sub.add_parser("test", help="Test images against a saved index")
    p_test.add_argument("output_dir", help="Training output directory (contains rooms_index.npz)")
    p_test.add_argument("test_dir", help="Directory of labelled room subdirs containing test images")
    p_test.add_argument("--model", default=MODEL, choices=[m.value for m in Model])
    p_test.add_argument("--method", default="kmeans", choices=["nn", "kmeans"],
                        help="Classification method: nearest-neighbour or K-means centroids (default: kmeans)")

    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.mode == "train":
        cmd_train(args)
    elif args.mode == "test":
        cmd_test(args)
