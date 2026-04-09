import asyncio
import io
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

model = None
transform = None
device = None
X_index = None
index_labels = None
method = None
semaphore: asyncio.Semaphore | None = None
executor = ThreadPoolExecutor(max_workers=1)


def load(output_dir: str, infer_method: str = 'kmeans'):
    global model, transform, device, X_index, index_labels, method, semaphore

    method = infer_method

    meta_path = Path(output_dir) / 'metadata.json'
    meta = json.loads(meta_path.read_text()) if meta_path.is_file() else {}

    index_path = Path(output_dir) / ('rooms_clusters.npz' if method == 'kmeans' else 'rooms_index.npz')
    if not index_path.is_file():
        raise RuntimeError(f"Index not found: {index_path} — run 'train' first")

    data = np.load(index_path, allow_pickle=True)
    X_index = data['embeddings']
    index_labels = list(data['labels'])

    from room_finder_core import get_device, load_fb_model, get_norm_transform
    device = get_device()
    model = load_fb_model(meta.get('model', 'dinov2_vits14'), device)
    transform = get_norm_transform()
    semaphore = asyncio.Semaphore(1)

    print(f"[room_inference] loaded {len(index_labels)} vectors ({len(set(index_labels))} rooms) via {method}")


def run(image_bytes: bytes) -> dict:
    from room_finder_core import embed_pil

    t0 = time.perf_counter()
    img = Image.open(io.BytesIO(image_bytes)).convert('RGB')
    t_load = time.perf_counter() - t0

    t1 = time.perf_counter()
    Q = embed_pil([img], model, transform, device)
    t_embed = time.perf_counter() - t1

    t2 = time.perf_counter()
    sims = (Q @ X_index.T)[0]
    nn_idx = int(sims.argmax())
    t_search = time.perf_counter() - t2

    predicted = index_labels[nn_idx]
    confidence = float(sims[nn_idx])

    labels_arr = np.array(index_labels)
    room_scores = {r: float(sims[labels_arr == r].max()) for r in sorted(set(index_labels))}
    top5 = dict(sorted(room_scores.items(), key=lambda x: x[1], reverse=True)[:5])

    return {
        'predicted_room': predicted,
        'confidence':     round(confidence, 4),
        'method':         method,
        'top5':           {r: round(s, 4) for r, s in top5.items()},
        'timing_ms': {
            'load':   round(t_load  * 1000, 2),
            'embed':  round(t_embed * 1000, 2),
            'search': round(t_search * 1000, 3),
            'total':  round((t_load + t_embed + t_search) * 1000, 2),
        },
    }
