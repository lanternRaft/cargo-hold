extends Node3D
## Cargo Hold visuals. The shadow grating never participates in Box3D physics.
const PALETTE := [Color("ff791f"), Color("215bdb"), Color("eef2f5"), Color("929eaa")]
const WALL_COLOR := Color("24262c")
const GRID_SPACING := 2.1
const GRID_BAR_WIDTH := 0.14
const GRID_ANGLE := deg_to_rad(8.0)
const GRID_LIGHT_ROTATION := Vector3(-22, -24, 0)
var panels: Material
var shadow_grid: Array[MultiMeshInstance3D] = []
var key_light: DirectionalLight3D

func configure() -> void:
	panels = _material(WALL_COLOR, 0.82, 0.15)
	for axis in 2:
		var grid := MultiMeshInstance3D.new()
		grid.name = "ShadowGrating%d" % axis
		grid.multimesh = MultiMesh.new()
		grid.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		grid.multimesh.mesh = BoxMesh.new()
		grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(grid)
		shadow_grid.append(grid)

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func piece_materials() -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	for i in PALETTE.size():
		# Painted cargo with a satin finish; gray pieces are rough metal.
		result.append(_material(PALETTE[i], 0.36 if i == 3 else 0.57, 0.72 if i == 3 else 0.08))
	return result

func resize(half: Vector3) -> void:
	_resize_shadow_grid(half)

func _resize_shadow_grid(half: Vector3) -> void:
	# A real grating in front of the lid, invisible to the camera but present in
	# the key light's shadow map. No colliders: it cannot interfere with picking.
	var grid_z := half.z + 1.25
	var direction := Basis.from_euler(GRID_LIGHT_ROTATION * PI / 180.0) * Vector3.FORWARD
	var travel := (grid_z + half.z) / -direction.z
	var center := Vector3(-direction.x * travel, -direction.y * travel, grid_z)
	var rotation := Basis(Vector3.BACK, GRID_ANGLE)
	var extent := Vector2(half.x * cos(GRID_ANGLE) + half.y * sin(GRID_ANGLE),
		half.x * sin(GRID_ANGLE) + half.y * cos(GRID_ANGLE)) + Vector2.ONE * 2.0
	for axis in 2:
		var count := ceili(extent[axis] / GRID_SPACING)
		var batch := shadow_grid[axis].multimesh
		batch.instance_count = count * 2 + 1
		for i in batch.instance_count:
			var offset := Vector3.ZERO
			offset[axis] = (i - count) * GRID_SPACING
			var size := Vector3(GRID_BAR_WIDTH, extent.y * 2.0, 0.05) if axis == 0 else Vector3(extent.x * 2.0, GRID_BAR_WIDTH, 0.05)
			batch.set_instance_transform(i, Transform3D(rotation * Basis.from_scale(size), center + rotation * offset))
	if key_light != null:
		# Keep the entire enclosure inside the single directional shadow volume,
		# including tall portrait views and the caster outside the front collider.
		key_light.directional_shadow_max_distance = 6.0 + half.y / tan(deg_to_rad(18.0))

func build_lighting(parent: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = WALL_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.25
	# Explicitly keep screen-space effects off for the mobile web budget.
	environment.environment.glow_enabled = false
	environment.environment.ssao_enabled = false
	environment.environment.ssr_enabled = false
	parent.add_child(environment)
	var key := DirectionalLight3D.new()
	key_light = key
	key.rotation_degrees = GRID_LIGHT_ROTATION
	key.light_energy = 0.65
	key.light_color = Color.WHITE
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 24.0
	key.directional_shadow_fade_start = 0.95
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 40, 0)
	fill.light_energy = 0.07
	fill.light_color = Color.WHITE
	parent.add_child(fill)
