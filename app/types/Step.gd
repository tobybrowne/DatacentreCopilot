class_name Step

const TYPE_INSTRUCTION := "instruction"
const TYPE_GOTO        := "goto"

var id: String        = ""
var type: String      = TYPE_INSTRUCTION
var text: String      = ""
var anchor_id: String = ""
var log_id: String    = ""
var timer_duration: float  = 0.0
var timer_target_uuid: String = ""


static func from_value(v) -> Step:
	var step := Step.new()
	if v is String:
		# Backwards-compat: bare strings are plain instructions.
		step.type = TYPE_INSTRUCTION
		step.text = v
	elif v is Dictionary:
		step.id        = v.get("id", "")
		step.type      = v.get("type", TYPE_INSTRUCTION)
		step.text      = v.get("text", "")
		step.anchor_id = v.get("anchor_id", "")
		step.log_id    = v.get("log_id", "")
		var timer: Variant = v.get("timer", null)
		if timer is Dictionary:
			step.timer_duration    = float(timer.get("duration", 0.0))
			step.timer_target_uuid = str(timer.get("target_uuid", ""))
	return step


func has_timer() -> bool:
	return timer_duration > 0.0 and not timer_target_uuid.is_empty()
