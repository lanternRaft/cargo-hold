class_name CargoHold
extends Node3D
const Motion = preload("res://scripts/motion_processor.gd")
const BrowserInput = preload("res://scripts/browser_input.gd")
const CargoTheme = preload("res://scripts/cargo_theme.gd")
const HALF_DEPTH := 0.675
const COUNT := 100
const SEED := 7281
@export var object_count := COUNT
var cargo: Node3D
var half := Vector3(3.0, 4.0, HALF_DEPTH)
var walls: Array[Box3DBody] = []
var wall_material: Material
var rim: Array[MeshInstance3D] = []
var world: Box3DWorld
var camera: Camera3D
var bodies: Array[Box3DBody] = []
var meshes: Array[Mesh] = []
var materials: Array[StandardMaterial3D] = []
var piece_batches: Array[MultiMeshInstance3D] = []
var piece_slots: Array[Vector2i] = []
var motion := Motion.new()
var input_provider: RefCounted = BrowserInput.new()
var manual_tilt := Vector2.ZERO
var suspended := false
var grabbed: Box3DBody
var grab_local := Vector3.ZERO
var grab_depth := 0.0
var grab_target := Vector3.ZERO
var pointer_id := -1
var pointer_last := Vector2.ZERO
var pointer_time := 0.0
var pointer_history: Array[Dictionary] = []
var fallback_drag := false
var simulation_ticks := 0
var last_action := "reset"
var last_wake_acceleration := Vector3(0, -Motion.G, 0)
var initial_positions: Array[Vector3] = []

func _ready() -> void:
	world = Box3DWorld.new()
	world.name = "Box3DSimulation"
	world.auto_step = false
	world.substep_count = 4
	world.continuous_collision = true
	world.max_linear_speed = 18.0
	add_child(world)
	cargo = CargoTheme.new()
	cargo.configure()
	add_child(cargo)
	_build_box()
	_build_resources()
	_build_view()
	get_viewport().size_changed.connect(fit_camera)
	fit_camera()
	reset_box()

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.87
	result.metallic_specular = 0.22
	return result

