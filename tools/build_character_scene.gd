@tool
extends SceneTree

func _init() -> void:
	print("Building player_boy_character.tscn...")

	var boy_scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var boy_root: Node3D = boy_scene.instantiate() as Node3D
	boy_root.name = "BoyCharacter"
	boy_root.scale = Vector3(0.32, 0.32, 0.32)

	# Material: Inside boy palette
	var mat_boy: StandardMaterial3D = StandardMaterial3D.new()
	var boy_tex: Texture2D = load("res://assets/models/character/inside_boy_palette.png") as Texture2D
	mat_boy.albedo_texture = boy_tex
	mat_boy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_boy.roughness = 0.85
	ResourceSaver.save(mat_boy, "res://resources/materials/inside_boy_material.tres")

	var human_mesh: MeshInstance3D = boy_root.find_children("*", "MeshInstance3D")[0] as MeshInstance3D
	human_mesh.set_surface_override_material(0, mat_boy)

	# Animation Player: merge Inside boy animations
	var anim_player: AnimationPlayer = boy_root.find_children("*", "AnimationPlayer")[0] as AnimationPlayer
	var anim_lib: AnimationLibrary = load("res://resources/animations/inside_boy_animations.tres") as AnimationLibrary
	if anim_lib != null and anim_player != null and anim_player.has_animation_library(&""):
		var default_lib: AnimationLibrary = anim_player.get_animation_library(&"")
		for anim_name: StringName in anim_lib.get_animation_list():
			if not default_lib.has_animation(anim_name):
				default_lib.add_animation(anim_name, anim_lib.get_animation(anim_name))

	var animator: PlayerAnimator = PlayerAnimator.new()
	animator.name = "PlayerAnimator"
	animator.animation_player = anim_player
	boy_root.add_child(animator)

	_set_owners(boy_root, boy_root)
	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(boy_root)
	if pack_err != OK:
		push_error("Failed to pack boy character scene: " + str(pack_err))
		quit(1)
		return

	var save_err: Error = ResourceSaver.save(packed, "res://scenes/player_boy_character.tscn")
	print("Saved player_boy_character.tscn: ", save_err)

	boy_root.free()
	quit(0 if save_err == OK else 1)


static func _set_owners(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owners(child, owner_node)
