extends GdUnitTestSuite
const Motion = preload("res://scripts/motion_processor.gd")

func sample(stamp: float, beta: float = 90, gamma: float = 0, acceleration: Variant = [0,0,0], angle: float = 0) -> Dictionary:
	return {"timestamp_ms":stamp,"orientation":[beta,gamma],"acceleration":acceleration,"angle":angle}

func test_known_poses_and_screen_rotations() -> void:
	assert_vector(Motion.orientation_gravity(0, 0)).is_equal_approx(Vector3(0,0,-9.81), Vector3.ONE * 0.001)
	assert_vector(Motion.orientation_gravity(90, 0)).is_equal_approx(Vector3(0,-9.81,0), Vector3.ONE * 0.001)
	assert_vector(Motion.orientation_gravity(180, 0)).is_equal_approx(Vector3(0,0,9.81), Vector3.ONE * 0.001)
	for angle in [0, 90, 180, 270]:
		var rotated := Motion.screen_vector(Vector3(1,2,3),angle)
		assert_float(rotated.length()).is_equal_approx(sqrt(14),0.001)
		assert_float(rotated.z).is_equal_approx(3,0.001)
	assert_vector(Motion.screen_vector(Vector3(0,-9.81,0),90)).is_equal_approx(Vector3(9.81,0,0), Vector3.ONE * 0.001)

func test_shake_limits_and_gravity_not_counted_twice() -> void:
	var motion := Motion.new()
	assert_bool(motion.ingest(sample(100),100)).is_true()
	assert_vector(motion.tick(1.0/60,100)).is_equal_approx(Vector3(0,-9.81,0),Vector3.ONE * 0.001)
	motion.ingest(sample(110,90,0,[0,0,999]),110)
	assert_float(motion.shake.length()).is_equal_approx(195,0.001)
	assert_float(motion.tick(1.0/60,110).length()).is_less_equal(205)
	assert_float(motion.shake.z).is_less(0)

func test_null_stale_and_out_of_order_samples() -> void:
	var motion := Motion.new()
	assert_bool(motion.ingest({"timestamp_ms":100,"including":[null,0,1]},100)).is_false()
	assert_bool(motion.ingest(sample(100),600)).is_false()
	assert_bool(motion.ingest(sample(100),100)).is_true()
	assert_bool(motion.ingest(sample(99,0),100)).is_false()
	motion.tick(1.0/60,500)
	assert_bool(motion.active).is_false()
	assert_vector(motion.shake).is_equal(Vector3.ZERO)
	assert_bool(motion.ingest(sample(700),100)).is_false()

func test_missing_linear_acceleration_uses_filtered_fallback() -> void:
	var motion := Motion.new()
	var input := {"timestamp_ms":100,"including":[0,0,9.81],"acceleration":null}
	assert_bool(motion.ingest(input,100)).is_true()
	assert_vector(motion.target_gravity).is_equal_approx(Vector3(0,0,-9.81),Vector3.ONE * 0.001)
	assert_vector(motion.shake).is_equal_approx(Vector3.ZERO,Vector3.ONE * 0.001)
	input.timestamp_ms=120
	input.including=[8,0,9.81]
	motion.ingest(input,120)
	assert_float(motion.shake.x).is_less(-5)

func test_recenter_retains_depth_and_rotation_clears_calibration() -> void:
	var motion := Motion.new()
	motion.ingest(sample(100,45,20),100)
	motion.recenter()
	assert_vector(motion.target_gravity).is_equal_approx(Vector3(0,-9.81,0),Vector3.ONE*0.001)
	motion.ingest(sample(120,0,0),120)
	assert_float(absf(motion.target_gravity.z)).is_greater(1)
	motion.ingest(sample(140,0,0,[0,0,0],90),140)
	assert_vector(motion.target_gravity).is_equal_approx(Vector3(0,0,-9.81),Vector3.ONE*0.001)
	motion.clear()
	assert_bool(motion.active).is_false()
	assert_float(motion.last_stamp).is_equal(-1.0)

func test_fixed_step_force_is_independent_of_sensor_rate() -> void:
	var results: Array[Vector3] = []
	for rate in [30,60,120]:
		var motion := Motion.new()
		var integrated := Vector3.ZERO
		var next_sample := 0.0
		for frame in 120:
			var now := frame * 1000.0 / 60.0
			while next_sample <= now:
				motion.ingest(sample(next_sample,60,10,[2,0,3]),now)
				next_sample += 1000.0 / rate
			integrated += motion.tick(1.0/60,now)/60.0
		results.append(integrated)
	assert_vector(results[0]).is_equal_approx(results[1],Vector3.ONE*0.01)
	assert_vector(results[1]).is_equal_approx(results[2],Vector3.ONE*0.01)

