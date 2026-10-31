@tool
extends SceneTree
## Phase 1 Architecture & Systems Verification Runner

func _init() -> void:
	print("=================================================================")
	print("   INSIDE LAB — PHASE 1 MASTER VERIFICATION SUITE")
	print("=================================================================")

	# 1. Test SecondOrderDynamics
	print("[Check 1/6] Testing SecondOrderDynamics...")
	var sod: SecondOrderDynamics = SecondOrderDynamics.new(1.2, 1.0, 0.0, Vector3.ZERO)
	var v: Vector3 = sod.update(0.016, Vector3(1.0, 0.0, 0.0))
	assert(v != Vector3.ZERO, "Solver must integrate non-zero delta")
	sod.apply_impulse(Vector3(0.0, -2.0, 0.0))
	sod.reconfigure(2.0, 1.5, -0.5)
	sod.reset(Vector3.ZERO)
	print("   -> SecondOrderDynamics differential solver operational.")

	# 2. Test Audio Profiles
	print("[Check 2/6] Verifying Audio Profile Resources...")
	var p_concrete: SurfaceAudioProfile = load("res://resources/audio_profiles/concrete_dry.tres") as SurfaceAudioProfile
	var p_swamp: SurfaceAudioProfile = load("res://resources/audio_profiles/swamp_deep_mud.tres") as SurfaceAudioProfile
	var p_field: SurfaceAudioProfile = load("res://resources/audio_profiles/field_tall_grass.tres") as SurfaceAudioProfile
	assert(p_concrete != null and p_concrete.surface_id == &"concrete_dry")
	assert(p_swamp != null and p_swamp.adds_wetness == 1.0)
	assert(p_field != null and p_field.surface_id == &"field_tall_grass")
	print("   -> concrete_dry.tres, swamp_deep_mud.tres, field_tall_grass.tres verified.")

	# 3. Test Scene Instantiation
	print("[Check 3/6] Instantiating res://scenes/test_lab_inside.tscn...")
	var packed: PackedScene = load("res://scenes/test_lab_inside.tscn") as PackedScene
	assert(packed != null, "Failed to load test_lab_inside.tscn")
	var scene_root: Node = packed.instantiate()
	assert(scene_root != null, "Failed to instantiate test_lab_inside.tscn")

	# 4. Check Nodes
	print("[Check 4/6] Verifying scene node graph...")
	var player: PlayerController3D = scene_root.get_node("Player") as PlayerController3D
	var rig: DynamicCameraRig3D = scene_root.get_node("DynamicCameraRig3D") as DynamicCameraRig3D
	var foley: FoleyAudioDirector3D = scene_root.get_node("FoleyAudioDirector3D") as FoleyAudioDirector3D
	var env_node: WorldEnvironment = scene_root.get_node("WorldEnvironment") as WorldEnvironment
	var sun: DirectionalLight3D = scene_root.get_node("DirectionalLight3D") as DirectionalLight3D
	var lightmap: LightmapGI = scene_root.get_node("LightmapGI") as LightmapGI
	var crate: RigidBody3D = scene_root.get_node("Zone3_WindyField/HeavyPushableCrate") as RigidBody3D

	assert(player != null, "PlayerController3D missing")
	assert(rig != null, "DynamicCameraRig3D missing")
	assert(foley != null, "FoleyAudioDirector3D missing")
	assert(env_node != null, "WorldEnvironment missing")
	assert(sun != null, "DirectionalLight3D missing")
	assert(lightmap != null, "LightmapGI missing")
	assert(crate != null and crate.is_in_group(&"pushable_heavy"), "Heavy pushable crate missing")

	# 5. Check Signal Connections
	print("[Check 5/6] Verifying signal connections...")
	assert(player.is_connected("kinetic_state_changed", Callable(rig, "_on_player_kinetic_state_changed")))
	assert(player.is_connected("stride_phase_triggered", Callable(rig, "_on_player_stride_phase_triggered")))
	assert(player.is_connected("strain_factor_updated", Callable(rig, "_on_player_strain_factor_updated")))
	assert(player.is_connected("kinetic_state_changed", Callable(foley, "_on_player_kinetic_state_changed")))
	assert(player.is_connected("stride_phase_triggered", Callable(foley, "_on_player_stride_phase_triggered")))
	assert(player.is_connected("strain_factor_updated", Callable(foley, "_on_player_strain_factor_updated")))
	print("   -> All 6 player signals connected to DynamicCameraRig3D and FoleyAudioDirector3D.")

	# 6. Check Hardware Environment Targets
	print("[Check 6/6] Checking Intel UHD WorldEnvironment budget...")
	var env: Environment = env_node.environment
	assert(not env.sdfgi_enabled, "SDFGI must be DISABLED")
	assert(not env.ssao_enabled, "SSAO must be DISABLED")
	assert(not env.ssil_enabled, "SSIL must be DISABLED")
	assert(not env.ssr_enabled, "SSR must be DISABLED")
	assert(not env.volumetric_fog_enabled, "VolumetricFog must be DISABLED")
	assert(env.fog_enabled, "Exponential height/depth fog must be ENABLED")
	assert(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "Directional shadow splits must be 2")
	assert(sun.directional_shadow_max_distance <= 35.0, "Directional shadow max distance must be <= 35m")
	print("   -> Intel UHD hardware constraints verified.")

	scene_root.free()
	print("=================================================================")
	print("   ALL PHASE 1 ARCHITECTURE CHECKS PASSED WITH 100% SUCCESS")
	print("=================================================================")
	quit(0)
