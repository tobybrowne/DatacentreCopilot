# room_tsne.py — Room Place Recognition with DINOv2

A script for room-level place recognition using DINOv2 visual embeddings and nearest-neighbour retrieval.

## How It Works

### Embedding

Images (or video frames) are embedded using a pretrained **DINOv2** ViT model from Facebook Research. Patch tokens from the final layer are aggregated using **Generalized Mean (GeM) pooling**, then L2-normalized to produce a fixed-size descriptor per image.

#### 1. Preprocessing

Each image is resized to 256px on the shorter edge, center-cropped to 224×224, converted to a tensor, and normalized with ImageNet mean/std. This matches DINOv2's training distribution.

#### 2. DINOv2 Patch Tokens

DINOv2 is a Vision Transformer (ViT). It divides the 224×224 image into a grid of non-overlapping **14×14 pixel patches** — giving 256 patches per image. Each patch is projected into a high-dimensional embedding space (384-dim for `vits14`, up to 1536-dim for `vitg14`) and processed through transformer attention layers.

The script calls `model.get_intermediate_layers(tensor, n=1)[0]`, returning patch tokens from the **last transformer layer** with shape `[1, 256, D]` — 256 spatial embeddings, each D-dimensional. The `[CLS]` token (global summary token) is deliberately not used — patch tokens carry more local spatial detail, which matters for distinguishing visually similar rooms.

#### 3. GeM Pooling

To collapse `[1, 256, D]` → `[1, D]`, the script uses **Generalized Mean pooling**:

```
GeM(x) = mean(x^p)^(1/p)   where p=3.0
```

Compared to simple average pooling (p=1), GeM with p>1 suppresses near-zero activations and amplifies strong responses, making the descriptor more discriminative. It is a standard technique in image retrieval (used in NetVLAD, CosPlace, etc.).

#### 4. L2 Normalization

After pooling, the descriptor is L2-normalized:

```python
X = X / (np.linalg.norm(X, axis=1, keepdims=True) + 1e-8)
```

This maps all descriptors onto the unit hypersphere, so **cosine similarity becomes a dot product**. At query time the full similarity matrix `Q @ X_index.T` is computed in one matrix multiply — no explicit distance calculation needed.

#### Why this works for room recognition

DINOv2 was trained with self-supervised learning on diverse internet imagery. Its patch tokens capture semantic content (furniture, walls, lighting, textures) rather than just low-level edges. GeM pooling compresses this into a single vector that acts as a **visual fingerprint** of the scene. Rooms with distinct appearances cluster tightly in this space, enabling reliable nearest-neighbour retrieval even across different viewpoints or lighting conditions.

### Three Modes

#### `index` — Build the database

Scans a directory of rooms. Each room is a subdirectory containing one or more `.mp4` videos. Frames are sampled at a configurable rate (default: 2 fps), embedded with DINOv2, and saved to a `.npz` file alongside a `.pkl` of the raw PIL frames.

```
python room_tsne.py index --rooms-dir /path/to/Rooms --index-file rooms_index.npz
```

#### `tsne` — Visualize the index

Builds the index (same as above) then runs optional PCA dimensionality reduction followed by **t-SNE** to project embeddings into 2D. Produces a scatter plot coloured by room label, useful for checking whether the embedding space separates rooms cleanly.

```
python room_tsne.py tsne --rooms-dir /path/to/Rooms --out tsne.png
```

#### `query` — Predict room for new images

Loads a pre-built index, embeds query images from a directory, and finds the nearest neighbour in the index for each query using **cosine similarity** (fast dot product since vectors are L2-normalized). Reports the predicted room and similarity score, then saves a panel image showing each query paired with its nearest index frame.

```
python room_tsne.py query --index-file rooms_index.npz --query-dir /path/to/NewTest --out predictions.png
```

## Directory Structure

```
Rooms/
  kitchen/
    video1.mp4
  living_room/
    video1.mp4
    video2.mp4
  bedroom/
    video1.mp4

rooms_index.npz        ← saved embeddings + labels
rooms_index_frames.pkl ← saved PIL frames for visualisation
```

## Arguments

| Mode  | Argument            | Default           | Description                                  |
| ----- | ------------------- | ----------------- | -------------------------------------------- |
| all   | `--model`           | `dinov2_vits14`   | DINOv2 variant (vits14/vitb14/vitl14/vitg14) |
| index | `--rooms-dir`       | required          | Root directory containing room subdirs       |
| index | `--sample-fps`      | `2.0`             | Frames per second to sample from videos      |
| index | `--index-file`      | `rooms_index.npz` | Output path for the saved index              |
| tsne  | `--pca-dims`        | `50`              | PCA dimensions before t-SNE                  |
| tsne  | `--tsne-perplexity` | `30.0`            | t-SNE perplexity                             |
| query | `--index-file`      | required          | Path to pre-built `.npz` index               |
| query | `--query-dir`       | required          | Directory of query images                    |
| query | `--out`             | `predictions.png` | Output panel image path                      |

## Device Support

Automatically selects **MPS** (Apple Silicon), **CUDA**, or **CPU** in that order.
