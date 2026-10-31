@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node3D = scene.instantiate() as Node3D
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D")[0] as Skeleton3D
	var head_idx: int = skel.find_bone("Head")
	var nose_or_head: Transform3D = skel.get_bone_global_pose(head_idx)
	print("Head global pose: ", nose_or_head.origin)
	var foot_l: Transform3D = skel.get_bone_global_pose(skel.find_bone("LeftFoot"))
	var toe_l: Transform3D = skel.get_bone_global_pose(skel.find_bone("LeftToeBase"))
	print("LeftFoot: ", foot_l.origin)
	print("LeftToe:  ", toe_l.origin)
	var toe_dir: Vector3 = toe_l.origin - foot_l.origin
	print("Toe direction from foot: ", toe_dir)
	inst.free()
	quit(0)
