"""
Room inference handler.

Loads the trained index/clusters from a room_finder output_dir once at startup,
then handles individual image inference requests.
"""

import io
import json
import os
import pickle
import time

import numpy as np
from PIL import Image

from room_finder import get_device, load_fb_model, get_norm_transform, embed_pil


from dataclasses import dataclass


@dataclass
class InferencePayload:
    image_bytes: bytes
    mime_type:   str = "image/jpeg"


@dataclass
class InferenceResult:
    predicted_room: str
    confidence:     float
    method:         str
    timing_ms:      dict[str, float]
    all_scores:     dict[str, float]  # top-5 rooms by similarity


class RoomInferenceHandler:
    def __init__(self, output_dir: str, method: str = "kmeans"):
        self.output_dir = output_dir
        self.method     = method
        self._load()

    def _load(self):
        meta_path = os.path.join(self.output_dir, "metadata.json")
        if os.path.isfile(meta_path):
            with open(meta_path) as f:
                self.meta = json.load(f)
        else:
            self.meta = {}

        if self.method == "kmeans":
            index_path  = os.path.join(self.output_dir, "rooms_clusters.npz")
            frames_path = os.path.join(self.output_dir, "rooms_clusters_frames.pkl")
        else:
            index_path  = os.path.join(self.output_dir, "rooms_index.npz")
            frames_path = os.path.join(self.output_dir, "rooms_index_frames.pkl")

        if not os.path.isfile(index_path):
            raise RuntimeError(f"Index not found: {index_path} — run 'train' first")

        data = np.load(index_path, allow_pickle=True)
        self.X_index      = data["embeddings"]
        self.index_labels = list(data["labels"])

        self.index_frames = None
        if os.path.isfile(frames_path):
            with open(frames_path, "rb") as f:
                self.index_frames = pickle.load(f)

        model_name    = self.meta.get("model", "dinov2_vits14")
        self.device   = get_device()
        self.model    = load_fb_model(model_name, self.device)
        self.transform = get_norm_transform()

        print(f"[room_inference] loaded {len(self.index_labels)} vectors "
              f"({len(set(self.index_labels))} rooms) via {self.method}")

    def __call__(self, payload: InferencePayload) -> dict:
        t0 = time.perf_counter()
        img = Image.open(io.BytesIO(payload.image_bytes)).convert("RGB")
        t_load = time.perf_counter() - t0

        t1 = time.perf_counter()
        Q = embed_pil([img], self.model, self.transform, self.device)  # [1, D]
        t_embed = time.perf_counter() - t1

        t2 = time.perf_counter()
        sims = (Q @ self.X_index.T)[0]  # [N]
        nn_idx = int(sims.argmax())
        t_search = time.perf_counter() - t2

        predicted   = self.index_labels[nn_idx]
        confidence  = float(sims[nn_idx])

        # aggregate top-5 unique rooms by max similarity
        labels_arr = np.array(self.index_labels)
        unique_rooms = sorted(set(self.index_labels))
        room_scores = {r: float(sims[labels_arr == r].max()) for r in unique_rooms}
        top5 = dict(sorted(room_scores.items(), key=lambda x: x[1], reverse=True)[:5])

        return {
            "predicted_room": predicted,
            "confidence":     round(confidence, 4),
            "method":         self.method,
            "top5":           {r: round(s, 4) for r, s in top5.items()},
            "timing_ms": {
                "load":   round(t_load  * 1000, 2),
                "embed":  round(t_embed * 1000, 2),
                "search": round(t_search * 1000, 3),
                "total":  round((t_load + t_embed + t_search) * 1000, 2),
            },
        }
