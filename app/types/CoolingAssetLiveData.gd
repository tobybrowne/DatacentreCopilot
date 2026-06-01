class_name CoolingAssetLiveData

var temperature: float  = 0.0   # °C - supply temperature
var load_percent: float = 0.0   # 0–100

static func from_dict(data: Dictionary) -> CoolingAssetLiveData:
	var d := CoolingAssetLiveData.new()
	d.temperature  = float(data.get("temperature",  0.0))
	d.load_percent = float(data.get("load_percent", 0.0))
	return d

static func dummy() -> CoolingAssetLiveData:
	var d := CoolingAssetLiveData.new()
	d.temperature  = 18.0
	d.load_percent = 45.0
	return d
