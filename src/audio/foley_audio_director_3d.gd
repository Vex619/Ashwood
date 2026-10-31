class_name FoleyAudioDirector3D
extends Node3D
## Playdead-style footstep & body Foley director (LIMBO / INSIDE techniques).
##
## Voice architecture
##   - 24 pre-allocated AudioStreamPlayer3D voices in a ring buffer (oldest voice
##     is stolen). Created once in _ready(); no runtime instantiate()/timers.
##   - Each footstep event is routed to one of 4 sub-buses
##     (Foley_Voice_0..3 -> Foley -> Master), round-robin. Each sub-bus carries a
##     low-pass filter whose cutoff is set per event from the surface profile,
##     impact energy and foot (dynamic filtering without per-voice effects).
##   - Layer 3 tails (mud suction on foot lift, grass blades springing back) are
##     fired from a fixed-capacity queue made of Packed*Array columns, ticked in
##     _physics_process.
##
## Performance techniques
##   - Left/Right foot asymmetry: per-foot pitch offset and low-pass "formant"
##     tilt so alternating steps never sound machine-gunned.
##   - LIMBO sustained-run amplitude decay: steps 1-3 at 0 dB, steps 4-12 ease
##     down to -3.5 dB; reset on surface change, jump, land or scuff.
##   - INSIDE wetness carry-over: swamp mud soaks the shoes (_shoe_wetness = 1);
##     on dry surfaces a squelch layer from the swamp profile is blended into
##     each step while wetness decays by 0.12 per step.
##   - Breathing voice sequencer (Jakob Schmid): inhale/exhale micro-clips locked
##     to every 2nd/3rd stride in Run / WadingSwamp / PushPullHeavy, scaled by
##     exertion and strain; recovery breaths on Idle until exertion settles.
##   - Inverse ambience ducking ("naked world"): high-detail steps and scuffs in
##     quiet zones dip the Ambience bus by -2.5 dB (fast attack, 0.4 s release).

const VOICE_COUNT: int = 24
const SUB_BUS_COUNT: int = 4
const TAIL_QUEUE_CAPACITY: int = 32
const MAX_PROFILES: int = 255

const MASTER_BUS: StringName = &"Master"
const FOLEY_BUS: StringName = &"Foley"
const SUB_BUS_PREFIX: String = "Foley_Voice_"
const VOICE_BUS: StringName = &"Voice"
const AMBIENCE_BUS: StringName = &"Ambience"

const TAIL_KIND_RELEASE: int = 0
const TAIL_KIND_WET_SQUELCH: int = 1

const LANDING_WINDOW_SEC: float = 0.12

@export var player: PlayerController3D
@export var left_foot_ray: RayCast3D
@export var right_foot_ray: RayCast3D
@export var surface_profiles: Array[SurfaceAudioProfile] = []
## Used when the floor carries no (or an unknown) surface_id.
@export var default_profile: SurfaceAudioProfile
## Metadata key read from floor colliders (StaticBody3D) to identify surfaces.
@export var surface_meta_key: StringName = &"surface_id"
## Optional reactive swamp shader material updated on each footstep for mud ripples.
@export var swamp_surface_material: ShaderMaterial

@export_group("Mix")
@export var stride_min_db: float = -14.0
@export var stride_max_db: float = 0.0
@export var stride_speed_for_max: float = 6.0
@export var hard_strike_speed: float = 3.4
@export var land_speed_min: float = 2.0
@export var land_speed_max: float = 14.0
@export var land_min_db: float = -8.0
@export var land_max_db: float = 1.5
@export var body_layer_offset_db: float = -4.0
@export var scuff_layer_offset_db: float = -1.5
@export var dampening_strike_attenuation_db: float = 4.0
@export var voice_unit_size: float = 6.0
@export var voice_max_distance: float = 40.0
@export_range(0.0, 1.0) var voice_panning_strength: float = 0.6

