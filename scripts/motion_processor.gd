class_name MotionProcessor
extends RefCounted
## Device: +X right, +Y toward top, +Z out of screen. Box uses the same axes.
## SI m/s². Screen rotation rotates XY only; depth is always retained.
const G := 9.81
const STALE_MS := 350.0
const SHAKE_GAIN := 13.0
const MAX_SHAKE := 195.0
const MAX_TOTAL := 205.0
var gravity := Vector3(0, -G, 0)
var target_gravity := gravity
var shake := Vector3.ZERO
var calibration := Basis.IDENTITY
var last_stamp := -1.0
var last_angle := 0.0
var filtered_including := Vector3.ZERO
var has_filter := false
# Safari includes downward gravity; other implementations report its opposite.
# Learn from a valid pose and retain the convention across stale poses/reset.
var including_gravity_sign := -1.0
var active := false

static func screen_vector(value: Vector3, angle: float) -> Vector3:
	# Screen angle is the display's counter-clockwise rotation from natural
	# orientation. Device axes stay fixed; rotate into the displayed box axes.
	return Basis(Vector3.BACK, deg_to_rad(angle)) * value

static func orientation_gravity(beta: float, gamma: float) -> Vector3:
	# W3C intrinsic Z-X-Y device-to-earth rotation: transform earth DOWN
	# back into device coordinates with its transpose. Alpha cancels out.
	var b := deg_to_rad(beta)
	var c := deg_to_rad(gamma)
	return Vector3(cos(b) * sin(c), -sin(b), -cos(b) * cos(c)) * G

static func vector_or_null(value: Variant) -> Variant:
	if not value is Array or value.size() != 3:
		return null
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return null
	return Vector3(value[0], value[1], value[2])

func ingest(sample: Dictionary, now_ms: float) -> bool:
	var stamp := float(sample.get("timestamp_ms", -1.0))
	if stamp < 0 or now_ms - stamp > STALE_MS or stamp > now_ms + 50:
		return false
	if stamp <= last_stamp:
		return false
	var angle := float(sample.get("angle", 0.0))
	if not is_equal_approx(angle, last_angle):
		calibration = Basis.IDENTITY
		has_filter = false
	var dt := clampf((stamp - last_stamp) / 1000.0, 0.001, 0.1) if last_stamp >= 0 else 0.016
	var incl: Variant = vector_or_null(sample.get("including"))
	var acceleration: Variant = vector_or_null(sample.get("acceleration"))
	var device_gravity: Variant = null
	var orientation: Variant = sample.get("orientation")
	if orientation is Array and orientation.size() == 2:
		if orientation[0] != null and orientation[1] != null:
			device_gravity = orientation_gravity(float(orientation[0]), float(orientation[1]))
	if incl != null:
		if not has_filter:
			filtered_including = incl
			has_filter = true
		else:
			filtered_including = filtered_including.lerp(incl, 1.0 - exp(-dt / 0.35))
		# Removing supplied linear acceleration isolates sensor gravity directly.
		# Without it, use the low-pass estimate for fallback tilt.
		var sensor_gravity: Vector3 = incl - acceleration if acceleration != null else filtered_including
		if device_gravity != null:
			var sign_probe: Vector3 = incl - acceleration if acceleration != null else incl
			# Reject vigorous translation or poorly aligned samples before learning.
			if sign_probe.length() > G * 0.8 and sign_probe.length() < G * 1.2:
				var alignment := sign_probe.normalized().dot(device_gravity.normalized())
				if absf(alignment) > 0.9:
					including_gravity_sign = 1.0 if alignment > 0 else -1.0
		if device_gravity == null and sensor_gravity.length() > 1.0:
			device_gravity = sensor_gravity.normalized() * G * including_gravity_sign
		if acceleration == null and device_gravity != null:
			acceleration = incl - filtered_including if orientation == null else incl - device_gravity * including_gravity_sign
	if device_gravity == null:
		return false
	target_gravity = calibration * screen_vector(device_gravity, angle)
	shake = -(calibration * screen_vector(acceleration, angle) * SHAKE_GAIN).limit_length(MAX_SHAKE) if acceleration != null else Vector3.ZERO
	last_stamp = stamp
	last_angle = angle
	active = true
	return true

func tick(delta: float, now_ms: float, fallback: Vector3 = Vector3(0, -G, 0)) -> Vector3:
	if last_stamp < 0 or now_ms - last_stamp > STALE_MS:
		active = false
		shake = Vector3.ZERO
		target_gravity = fallback
	gravity = gravity.lerp(target_gravity, 1.0 - exp(-delta / 0.12))
	return (gravity + shake).limit_length(MAX_TOTAL)

func recenter() -> void:
	if active and target_gravity.length() > 1.0:
		var correction := Basis(Quaternion(target_gravity.normalized(), Vector3.DOWN))
		calibration = correction * calibration
		target_gravity = correction * target_gravity
		gravity = target_gravity
	shake = Vector3.ZERO

func clear() -> void:
	gravity = Vector3(0, -G, 0)
	target_gravity = gravity
	shake = Vector3.ZERO
	calibration = Basis.IDENTITY
	last_stamp = -1.0
	last_angle = 0.0
	has_filter = false
	active = false
