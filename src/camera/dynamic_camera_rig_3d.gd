class_name DynamicCameraRig3D
extends Node3D
## INSIDE-style side-on camera rig.
##
## Macro layer: the highest-priority CameraRegionVolume3D overlapping the player
## supplies framing (offset, distance, pitch, yaw, FOV) and spring settings.
## Micro layer: activity modifiers derived from PlayerController3D state:
##   Run           - delayed predictive X look-ahead, FOV boost, stride cadence.
##   Jump / Fall   - vertical platforming deadzone, downward fall look-ahead,
##                   HardLand impulse + trauma roll.
##   PushPullHeavy - closer framing, Dutch lean into push, Perlin micro-strain.
##   WadingSwamp   - forced overdamped spring response.
##   Extended Idle - slow creep-in and FOV tighten after inactivity.
##
## Three SecondOrderDynamics solvers smooth the result:
##   Position -> camera world position
##   Rotation -> (pitch, yaw, 0) in degrees
##   Aux      -> (FOV, DutchTilt, TraumaRoll) in degrees
## High-frequency micro noise (strain / trauma) is layered after the solvers so
## it is never smeared by the springs.

const RIG_GROUP: StringName = &"dynamic_camera_rig"

@export var player: PlayerController3D
@export var camera: Camera3D

@export_group("Default Framing")
@export var default_framing_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
@export var default_distance_z: float = 8.0
@export var default_pitch_degrees: float = -6.0
@export var default_yaw_degrees: float = 0.0
@export var default_fov: float = 50.0
@export var default_spring_frequency: float = 1.2
@export var default_spring_damping_zeta: float = 1.0
@export var default_spring_response_r: float = 0.0
## Rate at which spring parameters blend between regions (1/s).
@export var spring_param_blend_rate: float = 2.5

@export_group("Rotation & Aux Springs")
@export var rotation_frequency_scale: float = 0.8
@export var aux_frequency: float = 1.4
@export var aux_damping_zeta: float = 0.8
@export var aux_response_r: float = 0.0

@export_group("Run")
@export var run_lookahead_delay_sec: float = 0.35
@export var run_lookahead_ramp_sec: float = 0.9
@export var run_lookahead_distance: float = 1.8
@export var run_fov_boost: float = 2.5
## Downward velocity kick per running stride (m/s) -> subtle vertical cadence.
@export var run_cadence_impulse: float = 0.11

@export_group("Jump & Fall")
@export var vertical_deadzone: float = 1.15
@export var fall_lookahead_speed_threshold: float = 7.0
@export var fall_lookahead_gain: float = 0.16
@export var fall_lookahead_max: float = 2.6
@export var hard_land_impulse: float = 2.4
@export var hard_land_roll_impulse_deg: float = 9.0
@export var hard_land_trauma: float = 0.55

@export_group("Push Pull Heavy")
@export var push_distance_offset: float = -1.25
@export var push_dutch_degrees: float = 0.85
@export var push_noise_frequency: float = 1.6
@export var push_noise_position_amplitude: float = 0.035
@export var push_noise_roll_amplitude_deg: float = 0.35
@export var push_blend_rate: float = 2.5

@export_group("Wading Swamp")
@export var swamp_min_zeta: float = 1.45
@export var swamp_frequency_scale: float = 0.65
@export var swamp_blend_rate: float = 2.0

@export_group("Extended Idle")
@export var idle_delay_sec: float = 3.0
@export var idle_ramp_sec: float = 2.5
@export var idle_fov_offset: float = -1.5
@export var idle_distance_offset: float = -0.65
@export var idle_release_rate: float = 2.5

@export_group("Trauma")
@export var trauma_decay_rate: float = 1.4
@export var trauma_noise_frequency: float = 9.0
@export var trauma_roll_amplitude_deg: float = 1.2
@export var trauma_position_amplitude: float = 0.05

var _regions: Array[CameraRegionVolume3D] = []
var _active_region: CameraRegionVolume3D = null

var _pos_solver: SecondOrderDynamics
var _rot_solver: SecondOrderDynamics
var _aux_solver: SecondOrderDynamics
var _noise: FastNoiseLite

var _cur_frequency: float = 1.2
var _cur_zeta: float = 1.0
var _cur_response: float = 0.0

var _state_name: StringName = PlayerController3D.STATE_IDLE
var _strain: float = 0.0
var _anchor_y: float = 0.0
var _run_time: float = 0.0
var _push_weight: float = 0.0
var _swamp_weight: float = 0.0
var _idle_weight: float = 0.0
var _trauma: float = 0.0
var _noise_time: float = 0.0
var _initialized: bool = false