@export_group("Left Right Asymmetry")
@export var left_foot_pitch_offset: float = -0.025
@export var right_foot_pitch_offset: float = 0.02
## Low-pass tilt per foot: a subtle formant-like timbre difference.
@export var left_foot_cutoff_scale: float = 0.94
@export var right_foot_cutoff_scale: float = 1.03

@export_group("Sustained Run Decay")
@export var decay_full_level_steps: int = 3
@export var decay_floor_step: int = 12
@export var decay_floor_db: float = -3.5

@export_group("Wetness Carry Over")
@export var wetness_decay_per_step: float = 0.12
@export var wet_squelch_offset_db: float = -3.0
@export var wet_body_offset_db: float = -6.0
@export var wet_squelch_delay_scale: float = 0.6
@export var wet_squelch_pitch_offset: float = 0.04

@export_group("Breathing Voice Sequencer")
@export var breath_inhale_randomizer: AudioStreamRandomizer
@export var breath_exhale_randomizer: AudioStreamRandomizer
@export var breath_recovery_randomizer: AudioStreamRandomizer
@export var breath_min_db: float = -18.0
@export var breath_max_db: float = -4.0
@export var breath_head_height: float = 1.45
## Strain / exertion above which breaths lock to every 2nd stride (else 3rd).
@export var breath_fast_cadence_threshold: float = 0.5
@export var exertion_rise_rate: float = 0.12
@export var exertion_decay_rate: float = 0.07
@export var recovery_interval_min_sec: float = 1.4
@export var recovery_interval_max_sec: float = 3.2
@export var recovery_threshold: float = 0.08

@export_group("Ambience Ducking")
@export var ambience_duck_db: float = -2.5
@export var ambience_duck_attack_sec: float = 0.03
@export var ambience_duck_release_sec: float = 0.4
## Footsteps at or above this level count as "high detail" for ducking.
@export var high_detail_threshold_db: float = -7.0

# Voices & buses ------------------------------------------------------------
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_cursor: int = 0
var _sub_bus_names: Array[StringName] = []
var _sub_bus_filters: Array[AudioEffectLowPassFilter] = []
var _sub_bus_cursor: int = 0
var _breath_player: AudioStreamPlayer3D = null

# Profiles ------------------------------------------------------------------
var _profile_table: Array[SurfaceAudioProfile] = []
var _profile_lookup: Dictionary[StringName, int] = {}
var _default_profile_index: int = -1

# Fixed tail queue (column store, pre-allocated) -----------------------------
var _tail_active: PackedByteArray = PackedByteArray()
var _tail_kind: PackedByteArray = PackedByteArray()
var _tail_profile: PackedByteArray = PackedByteArray()
var _tail_foot: PackedByteArray = PackedByteArray()
var _tail_time_left: PackedFloat32Array = PackedFloat32Array()
var _tail_volume_db: PackedFloat32Array = PackedFloat32Array()
var _tail_cutoff_hz: PackedFloat32Array = PackedFloat32Array()
var _tail_position: PackedVector3Array = PackedVector3Array()
var _tail_pending: int = 0

# Gait memory ---------------------------------------------------------------
var _state_name: StringName = PlayerController3D.STATE_IDLE
var _strain: float = 0.0
var _last_surface_id: StringName = &""
var _last_profile_index: int = -1
var _consecutive_steps: int = 0
var _landing_window: float = 0.0
var _shoe_wetness: float = 0.0
var _wet_source_profile_index: int = -1

# Breathing -----------------------------------------------------------------
var _exertion: float = 0.0
var _breath_stride_counter: int = 0
var _breath_inhale_next: bool = true
var _recovery_timer: float = 0.0

# Ambience ducking ----------------------------------------------------------
var _ambience_bus_index: int = -1
var _ambience_base_db: float = 0.0
var _duck_current_db: float = 0.0
var _duck_hold_timer: float = 0.0

# Telemetry & reactive shader state -----------------------------------------
var _last_layer1_wav: String = "-"
var _last_layer2_wav: String = "-"
var _last_layer3_wav: String = "-"
var _breath_phase: String = "Idle"
var _foot_ripple_age: float = 10.0
var _rng_cursor: int = 0


