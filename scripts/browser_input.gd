extends RefCounted
## Replaceable source. Tests provide dictionaries without browser dependencies.
func snapshot() -> Dictionary:
	if not OS.has_feature("web"):
		return {"now_ms": Time.get_ticks_msec(), "hidden": false, "events": []}
	var raw: Variant = JavaScriptBridge.eval("window.CargoHold ? window.CargoHold.take() : '{}'")
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			return parsed
	return {"now_ms": Time.get_ticks_msec(), "hidden": false, "events": []}