func _ready() -> void:
	add_to_group(RIG_GROUP)
	process_physics_priority = 10
	if camera == null:
		camera = get_node_or_null(^"Camera3D") as Camera3D
	if camera != null:
		camera.top_level = true
		camera.make_current()

	_cur_frequency = default_spring_frequency
	_cur_zeta = default_spring_damping_zeta
	_cur_response = default_spring_response_r
	_pos_solver = SecondOrderDynamics.new(_cur_frequency, _cur_zeta, _cur_response, global_position)
	_rot_solver = SecondOrderDynamics.new(_cur_frequency * rotation_frequency_scale, _cur_zeta, 0.0, Vector3.ZERO)
	_aux_solver = SecondOrderDynamics.new(aux_frequency, aux_damping_zeta, aux_response_r, Vector3(default_fov, 0.0, 0.0))

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0
	_noise.seed = 1337
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


func register_region(region: CameraRegionVolume3D) -> void:
	if region == null:
		return
	_regions.erase(region)
	_regions.append(region)
	_refresh_active_region()


func unregister_region(region: CameraRegionVolume3D) -> void:
	_regions.erase(region)
	_refresh_active_region()


func get_active_region() -> CameraRegionVolume3D:
	return _active_region


func get_spring_velocity() -> Vector3:
	return _pos_solver.get_velocity() if _pos_solver != null else Vector3.ZERO



func _refresh_active_region() -> void:
	var best: CameraRegionVolume3D = null
	for region: CameraRegionVolume3D in _regions:
		if not is_instance_valid(region):
			continue
		# >= : ties go to the most recently entered volume (later in the list).
		if best == null or region.priority >= best.priority:
			best = region
	_active_region = best


func _physics_process(delta: float) -> void:
	if player == null or camera == null or delta <= 0.0:
		return

	# ---- Macro: region framing --------------------------------------------
	var offset: Vector3 = default_framing_offset
	var distance: float = default_distance_z
	var pitch: float = default_pitch_degrees
	var yaw: float = default_yaw_degrees
	var fov: float = default_fov
	var target_f: float = default_spring_frequency
	var target_z: float = default_spring_damping_zeta
	var target_r: float = default_spring_response_r
	if _active_region != null and is_instance_valid(_active_region):
		offset = _active_region.framing_offset
		distance = _active_region.target_distance_z
		pitch = _active_region.pitch_degrees
		yaw = _active_region.yaw_degrees
		fov = _active_region.base_fov
		target_f = _active_region.spring_frequency
		target_z = _active_region.spring_damping_zeta
		target_r = _active_region.spring_response_r

	var player_pos: Vector3 = player.global_position
	var player_vel: Vector3 = player.velocity
	var airborne: bool = player.is_airborne_state()

	# ---- Micro: Run look-ahead -------------------------------------------
	var run_speed: float = maxf(player.get_run_speed(), 0.01)
	var running: bool = _state_name == PlayerController3D.STATE_RUN \
			or (airborne and absf(player_vel.x) > run_speed * 0.6)
	var ramp_end: float = run_lookahead_delay_sec + run_lookahead_ramp_sec
	if running:
		_run_time = minf(_run_time + delta, ramp_end)
	else:
		_run_time = maxf(_run_time - delta * 1.5, 0.0)
	var run_ramp: float = smoothstep(run_lookahead_delay_sec, ramp_end, _run_time)
	var speed_ratio: float = clampf(absf(player_vel.x) / run_speed, 0.0, 1.0)
	var lookahead_x: float = signf(player_vel.x) * run_lookahead_distance * run_ramp * speed_ratio

	# ---- Micro: vertical deadzone & fall look-ahead ----------------------
	if not _initialized or not airborne:
		_anchor_y = player_pos.y
	elif player_pos.y > _anchor_y + vertical_deadzone:
		_anchor_y = player_pos.y - vertical_deadzone
	elif player_pos.y < _anchor_y:
		_anchor_y = player_pos.y
	var fall_lookahead: float = 0.0
	if airborne and player_vel.y < -fall_lookahead_speed_threshold:
		fall_lookahead = -clampf((-player_vel.y - fall_lookahead_speed_threshold) * fall_lookahead_gain, 0.0, fall_lookahead_max)

	# ---- Micro: activity weights -----------------------------------------
	var push_target: float = 1.0 if _state_name == PlayerController3D.STATE_PUSH_PULL_HEAVY else 0.0
	_push_weight = move_toward(_push_weight, push_target, push_blend_rate * delta)
	var swamp_target: float = 1.0 if (_state_name == PlayerController3D.STATE_WADING_SWAMP or player.is_in_swamp()) else 0.0
	_swamp_weight = move_toward(_swamp_weight, swamp_target, swamp_blend_rate * delta)
	var idle_time: float = player.get_time_since_input()
	if idle_time > idle_delay_sec and not airborne:
		_idle_weight = maxf(_idle_weight, smoothstep(idle_delay_sec, idle_delay_sec + idle_ramp_sec, idle_time))
	else:
		_idle_weight = move_toward(_idle_weight, 0.0, idle_release_rate * delta)

	# ---- Spring parameters (blended, swamp override) ---------------------
	var param_blend: float = 1.0 - exp(-spring_param_blend_rate * delta)
	_cur_frequency = lerpf(_cur_frequency, target_f, param_blend)
	_cur_zeta = lerpf(_cur_zeta, target_z, param_blend)
	_cur_response = lerpf(_cur_response, target_r, param_blend)
	var f: float = _cur_frequency * lerpf(1.0, swamp_frequency_scale, _swamp_weight)
	var z: float = lerpf(_cur_zeta, maxf(_cur_zeta, swamp_min_zeta), _swamp_weight)
	var r: float = lerpf(_cur_response, minf(_cur_response, 0.0), _swamp_weight)
	_pos_solver.reconfigure(f, z, r)
	_rot_solver.reconfigure(f * rotation_frequency_scale, z, 0.0)
	var aux_f: float = aux_frequency * lerpf(1.0, swamp_frequency_scale, _swamp_weight)
	var aux_z: float = lerpf(aux_damping_zeta, maxf(aux_damping_zeta, swamp_min_zeta), _swamp_weight)
	_aux_solver.reconfigure(aux_f, aux_z, aux_response_r)

	# ---- Targets ----------------------------------------------------------
	var final_distance: float = distance + push_distance_offset * _push_weight + idle_distance_offset * _idle_weight
	var final_fov: float = fov + run_fov_boost * run_ramp + idle_fov_offset * _idle_weight
	var dutch: float = push_dutch_degrees * player.get_push_direction() * _push_weight
	var focus: Vector3 = Vector3(player_pos.x + lookahead_x, _anchor_y + fall_lookahead, player_pos.z) + offset
	var target_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	var cam_target: Vector3 = focus + target_basis * Vector3(0.0, 0.0, final_distance)
	var rot_target: Vector3 = Vector3(pitch, yaw, 0.0)
	var aux_target: Vector3 = Vector3(final_fov, dutch, 0.0)

	if not _initialized:
		_pos_solver.reset(cam_target)
		_rot_solver.reset(rot_target)
		_aux_solver.reset(aux_target)
		_initialized = true

	var cam_pos: Vector3 = _pos_solver.update(delta, cam_target)
	var rot: Vector3 = _rot_solver.update(delta, rot_target)
	var aux: Vector3 = _aux_solver.update(delta, aux_target)

	# ---- Post-solver micro noise -----------------------------------------
	_noise_time += delta
	_trauma = maxf(_trauma - trauma_decay_rate * delta, 0.0)
	var shake: float = _trauma * _trauma
	var strain_amount: float = _strain * _push_weight
	var ts: float = _noise_time * push_noise_frequency
	var tt: float = _noise_time * trauma_noise_frequency
	var strain_noise: Vector3 = Vector3(
			_noise.get_noise_2d(ts, 0.0),
			_noise.get_noise_2d(ts, 37.1),
			_noise.get_noise_2d(ts, 91.7))
	var trauma_noise: Vector3 = Vector3(
			_noise.get_noise_2d(tt, 211.3),
			_noise.get_noise_2d(tt, 263.9),
			_noise.get_noise_2d(tt, 317.5))
	var pos_jitter: Vector3 = Vector3(strain_noise.x, strain_noise.y, 0.0) * (push_noise_position_amplitude * strain_amount) \
			+ Vector3(trauma_noise.x, trauma_noise.y, 0.0) * (trauma_position_amplitude * shake)
	var roll: float = aux.y + aux.z \
			+ strain_noise.z * push_noise_roll_amplitude_deg * strain_amount \
			+ trauma_noise.z * trauma_roll_amplitude_deg * shake

	var cam_basis: Basis = Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(roll)))
	camera.global_transform = Transform3D(cam_basis, cam_pos + cam_basis * pos_jitter)
	camera.fov = clampf(aux.x, 1.0, 179.0)
	global_position = focus