func _ready() -> void:
	_ensure_bus_layout()
	_allocate_voices()
	_build_profile_table()
	_allocate_tail_queue()
	_ambience_bus_index = AudioServer.get_bus_index(AMBIENCE_BUS)
	if _ambience_bus_index >= 0:
		_ambience_base_db = AudioServer.get_bus_volume_db(_ambience_bus_index)


func _physics_process(delta: float) -> void:
	_landing_window = maxf(_landing_window - delta, 0.0)
	_foot_ripple_age = minf(_foot_ripple_age + delta, 10.0)
	if swamp_surface_material != null:
		swamp_surface_material.set_shader_parameter(&"foot_ripple_age", _foot_ripple_age)
	_process_tail_queue(delta)
	_process_breathing(delta)
	_process_ducking(delta)


# --------------------------------------------------------------------------
# Debug / query API
# --------------------------------------------------------------------------

func get_shoe_wetness() -> float:
	return _shoe_wetness


func get_consecutive_steps() -> int:
	return _consecutive_steps


func get_exertion() -> float:
	return _exertion


func get_last_surface_id() -> StringName:
	return _last_surface_id


func get_ambience_duck_db() -> float:
	return _duck_current_db


func get_pending_tail_count() -> int:
	return _tail_pending


func get_last_layer1_wav() -> String:
	return _last_layer1_wav


func get_last_layer2_wav() -> String:
	return _last_layer2_wav


func get_last_layer3_wav() -> String:
	return _last_layer3_wav


func get_breath_phase() -> String:
	return _breath_phase


func get_sustained_decay_db(step_number: int) -> float:
	if step_number <= decay_full_level_steps:
		return 0.0
	var span: float = float(maxi(decay_floor_step - decay_full_level_steps, 1))
	var t: float = clampf(float(step_number - decay_full_level_steps) / span, 0.0, 1.0)
	return decay_floor_db * smoothstep(0.0, 1.0, t)


# --------------------------------------------------------------------------
# Player signal handlers (wired in the scene)
# --------------------------------------------------------------------------

func _on_player_kinetic_state_changed(new_state: StringName, prev_state: StringName) -> void:
	_state_name = new_state
	if new_state == PlayerController3D.STATE_IDLE or _is_airborne_state(new_state) \
			or new_state == PlayerController3D.STATE_CLIMB_LEDGE:
		_cancel_pending_tails()
	if new_state == PlayerController3D.STATE_JUMP_START:
		_consecutive_steps = 0
	var landed: bool = _is_airborne_state(prev_state) and not _is_airborne_state(new_state)
	if landed or new_state == PlayerController3D.STATE_HARD_LAND:
		_landing_window = LANDING_WINDOW_SEC
		_consecutive_steps = 0
	if new_state == PlayerController3D.STATE_IDLE and _is_exertion_state(prev_state):
		_recovery_timer = 0.35
		_breath_stride_counter = 0
	elif _is_exertion_state(new_state) and not _is_exertion_state(prev_state):
		_breath_stride_counter = 0


func _on_player_strain_factor_updated(strain_0_to_1: float) -> void:
	_strain = clampf(strain_0_to_1, 0.0, 1.0)


