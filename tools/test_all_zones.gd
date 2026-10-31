extends Node
## End-to-end traversal test (no teleports). Holds move_right, auto-jumps only
## when blocked by a wall, and asserts every Phase 1 system fires along the way:
## HSM states, HardLand, swamp wading, wetness carry-over, LIMBO step decay,
## crate push + strain, camera region registration, reverb zone switching and
## reverb crossfade, ambience ducking, exertion build-up.

const MAX_FRAMES: int = 60 * 30

var _player: PlayerController3D
var _rig: DynamicCameraRig3D
var _foley: FoleyAudioDirector3D
var _crate: RigidBody3D
var _reverb: AudioEffectReverb

var _frames: int = 0
var _jump_hold: int = 0
var _states_seen: Dictionary[StringName, bool] = {}
var _regions_seen: Dictionary[StringName, bool] = {}
var _zones_seen: Dictionary[StringName, bool] = {}
var _left_steps: int = 0
var _right_steps: int = 0
var _max_wetness: float = 0.0
var _saw_dry_decay: bool = false
var _max_consecutive: int = 0
var _max_strain: float = 0.0
var _min_duck_db: float = 0.0
var _max_exertion: float = 0.0
var _crate_start_x: float = 0.0
var _bunker_fov: float = 0.0
var _field_fov: float = 0.0


func _ready() -> void:
	_player = get_parent().get_node("Player") as PlayerController3D
	_rig = get_parent().get_node("DynamicCameraRig3D") as DynamicCameraRig3D
	_foley = get_parent().get_node("FoleyAudioDirector3D") as FoleyAudioDirector3D
	_crate = get_parent().get_node("Zone3_WindyField/HeavyPushableCrate") as RigidBody3D
	var foley_bus: int = AudioServer.get_bus_index(&"Foley")
	_reverb = AudioServer.get_bus_effect(foley_bus, 0) as AudioEffectReverb
	_crate_start_x = _crate.global_position.x
	_player.kinetic_state_changed.connect(_on_state)
	_player.stride_phase_triggered.connect(_on_stride)
	print("--- END-TO-END TRAVERSAL TEST ---")


func _on_state(new_state: StringName, prev_state: StringName) -> void:
	_states_seen[new_state] = true
	print("  [%4d] x=%6.2f  %s -> %s" % [_frames, _player.global_position.x, prev_state, new_state])


func _on_stride(foot_index: int, _pos: Vector3, _impact: float, _is_scuff: bool) -> void:
	if foot_index == 0:
		_left_steps += 1
	else:
		_right_steps += 1


func _physics_process(_delta: float) -> void:
	_frames += 1
	Input.action_press(&"move_right", 1.0)

	# Auto-jump when entering the open field to test jump kinematics alongside mantle climbs
	if _jump_hold > 0:
		_jump_hold -= 1
		if _jump_hold == 0:
			Input.action_release(&"jump")
	elif _player.global_position.x > 21.2 and _player.global_position.x < 22.2 and _player.is_on_floor() and not _states_seen.has(PlayerController3D.STATE_JUMP_START):
		Input.action_press(&"jump", 1.0)
		_jump_hold = 14
	elif _player.is_on_floor() and _player.is_on_wall() and _player.global_position.x < 20.0:
		Input.action_press(&"jump", 1.0)
		_jump_hold = 18

	var region: CameraRegionVolume3D = _rig.get_active_region()
	if region != null:
		_regions_seen[StringName(region.name)] = true
	var zone: AcousticReverbZone3D = AcousticReverbZone3D.get_active_zone()
	if zone != null:
		_zones_seen[zone.zone_id] = true

	var wet: float = _foley.get_shoe_wetness()
	_max_wetness = maxf(_max_wetness, wet)
	if _player.global_position.x > 20.5 and wet < 1.0 and wet > 0.0:
		_saw_dry_decay = true
	_max_consecutive = maxi(_max_consecutive, _foley.get_consecutive_steps())
	_max_strain = maxf(_max_strain, _player.get_strain())
	_min_duck_db = minf(_min_duck_db, _foley.get_ambience_duck_db())
	_max_exertion = maxf(_max_exertion, _foley.get_exertion())
	if _player.global_position.x < -10.0 and _player.global_position.x > -12.0:
		_bunker_fov = _rig.camera.fov

	if _frames % 120 == 0:
		print("  frame %4d | x=%6.2f y=%5.2f | %s | wet=%.2f strain=%.2f | cam z=%.2f fov=%.1f | reverb room=%.2f wet=%.2f" % [
				_frames, _player.global_position.x, _player.global_position.y, _player.get_state_name(),
				wet, _player.get_strain(), _rig.camera.global_position.z, _rig.camera.fov,
				_reverb.room_size, _reverb.wet])

	if _crate.global_position.x > 41.0 or _frames >= MAX_FRAMES:
		_field_fov = _rig.camera.fov
		_finish()


