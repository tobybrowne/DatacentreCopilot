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


static func _read_transform(buf: StreamPeerBuffer) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(buf.get_float(), buf.get_float(), buf.get_float()),
			Vector3(buf.get_float(), buf.get_float(), buf.get_float()),
			Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		),
		Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	)


static func frames_from_bytes(data: PackedByteArray) -> Array[PoseRec]:
	var raw := data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty():
		return []
	var buf := StreamPeerBuffer.new()
	buf.data_array = raw
	var frame_count := buf.get_32()
	var result: Array[PoseRec] = []
	result.resize(frame_count)
	for i in frame_count:
		var rec := PoseRec.new()
		rec.timestamp_msec = buf.get_32()
		rec.left_tracked   = buf.get_u8() != 0
		rec.right_tracked  = buf.get_u8() != 0
		rec.head_transform = _read_transform(buf)
		for j in JOINT_COUNT:
			rec.left_joints[j]  = _read_transform(buf)
		for j in JOINT_COUNT:
			rec.right_joints[j] = _read_transform(buf)
		result[i] = rec
	return result