# The reference uses physical screen poses, independently of beta/gamma formulas.
# Rx(90) stands the screen up; clockwise roll lowers its right edge.
func test_gravity_follows_lowered_screen_edge_with_orientation_locked() -> void:
	var tilt := deg_to_rad(30.0)
	var earth_down := Vector3(0, 0, -Motion.G)
	var upright := Basis(Vector3.RIGHT, PI / 2)
	var right_lowered := upright * Basis(Vector3.BACK, -tilt)
	var expected := right_lowered.transposed() * earth_down
	# Same upright pose on both sides of the Euler branch near gamma=90.
	for pose in [Vector2(60, 90), Vector2(120, -90)]:
		var motion := Motion.new()
		motion.ingest(sample(100, pose.x, pose.y), 100)
		assert_vector(motion.target_gravity).is_equal_approx(expected, Vector3.ONE * 0.001)
		assert_float(motion.target_gravity.x).is_greater(4.8)
		assert_float(motion.target_gravity.y).is_less(-8.4)
	var left_lowered := upright * Basis(Vector3.BACK, tilt)
	var motion := Motion.new()
	motion.ingest(sample(100, 60, -90), 100)
	assert_vector(motion.target_gravity).is_equal_approx(left_lowered.transposed() * earth_down, Vector3.ONE * 0.001)
	assert_float(motion.target_gravity.x).is_less(-4.8)

func test_displayed_down_and_right_tilt_for_both_landscapes() -> void:
	# Physical device poses for upright displays at 90 and 270 degrees.
	# A neutral displayed screen must fall down, not up; then lower its right edge.
	for pose in [Vector3(0, -90, 90), Vector3(0, 90, 270)]:
		var motion := Motion.new()
		motion.ingest(sample(100, pose.x, pose.y, [0,0,0], pose.z), 100)
		assert_vector(motion.target_gravity).is_equal_approx(Vector3.DOWN * Motion.G, Vector3.ONE * 0.001)
		var beta := 30.0 if pose.z == 90 else -30.0
		motion.ingest(sample(120, beta, pose.y, [0,0,0], pose.z), 120)
		assert_vector(motion.target_gravity).is_equal_approx(Vector3(0.5, -sqrt(3.0)/2, 0) * Motion.G, Vector3.ONE * 0.001)
		# Shake uses the same displayed axes. Device motion right pushes shapes left.
		var device_right := Vector3(0, -2, 0) if pose.z == 90 else Vector3(0, 2, 0)
		motion.ingest(sample(140, beta, pose.y, [device_right.x,device_right.y,device_right.z], pose.z), 140)
		assert_vector(motion.shake).is_equal_approx(Vector3(-2 * Motion.SHAKE_GAIN,0,0), Vector3.ONE * 0.001)

func test_compound_pose_matches_device_to_earth_rotation() -> void:
	# Independent full rotations cover pitch, roll, depth and both beta branches.
	for pose in [Vector3(35, 40, 25), Vector3(120, 135, -50), Vector3(275, -65, 35)]:
		var device_to_earth := Basis(Vector3.BACK, deg_to_rad(pose.x)) * Basis(Vector3.RIGHT, deg_to_rad(pose.y)) * Basis(Vector3.UP, deg_to_rad(pose.z))
		var expected := device_to_earth.transposed() * Vector3(0,0,-Motion.G)
		assert_vector(Motion.orientation_gravity(pose.y,pose.z)).is_equal_approx(expected, Vector3.ONE * 0.001)

func test_stale_orientation_preserves_safari_and_opposite_sensor_gravity_signs() -> void:
	for sign_value in [1.0, -1.0]:
		var motion := Motion.new()
		var down := Vector3(0, -Motion.G, 0)
		var input := sample(100)
		input.including = [0, down.y * sign_value, 0]
		motion.ingest(input,100)
		# Tilt collection can go stale while devicemotion continues. Never flip up.
		input.timestamp_ms = 500
		input.orientation = null
		motion.ingest(input,500)
		assert_vector(motion.target_gravity).is_equal_approx(down, Vector3.ONE * 0.001)
		assert_vector(motion.shake).is_equal(Vector3.ZERO)
		# Repeated reset/hide/resume must not forget the sensor's convention.
		motion.clear()
		input.timestamp_ms = 600
		motion.ingest(input,600)
		assert_vector(motion.target_gravity).is_equal_approx(down, Vector3.ONE * 0.001)
		# Gravity is isolated from raw acceleration, so a shake does not tilt it.
		input.timestamp_ms = 620
		input.acceleration = [2,0,3]
		input.including = [2, down.y * sign_value, 3]
		motion.ingest(input,620)
		assert_vector(motion.target_gravity).is_equal_approx(down, Vector3.ONE * 0.001)
		assert_vector(motion.shake).is_equal_approx(Vector3(-2,0,-3) * Motion.SHAKE_GAIN, Vector3.ONE * 0.001)

func test_moderate_accelerometer_shake_is_amplified_and_releases_promptly() -> void:
	var motion := Motion.new()
	motion.ingest(sample(100,90,0,[0,-8,0]),100)
	# A moderate downward box shake must overcome gravity and lift the contents.
	assert_float(motion.tick(1.0/60,100).y).is_equal_approx(104.0 - Motion.G, 0.001)
	motion.ingest(sample(120),120)
	assert_vector(motion.shake).is_equal(Vector3.ZERO)
	assert_vector(motion.tick(1.0/60,120)).is_equal_approx(Vector3.DOWN * Motion.G, Vector3.ONE * 0.001)

func test_pose_change_without_linear_sensor_does_not_create_false_shake() -> void:
	var motion := Motion.new()
	var input := sample(100,0,0,null)
	input.including = [0,0,-Motion.G]
	motion.ingest(input,100)
	input = sample(120,180,0,null)
	input.including = [0,0,Motion.G]
	motion.ingest(input,120)
	assert_vector(motion.shake).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_vector(motion.target_gravity).is_equal_approx(Vector3(0,0,Motion.G), Vector3.ONE * 0.001)
