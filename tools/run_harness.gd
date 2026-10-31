@tool
extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://scenes/test_lab_inside.tscn") as PackedScene
	var root_node: Node = packed.instantiate()
	var harness_script: GDScript = load("res://tools/test_all_zones.gd") as GDScript
	var harness: Node = Node.new()
	harness.set_script(harness_script)
	root_node.add_child(harness)
	root.add_child(root_node)
