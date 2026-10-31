@tool
extends SceneTree

func _init() -> void:
	print("Testing player boy assembly...")
	var root_node: Node3D = Node3D.new()

	var player: PlayerController3D = PlayerController3D.new()
	player.name = "Player"
	root_node.add_child(player)

	var visual_root: Node3D = Node3D.new()
	visual_root.name = "VisualRoot"
	player.add_child(visual_root)
	player.visual_root = visual_root

	var boy_scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	if boy_scene == null:
		push_error("Failed to load animated_human.fbx")
		quit(1)
		return

	var boy_model: Node3D = boy_scene.instantiate() as Node3D
	boy_model.name = "BoyCharacter"
	boy_model.scale = Vector3(0.32, 0.32, 0.32)
	boy_model.position = Vector3(0.0, 0.0, 0.0)

	var mat_boy: StandardMaterial3D = StandardMaterial3D.new()
	var boy_tex: Texture2D = load("res://assets/models/character/inside_boy_palette.png") as Texture2D
	mat_boy.albedo_texture = boy_tex
	mat_boy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_boy.roughness = 0.85

	var meshes: Array[Node] = boy_model.find_children("*", "MeshInstance3D")
	if meshes.is_empty():
		push_error("No MeshInstance3D in boy model")
		quit(1)
		return
	var human_mesh: MeshInstance3D = meshes[0] as MeshInstance3D
	human_mesh.set_surface_override_material(0, mat_boy)

	var anim_players: Array[Node] = boy_model.find_children("*", "AnimationPlayer")
	var anim_player: AnimationPlayer = anim_players[0] as AnimationPlayer
	var anim_lib: AnimationLibrary = load("res://resources/animations/inside_boy_animations.tres") as AnimationLibrary
	if anim_lib != null and anim_player.has_animation_library(&""):
		var default_lib: AnimationLibrary = anim_player.get_animation_library(&"")
		for anim_name: StringName in anim_lib.get_animation_list():
			if not default_lib.has_animation(anim_name):
				default_lib.add_animation(anim_name, anim_lib.get_animation(anim_name))

	visual_root.add_child(boy_model)

	var animator: PlayerAnimator = PlayerAnimator.new()
	animator.name = "PlayerAnimator"
	animator.player = player
	animator.animation_player = anim_player
	visual_root.add_child(animator)

	# Test animation switching
	animator._play_state_animation(PlayerController3D.STATE_IDLE, 0.0)
	print("Playing idle: ", anim_player.current_animation)
	assert(anim_player.current_animation == &"idle")

	animator._play_state_animation(PlayerController3D.STATE_RUN, 0.1)
	print("Playing run: ", anim_player.current_animation)
	assert(anim_player.current_animation == &"run")

	animator._play_state_animation(PlayerController3D.STATE_WADING_SWAMP, 0.1)
	print("Playing wade: ", anim_player.current_animation)
	assert(anim_player.current_animation == &"wade")

	animator._play_state_animation(PlayerController3D.STATE_CLIMB_LEDGE, 0.1)
	print("Playing climb_ledge: ", anim_player.current_animation)
	assert(anim_player.current_animation == &"climb_ledge")

	animator._play_state_animation(PlayerController3D.STATE_PUSH_PULL_HEAVY, 0.1)
	print("Playing push: ", anim_player.current_animation)
	assert(anim_player.current_animation == &"push")

	root_node.free()
	print("All player boy assembly and animation tests passed!")
	quit(0)
