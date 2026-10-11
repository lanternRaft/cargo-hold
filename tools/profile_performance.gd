extends SceneTree
## Audit only: headless CPU timings or native Compatibility draw-call counters.
## The unbatched comparison is confined to this standalone process.
const Box = preload("res://scripts/magic_box.gd")
var box: Node3D
var frame := 0
var unbatched := false

func _initialize() -> void:
	call_deferred("run")

func stats(values: Array[float]) -> Dictionary:
	values.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean_ms":total / values.size(), "p95_ms":values[int(values.size() * 0.95)]}

func run() -> void:
	box = Box.new()
	root.add_child(box)
	box.set_physics_process(false)
	box.fit_camera(Vector2(390, 844))
	for tick in 1200: box.world.step(1.0 / 60)
	box._sync_piece_transforms()
	if DisplayServer.get_name() == "headless":
		cpu_phase("settled", false)
		cpu_phase("forced_awake", false, true)
		box.reset_box()
		for tick in 120: box.world.step(1.0 / 60)
		cpu_phase("vigorous_shake", true)
		var resize: Array[float] = []
		for tick in 120:
			var start := Time.get_ticks_usec()
			box.fit_camera(Vector2(390, 844))
			resize.append((Time.get_ticks_usec() - start) / 1000.0)
		print(JSON.stringify({"phase":"redundant_resize", "cost":stats(resize)}))
		box.free()
		quit()
	else:
		root.size = Vector2i(390, 844)
		process_frame.connect(render_frame)

func cpu_phase(label: String, shake: bool, force_wake: bool = false) -> void:
	var steps: Array[float] = []
	var inputs: Array[float] = []
	var awake_sum := 0
	for tick in 900:
		var start := Time.get_ticks_usec()
		if shake:
			var seconds := float(tick) / 60
			box._set_acceleration(Vector3(sin(seconds * 8), -0.5 + sin(seconds * 11), cos(seconds * 9)).normalized() * 205.0)
		elif force_wake:
			for body in box.bodies: body.set_awake(true)
		inputs.append((Time.get_ticks_usec() - start) / 1000.0)
		start = Time.get_ticks_usec()
		box.world.step(1.0 / 60)
		steps.append((Time.get_ticks_usec() - start) / 1000.0)
		for body in box.bodies:
			if body.is_awake(): awake_sum += 1
	print(JSON.stringify({"phase":label, "world_step":stats(steps), "input_wake":stats(inputs), "average_awake":float(awake_sum) / 900}))

func render_frame() -> void:
	frame += 1
	if frame < 240: return
	print(JSON.stringify({"phase":"unbatched_reference" if unbatched else "production_batched",
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}))
	if unbatched:
		process_frame.disconnect(render_frame)
		box.queue_free()
		quit()
	else:
		show_unbatched_reference()
		unbatched = true
		frame = 0

func show_unbatched_reference() -> void:
	for batch in box.piece_batches: batch.hide()
	for i in box.bodies.size():
		box.visual(box.bodies[i], box.meshes[i % 4], box.materials[(i / 4 + i) % 4])
