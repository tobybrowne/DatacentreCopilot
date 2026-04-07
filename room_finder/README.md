# room_finder

Room classification using DINOv2 embeddings and nearest-neighbour search.

## Data layout

Training data should be a directory of room subdirectories, each containing one or more `.mp4` files:

```
rooms/
  kitchen/
    video1.mp4
  bedroom/
    video1.mp4
    video2.mp4
  ...
```

Test data should follow the same structure as training data — subdirectories named after rooms containing images (`.jpg`, `.png`, `.bmp`, `.webp`):

```
test_data/
  kitchen/
    frame1.jpg
  bedroom/
    frame1.jpg
    frame2.jpg
  ...
```

## Train

```
python main.py train <output_dir> <rooms_dir>
```

Samples frames from each room's videos, embeds them with DINOv2, and saves the index. Also generates a t-SNE plot of the embedding space.

Outputs written to `output_dir/`:
- `rooms_index.npz` — embeddings + labels
- `rooms_index_frames.pkl` — sampled frames for nearest-neighbour visualisation
- `tsne.png` — t-SNE plot coloured by room

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--sample-fps` | `2.0` | Frames per second to sample from videos |
| `--model` | `dinov2_vits14` | DINOv2 variant (`dinov2_vits14/16/32/64`) |
| `--tsne-perplexity` | `30.0` | t-SNE perplexity |
| `--pca-dims` | `50` | PCA dimensionality reduction before t-SNE |

## Test

```
python main.py test <output_dir> <test_dir>
```

Classifies each image in `test_dir` against the trained index and computes accuracy. `output_dir` must be the same directory used during training. `test_dir` must use the same labelled-subdir structure as the training data.

Results are written to a timestamped subdir `output_dir/<YYYYMMDD_HHMMSS>/`:
- `predictions.png` — grid of query images vs nearest-neighbour training frames (green border = correct, red = wrong)
- `confusion_matrix.png` — per-room confusion matrix

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--model` | `dinov2_vits14` | Must match the model used during training |
