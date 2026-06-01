// Depth-only occluder for bounding-box fallback walls.
// Discards fragments closer than tof_range so the ToF world mesh is trusted
// for near geometry (valid holes like open doors stay open). Beyond the range
// the wall writes depth to cover areas the ToF sensor cannot reach.
shader_type spatial;
render_mode depth_draw_always, unshaded, cull_disabled;

uniform float tof_range : hint_range(1.0, 10.0) = 4.5;

void fragment() {
	// VERTEX is in view space - length() gives distance from camera.
	if (length(VERTEX) < tof_range) {
		discard;
	}
	ALPHA = 0.0;
}
