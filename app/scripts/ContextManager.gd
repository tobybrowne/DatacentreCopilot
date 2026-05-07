extends Node

# ── Internal refs ─────────────────────────────────────────────────────────────
var _debounce_timer: SceneTreeTimer = null

# ── Context state ─────────────────────────────────────────────────────────────
var ctx_space:      Space = null
var ctx_app_state:  String = ""
var ctx_panel:      String = ""
var ctx_procedure:  Procedure = null
var ctx_step:       Step = null
var ctx_looking_at:  Asset = null
var ctx_interacted:  Asset = null


func setup() -> void:
	pass


# ── Setters ───────────────────────────────────────────────────────────────────

func set_space(space_id: String) -> void:
	ctx_space = await SupabaseManager.get_space(space_id)
	_schedule_update()


func set_app_state(name: String) -> void:
	ctx_app_state = name
	_schedule_update()


func set_panel(panel_id: String) -> void:
	ctx_panel = panel_id
	_schedule_update()


func set_looking_at(asset: Asset) -> void:
	ctx_looking_at = asset
	_schedule_update()


func set_procedure(procedure: Procedure) -> void:
	ctx_procedure = procedure
	_schedule_update()


func set_step(step: Step) -> void:
	ctx_step = step
	_schedule_update()



func set_interacted(asset: Asset) -> void:
	ctx_interacted = asset
	_schedule_update()


# ── Internal ──────────────────────────────────────────────────────────────────

func _schedule_update() -> void:
	if _debounce_timer:
		return
	_debounce_timer = get_tree().create_timer(1.0)
	_debounce_timer.timeout.connect(_flush)


func _serialise_asset(asset: Asset) -> String:
	if not asset:
		return "null"
	return JSON.stringify({
		"name":         asset.name,
		"asset_type":   asset.asset_type,
		"model_name":   asset.model_name,
		"manufacturer": asset.manufacturer,
	})


func _flush() -> void:
	_debounce_timer = null
	if not CopilotManager._is_connected:
		return
	var parts := PackedStringArray()
	parts.append("space: %s"      % (ctx_space.name if ctx_space else "null"))
	parts.append("app_state: %s"  % (ctx_app_state if ctx_app_state else "null"))
	parts.append("panel: %s"      % (ctx_panel if ctx_panel else "null"))
	parts.append("procedure: %s"  % (ctx_procedure.title if ctx_procedure else "null"))
	parts.append("step: %s"       % (ctx_step.text if ctx_step else "null"))
	parts.append("looking_at: %s" % (_serialise_asset(ctx_looking_at)))
	parts.append("interacted: %s" % (_serialise_asset(ctx_interacted)))
	var text := "[context update]\n" + "\n".join(parts)
	print("ContextManager: %s" % text)
	CopilotManager.inject_context(text)