func _on_player_stride_phase_triggered(foot_index: int, foot_global_pos: Vector3, impact_velocity: float, is_scuff: bool) -> void:
	var profile_index: int = _resolve_surface_profile_index(foot_index)
	if profile_index < 0:
		return
	var profile: SurfaceAudioProfile = _profile_table[profile_index]
	var is_landing: bool = _landing_window > 0.0
	var is_takeoff: bool = _state_name == PlayerController3D.STATE_JUMP_START

	# ---- LIMBO sustained-run decay -----------------------------------------
	var surface_changed: bool = profile.surface_id != _last_surface_id
	if surface_changed or is_scuff or is_landing or is_takeoff:
		_consecutive_steps = 0
	_last_surface_id = profile.surface_id
	_last_profile_index = profile_index
	_consecutive_steps += 1
	var decay_db: float = get_sustained_decay_db(_consecutive_steps)

	# ---- Layer 1 selection & level -----------------------------------------
	var strike: AudioStreamRandomizer
	var base_db: float
	if is_landing:
		strike = profile.strike_land_randomizer
		base_db = remap(clampf(impact_velocity, land_speed_min, land_speed_max), land_speed_min, land_speed_max, land_min_db, land_max_db)
	else:
		strike = profile.strike_hard_randomizer if (impact_velocity >= hard_strike_speed or is_scuff or is_takeoff) else profile.strike_soft_randomizer
		base_db = remap(clampf(impact_velocity, 0.0, stride_speed_for_max), 0.0, stride_speed_for_max, stride_min_db, stride_max_db)
	base_db += decay_db - profile.surface_dampening * dampening_strike_attenuation_db

	# ---- Tone: per-surface, per-impact, per-foot filtering -----------------
	var impact_norm: float = clampf(impact_velocity / maxf(stride_speed_for_max, 0.01), 0.0, 1.0)
	var cutoff: float = profile.base_lowpass_cutoff_hz * (1.0 - 0.5 * profile.surface_dampening * (1.0 - impact_norm))
	var is_left: bool = foot_index == PlayerController3D.FOOT_LEFT
	cutoff *= left_foot_cutoff_scale if is_left else right_foot_cutoff_scale
	var pitch_offset: float = left_foot_pitch_offset if is_left else right_foot_pitch_offset
	var bus: StringName = _claim_sub_bus(cutoff)

	_play_layer(strike, foot_global_pos, base_db, pitch_offset, bus)
	_last_layer1_wav = _sample_randomizer_wav_name(strike)

	# ---- Layer 2: body texture or drag/scuff -------------------------------
	var dragging: bool = is_scuff or _state_name == PlayerController3D.STATE_PUSH_PULL_HEAVY
	var body: AudioStreamRandomizer = profile.scuff_drag_randomizer if dragging else profile.body_texture_randomizer
	_play_layer(body, foot_global_pos, base_db + (scuff_layer_offset_db if dragging else body_layer_offset_db), pitch_offset, bus)
	_last_layer2_wav = _sample_randomizer_wav_name(body)

	# ---- Reactive swamp surface shader uniform update ----------------------
	if swamp_surface_material != null:
		swamp_surface_material.set_shader_parameter(&"player_foot_world_pos", foot_global_pos)
		_foot_ripple_age = 0.0
		swamp_surface_material.set_shader_parameter(&"foot_ripple_age", 0.0)

	# ---- Layer 3: delayed release tail -------------------------------------
	_last_layer3_wav = _sample_randomizer_wav_name(profile.tail_release_randomizer)
	var allow_tail: bool = _state_name != PlayerController3D.STATE_IDLE \
			and not _is_airborne_state(_state_name) \
			and (player == null or player.is_on_floor())
	if allow_tail:
		_enqueue_tail(TAIL_KIND_RELEASE, profile_index, foot_index, foot_global_pos,
				profile.tail_release_delay_sec, base_db + profile.tail_volume_offset_db, cutoff)

	# ---- INSIDE wetness carry-over -----------------------------------------
	if profile.adds_wetness > 0.0:
		_shoe_wetness = maxf(_shoe_wetness, profile.adds_wetness)
		_wet_source_profile_index = profile_index
	elif get_shoe_wetness() > 0.05 and _wet_source_profile_index >= 0:
		var wet_profile: SurfaceAudioProfile = _profile_table[_wet_source_profile_index]
		var wet_db: float = base_db + wet_squelch_offset_db + linear_to_db(_shoe_wetness)
		_play_layer(wet_profile.body_texture_randomizer, foot_global_pos, wet_db + wet_body_offset_db,
				pitch_offset + wet_squelch_pitch_offset, bus)
		if allow_tail:
			_enqueue_tail(TAIL_KIND_WET_SQUELCH, _wet_source_profile_index, foot_index, foot_global_pos,
					wet_profile.tail_release_delay_sec * wet_squelch_delay_scale,
					wet_db + wet_profile.tail_volume_offset_db, cutoff)
		_shoe_wetness = maxf(_shoe_wetness - wetness_decay_per_step, 0.0)
		if _shoe_wetness <= 0.05:
			_shoe_wetness = 0.0
	else:
		_shoe_wetness = 0.0

	# ---- Breathing sequencer & ambience ducking ----------------------------
	_advance_breath_sequencer()
	if is_scuff or is_landing or base_db >= high_detail_threshold_db:
		_trigger_ambience_duck()


