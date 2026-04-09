extends BasePanel


func _ready() -> void:
	$VBoxContainer/ProcedureMode.pressed.connect(func(): navigate_to.emit("procedures", {}))
	$VBoxContainer/MapMode.pressed.connect(func(): navigate_to.emit("map", {}))
	$VBoxContainer/SpaceManager.pressed.connect(func(): navigate_to.emit("space_manager", {}))
