@tool
extends SceneTree

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_failures += 1


func _init() -> void:
	print("=== HUMAN PLAYER & MANTLE CLIMB VERIFICATION ===")

	var packed: PackedScene = load("res://scenes/test_lab_inside.tscn") as PackedScene
	_check(packed != null, "Loaded test_lab_inside.tscn")
	if packed == null:
		quit(1)
		return

	var scene: Node = packed.instantiate()
	root.add_child(scene)

	var player: PlayerController3D = scene.get_node_or_null("Player") as PlayerController3D
	_check(player != null, "PlayerController3D node found")

	var boy_model: Node3D = scene.get_node_or_null("Player/VisualRoot/BoyCharacter") as Node3D
	_check(boy_model != null, "Humanoid boy character model found under VisualRoot")

	var skel: Skeleton3D = null
	var mesh_inst: MeshInstance3D = null
	var anim_player: AnimationPlayer = null
	if boy_model != null:
		var skels: Array[Node] = boy_model.find_children("*", "Skeleton3D")
		if not skels.is_empty():
			skel = skels[0] as Skeleton3D
		var meshes: Array[Node] = boy_model.find_children("*", "MeshInstance3D")
		if not meshes.is_empty():
			mesh_inst = meshes[0] as MeshInstance3D
		var anims: Array[Node] = boy_model.find_children("*", "AnimationPlayer")
		if not anims.is_empty():
			anim_player = anims[0] as AnimationPlayer

	_check(skel != null and skel.get_bone_count() == 48, "Humanoid Skeleton3D with 48 bones confirmed")
	_check(mesh_inst != null, "Humanoid MeshInstance3D confirmed")

	if mesh_inst != null:
		var mat: StandardMaterial3D = mesh_inst.get_surface_override_material(0) as StandardMaterial3D
		_check(mat != null and mat.albedo_texture != null, "Inside boy palette material applied as surface override")

	var animator: PlayerAnimator = scene.get_node_or_null("Player/VisualRoot/BoyCharacter/PlayerAnimator") as PlayerAnimator
	if animator == null:
		animator = scene.find_children("*", "PlayerAnimator")[0] as PlayerAnimator
	_check(animator != null, "PlayerAnimator component active on BoyCharacter")

	_check(
		anim_player != null
		and anim_player.has_animation(&"idle")
		and anim_player.has_animation(&"run")
		and anim_player.has_animation(&"wade")
		and anim_player.has_animation(&"push")
		and anim_player.has_animation(&"climb_ledge"),
		"AnimationPlayer contains idle, run, wade, push, and climb_ledge animations"
	)

	_check(player.climb_ledge_probe != null, "PlayerController3D has climb_ledge_probe configured")

	# Physics simulation test
	await process_frame
	await physics_frame

	# Test 1: Animation state transitions
	player.kinetic_state_changed.emit(PlayerController3D.STATE_WADING_SWAMP, PlayerController3D.STATE_RUN)
	_check(anim_player.current_animation == &"wade", "WadingSwamp state triggers 'wade' movement animation")

	player.kinetic_state_changed.emit(PlayerController3D.STATE_PUSH_PULL_HEAVY, PlayerController3D.STATE_RUN)
	_check(anim_player.current_animation == &"push", "PushPullHeavy state triggers 'push' heavy crate animation")

	# Test 2: Obstacle Climbing (Mantle) on Zone 1 Terrace
	# Ledge_Tier1 is at X: -14.5, top at Y: 0.8
	player.global_position = Vector3(-17.2, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	await physics_frame
	await physics_frame

	# Trigger climb check facing +X toward the terrace
	player._facing = 1.0
	player._input_axis = 1.0
	var climbed: bool = player._check_ledge_climb()
	_check(climbed, "_check_ledge_climb() detects Ledge_Tier1 (0.8m height)")
	_check(player.get_state_name() == PlayerController3D.STATE_CLIMB_LEDGE, "Player transitions to State.CLIMB_LEDGE")
	_check(anim_player.current_animation == &"climb_ledge", "AnimationPlayer plays 'climb_ledge' animation")

	# Simulate the mantle pull-up and step onto ledge
	var start_y: float = player.global_position.y
	for f: int in 60:
		player._process_climb_state(1.0 / 60.0)

	var final_y: float = player.global_position.y
	print("  Climb result -> start Y: %.2f | final Y: %.2f" % [start_y, final_y])
	_check(final_y >= 0.75, "Player successfully hoisted up onto ledge surface (Y = %.2f)" % final_y)

	scene.free()
	print("=== VERIFICATION COMPLETE (failures = %d) ===" % _failures)
	quit(0 if _failures == 0 else 1)
