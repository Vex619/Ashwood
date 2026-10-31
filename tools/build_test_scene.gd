@tool
extends SceneTree

func _init() -> void:
	print("Building test_lab_inside.tscn (Phase 1 + Phase 2 Full Integration)...")
	var root: Node3D = Node3D.new()
	root.name = "TestLabInside"

	# -------------------------------------------------------------------------
	# 1. Environment & Lighting (Intel UHD budget: Forward+ without heavy passes)
	# -------------------------------------------------------------------------
	var env_node: WorldEnvironment = WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.14, 0.17)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Hardware target constraints: explicitly disable expensive passes
	env.sdfgi_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.volumetric_fog_enabled = false

	# Standard exponential height/depth fog enabled
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.09, 0.11, 0.14)
	env.fog_density = 0.018
	env.fog_height = 0.5
	env.fog_height_density = 0.12
	env_node.environment = env
	root.add_child(env_node)

	# 1 DirectionalLight3D (2 splits, max distance 35m, 2048 shadow atlas)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.light_color = Color(0.85, 0.88, 0.94)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 35.0
	root.add_child(sun)

	# LightmapGI node ready for baked indirect lighting
	var lightmap: LightmapGI = LightmapGI.new()
	lightmap.name = "LightmapGI"
	lightmap.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	root.add_child(lightmap)

	# -------------------------------------------------------------------------
	# 2. Materials & Phase 2 Custom Shaders
	# -------------------------------------------------------------------------
	var mat_concrete: StandardMaterial3D = StandardMaterial3D.new()
	mat_concrete.albedo_color = Color(0.24, 0.25, 0.27)
	mat_concrete.roughness = 0.85

	var mat_mud: StandardMaterial3D = StandardMaterial3D.new()
	mat_mud.albedo_color = Color(0.12, 0.11, 0.09)
	mat_mud.roughness = 0.35

	var mat_grass: StandardMaterial3D = StandardMaterial3D.new()
	mat_grass.albedo_color = Color(0.18, 0.22, 0.15)
	mat_grass.roughness = 0.92

	var mat_crate: StandardMaterial3D = StandardMaterial3D.new()
	mat_crate.albedo_color = Color(0.35, 0.28, 0.2)
	mat_crate.roughness = 0.7

	var mat_player: StandardMaterial3D = StandardMaterial3D.new()
	mat_player.albedo_color = Color(0.72, 0.15, 0.15)
	mat_player.roughness = 0.6

	# Deliverable D: Reactive Swamp Surface ShaderMaterial
	var shader_swamp: Shader = load("res://src/shaders/swamp_surface.gdshader") as Shader
	var mat_swamp_shader: ShaderMaterial = ShaderMaterial.new()
	mat_swamp_shader.shader = shader_swamp
	mat_swamp_shader.set_shader_parameter(&"mud_deep_color", Color(0.05, 0.065, 0.06, 0.94))
	mat_swamp_shader.set_shader_parameter(&"mud_sheen_color", Color(0.14, 0.17, 0.16, 0.94))
	mat_swamp_shader.set_shader_parameter(&"player_foot_world_pos", Vector3(0.0, -10.0, 0.0))
	mat_swamp_shader.set_shader_parameter(&"foot_ripple_age", 10.0)

	# Deliverable C: Fake Volumetric Light Shaft ShaderMaterials
	var shader_shaft: Shader = load("res://src/shaders/fake_volumetric_shaft.gdshader") as Shader
	var mat_shaft_bunker: ShaderMaterial = ShaderMaterial.new()
	mat_shaft_bunker.shader = shader_shaft
	mat_shaft_bunker.set_shader_parameter(&"ray_color", Color(0.62, 0.73, 0.84, 0.16))
	mat_shaft_bunker.set_shader_parameter(&"ray_energy", 1.25)
	mat_shaft_bunker.set_shader_parameter(&"depth_fade_distance", 1.35)

	var mat_shaft_swamp: ShaderMaterial = ShaderMaterial.new()
	mat_shaft_swamp.shader = shader_shaft
	mat_shaft_swamp.set_shader_parameter(&"ray_color", Color(0.52, 0.66, 0.68, 0.13))
	mat_shaft_swamp.set_shader_parameter(&"ray_energy", 1.1)
	mat_shaft_swamp.set_shader_parameter(&"depth_fade_distance", 1.6)

	# Deliverable B: Monochromatic Post-Process & Anti-Banding Dither ShaderMaterial
	var shader_post: Shader = load("res://src/shaders/inside_post_process.gdshader") as Shader
	var mat_post_process: ShaderMaterial = ShaderMaterial.new()
	mat_post_process.shader = shader_post
	mat_post_process.set_shader_parameter(&"desaturation", 0.78)
	mat_post_process.set_shader_parameter(&"vignette_base_intensity", 0.42)
	mat_post_process.set_shader_parameter(&"strain_vignette_boost", 0.0)
	mat_post_process.set_shader_parameter(&"dither_strength", 1.35)

	# -------------------------------------------------------------------------
	# 3. PlayerController3D
	# -------------------------------------------------------------------------
	var player: PlayerController3D = PlayerController3D.new()
	player.name = "Player"
	player.position = Vector3(-19.0, 0.0, 0.0)
	player.collision_layer = 2 # layer 2: player
	player.collision_mask = 1 | 4 # layer 1 (world) and layer 3 (pushables)

	var p_col: CollisionShape3D = CollisionShape3D.new()
	p_col.name = "CollisionShape3D"
	var p_capsule: CapsuleShape3D = CapsuleShape3D.new()
	p_capsule.radius = 0.35
	p_capsule.height = 1.75
	p_col.shape = p_capsule
	p_col.position = Vector3(0.0, 0.88, 0.0)
	player.add_child(p_col)

	var visual_root: Node3D = Node3D.new()
	visual_root.name = "VisualRoot"
	player.add_child(visual_root)
	player.visual_root = visual_root

	var boy_scene: PackedScene = load("res://scenes/player_boy_character.tscn") as PackedScene
	var boy_model: Node3D = boy_scene.instantiate() as Node3D
	boy_model.name = "BoyCharacter"
	visual_root.add_child(boy_model)

	var foot_l: RayCast3D = RayCast3D.new()
	foot_l.name = "FootRayLeft"
	foot_l.position = Vector3(-0.12, 0.5, 0.0)
	foot_l.target_position = Vector3(0.0, -0.65, 0.0)
	foot_l.collision_mask = 1
	player.add_child(foot_l)
	player.foot_ray_left = foot_l

	var foot_r: RayCast3D = RayCast3D.new()
	foot_r.name = "FootRayRight"
	foot_r.position = Vector3(0.12, 0.5, 0.0)
	foot_r.target_position = Vector3(0.0, -0.65, 0.0)
	foot_r.collision_mask = 1
	player.add_child(foot_r)
	player.foot_ray_right = foot_r

	var push_probe: RayCast3D = RayCast3D.new()
	push_probe.name = "PushProbe"
	push_probe.position = Vector3(0.0, 0.8, 0.0)
	push_probe.target_position = Vector3(0.62, 0.0, 0.0)
	push_probe.collision_mask = 1 | 4
	player.add_child(push_probe)
	player.push_probe = push_probe

	var climb_probe: RayCast3D = RayCast3D.new()
	climb_probe.name = "ClimbLedgeProbe"
	climb_probe.position = Vector3(0.52, 2.3, 0.0)
	climb_probe.target_position = Vector3(0.0, -2.0, 0.0)
	climb_probe.collision_mask = 1
	player.add_child(climb_probe)
	player.climb_ledge_probe = climb_probe

	var env_sensor: Area3D = Area3D.new()
	env_sensor.name = "EnvironmentSensor"
	env_sensor.collision_layer = 0
	env_sensor.collision_mask = 8 # layer 4: hazards
	var env_sensor_col: CollisionShape3D = CollisionShape3D.new()
	env_sensor_col.name = "SensorCollision"
	var env_sensor_shape: BoxShape3D = BoxShape3D.new()
	env_sensor_shape.size = Vector3(0.6, 1.6, 0.6)
	env_sensor_col.shape = env_sensor_shape
	env_sensor_col.position = Vector3(0.0, 0.88, 0.0)
	env_sensor.add_child(env_sensor_col)
	player.add_child(env_sensor)
	player.environment_sensor = env_sensor

	root.add_child(player)

	# -------------------------------------------------------------------------
	# 4. DynamicCameraRig3D
	# -------------------------------------------------------------------------
	var rig: DynamicCameraRig3D = DynamicCameraRig3D.new()
	rig.name = "DynamicCameraRig3D"
	rig.player = player

	var cam: Camera3D = Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	rig.add_child(cam)
	rig.camera = cam

	root.add_child(rig)

	# -------------------------------------------------------------------------
	# 5. FoleyAudioDirector3D (Wired to Phase 2 Mastered .wav Pools & Swamp Shader)
	# -------------------------------------------------------------------------
	var foley: FoleyAudioDirector3D = FoleyAudioDirector3D.new()
	foley.name = "FoleyAudioDirector3D"
	foley.player = player
	foley.left_foot_ray = foot_l
	foley.right_foot_ray = foot_r
	foley.swamp_surface_material = mat_swamp_shader

	var profile_concrete: SurfaceAudioProfile = load("res://resources/audio_profiles/concrete_dry.tres") as SurfaceAudioProfile
	var profile_swamp: SurfaceAudioProfile = load("res://resources/audio_profiles/swamp_deep_mud.tres") as SurfaceAudioProfile
	var profile_field: SurfaceAudioProfile = load("res://resources/audio_profiles/field_tall_grass.tres") as SurfaceAudioProfile

	foley.default_profile = profile_concrete
	var profiles: Array[SurfaceAudioProfile] = [profile_concrete, profile_swamp, profile_field]
	foley.surface_profiles = profiles

	# Breathing voice sequencer pools populated with 5 mastered variations each
	foley.breath_inhale_randomizer = _make_populated_breath_randomizer("breath_inhale", 5)
	foley.breath_exhale_randomizer = _make_populated_breath_randomizer("breath_exhale", 5)
	foley.breath_recovery_randomizer = _make_populated_breath_randomizer("breath_recovery", 5)

	root.add_child(foley)

	# Master ambient bed routed through the Ambience bus (ducked by the director).
	var ambience_bed: AudioStreamPlayer = AudioStreamPlayer.new()
	ambience_bed.name = "AmbienceBed"
	ambience_bed.bus = &"Ambience"
	ambience_bed.stream = _load_looping_wav("res://assets/audio/foley/ambience_master_hybrid.wav")
	ambience_bed.volume_db = -10.0
	ambience_bed.autoplay = true
	root.add_child(ambience_bed)

	# -------------------------------------------------------------------------
	# 6. Wire Signals (with CONNECT_PERSIST so PackedScene serializes them)
	# -------------------------------------------------------------------------
	player.kinetic_state_changed.connect(rig._on_player_kinetic_state_changed, CONNECT_PERSIST)
	player.stride_phase_triggered.connect(rig._on_player_stride_phase_triggered, CONNECT_PERSIST)
	player.strain_factor_updated.connect(rig._on_player_strain_factor_updated, CONNECT_PERSIST)

	player.kinetic_state_changed.connect(foley._on_player_kinetic_state_changed, CONNECT_PERSIST)
	player.stride_phase_triggered.connect(foley._on_player_stride_phase_triggered, CONNECT_PERSIST)
	player.strain_factor_updated.connect(foley._on_player_strain_factor_updated, CONNECT_PERSIST)

	# -------------------------------------------------------------------------
	# 7. ZONE 1: Concrete Bunker (X: -20 to 0)
	# -------------------------------------------------------------------------
	var z1_node: Node3D = Node3D.new()
	z1_node.name = "Zone1_ConcreteBunker"
	root.add_child(z1_node)

	# Bunker floor lower tier (spawn point at X = -19, top at Y = 0)
	z1_node.add_child(_make_static_box("Floor_Bunker_Start", Vector3(-19.5, -1.0, 0.0), Vector3(5.0, 2.0, 6.0), &"concrete_dry", mat_concrete))
	# Terrace 1: X: -17 to -12, top at Y = 0.8 (+0.8m hop)
	z1_node.add_child(_make_static_box("Ledge_Tier1", Vector3(-14.5, 0.4, 0.0), Vector3(5.0, 0.8, 6.0), &"concrete_dry", mat_concrete))
	# Terrace 2: X: -12 to -7, top at Y = 1.6 (+0.8m hop)
	z1_node.add_child(_make_static_box("Ledge_Tier2", Vector3(-9.5, 0.8, 0.0), Vector3(5.0, 1.6, 6.0), &"concrete_dry", mat_concrete))
	# Terrace 3: X: -7 to -2, top at Y = 2.4 (+0.8m hop, high summit)
	z1_node.add_child(_make_static_box("Ledge_Tier3", Vector3(-4.5, 1.2, 0.0), Vector3(5.0, 2.4, 6.0), &"concrete_dry", mat_concrete))
	# Lower landing pad: X: -2 to 0, top at Y = 0 (2.4m plunge for HardLand test)
	z1_node.add_child(_make_static_box("Floor_Bunker_Drop", Vector3(-1.0, -1.0, 0.0), Vector3(2.0, 2.0, 6.0), &"concrete_dry", mat_concrete))

	# Back Wall, Ceiling, and Left Wall
	z1_node.add_child(_make_static_box("BackWall_Bunker", Vector3(-10.0, 4.0, -3.0), Vector3(20.0, 8.0, 1.0), &"concrete_dry", mat_concrete))
	z1_node.add_child(_make_static_box("Ceiling_Bunker", Vector3(-10.0, 7.5, 0.0), Vector3(20.0, 1.0, 6.0), &"concrete_dry", mat_concrete))
	z1_node.add_child(_make_static_box("LeftWall_Bunker", Vector3(-22.5, 3.5, 0.0), Vector3(1.0, 9.0, 6.0), &"concrete_dry", mat_concrete))

	# Deliverable C: Volumetric Light Shafts in Concrete Bunker
	z1_node.add_child(_make_volumetric_shaft("VolumetricShaft_Bunker_01", Vector3(-16.5, 3.8, -0.6), Vector2(2.6, 6.8), Vector3(0.0, 0.0, -16.0), mat_shaft_bunker))
	z1_node.add_child(_make_volumetric_shaft("VolumetricShaft_Bunker_02", Vector3(-10.0, 4.2, -0.4), Vector2(3.0, 6.5), Vector3(0.0, 0.0, -16.0), mat_shaft_bunker))
	z1_node.add_child(_make_volumetric_shaft("VolumetricShaft_Bunker_03", Vector3(-3.5, 4.4, -0.5), Vector2(2.8, 6.6), Vector3(0.0, 0.0, -16.0), mat_shaft_bunker))

	# Spatialized Bunker Subterranean Drone
	z1_node.add_child(_make_zone_ambience_3d("Ambience_BunkerDrone", Vector3(-10.0, 2.5, 0.0), "res://assets/audio/foley/ambience_bunker_drone.wav", -6.0, 24.0))

	# Camera Region Volume 1 (Tight bunker framing)
	var cam_vol_1: CameraRegionVolume3D = CameraRegionVolume3D.new()
	_make_trigger_area(cam_vol_1, "CameraRegion_Bunker", Vector3(-10.0, 3.5, 0.0), Vector3(20.0, 9.0, 8.0))
	cam_vol_1.priority = 10
	cam_vol_1.camera_rig = rig
	cam_vol_1.framing_offset = Vector3(0.0, 1.3, 0.0)
	cam_vol_1.target_distance_z = 7.0
	cam_vol_1.pitch_degrees = -4.0
	cam_vol_1.yaw_degrees = 0.0
	cam_vol_1.base_fov = 48.0
	cam_vol_1.spring_frequency = 1.3
	cam_vol_1.spring_damping_zeta = 1.0
	cam_vol_1.spring_response_r = 0.0
	z1_node.add_child(cam_vol_1)

	# Reverb Zone 1 (Concrete Bunker)
	var rev_vol_1: AcousticReverbZone3D = AcousticReverbZone3D.new()
	_make_trigger_area(rev_vol_1, "ReverbZone_Bunker", Vector3(-10.0, 3.5, 0.0), Vector3(20.0, 9.0, 8.0))
	rev_vol_1.priority = 10
	rev_vol_1.zone_id = &"concrete_bunker"
	rev_vol_1.preset = AcousticReverbZone3D.AcousticPreset.CONCRETE_BUNKER
	z1_node.add_child(rev_vol_1)

	# -------------------------------------------------------------------------
	# 8. ZONE 2: Swampy Marsh (X: 0 to 20)
	# -------------------------------------------------------------------------
	var z2_node: Node3D = Node3D.new()
	z2_node.name = "Zone2_SwampMarsh"
	root.add_child(z2_node)

	# Swamp floor (top at Y = 0)
	z2_node.add_child(_make_static_box("Floor_Swamp", Vector3(10.0, -1.0, 0.0), Vector3(20.0, 2.0, 6.0), &"swamp_deep_mud", mat_mud))

	# Swamp hazard volume (Area3D in group "swamp_hazard")
	var swamp_hazard: Area3D = Area3D.new()
	swamp_hazard.add_to_group(&"swamp_hazard", true)
	# Layer 4 (hazards, bit value 8), mask 0: detected by the player's EnvironmentSensor.
	_make_trigger_area(swamp_hazard, "SwampHazardArea", Vector3(10.0, 0.75, 0.0), Vector3(20.0, 1.5, 6.0), 8, 0)
	swamp_hazard.monitoring = false
	z2_node.add_child(swamp_hazard)

	# Deliverable D: Reactive Swamp Visual Water/Mud Surface with subdivided mesh
	var water_mesh: MeshInstance3D = MeshInstance3D.new()
	water_mesh.name = "SwampVisualPlane"
	var water_box: BoxMesh = BoxMesh.new()
	water_box.size = Vector3(20.0, 0.22, 5.0)
	water_box.subdivide_width = 80
	water_box.subdivide_depth = 20
	water_box.material = mat_swamp_shader
	water_mesh.mesh = water_box
	water_mesh.position = Vector3(10.0, 0.1, 0.0)
	z2_node.add_child(water_mesh)

	# Deliverable C: Volumetric Light Shafts in Swampy Marsh
	z2_node.add_child(_make_volumetric_shaft("VolumetricShaft_Swamp_01", Vector3(6.0, 3.6, -0.8), Vector2(3.8, 7.2), Vector3(0.0, 0.0, -20.0), mat_shaft_swamp))
	z2_node.add_child(_make_volumetric_shaft("VolumetricShaft_Swamp_02", Vector3(14.5, 3.6, -0.6), Vector2(4.2, 7.2), Vector3(0.0, 0.0, -20.0), mat_shaft_swamp))

	# Spatialized Swamp Murk Ambience
	z2_node.add_child(_make_zone_ambience_3d("Ambience_SwampMurk", Vector3(10.0, 1.8, 0.0), "res://assets/audio/foley/ambience_swamp_murk.wav", -5.5, 24.0))

	# Camera Region Volume 2 (Overdamped heavy camera)
	var cam_vol_2: CameraRegionVolume3D = CameraRegionVolume3D.new()
	_make_trigger_area(cam_vol_2, "CameraRegion_Swamp", Vector3(10.0, 3.5, 0.0), Vector3(20.0, 9.0, 8.0))
	cam_vol_2.priority = 10
	cam_vol_2.camera_rig = rig
	cam_vol_2.framing_offset = Vector3(0.0, 1.2, 0.0)
	cam_vol_2.target_distance_z = 8.5
	cam_vol_2.pitch_degrees = -6.0
	cam_vol_2.yaw_degrees = 0.0
	cam_vol_2.base_fov = 50.0
	cam_vol_2.spring_frequency = 0.78
	cam_vol_2.spring_damping_zeta = 1.45
	cam_vol_2.spring_response_r = 0.0
	z2_node.add_child(cam_vol_2)

	# Reverb Zone 2 (Swamp Marsh)
	var rev_vol_2: AcousticReverbZone3D = AcousticReverbZone3D.new()
	_make_trigger_area(rev_vol_2, "ReverbZone_Swamp", Vector3(10.0, 3.5, 0.0), Vector3(20.0, 9.0, 8.0))
	rev_vol_2.priority = 10
	rev_vol_2.zone_id = &"swamp_marsh"
	rev_vol_2.preset = AcousticReverbZone3D.AcousticPreset.SWAMP_MARSH
	z2_node.add_child(rev_vol_2)

	# -------------------------------------------------------------------------
	# 9. ZONE 3: Windy Grass Field (X: 20 to 45)
	# -------------------------------------------------------------------------
	var z3_node: Node3D = Node3D.new()
	z3_node.name = "Zone3_WindyField"
	root.add_child(z3_node)

	# Field floor (top at Y = 0)
	z3_node.add_child(_make_static_box("Floor_Field", Vector3(32.5, -1.0, 0.0), Vector3(25.0, 2.0, 6.0), &"field_tall_grass", mat_grass))

	# Heavy pushable crate in group "pushable_heavy"
	var crate: RigidBody3D = RigidBody3D.new()
	crate.name = "HeavyPushableCrate"
	crate.add_to_group(&"pushable_heavy", true)
	crate.collision_layer = 4 # layer 3: pushables
	crate.collision_mask = 1 | 2 # collide with world and player
	crate.mass = 220.0
	crate.axis_lock_linear_z = true
	crate.axis_lock_angular_x = true
	crate.axis_lock_angular_y = true
	crate.position = Vector3(27.0, 0.75, 0.0)

	var crate_col: CollisionShape3D = CollisionShape3D.new()
	crate_col.name = "Collision"
	var crate_box: BoxShape3D = BoxShape3D.new()
	crate_box.size = Vector3(1.4, 1.4, 1.4)
	crate_col.shape = crate_box
	crate.add_child(crate_col)

	var crate_mesh: MeshInstance3D = MeshInstance3D.new()
	crate_mesh.name = "Mesh"
	var crate_mesh_box: BoxMesh = BoxMesh.new()
	crate_mesh_box.size = Vector3(1.4, 1.4, 1.4)
	crate_mesh_box.material = mat_crate
	crate_mesh.mesh = crate_mesh_box
	crate.add_child(crate_mesh)

	z3_node.add_child(crate)

	# Spatialized Open-Field Wind Ambience
	z3_node.add_child(_make_zone_ambience_3d("Ambience_FieldWind", Vector3(32.5, 2.5, 0.0), "res://assets/audio/foley/ambience_field_wind.wav", -5.0, 28.0))

	# Camera Region Volume 3 (Wide pull-back field framing)
	var cam_vol_3: CameraRegionVolume3D = CameraRegionVolume3D.new()
	_make_trigger_area(cam_vol_3, "CameraRegion_Field", Vector3(32.5, 3.5, 0.0), Vector3(25.0, 9.0, 8.0))
	cam_vol_3.priority = 10
	cam_vol_3.camera_rig = rig
	cam_vol_3.framing_offset = Vector3(0.0, 1.3, 0.0)
	cam_vol_3.target_distance_z = 11.5
	cam_vol_3.pitch_degrees = -8.0
	cam_vol_3.yaw_degrees = 0.0
	cam_vol_3.base_fov = 56.0
	cam_vol_3.spring_frequency = 1.0
	cam_vol_3.spring_damping_zeta = 1.05
	cam_vol_3.spring_response_r = 0.0
	z3_node.add_child(cam_vol_3)

	# Reverb Zone 3 (Open Field)
	var rev_vol_3: AcousticReverbZone3D = AcousticReverbZone3D.new()
	_make_trigger_area(rev_vol_3, "ReverbZone_Field", Vector3(32.5, 3.5, 0.0), Vector3(25.0, 9.0, 8.0))
	rev_vol_3.priority = 10
	rev_vol_3.zone_id = &"open_field"
	rev_vol_3.preset = AcousticReverbZone3D.AcousticPreset.OPEN_FIELD
	z3_node.add_child(rev_vol_3)

	# -------------------------------------------------------------------------
	# 10. Deliverable B: Post-Process CanvasLayer -> ColorRect
	# -------------------------------------------------------------------------
	var post_layer: CanvasLayer = CanvasLayer.new()
	post_layer.name = "PostProcessLayer"
	post_layer.layer = 32

	var post_rect: ColorRect = ColorRect.new()
	post_rect.name = "PostProcessRect"
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.material = mat_post_process
	post_layer.add_child(post_rect)
	root.add_child(post_layer)

	# -------------------------------------------------------------------------
	# 11. Deliverable E: 60 FPS Telemetry & Acoustic Debugger HUD (F3 Toggle)
	# -------------------------------------------------------------------------
	var hud: PerfHudOverlay = PerfHudOverlay.new()
	hud.name = "PerfHudOverlay"
	hud.player = player
	hud.camera_rig = rig
	hud.foley_director = foley
	hud.post_process_material = mat_post_process
	hud.start_visible = true
	root.add_child(hud)

	# -------------------------------------------------------------------------
	# 12. Pack and Save Scene
	# -------------------------------------------------------------------------
	_set_owners(root, root)
	var packed_scene: PackedScene = PackedScene.new()
	var pack_err: Error = packed_scene.pack(root)
	if pack_err != OK:
		print("FAILED to pack scene: ", pack_err)
		quit(1)
		return

	var save_err: Error = ResourceSaver.save(packed_scene, "res://scenes/test_lab_inside.tscn")
	print("Saved test_lab_inside.tscn: ", save_err)

	root.free()
	quit(0 if save_err == OK else 1)


