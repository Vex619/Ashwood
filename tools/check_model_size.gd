@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	var mesh_inst: MeshInstance3D = inst.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
	var aabb: AABB = mesh_inst.get_aabb()
	print("Mesh AABB: position=", aabb.position, " size=", aabb.size)
	inst.free()
	quit(0)
