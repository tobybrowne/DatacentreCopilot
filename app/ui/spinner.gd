class_name Spinner
extends Control

@export var color: Color = Color.WHITE
@export var speed: float = 1.5        # rotations per second
@export var thickness: float = 3.0
@export var arc_degrees: float = 270.0

var _angle: float = 0.0


func _process(delta: float) -> void:
	_angle += speed * TAU * delta
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := minf(size.x, size.y) / 2.0 - thickness
	draw_arc(center, radius, _angle, _angle + deg_to_rad(arc_degrees), 32, color, thickness, true)
