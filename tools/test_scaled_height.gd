@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	inst.scale = Vector3(0.32, 0.32, 0.32)
	root.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D")[0] as Skeleton3D
	var head_idx: int = skel.find_bone("HeadTop_End")
	var foot_l: int = skel.find_bone("LeftFoot")
	var head_global: Vector3 = skel.global_transform * skel.get_bone_global_pose(head_idx).origin
	var foot_global: Vector3 = skel.global_transform * skel.get_bone_global_pose(foot_l).origin
	print("Scaled Head global pos: ", head_global)
	print("Scaled Foot global pos: ", foot_global)
	print("Scaled Height: ", head_global.y - foot_global.y)
	inst.free()
	quit(0)
