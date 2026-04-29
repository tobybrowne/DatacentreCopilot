class_name AppState
extends Node

## State machine root. Owns the shared progress indicator, forwards gesture
## signals to whichever state is active, and handles the global home gesture
## (which always returns to idle regardless of current state).
##
## main.gd instantiates this, injects managers via setup(), and calls
## transition_to() once to pick the initial state. After that, states drive
## their own transitions.

signal state_changed(from_name: String, to_name: String)

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

var _current: State = null
var _states: Dictionary = {}  # snake_case name → State


func setup(
	app_: Node3D,
	ui_panel_: ViewportPanel3D,
	gm: GestureManager,
	lm: LocationManager,
	am: AnchorManager,
	sm: SpaceManager,
	rm: RouteManager,
	nm: NoteManager,
	vm: VoiceManager,
	pi: ProgressIndicator,
) -> void:
	app                = app_
	ui_panel           = ui_panel_
	gesture_manager    = gm
	location_manager   = lm
	anchor_manager     = am
	space_manager      = sm
	route_manager      = rm
	note_manager       = nm
	voice_manager      = vm
	progress_indicator = pi

	for child in get_children():
		if child is State:
			_states[String(child.name)] = child
			child.app                = app
			child.ui_panel           = ui_panel
			child.gesture_manager    = gm
			child.location_manager   = lm
			child.anchor_manager     = am
			child.space_manager      = sm
			child.route_manager      = rm
			child.note_manager       = nm
			child.voice_manager      = vm
			child.progress_indicator = pi

	gesture_manager.pinch_started.connect(_on_pinch_started)
	gesture_manager.pinch_held.connect(_on_pinch_held)
	gesture_manager.pinch_completed.connect(_on_pinch_completed)
	gesture_manager.pinch_ended.connect(_on_pinch_ended)

	gesture_manager.home_gesture_held.connect(_on_home_held)
	gesture_manager.home_gesture_completed.connect(_on_home_completed)
	gesture_manager.home_gesture_ended.connect(func(_h: String): progress_indicator.clear())


func transition_to(state_name: String, data: Dictionary = {}) -> void:
	var next: State = _states.get(state_name)
	if next == null:
		push_warning("AppState: unknown state '%s'" % state_name)
		return
	if _current == next:
		return
	var from_name: String = String(_current.name) if _current else ""
	if _current:
		_current.exit()
	_current = next
	print("AppState: → ", state_name)
	_current.enter(data)
	state_changed.emit(from_name, state_name)


func current_name() -> String:
	return String(_current.name) if _current else ""


# ── Gesture forwarding ────────────────────────────────────────────────────────

func _on_pinch_started(hand: String, pos: Vector3) -> void:
	if _current: _current.on_pinch_started(hand, pos)

func _on_pinch_held(hand: String, pos: Vector3, duration: float) -> void:
	if _current: _current.on_pinch_held(hand, pos, duration)

func _on_pinch_completed(hand: String, pos: Vector3) -> void:
	if _current: _current.on_pinch_completed(hand, pos)

func _on_pinch_ended(hand: String) -> void:
	if _current: _current.on_pinch_ended(hand)


# ── Home gesture (global) ────────────────────────────────────────────────────

func _on_home_held(_hand: String, pos: Vector3, duration: float) -> void:
	progress_indicator.update(pos, minf(duration / gesture_manager.hold_time, 1.0), Color(0.2, 0.8, 1.0))


func _on_home_completed(_hand: String) -> void:
	progress_indicator.clear()
	go_home()


func go_home() -> void:
	PanelRouter.pop_to_root()
	transition_to("idle")


