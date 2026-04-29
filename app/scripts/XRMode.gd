# classes are globally accessible, so any other code can call "XRMode.is_active()"
# to check if we're running on an XR device or a desktop simulator

class_name XRMode

static func is_active() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and xr.is_initialized()
