import argparse
import os
import cv2
import torch
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.cm as cm
from PIL import Image, ImageEnhance
from torchvision import transforms
from sklearn.manifold import TSNE
from sklearn.decomposition import PCA
from sklearn.cluster import KMeans
from tqdm import tqdm


# Deterministic photometric augmentations targeting lighting variation.
# Each entry is (brightness, contrast) factor pair.
_AUGMENT_VARIANTS = [
    (0.5,  1.0),   # dim
    (0.7,  1.0),   # slightly dim
    (1.3,  1.0),   # slightly bright
    (1.6,  1.0),   # bright
    (1.0,  0.7),   # low contrast
    (1.0,  1.3),   # high contrast
]

# White balance shifts as per-channel (R, G, B) multipliers.
# Simulates warm/cool lighting and common indoor colour casts.
_WHITE_BALANCE_VARIANTS = [
    (1.1, 1.0, 0.95),  # slightly warm
    (1.2, 1.0, 0.85),  # warm (tungsten/incandescent)
    (0.95, 1.0, 1.1),  # slightly cool
    (0.85, 0.95, 1.2), # cool (overcast / LED)
    (1.0, 1.05, 0.95), # slight green-yellow (fluorescent warm)
]


def _apply_wb(img: Image.Image, r: float, g: float, b: float) -> Image.Image:
    arr = np.array(img, dtype=np.float32)
    arr[..., 0] = np.clip(arr[..., 0] * r, 0, 255)
    arr[..., 1] = np.clip(arr[..., 1] * g, 0, 255)
    arr[..., 2] = np.clip(arr[..., 2] * b, 0, 255)
    return Image.fromarray(arr.astype(np.uint8))


def augment_frames(frames: list) -> list:
    """Return original frames + photometric and white-balance variants."""
    out = []
    for img in frames:
        out.append(img)
        for brightness, contrast in _AUGMENT_VARIANTS:
            aug = ImageEnhance.Brightness(img).enhance(brightness)
            aug = ImageEnhance.Contrast(aug).enhance(contrast)
            out.append(aug)
        for r, g, b in _WHITE_BALANCE_VARIANTS:
            out.append(_apply_wb(img, r, g, b))
    return out


def get_device():
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def load_fb_model(name: str, device):
    print(f"Loading {name} ...")
    model = torch.hub.load("facebookresearch/dinov2", name)
    return model.eval().to(device)


def get_norm_transform():
    return transforms.Compose([
        transforms.Resize(256),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])


def gem_pool(patch_tokens: torch.Tensor, p: float = 3.0) -> torch.Tensor:
    """Generalized Mean pooling. [1, N, D] -> [1, D]"""
    return patch_tokens.clamp(min=1e-6).pow(p).mean(dim=1).pow(1.0 / p)


def embed_pil(images: list, model, transform, device) -> np.ndarray:
    """Embed a list of PIL images, return L2-normalized GeM embeddings [N, D]."""
    embeddings = []
    for img in images:
        tensor = transform(img).unsqueeze(0).to(device)

        # get the patch-by-path embeddings rather than the final transformer output
        with torch.no_grad():
            out = model.get_intermediate_layers(tensor, n=1)[0]  # [1, patches, D]

        # pool the patch tokens into a single embedding using GeM pooling
        pooled = gem_pool(out).cpu().float().numpy()  # [1, D]

        embeddings.append(pooled)

    X = np.concatenate(embeddings, axis=0)
    X = X / (np.linalg.norm(X, axis=1, keepdims=True) + 1e-8)
    return X


def sample_frames(video_path: str, fps: float) -> list:
    """Return evenly-sampled frames as PIL Images."""
    cap = cv2.VideoCapture(video_path)
    video_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if total == 0:
        cap.release()
        return []
    step = max(1, int(round(video_fps / fps)))
    frames = []
    for idx in range(0, total, step):
        cap.set(cv2.CAP_PROP_POS_FRAMES, idx)
        ret, frame = cap.read()
        if ret:
            frames.append(Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)))
    cap.release()
    return frames


IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def find_rooms(rooms_dir: str) -> dict:
    """
    Return room name -> {"videos": [...], "images": [...]} for each room subdir.
    A subdir can have .mp4 files, image files, or both.
    """
    rooms = {}
    for name in sorted(os.listdir(rooms_dir)):
        subdir = os.path.join(rooms_dir, name)
        if not os.path.isdir(subdir):
            continue
        files = os.listdir(subdir)
        mp4s = [os.path.join(subdir, f) for f in files if f.lower().endswith(".mp4")]
        imgs = [os.path.join(subdir, f) for f in files if os.path.splitext(f)[1].lower() in IMG_EXTS]
        if mp4s or imgs:
            rooms[name] = {"videos": mp4s, "images": sorted(imgs)}
        else:
            print(f"  Skipping {name} — no .mp4 or image files found")
    return rooms


