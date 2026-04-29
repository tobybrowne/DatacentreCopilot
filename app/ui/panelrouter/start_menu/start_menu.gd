extends BasePanel


func _ready() -> void:
	await AuthManager.wait_for_auth()
	$VBoxContainer/ProcedureMode.pressed.connect(func(): navigate_to.emit("procedures", {}))
	$VBoxContainer/MapMode.pressed.connect(func(): navigate_to.emit("map", {}))
	$VBoxContainer/SpaceManager.pressed.connect(func(): PanelRouter.request("open_space_manager", {}))
