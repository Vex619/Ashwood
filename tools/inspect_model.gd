@tool
extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	print("Loaded scene: ", scene)
	if scene == null:
		quit(1)
		return
	var inst: Node = scene.instantiate()
	print("Instantiated root: ", inst.name)
	_print_tree(inst, 0)
	var players: Array[Node] = inst.find_children("*", "AnimationPlayer")
	for p: Node in players:
		var anim_player: AnimationPlayer = p as AnimationPlayer
		print("AnimationPlayer found at: ", anim_player.get_path())
		for anim_name: StringName in anim_player.get_animation_list():
			var anim: Animation = anim_player.get_animation(anim_name)
			print("   Animation: '", anim_name, "' length=", anim.length)
	inst.free()
	quit(0)

func _print_tree(n: Node, depth: int) -> void:
	var prefix: String = ""
	for i: int in depth:
		prefix += "  "
	print(prefix, "- ", n.name, " (", n.get_class(), ")")
	for c: Node in n.get_children():
		_print_tree(c, depth + 1)