# --------------------------------------------------------------------------
# Surface resolution
# --------------------------------------------------------------------------

func _resolve_surface_profile_index(foot_index: int) -> int:
	var ray: RayCast3D = left_foot_ray if foot_index == PlayerController3D.FOOT_LEFT else right_foot_ray
	if ray != null:
		ray.force_raycast_update()
		if ray.is_colliding():
			var collider: Object = ray.get_collider()
			if collider != null and collider.has_meta(surface_meta_key):
				var surface_id: StringName = StringName(str(collider.get_meta(surface_meta_key)))
				if _profile_lookup.has(surface_id):
					return _profile_lookup[surface_id]
			return _default_profile_index
	# Ray missed (edge of ledge / takeoff frame): reuse the last known surface.
	if _last_profile_index >= 0:
		return _last_profile_index
	return _default_profile_index


# --------------------------------------------------------------------------
# Voice playback
# --------------------------------------------------------------------------

func _claim_sub_bus(cutoff_hz: float) -> StringName:
	var slot: int = _sub_bus_cursor
	_sub_bus_cursor = (_sub_bus_cursor + 1) % SUB_BUS_COUNT
	var filter: AudioEffectLowPassFilter = _sub_bus_filters[slot]
	if filter != null:
		filter.cutoff_hz = clampf(cutoff_hz, 20.0, 20500.0)
	return _sub_bus_names[slot]


func _play_layer(randomizer: AudioStreamRandomizer, position_3d: Vector3, volume_db: float, pitch_offset: float, bus: StringName) -> void:
	if not SurfaceAudioProfile.randomizer_is_playable(randomizer):
		return
	var voice: AudioStreamPlayer3D = _voices[_voice_cursor]
	_voice_cursor = (_voice_cursor + 1) % VOICE_COUNT
	if voice.stream != randomizer:
		voice.stream = randomizer
	voice.bus = bus
	voice.global_position = position_3d
	voice.volume_db = volume_db
	voice.pitch_scale = maxf(1.0 + pitch_offset, 0.01)
	voice.play()


# --------------------------------------------------------------------------
# Layer 3 fixed tail queue
# --------------------------------------------------------------------------

func _enqueue_tail(kind: int, profile_index: int, foot_index: int, position_3d: Vector3, delay_sec: float, volume_db: float, cutoff_hz: float) -> void:
	var profile: SurfaceAudioProfile = _profile_table[profile_index]
	if not SurfaceAudioProfile.randomizer_is_playable(profile.tail_release_randomizer):
		return
	var slot: int = -1
	var soonest_slot: int = 0
	var soonest_time: float = INF
	for i: int in TAIL_QUEUE_CAPACITY:
		if _tail_active[i] == 0:
			slot = i
			break
		if _tail_time_left[i] < soonest_time:
			soonest_time = _tail_time_left[i]
			soonest_slot = i
	if slot < 0:
		# Queue saturated: fire the most imminent tail now and reuse its slot.
		_fire_tail(soonest_slot)
		slot = soonest_slot
	_tail_active[slot] = 1
	_tail_kind[slot] = kind
	_tail_profile[slot] = profile_index
	_tail_foot[slot] = foot_index
	_tail_time_left[slot] = maxf(delay_sec, 0.0)
	_tail_volume_db[slot] = volume_db
	_tail_cutoff_hz[slot] = cutoff_hz
	_tail_position[slot] = position_3d
	_tail_pending += 1