def build_index(rooms_dir: str, sample_fps: float, model, transform, device,
                augment: bool = True) -> tuple[np.ndarray, list, list]:
    rooms = find_rooms(rooms_dir)
    if not rooms:
        raise RuntimeError(f"No rooms found in {rooms_dir}")
    print(f"Found {len(rooms)} rooms: {list(rooms.keys())}")
    if augment:
        print(f"Augmentation enabled — {1 + len(_AUGMENT_VARIANTS)}x frames per room")

    all_embeddings, all_labels, all_frames = [], [], []
    for room_name, sources in tqdm(rooms.items(), desc="Indexing rooms"):
        frames = []

        for vp in sources["videos"]:
            frames.extend(sample_frames(vp, sample_fps))

        for ip in sources["images"]:
            frames.append(Image.open(ip).convert("RGB"))

        if not frames:
            continue

        if augment:
            frames = augment_frames(frames)

        embs = embed_pil(frames, model, transform, device)
        all_embeddings.append(embs)
        all_labels.extend([room_name] * len(frames))
        all_frames.extend(frames)
        tqdm.write(f"  {room_name}: {len(frames)} frames "
                   f"({len(sources['videos'])} videos, {len(sources['images'])} images)"
                   + (" [augmented]" if augment else ""))

    X = np.concatenate(all_embeddings, axis=0)
    print(f"Index: {X.shape[0]} frames, {X.shape[1]}-dim")
    return X, all_labels, all_frames


def build_clusters(X: np.ndarray, labels: list, n_clusters: int) -> tuple[np.ndarray, list, list]:
    """
    Run K-means per room. Returns (centroids, centroid_labels, representative_frame_indices).
    Each centroid's representative frame is the closest real frame to that centroid in X.
    """
    unique_rooms = sorted(set(labels))
    labels_arr = np.array(labels)

    all_centroids, all_centroid_labels, all_rep_indices = [], [], []

    for room in unique_rooms:
        mask = np.where(labels_arr == room)[0]
        room_embs = X[mask]
        k = min(n_clusters, len(room_embs))

        km = KMeans(n_clusters=k, random_state=42, n_init="auto")
        km.fit(room_embs)
        centroids = km.cluster_centers_
        centroids = centroids / (np.linalg.norm(centroids, axis=1, keepdims=True) + 1e-8)

        # closest real frame to each centroid (for visualisation)
        sims = centroids @ room_embs.T
        closest_global = mask[sims.argmax(axis=1)]

        all_centroids.append(centroids)
        all_centroid_labels.extend([room] * k)
        all_rep_indices.extend(closest_global.tolist())
        print(f"  {room}: {k} clusters from {len(room_embs)} frames")

    C = np.concatenate(all_centroids, axis=0)
    return C, all_centroid_labels, all_rep_indices


def create_tsne(X: np.ndarray, labels: list[str], args, out_path: str,
                centroids: np.ndarray = None, centroid_labels: list[str] = None) -> None:
    import math

    n_frames = len(X)

    # optionally append centroids so they're projected into the same space
    if centroids is not None:
        X_all = np.concatenate([X, centroids], axis=0)
    else:
        X_all = X

    pca_dims = min(args.pca_dims, X_all.shape[0] - 1, X_all.shape[1])
    if pca_dims > 0:
        print(f"PCA: {X_all.shape[1]} → {pca_dims} dims ...")
        pca = PCA(n_components=pca_dims, random_state=42)
        X_all = pca.fit_transform(X_all)
        print(f"  Explained variance: {pca.explained_variance_ratio_.sum()*100:.1f}%")

    perplexity = min(args.tsne_perplexity, X_all.shape[0] - 1)
    print(f"t-SNE (perplexity={perplexity}) ...")
    tsne = TSNE(n_components=2, perplexity=perplexity, max_iter=2000,
                init="pca", learning_rate="auto", random_state=42, verbose=1)
    X_2d = tsne.fit_transform(X_all)

    frames_2d   = X_2d[:n_frames]
    centroid_2d = X_2d[n_frames:] if centroids is not None else None

    unique_rooms = sorted(set(labels))
    n_rooms = len(unique_rooms)
    colors = cm.get_cmap("tab20", n_rooms)
    room_to_color = {r: colors(i) for i, r in enumerate(unique_rooms)}
    labels_arr = np.array(labels)

    # dynamic figure: fixed scatter area + legend rows below
    ncol = max(1, min(6, math.ceil(math.sqrt(n_rooms))))
    legend_rows = math.ceil(n_rooms / ncol)
    fig_h = 9 + legend_rows * 0.3
    fig, ax = plt.subplots(figsize=(14, fig_h))

    for room in unique_rooms:
        mask = labels_arr == room
        ax.scatter(frames_2d[mask, 0], frames_2d[mask, 1],
                   c=[room_to_color[room]], label=room,
                   alpha=0.5, s=20, edgecolors="none")

    if centroid_2d is not None:
        centroid_labels_arr = np.array(centroid_labels)
        for room in unique_rooms:
            mask = centroid_labels_arr == room
            ax.scatter(centroid_2d[mask, 0], centroid_2d[mask, 1],
                       c=[room_to_color[room]],
                       s=120, marker="*", edgecolors="white", linewidths=0.5, zorder=5)

    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.02),
              ncol=ncol, fontsize=8, frameon=False)
    ax.set_title("DINOv2 GeM t-SNE — frames by room  (★ = cluster centroid)")
    ax.axis("off")
    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches="tight")