func visual(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

func box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _wall(at: Vector3, size: Vector3, visible_wall: bool, mat: Material) -> void:
	var body := Box3DBody.new()
	body.body_type = Box3DBody.STATIC
	body.collision_layer = 2
	body.position = at
	var shape := Box3DCollisionShape.new()
	shape.box_size = size
	shape.friction = 0.28
	shape.restitution = 0.605
	body.add_child(shape)
	if visible_wall:
		visual(body, box_mesh(size), mat)
	world.add_child(body)
	walls.append(body)

func _build_box() -> void:
	wall_material = cargo.panels
	var frame := material(Color("141b24"))
	for i in 4:
		rim.append(visual(self, box_mesh(Vector3.ONE), frame))

func _resize_enclosure() -> void:
	var sizes := [Vector3(0.36, half.y * 2 + 0.72, half.z * 2 + 0.72),
		Vector3(half.x * 2 + 0.72, 0.36, half.z * 2 + 0.72),
		Vector3(half.x * 2 + 0.72, half.y * 2 + 0.72, 0.36)]
	# Compound collider dimensions are captured when Box3D registers the body.
	# Recreate the static walls on resize; dynamic body identities stay intact.
	for wall in walls:
		world.remove_child(wall)
		wall.free()
	walls.clear()
	for i in 6:
		var axis := i / 2
		var at := Vector3.ZERO
		at[axis] = (half[axis] + 0.18) * (-1 if i % 2 == 0 else 1)
		_wall(at, sizes[axis], i != 5, wall_material)
	for i in 4:
		var vertical := i < 2
		var sign_side := -1 if i % 2 == 0 else 1
		rim[i].position = Vector3(sign_side * (half.x + 0.32) if vertical else 0.0,
			0.0 if vertical else sign_side * (half.y + 0.32), HALF_DEPTH + 0.37)
		rim[i].mesh.size = Vector3(0.32, half.y * 2 + 0.96, 0.32) if vertical else Vector3(half.x * 2 + 0.96, 0.32, 0.32)
	cargo.resize(half)
	for batch in piece_batches:
		# The whole enclosed pile shares a culling bound. Avoid recalculating an
		# aggregate AABB after every instance transform update.
		batch.multimesh.custom_aabb = AABB(-half - Vector3.ONE * 0.5, (half + Vector3.ONE * 0.5) * 2)

func _build_resources() -> void:
	materials = cargo.piece_materials()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	sphere.radial_segments = 20
	sphere.rings = 10
	meshes.append(sphere)
	meshes.append(box_mesh(Vector3.ONE * 0.43))
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.19
	capsule.height = 0.60
	capsule.radial_segments = 16
	capsule.rings = 6
	meshes.append(capsule)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.23
	cylinder.bottom_radius = 0.23
	cylinder.height = 0.43
	cylinder.radial_segments = 16
	meshes.append(cylinder)
	for shape in meshes.size():
		for color in materials.size():
			var batch := MultiMeshInstance3D.new()
			batch.name = "Pieces%dColor%d" % [shape, color]
			batch.multimesh = MultiMesh.new()
			batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			batch.multimesh.mesh = meshes[shape]
			batch.material_override = materials[color]
			add_child(batch)
			piece_batches.append(batch)

func _rebuild_piece_instances() -> void:
	piece_slots.clear()
	var counts := PackedInt32Array()
	counts.resize(piece_batches.size())
	for i in bodies.size():
		var batch_index := (i % 4) * 4 + (i / 4 + i) % 4
		piece_slots.append(Vector2i(batch_index, counts[batch_index]))
		counts[batch_index] += 1
	for i in piece_batches.size():
		piece_batches[i].multimesh.instance_count = counts[i]
	_sync_piece_transforms()

func _sync_piece_transform(index: int) -> void:
	var body := bodies[index]
	var pose := world.transform * body.transform
	if body == grabbed:
		pose.basis = pose.basis.scaled(Vector3.ONE * 1.06)
	var slot := piece_slots[index]
	piece_batches[slot.x].multimesh.set_instance_transform(slot.y, pose)

func _sync_piece_transforms() -> void:
	for i in bodies.size():
		_sync_piece_transform(i)

func _build_view() -> void:
	cargo.build_lighting(self)
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0, 0, 18)
	camera.current = true
	add_child(camera)

func fit_camera(viewport_size: Vector2 = Vector2.ZERO) -> void:
	if camera == null:
		return
	if viewport_size == Vector2.ZERO:
		viewport_size = get_viewport().get_visible_rect().size
	var aspect := maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0)
	# Fit the cargo cavity opening to the viewport, with the outer rim outside
	# the view. Preserve the short-side dimensions and the shapes' physical scale.
	var interior := Vector2(3.0, 3.0)
	if aspect >= 1.0:
		interior.x *= aspect
	else:
		interior.y /= aspect
	var previous := half
	half = Vector3(interior.x, interior.y, HALF_DEPTH)
	cancel_pointer()
	_resize_enclosure()
	for body in bodies:
		var at := body.position
		at.x *= (half.x - 0.4) / (previous.x - 0.4)
		at.y *= (half.y - 0.4) / (previous.y - 0.4)
		var pose := body.global_transform
		pose.origin = at.clamp(-half + Vector3.ONE * 0.4, half - Vector3.ONE * 0.4)
		var linear := body.get_linear_velocity()
		var angular := body.get_angular_velocity()
		body.teleport(pose)
		body.set_linear_velocity(linear)
		body.set_angular_velocity(angular)
		body.set_awake(true)
	_sync_piece_transforms()
	camera.position.z = HALF_DEPTH + 0.36 + interior.y / tan(deg_to_rad(camera.fov * 0.5))