func _cancel_pending_tails() -> void:
	if _tail_pending <= 0:
		return
	_tail_active.fill(0)
	_tail_time_left.fill(0.0)
	_tail_pending = 0


func _process_tail_queue(delta: float) -> void:
	if _tail_pending <= 0:
		return
	if _state_name == PlayerController3D.STATE_IDLE or _is_airborne_state(_state_name) \
			or (player != null and (player.get_state_name() == PlayerController3D.STATE_IDLE or not player.is_on_floor())):
		_cancel_pending_tails()
		return
	for i: int in TAIL_QUEUE_CAPACITY:
		if _tail_active[i] == 0:
			continue
		var remaining: float = _tail_time_left[i] - delta
		if remaining <= 0.0:
			_fire_tail(i)
		else:
			_tail_time_left[i] = remaining


func _fire_tail(slot: int) -> void:
	if _tail_active[slot] == 0:
		return
	_tail_active[slot] = 0
	_tail_pending = maxi(_tail_pending - 1, 0)
	if _tail_kind[slot] == TAIL_KIND_WET_SQUELCH and get_shoe_wetness() <= 0.05:
		return
	var profile: SurfaceAudioProfile = _profile_table[_tail_profile[slot]]
	var is_left: bool = _tail_foot[slot] == PlayerController3D.FOOT_LEFT
	var pitch_offset: float = left_foot_pitch_offset if is_left else right_foot_pitch_offset
	if _tail_kind[slot] == TAIL_KIND_WET_SQUELCH:
		pitch_offset += wet_squelch_pitch_offset
	var bus: StringName = _claim_sub_bus(_tail_cutoff_hz[slot])
	_play_layer(profile.tail_release_randomizer, _tail_position[slot], _tail_volume_db[slot], pitch_offset, bus)
	if _tail_kind[slot] == TAIL_KIND_RELEASE or get_shoe_wetness() > 0.05:
		_last_layer3_wav = _sample_randomizer_wav_name(profile.tail_release_randomizer)


func _sample_randomizer_wav_name(randomizer: AudioStreamRandomizer) -> String:
	if randomizer == null or randomizer.streams_count <= 0:
		return "-"
	var count: int = randomizer.streams_count
	var start_idx: int = _rng_cursor % count
	_rng_cursor = (_rng_cursor + 1) % 1024
	for offset: int in count:
		var idx: int = (start_idx + offset) % count
		var stream: AudioStream = randomizer.get_stream(idx)
		if stream != null and not stream.resource_path.is_empty():
			return stream.resource_path.get_file()
	return "-"


# --------------------------------------------------------------------------
# Breathing voice sequencer
# --------------------------------------------------------------------------

func _advance_breath_sequencer() -> void:
	if not _is_exertion_state(_state_name):
		return
	_breath_stride_counter += 1
	var intensity: float = maxf(_strain, _exertion)
	var interval: int = 2 if intensity >= breath_fast_cadence_threshold else 3
	if _breath_stride_counter < interval:
		return
	_breath_stride_counter = 0
	var is_inhale: bool = _breath_inhale_next
	var clip: AudioStreamRandomizer = breath_inhale_randomizer if is_inhale else breath_exhale_randomizer
	_breath_inhale_next = not _breath_inhale_next
	_breath_phase = "Inhale (Cadence 1/%d)" % interval if is_inhale else "Exhale (Cadence 1/%d)" % interval
	_play_breath(clip, lerpf(breath_min_db, breath_max_db, intensity))


