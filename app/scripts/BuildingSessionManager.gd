class_name BuildingSessionManager
extends Node

# Singleton reference — set on _ready, accessible globally
static var instance: BuildingSessionManager = null

var building_id: String = ""
var spaces: Array[Space] = []
var space_offsets: Dictionary = {}  # space_id → Transform3D
var anchors: Array[Anchor] = []

# Asset data — keyed by anchor_id / asset_id / manual_id
var asset_rows: Dictionary = {}       # anchor_id → raw asset dict (with asset_models join)
var manuals: Dictionary = {}          # manual_id → {title, url}
var logged_asset_ids: Dictionary = {} # asset_id → true
var live_data: Dictionary = {}        # asset_id → live data dict

signal loaded(building_id: String)


func _ready() -> void:
	instance = self


func is_loaded_for(bid: String) -> bool:
	return building_id == bid and not anchors.is_empty()


func load_for_space(space_id: String) -> void:
	# Resolve spaces / building_id
	var t0 := Time.get_ticks_msec()
	var sibling_spaces: Array[Space] = await SupabaseManager.get_sibling_spaces(space_id)
	if sibling_spaces.is_empty():
		push_warning("BuildingSessionManager: no building found for space " + space_id)
		return

	var bid: String = sibling_spaces[0].building_id
	if is_loaded_for(bid):
		return  # already loaded for this building

	clear()
	building_id = bid
	spaces = sibling_spaces
	for s in spaces:
		space_offsets[s.id] = s.offset_transformation
	print("[BSM] spaces: ", Time.get_ticks_msec() - t0, "ms")

	# Anchors
	var t1 := Time.get_ticks_msec()
	var space_ids: Array[String] = []
	for s in spaces:
		space_ids.append(s.id)
	anchors = await SupabaseManager.get_anchors_for_spaces(space_ids)
	print("[BSM] anchors (", anchors.size(), "): ", Time.get_ticks_msec() - t1, "ms")

	# Assets for TYPE_ASSET anchors
	var t2 := Time.get_ticks_msec()
	var asset_anchor_ids: Array[String] = []
	for anchor in anchors:
		if anchor.anchor_type == Anchor.TYPE_ASSET:
			asset_anchor_ids.append(anchor.id)

	if not asset_anchor_ids.is_empty():
		asset_rows = await SupabaseManager.get_assets_for_anchors(asset_anchor_ids)

		var manual_ids: Array[String] = []
		var asset_ids: Array[String] = []
		for row in asset_rows.values():
			var aid: String = row.get("id", "")
			if not aid.is_empty():
				asset_ids.append(aid)
			var model = row.get("asset_models", null)
			if model is Dictionary:
				var mid: String = model.get("manual_id", "")
				if not mid.is_empty() and mid not in manual_ids:
					manual_ids.append(mid)

		if not manual_ids.is_empty():
			manuals = await SupabaseManager.get_manuals_for_ids(manual_ids)
		if not asset_ids.is_empty():
			logged_asset_ids = await SupabaseManager.get_logged_asset_ids(asset_ids)
			live_data        = await SupabaseManager.get_latest_live_data(asset_ids)
	print("[BSM] assets + manuals + logs + live data: ", Time.get_ticks_msec() - t2, "ms")
	print("[BSM] total load: ", Time.get_ticks_msec() - t0, "ms")

	loaded.emit(building_id)


func invalidate_anchors() -> void:
	anchors.clear()


# ── Lookups ───────────────────────────────────────────────────────────────────

func get_asset_row(anchor_id: String) -> Dictionary:
	return asset_rows.get(anchor_id, {})

func get_manual(manual_id: String) -> Dictionary:
	return manuals.get(manual_id, {})

func asset_has_logs(asset_id: String) -> bool:
	return logged_asset_ids.has(asset_id)

func get_live_data(asset_id: String) -> Dictionary:
	return live_data.get(asset_id, {})


# ── Private ───────────────────────────────────────────────────────────────────

func clear() -> void:
	building_id = ""
	spaces.clear()
	space_offsets.clear()
	anchors.clear()
	asset_rows.clear()
	manuals.clear()
	logged_asset_ids.clear()
	live_data.clear()
