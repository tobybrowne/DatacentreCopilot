class_name PoseRec

const JOINT_COUNT := 26

var timestamp_msec: int
var head_transform: Transform3D
var left_joints:    Array[Transform3D]
var right_joints:   Array[Transform3D]
var left_tracked:   bool = true
var right_tracked:  bool = true

func _init() -> void:
	left_joints.resize(JOINT_COUNT)
	right_joints.resize(JOINT_COUNT)


static func _transform_from_array(arr: Array, offset: int) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(arr[offset + 0], arr[offset + 1], arr[offset + 2]),
			Vector3(arr[offset + 3], arr[offset + 4], arr[offset + 5]),
			Vector3(arr[offset + 6], arr[offset + 7], arr[offset + 8])
		),
		Vector3(arr[offset + 9], arr[offset + 10], arr[offset + 11])
	)


static func from_flat_row(row: Array) -> PoseRec:
	var rec := PoseRec.new()
	rec.timestamp_msec = int(row[0])
	var off := 1
	rec.head_transform = _transform_from_array(row, off)
	off += 12
	for i in JOINT_COUNT:
		rec.left_joints[i] = _transform_from_array(row, off)
		off += 12
	for i in JOINT_COUNT:
		rec.right_joints[i] = _transform_from_array(row, off)
		off += 12
	if row.size() > off + 1:
		rec.left_tracked  = int(row[off])     != 0
		rec.right_tracked = int(row[off + 1]) != 0
	return rec


static func frames_from_bytes(data: PackedByteArray) -> Array[PoseRec]:
	var parsed = JSON.parse_string(data.get_string_from_utf8())
	if not parsed or not parsed.has("frames"):
		return []
	var result: Array[PoseRec] = []
	for row in parsed["frames"]:
		result.append(from_flat_row(row))
	return result