func _process_breathing(delta: float) -> void:
	if _is_exertion_state(_state_name):
		var rate: float = exertion_rise_rate
		if _state_name == PlayerController3D.STATE_WADING_SWAMP:
			rate *= 1.25
		elif _state_name == PlayerController3D.STATE_PUSH_PULL_HEAVY:
			rate *= 0.5 + _strain
		_exertion = minf(_exertion + rate * delta, 1.0)
	else:
		_exertion = maxf(_exertion - exertion_decay_rate * delta, 0.0)
		if _exertion <= recovery_threshold:
			_breath_phase = "Idle (Calm)"

	if _breath_player != null and player != null:
		_breath_player.global_position = player.global_position + Vector3(0.0, breath_head_height, 0.0)

	if _state_name == PlayerController3D.STATE_IDLE and _exertion > recovery_threshold:
		_recovery_timer -= delta
		if _recovery_timer <= 0.0:
			_breath_phase = "Recovery Pant"
			_play_breath(breath_recovery_randomizer, lerpf(breath_min_db, breath_max_db - 4.0, _exertion))
			_recovery_timer = lerpf(recovery_interval_max_sec, recovery_interval_min_sec, _exertion)


func _play_breath(clip: AudioStreamRandomizer, volume_db: float) -> void:
	if _breath_player == null or not SurfaceAudioProfile.randomizer_is_playable(clip):
		return
	if _breath_player.stream != clip:
		_breath_player.stream = clip
	_breath_player.volume_db = volume_db
	_breath_player.play()


# --------------------------------------------------------------------------
# Inverse ambience ducking
# --------------------------------------------------------------------------

func _trigger_ambience_duck() -> void:
	var zone: AcousticReverbZone3D = AcousticReverbZone3D.get_active_zone()
	if zone == null or not zone.is_quiet_zone:
		return
	_duck_hold_timer = maxf(ambience_duck_attack_sec * 2.0, 0.02)


func _process_ducking(delta: float) -> void:
	if _ambience_bus_index < 0:
		return
	var target: float = ambience_duck_db if _duck_hold_timer > 0.0 else 0.0
	_duck_hold_timer = maxf(_duck_hold_timer - delta, 0.0)
	var time_constant: float
	if target < _duck_current_db:
		time_constant = maxf(ambience_duck_attack_sec / 3.0, 0.001)
	else:
		time_constant = maxf(ambience_duck_release_sec / 3.0, 0.001)
	var previous: float = _duck_current_db
	_duck_current_db = lerpf(_duck_current_db, target, 1.0 - exp(-delta / time_constant))
	if absf(_duck_current_db) < 0.001 and target == 0.0:
		_duck_current_db = 0.0
	if _duck_current_db != previous:
		AudioServer.set_bus_volume_db(_ambience_bus_index, _ambience_base_db + _duck_current_db)


# --------------------------------------------------------------------------
# Setup (runs once)
# --------------------------------------------------------------------------

func _ensure_bus_layout() -> void:
	var foley_index: int = _ensure_bus(FOLEY_BUS, MASTER_BUS)
	if _find_effect_reverb(foley_index) == null:
		AudioServer.add_bus_effect(foley_index, AudioEffectReverb.new())

	_sub_bus_names.clear()
	_sub_bus_filters.clear()
	for k: int in SUB_BUS_COUNT:
		var bus_name: StringName = StringName(SUB_BUS_PREFIX + str(k))
		var index: int = _ensure_bus(bus_name, FOLEY_BUS)
		var filter: AudioEffectLowPassFilter = _find_effect_lowpass(index)
		if filter == null:
			filter = AudioEffectLowPassFilter.new()
			filter.cutoff_hz = 12000.0
			AudioServer.add_bus_effect(index, filter)
		_sub_bus_names.append(bus_name)
		_sub_bus_filters.append(filter)

	_ensure_bus(VOICE_BUS, FOLEY_BUS)
	_ensure_bus(AMBIENCE_BUS, MASTER_BUS)


func _ensure_bus(bus_name: StringName, send: StringName) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, send)
	return index


func _find_effect_reverb(bus_index: int) -> AudioEffectReverb:
	for i: int in AudioServer.get_bus_effect_count(bus_index):
		var effect: AudioEffectReverb = AudioServer.get_bus_effect(bus_index, i) as AudioEffectReverb
		if effect != null:
			return effect
	return null