func _finish() -> void:
	set_physics_process(false)
	Input.action_release(&"move_right")
	print("--- RESULTS after %d frames ---" % _frames)
	print("  player x: %.2f | crate moved: %.2f m" % [_player.global_position.x, _crate.global_position.x - _crate_start_x])
	print("  states seen: ", _states_seen.keys())
	print("  camera regions seen: ", _regions_seen.keys())
	print("  reverb zones seen: ", _zones_seen.keys())
	print("  steps L/R: %d/%d | max consecutive: %d | max wetness: %.2f | dry decay: %s" % [_left_steps, _right_steps, _max_consecutive, _max_wetness, _saw_dry_decay])
	print("  max strain: %.2f | min ambience duck: %.2f dB | max exertion: %.2f" % [_max_strain, _min_duck_db, _max_exertion])
	print("  bunker fov: %.2f | field fov: %.2f | final reverb room=%.2f damping=%.2f wet=%.2f" % [_bunker_fov, _field_fov, _reverb.room_size, _reverb.damping, _reverb.wet])

	var failures: PackedStringArray = PackedStringArray()
	for s: StringName in [PlayerController3D.STATE_RUN, PlayerController3D.STATE_JUMP_START, PlayerController3D.STATE_AIRBORNE_RISE,
			PlayerController3D.STATE_AIRBORNE_FALL, PlayerController3D.STATE_HARD_LAND, PlayerController3D.STATE_WADING_SWAMP,
			PlayerController3D.STATE_PUSH_PULL_HEAVY, PlayerController3D.STATE_CLIMB_LEDGE]:
		if not _states_seen.has(s):
			failures.append("state not reached: %s" % s)
	for r: StringName in [&"CameraRegion_Bunker", &"CameraRegion_Swamp", &"CameraRegion_Field"]:
		if not _regions_seen.has(r):
			failures.append("camera region never active: %s" % r)
	for z: StringName in [&"concrete_bunker", &"swamp_marsh", &"open_field"]:
		if not _zones_seen.has(z):
			failures.append("reverb zone never active: %s" % z)
	if _crate.global_position.x - _crate_start_x < 3.0:
		failures.append("crate barely moved")
	if _left_steps < 5 or _right_steps < 5:
		failures.append("left/right stride alternation missing")
	if _max_wetness < 1.0 or not _saw_dry_decay:
		failures.append("wetness carry-over not observed")
	if _max_consecutive < 5:
		failures.append("sustained-run step counter never exceeded 4")
	if _max_strain < 0.3:
		failures.append("push strain too low")
	if _min_duck_db > -1.0:
		failures.append("ambience ducking never engaged")
	if _max_exertion < 0.2:
		failures.append("exertion never built up")
	# Bunker region base FOV is 48 (+ up to 2.5 run boost); the rig default is 50.
	if _bunker_fov < 47.0 or _bunker_fov > 50.6:
		failures.append("bunker region FOV not applied (%.2f)" % _bunker_fov)
	if _field_fov < 54.0:
		failures.append("field region FOV not applied (%.2f)" % _field_fov)
	if absf(_reverb.room_size - 0.85) > 0.05:
		failures.append("reverb did not crossfade to open field")

	if failures.is_empty():
		print("✅ END-TO-END TRAVERSAL: ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for f: String in failures:
			print("❌ ", f)
		get_tree().quit(1)
