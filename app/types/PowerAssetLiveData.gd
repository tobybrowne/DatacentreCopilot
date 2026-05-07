class_name PowerAssetLiveData

var load_percent: float = 0.0   # 0–100
var input_volt: float   = 0.0   # volts
var output_volt: float  = 0.0   # volts

static func from_dict(data: Dictionary) -> PowerAssetLiveData:
	var d := PowerAssetLiveData.new()
	d.load_percent = float(data.get("load_percent", 0.0))
	d.input_volt   = float(data.get("input_volt",   0.0))
	d.output_volt  = float(data.get("output_volt",  0.0))
	return d

static func dummy() -> PowerAssetLiveData:
	var d := PowerAssetLiveData.new()
	d.load_percent = 67.0
	d.input_volt   = 230.0
	d.output_volt  = 226.0
	return d
