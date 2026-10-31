@tool
extends SceneTree

func _init() -> void:
	print("Building Inside character animation library...")
	var scene: PackedScene = load("res://assets/models/character/animated_human.fbx") as PackedScene
	var inst: Node = scene.instantiate()
	var base_anim_player: AnimationPlayer = inst.find_children("*", "AnimationPlayer")[0] as AnimationPlayer

	var idle_src: Animation = base_anim_player.get_animation("Human Armature|Idle")
	var walk_src: Animation = base_anim_player.get_animation("Human Armature|Walk")
	var run_src: Animation = base_anim_player.get_animation("Human Armature|Run")
	var jump_src: Animation = base_anim_player.get_animation("Human Armature|Jump")

	var lib: AnimationLibrary = AnimationLibrary.new()

	# 1. Idle
	var anim_idle: Animation = idle_src.duplicate()
	anim_idle.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(&"idle", anim_idle)

	# 2. Walk / Creep
	var anim_walk: Animation = walk_src.duplicate()
	anim_walk.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(&"walk", anim_walk)

	# 3. Run
	var anim_run: Animation = run_src.duplicate()
	anim_run.loop_mode = Animation.LOOP_LINEAR
	lib.add_animation(&"run", anim_run)

	# 4. Wade (Swamp Mud / Water)
	var anim_wade: Animation = _create_wade_animation(walk_src)
	lib.add_animation(&"wade", anim_wade)

	# 5. Push (Heavy Crate Pushing)
	var anim_push: Animation = _create_push_animation(walk_src)
	lib.add_animation(&"push", anim_push)

	# 6. Jump Rise
	var anim_rise: Animation = _create_jump_rise_animation(jump_src)
	lib.add_animation(&"jump_rise", anim_rise)

	# 7. Jump Fall
	var anim_fall: Animation = _create_jump_fall_animation(jump_src)
	lib.add_animation(&"jump_fall", anim_fall)

	# 8. Hard Land
	var anim_land: Animation = _create_hard_land_animation(idle_src)
	lib.add_animation(&"hard_land", anim_land)

	# 9. Climb Ledge (Obstacle Mantling)
	var anim_climb: Animation = _create_climb_animation(idle_src)
	lib.add_animation(&"climb_ledge", anim_climb)

	var err: Error = ResourceSaver.save(lib, "res://resources/animations/inside_boy_animations.tres")
	print("Saved inside_boy_animations.tres: ", err)

	inst.free()
	quit(0 if err == OK else 1)


static func _create_wade_animation(base_walk: Animation) -> Animation:
	var a: Animation = base_walk.duplicate()
	a.loop_mode = Animation.LOOP_LINEAR
	# Lengthen walk cycle for slow viscous swamp stride
	a.length = 1.35
	# Scale time of all keyframes
	var scale_t: float = 1.35 / maxf(base_walk.length, 0.01)
	for t_idx: int in a.get_track_count():
		var path: String = String(a.track_get_path(t_idx))
		for k: int in a.track_get_key_count(t_idx):
			var orig_time: float = a.track_get_key_time(t_idx, k)
			# We adjust timing by rebuilding or scaling
			var val: Variant = a.track_get_key_value(t_idx, k)
			# Add forward pitch lean to Spine / Spine1
			if path.ends_with(":Spine") or path.ends_with(":Spine1"):
				if val is Quaternion:
					var q: Quaternion = val as Quaternion
					var lean: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(18.0))
					a.track_set_key_value(t_idx, k, q * lean)
			# Lift knees higher on UpLegs
			elif path.ends_with(":LeftUpLeg") or path.ends_with(":RightUpLeg"):
				if val is Quaternion:
					var q_leg: Quaternion = val as Quaternion
					var high_knee: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(15.0))
					a.track_set_key_value(t_idx, k, q_leg * high_knee)
			# Spread arms for wading balance
			elif path.ends_with(":LeftArm"):
				if val is Quaternion:
					var q_arm: Quaternion = val as Quaternion
					var spread_l: Quaternion = Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(22.0))
					a.track_set_key_value(t_idx, k, q_arm * spread_l)
			elif path.ends_with(":RightArm"):
				if val is Quaternion:
					var q_arm: Quaternion = val as Quaternion
					var spread_r: Quaternion = Quaternion(Vector3(0.0, 0.0, -1.0), deg_to_rad(22.0))
					a.track_set_key_value(t_idx, k, q_arm * spread_r)
	return a


static func _create_push_animation(base_walk: Animation) -> Animation:
	var a: Animation = base_walk.duplicate()
	a.loop_mode = Animation.LOOP_LINEAR
	a.length = 0.85
	for t_idx: int in a.get_track_count():
		var path: String = String(a.track_get_path(t_idx))
		for k: int in a.track_get_key_count(t_idx):
			var val: Variant = a.track_get_key_value(t_idx, k)
			# Forward lean against the heavy crate
			if path.ends_with(":Spine") or path.ends_with(":Spine1") or path.ends_with(":Spine2"):
				if val is Quaternion:
					var q: Quaternion = val as Quaternion
					var push_lean: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(24.0))
					a.track_set_key_value(t_idx, k, q * push_lean)
			# Arms extended forward bracing against crate
			elif path.ends_with(":LeftArm") or path.ends_with(":RightArm"):
				if val is Quaternion:
					var brace: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(75.0))
					a.track_set_key_value(t_idx, k, brace)
			elif path.ends_with(":LeftForeArm") or path.ends_with(":RightForeArm"):
				if val is Quaternion:
					var reach: Quaternion = Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(20.0))
					a.track_set_key_value(t_idx, k, reach)
	return a


