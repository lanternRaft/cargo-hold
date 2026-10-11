extends GdUnitTestSuite
const Box = preload("res://scripts/magic_box.gd")
var box: Node3D

func before_test() -> void:
	box = auto_free(Box.new())
	add_child(box)
	box.set_physics_process(false)

func contained() -> void:
	for body in box.bodies:
		assert_float(absf(body.position.x)).is_less(box.half.x + 0.05)
		assert_float(absf(body.position.y)).is_less(box.half.y + 0.05)
		assert_float(absf(body.position.z)).is_less(box.half.z + 0.05)

func assert_piece_pose(index: int, highlight: float = 1.0) -> void:
	# Godot's headless Dummy mesh storage discards instance transforms. Run
	# this suite with Compatibility rendering to verify actual visual poses.
	if DisplayServer.get_name() == "headless": return
	var slot: Vector2i = box.piece_slots[index]
	var actual: Transform3D = box.piece_batches[slot.x].multimesh.get_instance_transform(slot.y)
	var expected: Transform3D = box.world.transform * box.bodies[index].transform
	assert_vector(actual.origin).is_equal_approx(expected.origin, Vector3.ONE * 0.0001)
	assert_vector(actual.basis.x).is_equal_approx(expected.basis.x * highlight, Vector3.ONE * 0.0001)
	assert_vector(actual.basis.y).is_equal_approx(expected.basis.y * highlight, Vector3.ONE * 0.0001)
	assert_vector(actual.basis.z).is_equal_approx(expected.basis.z * highlight, Vector3.ONE * 0.0001)

func test_batched_visuals_follow_physics_and_resize() -> void:
	assert_int(box.piece_batches.size()).is_equal(16)
	var rendered := 0
	for batch in box.piece_batches:
		rendered += batch.multimesh.instance_count
	assert_int(rendered).is_equal(100)
	for body in box.bodies:
		# Visual batching must not add scaled children to physics bodies.
		assert_int(body.get_child_count()).is_equal(0)
	box.bodies[0].set_linear_velocity(Vector3(2, 1, 0))
	box.bodies[0].set_angular_velocity(Vector3(1, 2, 3))
	for tick in 30: box._physics_process(1.0 / 60)
	for i in box.bodies.size(): assert_piece_pose(i)
	for size in [Vector2(390,844), Vector2(844,390)]:
		box.fit_camera(size)
		for i in box.bodies.size(): assert_piece_pose(i)
		contained()

func test_batch_reset_reuses_nodes_and_removes_old_instances() -> void:
	var original: Array = box.piece_batches.duplicate()
	for count in [7, 0, 100]:
		box.object_count = count
		box.reset_box()
		assert_array(box.piece_batches).is_equal(original)
		assert_int(box.world.get_child_count()).is_equal(count + 6)
		assert_int(box.piece_slots.size()).is_equal(count)
		var rendered := 0
		for batch in box.piece_batches: rendered += batch.multimesh.instance_count
		assert_int(rendered).is_equal(count)
		var slots: Array[Vector2i] = []
		for i in count:
			var slot: Vector2i = box.piece_slots[i]
			assert_bool(slot in slots).is_false()
			slots.append(slot)
			assert_bool(box.piece_batches[slot.x].multimesh.mesh == box.meshes[i % 4]).is_true()
			assert_bool(box.piece_batches[slot.x].material_override == box.materials[(i / 4 + i) % 4]).is_true()
			assert_piece_pose(i)

func test_enclosure_under_depth_gravity_and_vigorous_shakes() -> void:
	assert_int(box.bodies.size()).is_equal(100)
	assert_int(box.world.get_child_count()).is_equal(106)
	for direction in [Vector3(0,0,30),Vector3(0,0,-30),Vector3(25,-20,25),Vector3(-25,20,-25),
		Vector3(0,0,280),Vector3(0,0,-280),Vector3(1,-1,1).normalized()*280,Vector3(-1,1,-1).normalized()*280]:
		box._set_acceleration(direction)
		for tick in 180:
			box.world.step(1.0/60)
			if tick % 30 == 0: contained()
		contained()

func test_reset_is_deterministic_and_removes_grab_and_velocity() -> void:
	var positions: Array[Vector3] = box.initial_positions.duplicate()
	var first: Box3DBody = box.bodies[0]
	box.grabbed = first
	box.pointer_id = 3
	first.set_linear_velocity(Vector3(8,7,6))
	box.manual_tilt = Vector2(1,1)
	box.reset_box()
	assert_bool(is_instance_valid(first)).is_false()
	assert_bool(box.grabbed == null).is_true()
	assert_int(box.pointer_id).is_equal(-1)
	assert_int(box.world.get_child_count()).is_equal(106)
	assert_array(box.initial_positions).is_equal(positions)
	for body in box.bodies:
		assert_vector(body.get_linear_velocity()).is_equal(Vector3.ZERO)

func test_box3d_pick_spring_throw_and_cancel() -> void:
	box.world.gravity = Vector3.ZERO
	for tick in 2: box.world.step(1.0/60)
	var target: Box3DBody = box.bodies[-1]
	var screen_pos: Vector2 = box.camera.unproject_position(target.position)
	box.begin_pointer(7,screen_pos,100)
	assert_bool(box.grabbed != null).is_true()
	var picked: Box3DBody = box.grabbed
	var picked_index: int = box.bodies.find(picked)
	assert_piece_pose(picked_index, 1.06)
	box.move_pointer(99,screen_pos+Vector2(500,0),110)
	assert_int(box.pointer_id).is_equal(7)
	box.move_pointer(7,screen_pos+Vector2(40,20),130)
	for tick in 60:
		box._apply_grab()
		box.world.step(1.0/60)
	contained()
	box.release_pointer(7,140)
	assert_piece_pose(picked_index)
	assert_bool(box.grabbed == null).is_true()
	assert_float(picked.get_linear_velocity().length()).is_less_equal(12.01)
	assert_float(picked.get_linear_velocity().length()).is_greater(0.1)
	box.begin_pointer(8,box.camera.unproject_position(picked.position),150)
	assert_bool(box.grabbed != null).is_true()
	var cancelled_index: int = box.bodies.find(box.grabbed)
	assert_piece_pose(cancelled_index, 1.06)
	box.suspend(true)
	assert_int(box.pointer_id).is_equal(-1)
	assert_bool(box.grabbed == null).is_true()
	assert_piece_pose(cancelled_index)
	box.suspend(false)
	assert_bool(box.motion.active).is_false()