func reset_box() -> void:
	cancel_pointer()
	for body in bodies:
		world.remove_child(body)
		body.free()
	bodies.clear()
	initial_positions.clear()
	motion.clear()
	manual_tilt = Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var per_layer := ceili(object_count / 2.0)
	var columns := maxi(2, ceili(sqrt(per_layer * half.x / half.y)))
	var rows := maxi(2, ceili(float(per_layer) / columns))
	for i in object_count:
		var body := Box3DBody.new()
		body.name = "Shape%03d" % i
		body.shape_type = [Box3DBody.SPHERE, Box3DBody.BOX, Box3DBody.CAPSULE, Box3DBody.CYLINDER][i % 4]
		body.sphere_radius = 0.24
		body.box_size = Vector3.ONE * 0.43
		body.capsule_radius = 0.19 if i % 4 == 2 else 0.23
		body.capsule_height = 0.60 if i % 4 == 2 else 0.43
		body.cylinder_sides = 16
		body.friction = 0.24
		body.restitution = 0.605
		body.linear_damping = 0.12
		body.angular_damping = 0.3
		body.continuous = true
		body.collision_layer = 1
		var cell := i % per_layer
		body.position = Vector3(lerpf(-half.x + 0.5, half.x - 0.5, float(cell % columns) / (columns - 1)),
			lerpf(-half.y + 0.5, half.y - 0.5, float(cell / columns) / (rows - 1)), (i / per_layer - 0.5) * 0.60)
		body.rotation = Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3), rng.randf_range(-1.3, 1.3))
		world.add_child(body)
		bodies.append(body)
		initial_positions.append(body.position)
	_rebuild_piece_instances()
	simulation_ticks = 0
	last_action = "reset"

func recenter() -> void:
	motion.recenter()
	manual_tilt = Vector2.ZERO

func suspend(value: bool) -> void:
	if suspended != value:
		cancel_pointer()
		motion.clear()
		suspended = value

