extends Node

var _registry: Dictionary = {}  # asset_id → AssetAnchorMarker
var _rt_client: RealtimeClient = null
var _channel: RealtimeChannel = null


func _ready() -> void:
	_rt_client = Supabase.realtime.client()
	_channel = _rt_client.channel("public", "asset_live_data")
	_channel.on("insert", _on_insert)
	_rt_client.connected.connect(_on_connected)
	_rt_client.connect_client()


func _on_connected() -> void:
	_channel.subscribe()


func register(asset_id: String, marker: Node) -> void:
	_registry[asset_id] = marker


func deregister(asset_id: String) -> void:
	_registry.erase(asset_id)


func fetch_latest(asset_ids: Array) -> void:
	if asset_ids.is_empty():
		return
	var ids := PackedStringArray(asset_ids)
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("latest_asset_live_data").select().In("asset_id", ids)
	).completed
	if task.error != null or task.data == null:
		return
	for row in task.data:
		_dispatch(row)


func _on_insert(record: Dictionary, _ch: RealtimeChannel) -> void:
	_dispatch(record)


func _dispatch(record: Dictionary) -> void:
	var asset_id: String = record.get("asset_id", "")
	if _registry.has(asset_id):
		_registry[asset_id].on_live_data(record)
