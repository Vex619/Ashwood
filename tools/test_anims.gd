@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var anim_player: AnimationPlayer = inst.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	var working: Animation = anim_player.get_animation("Human Armature|Working")
	var skel: Skeleton3D = inst.find_children("*", "Skeleton3D")[0] as Skeleton3D
	print("Working anim tracks: ", working.get_track_count())
	inst.free()
	quit(0)
