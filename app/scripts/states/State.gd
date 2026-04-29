class_name State
extends Node

## Base class for app states. The AppState machine injects manager references
## before calling enter(), and forwards gesture signals to the currently
## active state. Subclasses override the lifecycle and gesture hooks they need.

var app: Node3D
var ui_panel: ViewportPanel3D
var gesture_manager: GestureManager
var location_manager: LocationManager
var anchor_manager: AnchorManager
var space_manager: SpaceManager
var route_manager: RouteManager
var note_manager: NoteManager
var voice_manager: VoiceManager
var progress_indicator: ProgressIndicator

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func enter(_data: Dictionary) -> void:
	pass

func exit() -> void:
	pass

# ── Gesture hooks ─────────────────────────────────────────────────────────────

func on_pinch_started(_hand: String, _position: Vector3) -> void:
	pass

func on_pinch_held(_hand: String, _position: Vector3, _duration: float) -> void:
	pass

func on_pinch_completed(_hand: String, _position: Vector3) -> void:
	pass

func on_pinch_ended(_hand: String) -> void:
	pass

# ── Context menu helpers (shared by nav-like states) ──────────────────────────
#
# Right-pinch-hold opens a radial context menu, pinch-end selects the hovered
# item. Helpers are opt-in — states call them from their own pinch handlers.

const _CONTEXT_HOLD_TIME := 1.5
const _CONTEXT_COLOR     := Color(0.2, 0.8, 1.0)
const _CONTEXT_MENU_SCENE := preload("res://ui/standalone/context_menu/context_menu_3d.tscn")

var _context_menu: ViewportPanel3D = null
var _context_pending := false
var _context_world_pos := Vector3.ZERO


func _context_update_hold(position: Vector3, duration: float) -> void:
	if _context_menu == null:
		progress_indicator.update(position, minf(duration / _CONTEXT_HOLD_TIME, 1.0), _CONTEXT_COLOR)
	if not _context_pending and duration >= _CONTEXT_HOLD_TIME:
		_context_pending = true
		progress_indicator.clear()
		_context_open(position)


## Returns true if the pinch end was consumed by the context menu. The first
## release after opening is swallowed (pending); subsequent releases that miss
## a button dismiss the menu. Button taps fire item_selected directly via the
## same ray → mouse-event path as every other panel.
func _context_handle_end() -> bool:
	progress_indicator.clear()
	if _context_pending:
		_context_pending = false
		return true
	if _context_menu != null:
		_context_close()
		return true
	return false


func _context_open(world_pos: Vector3) -> void:
	_context_world_pos = world_pos
	_context_close()
	_context_menu = _CONTEXT_MENU_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_context_menu)
	_context_menu.global_position = world_pos
	var inner := _context_menu.get_panel() as ContextMenu
	if inner:
		inner.item_selected.connect(_on_context_item_selected)


func _on_context_item_selected(_idx: int, label: String) -> void:
	var pos := _context_world_pos
	_context_close()
	if label == "Add Sticky Note":
		KeyboardManager.open("Add a note", "", func(text: String) -> void:
			if not text.is_empty():
				note_manager.create_note_at(pos, text)
		)


func _context_close() -> void:
	if _context_menu:
		_context_menu.queue_free()
		_context_menu = null
