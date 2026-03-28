# Godot Panel System

Each UI panel implements a 2D UI in a `.tscn` file, something like `procedure_panel.tscn` or `step_viewer.tscn`.
This defines the components of the UI: labels, images, etc..
The logic associated with the UI is then defined in the matching `.gd` file.

Each of these 2D scenes is part of a 3D scene which extends `ViewportPanel3D`, this is a wrapper which basically adds this 2D UI into the 3D world by:

- Creating a `SubViewPort` and instantiating the 2D scene into it.
- Creating a `QuadMesh` (a flat rectangle in 3D space) and setting it's texture to the output of the `SubViewPort`.

It handles all the XR-y things you would expect:

- In `_process()` it reads the camera position and moves the panel accordingly.
- In `_checkPoke()` it projects finger positions and converts them to mouse events on the 2D UI.
