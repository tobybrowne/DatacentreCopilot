Something like this usually means the headset tried to pull spatial anchors before being localised properly. Since we haven't added proper monitoring yet, just aim the headset at a better starting position.

```
WARNING: Failed to load ML2 spatial anchor: 3dd09a0d-1216-7018-a133-c7f67964cac4
03-27 20:42:30.253  7327  7364 E godot   :    at: _on_anchor_loaded (plugin/src/main/cpp/classes/openxr_ml_spatial_anchor_manager.cpp:302)
03-27 20:42:30.253  7327  7364 I godot   : AnchorManager: load failed for 3dd09a0d-1216-7018-a133-c7f67964cac4 — retrying in 3.0s (attempt 2/5)
03-27 20:42:33.258  7327  7364 E godot   : WARNING: xrCreateSpatialAnchorsCompleteML failed.
03-27 20:42:33.258  7327  7364 E godot   :    at: _on_process (plugin/src/main/cpp/extensions/openxr_ml_spatial_anchors_extension.cpp:161)
03-27 20:42:33.258  7327  7364 E godot   : WARNING: XR_ERROR_VALIDATION_FAILURE
03-27 20:42:33.258  7327  7364 E godot   :    at: _on_process (plugin/src/main/cpp/extensions/openxr_ml_spatial_anchors_extension.cpp:162)
03-27 20:42:33.258  7327  7364 E godot   : WARNING: Failed to load ML2 spatial anchor: 9014cc34-7a69-7018-b1a8-f52944b34d94
03-27 20:42:33.258  7327  7364 E godot   :    at: _on_anchor_loaded (plugin/src/main/cpp/classes/openxr_ml_spatial_anchor_manager.cpp:302)
03-27 20:42:33.258  7327  7364 I godot   : AnchorManager: load failed for 9014cc34-7a69-7018-b1a8-f52944b34d94 — retrying in 3.0s (attempt 3/5)
03-27 20:42:33.258  7327  7364 E godot   : WARNING: xrCreateSpatialAnchorsCompleteML failed.
```
