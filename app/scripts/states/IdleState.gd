class_name IdleState
extends State

## Home / menu state — user is browsing panels, nothing is calibrated or active.
## Owns the intents that transition *out* of idle, plus the async room-resolution
## handshake with LocationManager that some of those transitions depend on.
##
## Entered on boot, and whenever the user does the home gesture or says "go home".
##
## ── Deferred-transition flow ──────────────────────────────────────────────────
## Some intents ("navigate", "start_procedure" when not yet calibrated) can't
## transition immediately — we first need to resolve which room the user is in.
## Those intents call _begin() to remember what they *want* to do, then ask
## LocationManager.request_navigation(). The answer arrives one of two ways:
##
##   navigation_ready(space_id)      → room is known, _finish() directly.
##   space_picker_needed(spaces)     → user must pick → space_picker panel →
##                                     start_nav_for_{space,procedure} intent →
##                                     _finish() with the picked space.
##
## Both paths converge on _finish(), which merges the resolved space into the
## original pending data and performs the transition.

# The transition waiting on room-resolution, or {} if none is pending.
#   target: "navigating" | "procedure"
#   data:   extras to pass to the target state's enter() (e.g. {"procedure": proc})
var _pending: Dictionary = {}


func enter(_data: Dictionary) -> void:
	_pending = {}
	ui_panel.visible = true
	PanelRouter.action_requested.connect(_on_action)
	location_manager.space_picker_needed.connect(_on_space_picker_needed)
	location_manager.navigation_ready.connect(_on_navigation_ready)


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)
	location_manager.space_picker_needed.disconnect(_on_space_picker_needed)
	location_manager.navigation_ready.disconnect(_on_navigation_ready)


# Dispatched on every PanelRouter.request() from any 2D panel.
func _on_action(action: String, data: Dictionary) -> void:
	match action:
		# space_picker "localise" mode — prime a space without transitioning.
		"localise_space":
			var space := data.get("space") as Space
			if space and await location_manager.ensure_space_local(space):
				await location_manager.localize_to_space(space.id)

		# space_info "edit anchors" — AnchorEditingState handles the load flow.
		"localise_space_load_anchors":
			_machine().transition_to("anchor_editing", {"space": data.get("space")})

		# building_info "navigate" — room unknown, defer until resolved.
		"navigate":
			_begin("navigating", {}, data.get("building_id", ""))

		# procedure_panel "start" — if calibrated go now, else defer.
		"start_procedure":
			var proc := data.get("procedure") as Procedure
			if not proc:
				return
			if location_manager._calibrated:
				_machine().transition_to("procedure", {"procedure": proc})
			else:
				_begin("procedure", {"procedure": proc}, proc.building_id)

		# space_picker tapped — download map, kick off calibration, wait for it to
		# complete, then transition. pre_calibrated tells the target state to skip
		# its own calibrate_to_space call since it's already done.
		"start_nav_for_space", "start_nav_for_procedure":
			var space := data.get("space") as Space
			if not space:
				return
			if not await location_manager.ensure_space_local(space):
				return
			location_manager.calibrate_to_space(space.id)
			await location_manager.calibrated
			_finish({"space_id": space.id, "pre_calibrated": true})


# Step 1 of deferred transition: remember the target, kick off async resolution.
func _begin(target: String, data: Dictionary, building_id: String) -> void:
	_pending = {"target": target, "data": data}
	location_manager.request_navigation(building_id)


# Step 2: merge the resolved room into the pending data and transition.
# Called from _on_navigation_ready (direct resolution) or the space-picker
# actions above (user-picked resolution).
func _finish(resolved: Dictionary) -> void:
	if _pending.is_empty():
		return
	var target: String = _pending["target"]
	var data: Dictionary = (_pending["data"] as Dictionary).duplicate()
	data.merge(resolved)
	_pending = {}
	_machine().transition_to(target, data)


# LocationManager: multiple candidate rooms — push picker. Its mode tells it
# which intent to fire when the user taps; both end up at _finish().
func _on_space_picker_needed(spaces: Array[Space]) -> void:
	var mode := "procedure" if _pending.get("target", "") == "procedure" else "navigate"
	PanelRouter.push("space_picker", {"spaces": spaces, "mode": mode})


# LocationManager: room already known — resume directly, no picker needed.
func _on_navigation_ready(space_id: String) -> void:
	_finish({"space_id": space_id})


func _machine() -> AppState:
	return get_parent() as AppState
