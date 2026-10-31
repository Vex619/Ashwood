@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D")[0] as Skeleton3D
	print("Skeleton bone count: ", skel.get_bone_count())
	for i: int in skel.get_bone_count():
		print("  Bone %d: '%s' parent=%d" % [i, skel.get_bone_name(i), skel.get_bone_parent(i)])
	var mesh_inst: MeshInstance3D = inst.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
	print("Mesh: ", mesh_inst.mesh)
	print("Surface count: ", mesh_inst.mesh.get_surface_count())
	for s: int in mesh_inst.mesh.get_surface_count():
		print("Surface %d mat: " % s, mesh_inst.get_surface_override_material(s), " mesh mat: ", mesh_inst.mesh.surface_get_material(s))
	inst.free()
	quit(0)
