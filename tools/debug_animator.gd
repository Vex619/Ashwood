@tool
extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/test_lab_inside.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var animators: Array[Node] = scene.find_children("*", "PlayerAnimator")
	print("Animators found: ", animators.size())
	for a: Node in animators:
		print("Animator path: ", a.get_path())
	scene.free()
	quit(0)
