@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	root.add_child(inst)
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D")[0] as Skeleton3D
	var head_idx: int = skel.find_bone("HeadTop_End")
	var foot_l: int = skel.find_bone("LeftFoot")
	var head_pose: Transform3D = skel.get_bone_global_pose(head_idx)
	var foot_pose: Transform3D = skel.get_bone_global_pose(foot_l)
	print("Head global pose: ", head_pose.origin)
	print("Foot global pose: ", foot_pose.origin)
	print("Height diff: ", head_pose.origin.y - foot_pose.origin.y)
	inst.free()
	quit(0)
