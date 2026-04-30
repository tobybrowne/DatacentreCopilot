# Handles the "idle state", the behaviour when the app is in the starting menus
# most of the logic is handled by the UI panels and routers, so this really just needs to handle
# the transition into the other UI states

class_name IdleState
extends State

var _pending_procedure: Procedure = null

func enter(_data: Dictionary) -> void:
	ui_panel.visible = true
	PanelRouter.action_requested.connect(_on_action)


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)


func _on_action(action: String, data: Dictionary) -> void:
	match action:
		"start_anchor_edit":
			# anchor editing "on_enter" will handle loading the space and anchors
			_machine().transition_to(AppState.States.ANCHOR_EDITING, {"space": data.get("space")})

		# "delete_space_local" disabled — PW_MAP is signature-protected

		"open_space_manager":
			PanelRouter.push("space_manager", {"space_manager": space_manager})

		"start_navigate":
			var building_id: String = data.get("building_id", "")
			var spaces: Array[Space] = await SupabaseManager.get_spaces_for_building(building_id)
			PanelRouter.push("space_picker", {"spaces": spaces, "mode": "start_navigate", "space_manager": space_manager})

		"start_procedure":
			var proc := data.get("procedure") as Procedure
			if not proc:
				return
			_pending_procedure = proc
			var spaces: Array[Space] = await SupabaseManager.get_spaces_for_building(proc.building_id)
			PanelRouter.push("space_picker", {"spaces": spaces, "mode": "procedure", "space_manager": space_manager})

		# called by space picker when a location is chosen
		"start_nav_for_space":
			var space := data.get("space") as Space
			if not space:
				return
			if not await space_manager.ensure_space_local(space):
				return
			location_manager.calibrate_to_space(space.id)
			await location_manager.calibrated
			_machine().transition_to(AppState.States.NAVIGATING, {"space_id": space.id, "pre_calibrated": true})

		# called by space picker when a location is chosen
		"start_nav_for_procedure":
			var space := data.get("space") as Space
			if not space or not _pending_procedure:
				return
			if not await space_manager.ensure_space_local(space):
				return
			location_manager.calibrate_to_space(space.id)
			await location_manager.calibrated
			_machine().transition_to(AppState.States.PROCEDURE, {"procedure": _pending_procedure, "space_id": space.id, "pre_calibrated": true})
			_pending_procedure = null


func _machine() -> AppState:
	return get_parent() as AppState
