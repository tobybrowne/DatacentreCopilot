extends BasePanel

func init(data: Dictionary) -> void:
	var msg: String = data.get("message", "Authentication failed. Check credentials and restart.")
	$MarginContainer/VBoxContainer/Message.text = msg
