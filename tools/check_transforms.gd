@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	_print_transforms(inst)
	inst.free()
	quit(0)

func _print_transforms(n: Node) -> void:
	if n is Node3D:
		var n3d: Node3D = n as Node3D
		print(n.name, " scale=", n3d.scale, " pos=", n3d.position, " rot=", n3d.rotation_degrees)
	for c: Node in n.get_children():
		_print_transforms(c)
