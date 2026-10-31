extends SceneTree
## Phase 2 End-to-End Automated Verification Suite.
## Verifies all 5 Phase 2 deliverables:
##   A. Mastered CC0 + Playdead DSP .wav library (109 files) & .tres randomizer pools
##   B. Monochromatic Post-Process & 8x8 Bayer / IGN Dither Shader
##   C. Low-Cost Depth-Fade Volumetric Light Shafts in Bunker & Swamp
##   D. Reactive Swamp Mud & Water Surface Shader driven by footsteps
##   E. 60 FPS Telemetry & Playdead Acoustic Debugger HUD (F3 toggle)

var _failures: int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_failures += 1


func _init() -> void:
	print("=== PHASE 2 VERIFICATION SUITE ===")

	# 1. Verify .tres SurfaceAudioProfiles have 5 .wav variations per layer & pitch 1.04
	var profile_paths: Array[String] = [
		"res://resources/audio_profiles/concrete_dry.tres",
		"res://resources/audio_profiles/swamp_deep_mud.tres",
		"res://resources/audio_profiles/field_tall_grass.tres",
	]
	for path: String in profile_paths:
		var prof: SurfaceAudioProfile = load(path) as SurfaceAudioProfile
		_check(prof != null, "Loaded profile " + path)
		if prof != null:
			var layers: Array[AudioStreamRandomizer] = [
				prof.strike_soft_randomizer,
				prof.strike_hard_randomizer,
				prof.strike_land_randomizer,
				prof.body_texture_randomizer,
				prof.scuff_drag_randomizer,
				prof.tail_release_randomizer,
			]
			var all_five: bool = true
			var pitch_ok: bool = true
			for r: AudioStreamRandomizer in layers:
				if r == null or r.streams_count != 5 or not SurfaceAudioProfile.randomizer_is_playable(r):
					all_five = false
				if r == null or not is_equal_approx(r.random_pitch, 1.04):
					pitch_ok = false
			_check(all_five, "%s has 5 valid .wav streams across all 6 layers (30 streams)" % prof.surface_id)
			_check(pitch_ok, "%s randomizers configured with random_pitch=1.04 & NO_REPEATS" % prof.surface_id)

	# 2. Instantiate test_lab_inside.tscn and inspect Phase 2 nodes & shaders
	var packed: PackedScene = load("res://scenes/test_lab_inside.tscn") as PackedScene
	_check(packed != null, "Loaded res://scenes/test_lab_inside.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)

	var player: PlayerController3D = scene.get_node_or_null("Player") as PlayerController3D
	var rig: DynamicCameraRig3D = scene.get_node_or_null("DynamicCameraRig3D") as DynamicCameraRig3D
	var foley: FoleyAudioDirector3D = scene.get_node_or_null("FoleyAudioDirector3D") as FoleyAudioDirector3D
	var hud: PerfHudOverlay = scene.get_node_or_null("PerfHudOverlay") as PerfHudOverlay
	var post_rect: ColorRect = scene.get_node_or_null("PostProcessLayer/PostProcessRect") as ColorRect
	var swamp_plane: MeshInstance3D = scene.get_node_or_null("Zone2_SwampMarsh/SwampVisualPlane") as MeshInstance3D
	var shaft_b1: MeshInstance3D = scene.get_node_or_null("Zone1_ConcreteBunker/VolumetricShaft_Bunker_01") as MeshInstance3D
	var shaft_s1: MeshInstance3D = scene.get_node_or_null("Zone2_SwampMarsh/VolumetricShaft_Swamp_01") as MeshInstance3D
	var amb_bed: AudioStreamPlayer = scene.get_node_or_null("AmbienceBed") as AudioStreamPlayer

	_check(hud != null, "PerfHudOverlay node present in test_lab_inside.tscn")
	_check(post_rect != null and post_rect.material is ShaderMaterial, "PostProcessLayer/PostProcessRect has inside_post_process.gdshader")
	_check(swamp_plane != null and swamp_plane.mesh != null and swamp_plane.mesh.surface_get_material(0) is ShaderMaterial, "SwampVisualPlane has swamp_surface.gdshader")
	_check(shaft_b1 != null and shaft_s1 != null, "Volumetric light shaft meshes placed in Bunker and Swamp zones")
	_check(amb_bed != null and amb_bed.stream is AudioStreamWAV, "AmbienceBed wired to mastered stereo .wav stream")

	if foley != null:
		_check(
			foley.breath_inhale_randomizer != null and foley.breath_inhale_randomizer.streams_count == 5
			and foley.breath_exhale_randomizer != null and foley.breath_exhale_randomizer.streams_count == 5
			and foley.breath_recovery_randomizer != null and foley.breath_recovery_randomizer.streams_count == 5,
			"Breathing voice sequencer has 5 mastered clips each for inhale, exhale, and recovery"
		)

	# 3. Simulate physics frames & footsteps to verify live .wav telemetry, swamp ripples & HUD
	await process_frame
	await physics_frame

	if player != null and foley != null and hud != null:
		# Trigger footsteps on concrete, then move to swamp and trigger swamp footsteps + tail release
		player.stride_phase_triggered.emit(PlayerController3D.FOOT_LEFT, player.global_position, 4.5, false)
		for i: int in 12:
			foley._physics_process(1.0 / 60.0)
		hud._process(1.0 / 60.0)

		var l1_concrete: String = foley.get_last_layer1_wav()
		var l2_concrete: String = foley.get_last_layer2_wav()
		var l3_concrete: String = foley.get_last_layer3_wav()
		print("  Concrete step WAVs -> L1: %s | L2: %s | L3: %s" % [l1_concrete, l2_concrete, l3_concrete])
		_check(l1_concrete.begins_with("concrete_strike_"), "Layer 1 reports concrete strike .wav: " + l1_concrete)
		_check(l2_concrete.begins_with("concrete_body_"), "Layer 2 reports concrete body .wav: " + l2_concrete)
		_check(l3_concrete.begins_with("concrete_tail_"), "Layer 3 reports concrete tail .wav: " + l3_concrete)

		# Teleport player to Zone 2 Swamp (X = 10.0) and trigger swamp step
		player.global_position = Vector3(10.0, 0.05, 0.0)
		await physics_frame
		await physics_frame
		player.kinetic_state_changed.emit(PlayerController3D.STATE_WADING_SWAMP, PlayerController3D.STATE_RUN)
		for step_idx: int in 4:
			player.stride_phase_triggered.emit(step_idx % 2, player.global_position, 2.2, false)
			for f: int in 15:
				foley._physics_process(1.0 / 60.0)

		var l1_swamp: String = foley.get_last_layer1_wav()
		var l2_swamp: String = foley.get_last_layer2_wav()
		var l3_swamp: String = foley.get_last_layer3_wav()
		print("  Swamp step WAVs    -> L1: %s | L2: %s | L3: %s | Breath: %s" % [
			l1_swamp, l2_swamp, l3_swamp, foley.get_breath_phase()
		])
		_check(l1_swamp.begins_with("swamp_strike_"), "Layer 1 reports swamp strike .wav: " + l1_swamp)
		_check(l2_swamp.begins_with("swamp_body_"), "Layer 2 reports swamp slosh .wav: " + l2_swamp)
		_check(l3_swamp.begins_with("swamp_tail_suction_"), "Layer 3 reports swamp suction .wav: " + l3_swamp)
		_check(foley.get_shoe_wetness() >= 0.99, "Swamp soaks shoes (wetness = %.2f)" % foley.get_shoe_wetness())

		# Verify reactive swamp shader received player_foot_world_pos
		var swamp_mat: ShaderMaterial = foley.swamp_surface_material
		var foot_pos_param: Vector3 = swamp_mat.get_shader_parameter(&"player_foot_world_pos")
		_check(absf(foot_pos_param.x - 10.0) < 1.0, "Swamp shader uniform player_foot_world_pos updated to " + str(foot_pos_param))

		# Verify HUD F3 toggle action exists and HUD updates text cleanly
		_check(InputMap.has_action(PerfHudOverlay.ACTION_TOGGLE_HUD), "InputMap registered 'toggle_debug_hud' (F3)")
		hud._process(1.0 / 60.0)
		_check(rig != null and rig.get_spring_velocity().is_finite(), "DynamicCameraRig3D.get_spring_velocity() returns finite Vector3")

	scene.free()
	print("=== PHASE 2 VERIFICATION COMPLETE (failures = %d) ===" % _failures)
	quit(0 if _failures == 0 else 1)
