// Depth-only occluder for real-world mesh.
// Writes to the depth buffer so AR content behind real walls is properly occluded,
// but contributes nothing to the color buffer so passthrough shows through.
shader_type spatial;
render_mode depth_draw_always, unshaded, cull_disabled;

void fragment() {
	ALPHA = 0.0;
}
