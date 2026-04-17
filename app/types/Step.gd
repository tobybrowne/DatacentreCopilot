class_name Step

const TYPE_INSTRUCTION := "instruction"
const TYPE_GOTO        := "goto"

var type: String      = TYPE_INSTRUCTION
var text: String      = ""
var anchor_id: String = ""  # only populated for TYPE_GOTO


static func from_value(v) -> Step:
	var step := Step.new()
	if v is String:
		# Backwards-compat: bare strings are plain instructions.
		step.type = TYPE_INSTRUCTION
		step.text = v
	elif v is Dictionary:
		step.type      = v.get("type", TYPE_INSTRUCTION)
		step.text      = v.get("text", "")
		step.anchor_id = v.get("anchor_id", "")
	return step