func test_resize_adapts_walls_and_preserves_bodies_and_shallow_depth() -> void:
	var original: Array[Box3DBody] = box.bodies.duplicate()
	for size in [Vector2(390,844),Vector2(844,390),Vector2(932,932)]:
		box.pointer_id = 7
		box.grabbed = box.bodies[0]
		box.fit_camera(size)
		assert_int(box.pointer_id).is_equal(-1)
		assert_bool(box.grabbed == null).is_true()
		assert_array(box.bodies).is_equal(original)
		assert_int(box.world.get_child_count()).is_equal(106)
		assert_float(box.half.z).is_equal_approx(0.675, 0.00001)
		assert_float(box.half.x / box.half.y).is_equal_approx(size.x / size.y, 0.001)
		for direction in [Vector3(25,-20,25),Vector3(-25,20,-25)]:
			box._set_acceleration(direction)
			for tick in 180: box.world.step(1.0/60)
			contained()

class InjectedInput extends RefCounted:
	var value: Dictionary = {}
	func snapshot() -> Dictionary:
		return value

func test_injected_fixed_step_motion_and_hidden_resume() -> void:
	var source := InjectedInput.new()
	box.input_provider = source
	source.value = {"now_ms":100,"sample":{"timestamp_ms":100,"orientation":[0,0],"acceleration":[0,0,4]},"events":[]}
	for tick in 120:
		source.value.now_ms = 100.0 + tick * 1000.0 / 60
		source.value.sample.timestamp_ms = source.value.now_ms
		box._physics_process(1.0/60)
	assert_float(box.world.gravity.z).is_less(-5)
	contained()
	var before: Vector3 = box.bodies[0].position
	var ticks: int = box.simulation_ticks
	box.pointer_id = 42
	source.value = {"now_ms":3000,"hidden":true,"events":[]}
	box._physics_process(1.0/60)
	assert_int(box.simulation_ticks).is_equal(ticks)
	assert_int(box.pointer_id).is_equal(-1)
	assert_vector(box.bodies[0].position).is_equal(before)
	source.value = {"now_ms":6000,"hidden":false,"events":[]}
	box._physics_process(1.0/60)
	assert_bool(box.motion.active).is_false()
	assert_vector(box.motion.shake).is_equal(Vector3.ZERO)
	contained()

func test_normalized_dom_coordinates_pick_correctly() -> void:
	box.world.step(1.0/60)
	var target: Box3DBody = box.bodies[-1]
	var screen: Vector2 = box.camera.unproject_position(target.position)
	var size: Vector2 = box.get_viewport().get_visible_rect().size
	box._bridge_event({"type":"down","id":1,"x":screen.x/size.x,"y":screen.y/size.y,"time":100})
	assert_bool(box.grabbed != null).is_true()
	box._bridge_event({"type":"cancel"})
	assert_bool(box.grabbed == null).is_true()

func test_tilt_wakes_a_resting_pile_and_moves_it() -> void:
	for tick in 600: box.world.step(1.0/60)
	for body in box.bodies: body.set_awake(false)
	box.manual_tilt = Vector2(1.2, 0.8)
	box._physics_process(1.0/60)
	assert_bool(box.bodies[0].is_awake()).is_true()
	var before := Vector3.ZERO
	for body in box.bodies: before += body.position
	for tick in 180: box._physics_process(1.0/60)
	var after := Vector3.ZERO
	for body in box.bodies: after += body.position
	assert_float((after-before).length()/100).is_greater(0.5)
	contained()

func test_accelerometer_pulse_lifts_a_sleeping_pile_without_tilting() -> void:
	for tick in 600: box.world.step(1.0/60)
	var before := 0.0
	for body in box.bodies:
		before += body.position.y
		body.set_awake(false)
	var source := InjectedInput.new()
	box.input_provider = source
	for tick in 15:
		var now := 100.0 + tick * 1000.0 / 60
		source.value = {"now_ms":now,"sample":{"timestamp_ms":now,"orientation":[90,0],"including":[0,-17.81,0],"acceleration":[0,-8,0],"angle":0},"events":[]}
		box._physics_process(1.0/60)
	var after := 0.0
	for body in box.bodies: after += body.position.y
	assert_float(box.world.gravity.y).is_greater(10.0)
	assert_float((after - before)/100).is_greater(0.15)
	contained()

func test_shape_rebounds_from_cream_floor() -> void:
	var sphere: Box3DBody = box.bodies[0]
	for body in box.bodies:
		if body != sphere:
			box.world.remove_child(body)
			body.free()
	box.bodies.assign([sphere])
	var pose := sphere.global_transform
	pose.origin = Vector3.ZERO
	sphere.teleport(pose)
	sphere.set_linear_velocity(Vector3.ZERO)
	var bounced := false
	for tick in 180:
		box.world.step(1.0/60)
		if sphere.get_linear_velocity().y > 2.0:
			bounced = true
		contained()
	assert_bool(bounced).is_true()
