@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var anim_player: AnimationPlayer = inst.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	for name: StringName in anim_player.get_animation_list():
		var anim: Animation = anim_player.get_animation(name)
		print("Animation: '", name, "' len=", anim.length, " loop_mode=", anim.loop_mode, " tracks=", anim.get_track_count())
	inst.free()
	quit(0)