# --------------------------------------------------------------------------
# Player signal handlers (wired in the scene)
# --------------------------------------------------------------------------

func _on_player_kinetic_state_changed(new_state: StringName, _prev_state: StringName) -> void:
	_state_name = new_state
	if new_state == PlayerController3D.STATE_HARD_LAND and _initialized:
		_pos_solver.apply_impulse(Vector3(0.0, -hard_land_impulse, 0.0))
		var roll_sign: float = -1.0 if player != null and player.get_facing() > 0.0 else 1.0
		_aux_solver.apply_impulse(Vector3(0.0, 0.0, hard_land_roll_impulse_deg * roll_sign))
		_trauma = minf(_trauma + hard_land_trauma, 1.0)


func _on_player_stride_phase_triggered(_foot_index: int, _foot_global_pos: Vector3, impact_velocity: float, is_scuff: bool) -> void:
	if not _initialized:
		return
	if is_scuff:
		_trauma = minf(_trauma + 0.12, 1.0)
		return
	if _state_name == PlayerController3D.STATE_RUN:
		var run_speed: float = 4.6 if player == null else maxf(player.get_run_speed(), 0.01)
		var kick: float = run_cadence_impulse * clampf(impact_velocity / run_speed, 0.0, 1.0)
		_pos_solver.apply_impulse(Vector3(0.0, -kick, 0.0))


func _on_player_strain_factor_updated(strain_0_to_1: float) -> void:
	_strain = clampf(strain_0_to_1, 0.0, 1.0)
