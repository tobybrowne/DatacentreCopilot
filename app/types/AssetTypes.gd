class_name AssetTypes

const ICON_BASE := "res://ui/standalone/asset_fab/icons/"

const _ICON_MAP := {
	"ups":            "UPS",
	"generator":      "Generator",
	"ats":            "AutomaticTransferSwitch",
	"sts":            "transfer_switch",
	"mts":            "transfer_switch",
	"pdu":            "PDU",
	"rpp":            "RemotePowerPanel",
	"switchgear":     "switchgear",
	"switchboard":    "switchboard",
	"msb":            "switchboard",
	"panelboard":     "switchboard1",
	"breaker":        "Breaker",
	"transformer":    "TransformerVoltageDown",
	"battery_string": "battery_string",
	"battery_charger":"battery_charger",
	"fuel_tank":      "fuel_tank",
	"vfd":            "frequency",
	"humidifier":     "Humidifier",
	"dehumidifier":   "dehumidifier",
	"ahu":            "AirHandlingUnit",
	"acch":           "ACUnit",
	"crah":           "crah",
	"cooling_tower":  "cooling_tower",
	"dry_cooler":     "dry_cooler",
	"heat_exchanger": "heat_exchanger",
	"duct_heater":    "duct_heater",
	"heat_trace":     "heat_trace",
	"pump":           "Pump",
	"condensate_pump":"Pump",
	"exhaust_fan":    "fan",
	"vesda":          "vesda",
	"fire_system":    "fire_extinguisher",
}

# Asset types that carry load/volt live data
const POWER_TYPES := [
	"ups", "generator", "ats", "sts", "mts",
	"pdu", "rpp", "transformer", "vfd",
]

# Asset types that carry temperature/load live data
const COOLING_TYPES := [
	"ahu", "acch", "crah", "cooling_tower", "dry_cooler", "heat_exchanger",
]


static func icon_path(asset_type: String) -> String:
	var name: String = _ICON_MAP.get(asset_type, "")
	if name.is_empty():
		return ""
	return ICON_BASE + name + ".svg"


static func is_power_type(asset_type: String) -> bool:
	return asset_type in POWER_TYPES

static func is_cooling_type(asset_type: String) -> bool:
	return asset_type in COOLING_TYPES
