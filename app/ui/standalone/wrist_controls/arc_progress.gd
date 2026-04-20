extends Control

var progress: float = 0.0 :
	set(v):
		progress = v
		queue_redraw()

func _draw() -> void:
	if progress <= 0.0:
		return
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 3.0
	var end_angle := -PI / 2.0 + TAU * progress
	draw_arc(c, r, -PI / 2.0, end_angle, 64, Color.WHITE, 4.0, true)
