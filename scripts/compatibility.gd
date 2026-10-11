extends Node3D
var world: Box3DWorld
var falling: Box3DBody
var ticks := 0
func _ready() -> void:
	world = Box3DWorld.new()
	add_child(world)
	var floor_body := Box3DBody.new()
	floor_body.body_type = Box3DBody.STATIC
	floor_body.position.y = -1
	var floor_shape := Box3DCollisionShape.new()
	floor_shape.box_size = Vector3(6, 1, 6)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	falling = Box3DBody.new()
	falling.position.y = 2
	world.add_child(falling)
func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks == 180:
		var passed := falling.position.y < 0.2 and falling.position.y > -0.2
		print("BOX3D_COMPATIBILITY ", "PASS" if passed else "FAIL", " y=", falling.position.y)
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.magicBoxCompatibility = " + ("true" if passed else "false"))
		else:
			get_tree().quit(0 if passed else 1)