static func _make_populated_breath_randomizer(prefix: String, count: int = 5) -> AudioStreamRandomizer:
	var r: AudioStreamRandomizer = AudioStreamRandomizer.new()
	r.random_pitch = 1.04
	r.random_volume_offset_db = 1.0
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	for i: int in range(1, count + 1):
		var wav_path: String = "res://assets/audio/foley/%s_%02d.wav" % [prefix, i]
		var stream: AudioStream = load(wav_path) as AudioStream
		if stream != null:
			r.add_stream(-1, stream, 1.0)
	return r


static func _load_looping_wav(wav_path: String) -> AudioStreamWAV:
	var wav: AudioStreamWAV = load(wav_path) as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bytes_per_frame: int = (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
		if bytes_per_frame > 0 and wav.data.size() > bytes_per_frame:
			wav.loop_begin = 0
			wav.loop_end = int(wav.data.size() / bytes_per_frame)
	return wav


static func _make_zone_ambience_3d(node_name: String, pos: Vector3, wav_path: String, vol_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.name = node_name
	p.position = pos
	p.bus = &"Ambience"
	p.stream = _load_looping_wav(wav_path)
	p.volume_db = vol_db
	p.unit_size = 10.0
	p.max_distance = max_dist
	p.autoplay = true
	return p


static func _make_volumetric_shaft(shaft_name: String, pos: Vector3, quad_size: Vector2, rot_deg: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = shaft_name
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var qm: QuadMesh = QuadMesh.new()
	qm.size = quad_size
	qm.material = mat
	mi.mesh = qm
	return mi


static func _set_owners(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_set_owners(child, owner_node)


static func _make_static_box(box_name: String, center: Vector3, size: Vector3, surface_id: StringName, mat: Material) -> StaticBody3D:
	var sb: StaticBody3D = StaticBody3D.new()
	sb.name = box_name
	sb.position = center
	sb.collision_layer = 1 # layer 1: world
	sb.collision_mask = 0
	sb.set_meta(&"surface_id", surface_id)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	sb.add_child(col)

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Mesh"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = mat
	mi.mesh = box_mesh
	sb.add_child(mi)
	return sb


## Default layer/mask: trigger lives on no layer and watches layer 2 (player).
static func _make_trigger_area(area_node: Area3D, area_name: String, center: Vector3, size: Vector3, layer: int = 0, mask: int = 2) -> Area3D:
	area_node.name = area_name
	area_node.position = center
	area_node.collision_layer = layer
	area_node.collision_mask = mask
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Collision"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	col.shape = box_shape
	area_node.add_child(col)
	return area_node
