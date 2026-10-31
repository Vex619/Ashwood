@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var anim_player: AnimationPlayer = inst.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	var run_anim: Animation = anim_player.get_animation("Human Armature|Run")
	print("Run anim track count: ", run_anim.get_track_count())
	for i: int in min(run_anim.get_track_count(), 10):
		print("  Track %d: path='%s' type=%d" % [i, run_anim.track_get_path(i), run_anim.track_get_type(i)])
	inst.free()
	quit(0)