static func _create_jump_rise_animation(jump_src: Animation) -> Animation:
	var a: Animation = Animation.new()
	a.length = 0.4
	a.loop_mode = Animation.LOOP_NONE
	for t_idx: int in jump_src.get_track_count():
		var path: NodePath = jump_src.track_get_path(t_idx)
		var type: Animation.TrackType = jump_src.track_get_type(t_idx)
		var new_t: int = a.add_track(type)
		a.track_set_path(new_t, path)
		a.track_set_interpolation_type(new_t, Animation.INTERPOLATION_LINEAR)
		# Sample near the rise frame (t ~ 0.15s)
		var rise_val: Variant = _sample_track_value(jump_src, t_idx, 0.15)
		a.track_insert_key(new_t, 0.0, rise_val)
		a.track_insert_key(new_t, 0.4, rise_val)
	return a


static func _create_jump_fall_animation(jump_src: Animation) -> Animation:
	var a: Animation = Animation.new()
	a.length = 0.4
	a.loop_mode = Animation.LOOP_NONE
	for t_idx: int in jump_src.get_track_count():
		var path: NodePath = jump_src.track_get_path(t_idx)
		var type: Animation.TrackType = jump_src.track_get_type(t_idx)
		var new_t: int = a.add_track(type)
		a.track_set_path(new_t, path)
		a.track_set_interpolation_type(new_t, Animation.INTERPOLATION_LINEAR)
		# Sample near the falling frame (t ~ 0.6s)
		var fall_val: Variant = _sample_track_value(jump_src, t_idx, 0.6)
		a.track_insert_key(new_t, 0.0, fall_val)
		a.track_insert_key(new_t, 0.4, fall_val)
	return a


static func _create_hard_land_animation(idle_src: Animation) -> Animation:
	var a: Animation = Animation.new()
	a.length = 0.42
	a.loop_mode = Animation.LOOP_NONE
	for t_idx: int in idle_src.get_track_count():
		var path: NodePath = idle_src.track_get_path(t_idx)
		var path_str: String = String(path)
		var type: Animation.TrackType = idle_src.track_get_type(t_idx)
		var new_t: int = a.add_track(type)
		a.track_set_path(new_t, path)
		a.track_set_interpolation_type(new_t, Animation.INTERPOLATION_CUBIC)
		var idle_val: Variant = _sample_track_value(idle_src, t_idx, 0.0)
		var crouch_val: Variant = idle_val
		if path_str.ends_with(":Spine") or path_str.ends_with(":Spine1"):
			if idle_val is Quaternion:
				crouch_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(35.0))
		elif path_str.ends_with(":LeftUpLeg") or path_str.ends_with(":RightUpLeg"):
			if idle_val is Quaternion:
				crouch_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(65.0))
		elif path_str.ends_with(":LeftLeg") or path_str.ends_with(":RightLeg"):
			if idle_val is Quaternion:
				crouch_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-70.0))
		a.track_insert_key(new_t, 0.0, crouch_val)
		a.track_insert_key(new_t, 0.15, crouch_val)
		a.track_insert_key(new_t, 0.42, idle_val)
	return a


static func _create_climb_animation(idle_src: Animation) -> Animation:
	var a: Animation = Animation.new()
	a.length = 0.85
	a.loop_mode = Animation.LOOP_NONE
	for t_idx: int in idle_src.get_track_count():
		var path: NodePath = idle_src.track_get_path(t_idx)
		var path_str: String = String(path)
		var type: Animation.TrackType = idle_src.track_get_type(t_idx)
		var new_t: int = a.add_track(type)
		a.track_set_path(new_t, path)
		a.track_set_interpolation_type(new_t, Animation.INTERPOLATION_CUBIC)
		var idle_val: Variant = _sample_track_value(idle_src, t_idx, 0.0)

		# 3 keyframe phases: Grab (t=0), Hoist (t=0.4), Stand (t=0.85)
		var k0_val: Variant = idle_val
		var k1_val: Variant = idle_val
		var k2_val: Variant = idle_val

		if path_str.ends_with(":LeftArm") or path_str.ends_with(":RightArm"):
			if idle_val is Quaternion:
				# Reaching straight up to grab the ledge
				k0_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(135.0))
				# Pulling down level with chest
				k1_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(45.0))
				k2_val = idle_val
		elif path_str.ends_with(":Spine") or path_str.ends_with(":Spine1"):
			if idle_val is Quaternion:
				k0_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-10.0))
				k1_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(28.0))
				k2_val = idle_val
		elif path_str.ends_with(":RightUpLeg"):
			if idle_val is Quaternion:
				# Hanging dangling
				k0_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(-15.0))
				# Knee swings up onto ledge top
				k1_val = (idle_val as Quaternion) * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(75.0))
				k2_val = idle_val

		a.track_insert_key(new_t, 0.0, k0_val)
		a.track_insert_key(new_t, 0.4, k1_val)
		a.track_insert_key(new_t, 0.85, k2_val)
	return a


static func _sample_track_value(anim: Animation, track_idx: int, target_time: float) -> Variant:
	var count: int = anim.track_get_key_count(track_idx)
	if count <= 0:
		return null
	var best_k: int = 0
	var min_diff: float = INF
	for k: int in count:
		var diff: float = absf(anim.track_get_key_time(track_idx, k) - target_time)
		if diff < min_diff:
			min_diff = diff
			best_k = k
	return anim.track_get_key_value(track_idx, best_k)
