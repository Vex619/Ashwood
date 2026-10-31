@tool
extends SceneTree

static func _make_populated_randomizer(prefix: String, count: int = 5) -> AudioStreamRandomizer:
	var r: AudioStreamRandomizer = AudioStreamRandomizer.new()
	r.random_pitch = 1.04
	r.random_volume_offset_db = 1.2
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	for i: int in range(1, count + 1):
		var wav_path: String = "res://assets/audio/foley/%s_%02d.wav" % [prefix, i]
		var stream: AudioStream = load(wav_path) as AudioStream
		if stream == null:
			push_error("Failed to load audio stream: " + wav_path)
		else:
			r.add_stream(-1, stream, 1.0)
	return r


func _init() -> void:
	print("Populating SurfaceAudioProfile resources with mastered Playdead .wav pools...")

	# 1. Concrete Dry
	var concrete: SurfaceAudioProfile = SurfaceAudioProfile.new()
	concrete.surface_id = &"concrete_dry"
	concrete.strike_soft_randomizer = _make_populated_randomizer("concrete_strike_soft")
	concrete.strike_hard_randomizer = _make_populated_randomizer("concrete_strike_hard")
	concrete.strike_land_randomizer = _make_populated_randomizer("concrete_strike_land")
	concrete.body_texture_randomizer = _make_populated_randomizer("concrete_body_grit")
	concrete.scuff_drag_randomizer = _make_populated_randomizer("concrete_scuff_drag")
	concrete.tail_release_randomizer = _make_populated_randomizer("concrete_tail_release")
	concrete.tail_release_delay_sec = 0.08
	concrete.tail_volume_offset_db = -12.0
	concrete.base_lowpass_cutoff_hz = 14000.0
	concrete.surface_dampening = 0.0
	concrete.adds_wetness = 0.0
	var err1: Error = ResourceSaver.save(concrete, "res://resources/audio_profiles/concrete_dry.tres")
	print("Saved concrete_dry.tres: ", err1, " (streams per layer = ", concrete.strike_hard_randomizer.streams_count, ")")

	# 2. Swamp Deep Mud
	var swamp: SurfaceAudioProfile = SurfaceAudioProfile.new()
	swamp.surface_id = &"swamp_deep_mud"
	swamp.strike_soft_randomizer = _make_populated_randomizer("swamp_strike_soft")
	swamp.strike_hard_randomizer = _make_populated_randomizer("swamp_strike_hard")
	swamp.strike_land_randomizer = _make_populated_randomizer("swamp_strike_land")
	swamp.body_texture_randomizer = _make_populated_randomizer("swamp_body_slosh")
	swamp.scuff_drag_randomizer = _make_populated_randomizer("swamp_scuff_drag")
	swamp.tail_release_randomizer = _make_populated_randomizer("swamp_tail_suction")
	swamp.tail_release_delay_sec = 0.18
	swamp.tail_volume_offset_db = -4.0
	swamp.base_lowpass_cutoff_hz = 4200.0
	swamp.surface_dampening = 0.75
	swamp.adds_wetness = 1.0
	var err2: Error = ResourceSaver.save(swamp, "res://resources/audio_profiles/swamp_deep_mud.tres")
	print("Saved swamp_deep_mud.tres: ", err2, " (streams per layer = ", swamp.tail_release_randomizer.streams_count, ")")

	# 3. Field Tall Grass
	var field: SurfaceAudioProfile = SurfaceAudioProfile.new()
	field.surface_id = &"field_tall_grass"
	field.strike_soft_randomizer = _make_populated_randomizer("field_strike_soft")
	field.strike_hard_randomizer = _make_populated_randomizer("field_strike_hard")
	field.strike_land_randomizer = _make_populated_randomizer("field_strike_land")
	field.body_texture_randomizer = _make_populated_randomizer("field_body_turf")
	field.scuff_drag_randomizer = _make_populated_randomizer("field_scuff_drag")
	field.tail_release_randomizer = _make_populated_randomizer("field_tail_swish")
	field.tail_release_delay_sec = 0.14
	field.tail_volume_offset_db = -7.5
	field.base_lowpass_cutoff_hz = 9500.0
	field.surface_dampening = 0.35
	field.adds_wetness = 0.0
	var err3: Error = ResourceSaver.save(field, "res://resources/audio_profiles/field_tall_grass.tres")
	print("Saved field_tall_grass.tres: ", err3, " (streams per layer = ", field.tail_release_randomizer.streams_count, ")")

	quit(0 if (err1 == OK and err2 == OK and err3 == OK) else 1)