func _find_effect_lowpass(bus_index: int) -> AudioEffectLowPassFilter:
	for i: int in AudioServer.get_bus_effect_count(bus_index):
		var effect: AudioEffectLowPassFilter = AudioServer.get_bus_effect(bus_index, i) as AudioEffectLowPassFilter
		if effect != null:
			return effect
	return null


func _allocate_voices() -> void:
	_voices.clear()
	for i: int in VOICE_COUNT:
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "FoleyVoice_%02d" % i
		voice.top_level = true
		voice.bus = _sub_bus_names[i % SUB_BUS_COUNT]
		voice.unit_size = voice_unit_size
		voice.max_distance = voice_max_distance
		voice.panning_strength = voice_panning_strength
		voice.attenuation_filter_cutoff_hz = 20500.0
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		voice.max_polyphony = 1
		add_child(voice)
		_voices.append(voice)

	_breath_player = AudioStreamPlayer3D.new()
	_breath_player.name = "BreathVoice"
	_breath_player.top_level = true
	_breath_player.bus = VOICE_BUS
	_breath_player.unit_size = voice_unit_size
	_breath_player.max_distance = voice_max_distance
	_breath_player.panning_strength = voice_panning_strength * 0.5
	_breath_player.attenuation_filter_cutoff_hz = 20500.0
	_breath_player.max_polyphony = 1
	add_child(_breath_player)


func _build_profile_table() -> void:
	_profile_table.clear()
	_profile_lookup.clear()
	_default_profile_index = -1
	if default_profile != null:
		_default_profile_index = _register_profile(default_profile)
	for profile: SurfaceAudioProfile in surface_profiles:
		if profile != null:
			_register_profile(profile)
	if _default_profile_index < 0 and not _profile_table.is_empty():
		_default_profile_index = 0


func _register_profile(profile: SurfaceAudioProfile) -> int:
	if _profile_lookup.has(profile.surface_id):
		return _profile_lookup[profile.surface_id]
	if _profile_table.size() >= MAX_PROFILES:
		push_warning("FoleyAudioDirector3D: profile table full, ignoring '%s'." % profile.surface_id)
		return -1
	_profile_table.append(profile)
	var index: int = _profile_table.size() - 1
	_profile_lookup[profile.surface_id] = index
	return index


func _allocate_tail_queue() -> void:
	_tail_active.resize(TAIL_QUEUE_CAPACITY)
	_tail_kind.resize(TAIL_QUEUE_CAPACITY)
	_tail_profile.resize(TAIL_QUEUE_CAPACITY)
	_tail_foot.resize(TAIL_QUEUE_CAPACITY)
	_tail_time_left.resize(TAIL_QUEUE_CAPACITY)
	_tail_volume_db.resize(TAIL_QUEUE_CAPACITY)
	_tail_cutoff_hz.resize(TAIL_QUEUE_CAPACITY)
	_tail_position.resize(TAIL_QUEUE_CAPACITY)
	_tail_active.fill(0)
	_tail_kind.fill(0)
	_tail_profile.fill(0)
	_tail_foot.fill(0)
	_tail_time_left.fill(0.0)
	_tail_volume_db.fill(0.0)
	_tail_cutoff_hz.fill(0.0)
	_tail_position.fill(Vector3.ZERO)
	_tail_pending = 0


static func _is_airborne_state(state_name: StringName) -> bool:
	return state_name == PlayerController3D.STATE_JUMP_START \
			or state_name == PlayerController3D.STATE_AIRBORNE_RISE \
			or state_name == PlayerController3D.STATE_AIRBORNE_FALL


static func _is_exertion_state(state_name: StringName) -> bool:
	return state_name == PlayerController3D.STATE_RUN \
			or state_name == PlayerController3D.STATE_WADING_SWAMP \
			or state_name == PlayerController3D.STATE_PUSH_PULL_HEAVY