func _physics_process(delta: float) -> void:
	var snapshot: Dictionary = input_provider.snapshot()
	suspend(bool(snapshot.get("hidden", false)))
	if suspended:
		return
	var now := float(snapshot.get("now_ms", Time.get_ticks_msec()))
	var sample: Variant = snapshot.get("sample")
	if sample is Dictionary:
		motion.ingest(sample, now)
	for event in snapshot.get("events", []):
		_bridge_event(event)
	var fallback := Basis.from_euler(Vector3(manual_tilt.y, 0, manual_tilt.x)) * Vector3(0, -Motion.G, 0)
	_set_acceleration(motion.tick(delta, now, fallback))
	_apply_grab()
	world.step(minf(delta, 1.0 / 30.0))
	_sync_piece_transforms()
	simulation_ticks += 1
	if OS.has_feature("web") and simulation_ticks % 60 == 0:
		var inside := true
		for body in bodies:
			inside = inside and absf(body.position.x) < half.x + 0.1 and absf(body.position.y) < half.y + 0.1 and absf(body.position.z) < half.z + 0.1
		JavaScriptBridge.eval("window.CargoHold.report(" + JSON.stringify({"engine":"Box3D", "theme":"cargo", "bodies":bodies.size(), "contained":inside, "ticks":simulation_ticks, "grabbed":grabbed != null, "motion":motion.active, "last_action":last_action, "piece_batches":piece_batches.size(), "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}) + ")")

func _set_acceleration(value: Vector3) -> void:
	world.gravity = value
	# Box3D gravity changes do not wake a resting pile. Wake on accumulated
	# acceleration changes, keeping ordinary resting sleep available.
	if value.distance_to(last_wake_acceleration) > 0.10:
		for body in bodies:
			body.set_awake(true)
		last_wake_acceleration = value

func _bridge_event(event: Dictionary) -> void:
	# Normalized canvas coordinates avoid backing-pixel / logical-viewport mismatch.
	var screen_pos := Vector2(float(event.get("x", 0)), float(event.get("y", 0))) * get_viewport().get_visible_rect().size
	match event.get("type", ""):
		"reset": reset_box()
		"recenter": recenter()
		"cancel": cancel_pointer()
		"down": begin_pointer(int(event.id), screen_pos, float(event.time))
		"move": move_pointer(int(event.id), screen_pos, float(event.time))
		"up": release_pointer(int(event.id), float(event.time))

func _target(screen_pos: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var distance := (grab_depth - origin.z) / direction.z
	var point := origin + direction * distance
	return point.clamp(-half + Vector3.ONE * 0.35, half - Vector3.ONE * 0.35)

func begin_pointer(id: int, screen_pos: Vector2, time_ms: float) -> void:
	if pointer_id >= 0 or suspended:
		return
	pointer_id = id
	pointer_last = screen_pos
	pointer_time = time_ms
	var from := camera.project_ray_origin(screen_pos)
	var hit := world.raycast(from, from + camera.project_ray_normal(screen_pos) * 100, 1)
	if hit.get("hit", false) and hit.get("collider") in bodies:
		last_action = "grab"
		grabbed = hit.collider
		grabbed.set_awake(true)
		grab_local = grabbed.global_transform.affine_inverse() * hit.position
		grab_depth = hit.position.z
		grab_target = _target(screen_pos)
		pointer_history = [{"point":grab_target, "time":time_ms}]
		_sync_piece_transform(bodies.find(grabbed))
	else:
		fallback_drag = true
		last_action = "tilt"

func move_pointer(id: int, screen_pos: Vector2, time_ms: float) -> void:
	if id != pointer_id:
		return
	if grabbed != null:
		grab_target = _target(screen_pos)
		pointer_history.append({"point":grab_target, "time":time_ms})
		while pointer_history.size() > 2 and time_ms - float(pointer_history[0].time) > 100:
			pointer_history.pop_front()
	elif fallback_drag and not motion.active:
		var movement := screen_pos - pointer_last
		manual_tilt += Vector2(movement.x, movement.y) * 0.008
		manual_tilt = manual_tilt.clamp(Vector2(-1.35, -1.35), Vector2(1.35, 1.35))
	pointer_last = screen_pos
	pointer_time = time_ms

func _apply_grab() -> void:
	if not is_instance_valid(grabbed):
		return
	var picked := grabbed.global_transform * grab_local
	var arm := picked - grabbed.global_position
	var velocity := grabbed.get_linear_velocity() + grabbed.get_angular_velocity().cross(arm)
	var acceleration := ((grab_target - picked) * 85.0 - velocity * 15.0 - world.gravity).limit_length(95.0)
	var force := acceleration * grabbed.get_mass()
	grabbed.apply_central_force(force)
	grabbed.apply_torque(arm.cross(force).limit_length(2.0))

func release_pointer(id: int, time_ms: float) -> void:
	if id != pointer_id:
		return
	if grabbed != null and pointer_history.size() >= 2 and time_ms - pointer_time < 100:
		var first: Dictionary = pointer_history[0]
		var last: Dictionary = pointer_history[-1]
		var elapsed := (float(last.time) - float(first.time)) / 1000.0
		if elapsed > 0.008:
			var velocity: Vector3 = (last.point - first.point) / elapsed
			grabbed.set_linear_velocity(velocity.limit_length(12.0))
			last_action = "throw"
	cancel_pointer()

func cancel_pointer() -> void:
	var index := bodies.find(grabbed) if is_instance_valid(grabbed) else -1
	grabbed = null
	if index >= 0:
		_sync_piece_transform(index)
	pointer_id = -1
	fallback_drag = false
	pointer_history.clear()

func _unhandled_input(event: InputEvent) -> void:
	# Web pointers are handled by DOM capture; native events are for desktop QA.
	if OS.has_feature("web"):
		return
	var now := float(Time.get_ticks_msec())
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: begin_pointer(0, event.position, now)
		else: release_pointer(0, now)
	elif event is InputEventMouseMotion:
		move_pointer(0, event.position, now)
	elif event is InputEventScreenTouch:
		if event.pressed: begin_pointer(event.index, event.position, now)
		else: release_pointer(event.index, now)
	elif event is InputEventScreenDrag:
		move_pointer(event.index, event.position, now)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_pointer()
