Anchor Types

Each Anchor has two key flags:

- is_reference — a calibration anchor, placed once manually with a known position in the 3D model (GLB space)
- source — either "headset" (placed via ML2) or "desktop" (placed via the desktop app, no ML2 UUID)  


Startup / Loading

On XR session start, AnchorManager.\_load_anchors_from_db() fetches all anchors from Supabase and splits them:

- Reference anchors with a glb_position → tell ML2 to load them; they'll be used for calibration
- Headset content anchors → tell ML2 to load them for per-frame tracking
- Desktop content anchors → queue them; they'll be placed once calibration is ready  


Calibration (Kabsch algorithm)

This is the core of the system. The problem: ML2 tracks anchors in local/headset space, but content is authored in GLB model space. To place content correctly, you need a transform between the two.

As each reference anchor is tracked by ML2, a pair is recorded:

- glb_position (from DB) → where it is in the 3D model
- anchor_node.position (from ML2) → where it is in the physical room  


Once ≥3 pairs are accumulated, Kabsch.compute() runs:

1. Computes centroids of both point clouds
2. Builds a cross-covariance matrix H
3. Uses Horn's quaternion method (Jacobi eigenvalue iteration) to find the optimal rotation
4. Returns a Transform3D that maps GLB space → local headset space  


Content Placement

New headset anchor placed by user:

- ML2 fires \_on_anchor_tracked(is_new=true)
- Saved to Supabase immediately
- Its glb_position is computed by inverse-transforming its local position back through the calibration: calibration.affine_inverse() \* local_pos
- If calibration isn't ready yet, it's queued in \_pending_save and resolved once calibration runs  


Desktop-placed anchor materialised on headset:

- Forward-transform its stored glb_position through calibration: calibration \* glb_position
- A static marker is placed at that local position (orange = desktop, blue = headset, yellow = reference)  


Summary Flow

Supabase DB  
 └─ anchors (id, name, source, is_reference, glb_position)
│  
 ▼
AnchorManager.load()  
 ├─ reference anchors → ML2 load → Kabsch pairs → calibration Transform3D  
 ├─ headset anchors → ML2 load → tracked per-frame  
 └─ desktop anchors → queued → placed via calibration once ready

User places anchor → ML2 → local_pos → inverse calibration → glb_position → Supabase

The key insight is that GLB space is the canonical coordinate system — all positions are stored relative to the 3D model, and the Kabsch calibration bridges that to whatever physical space the headset happens to
be in each session.
