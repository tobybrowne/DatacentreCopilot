class_name Gauge
extends Control

var label_text: String = ""
var value: float = 0.0
var max_value: float = 100.0
var unit: String = ""

var color_low  := Color(0.25, 0.85, 0.45)
var color_mid  := Color(1.0,  0.75, 0.1)
var color_high := Color(0.9,  0.2,  0.2)

const _START := TAU / 3.0
const _SWEEP := TAU * 5.0 / 6.0
const _WIDTH := 8.0
const _SEGS  := 64


func _draw() -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.55
	var r  := minf(size.x, size.y) * 0.5 - _WIDTH

	draw_arc(Vector2(cx, cy), r, _START, _START + _SWEEP, _SEGS, Color(1, 1, 1, 0.12), _WIDTH, true)

	var frac := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
	if frac > 0.0:
		draw_arc(Vector2(cx, cy), r, _START, _START + _SWEEP * frac, _SEGS, _fill_color(frac), _WIDTH, true)

	var val_str := str(snappedf(value, 0.1)) + unit
	draw_string(ThemeDB.fallback_font, Vector2(cx - 40, cy + 18), val_str,
		HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color(1, 1, 1, 0.95))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 50, size.y - 4), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, 100, 16, Color(0.7, 0.7, 0.8, 1.0))


func _fill_color(frac: float) -> Color:
	if frac < 0.6:
		return color_low.lerp(color_mid, frac / 0.6)
	return color_mid.lerp(color_high, (frac - 0.6) / 0.4)


static func make(lbl: String, val: float, max_val: float, unit_str: String) -> Gauge:
	var g := Gauge.new()
	g.label_text = lbl
	g.value      = val
	g.max_value  = max_val
	g.unit       = unit_str
	g.custom_minimum_size = Vector2(140, 140)
	return g
