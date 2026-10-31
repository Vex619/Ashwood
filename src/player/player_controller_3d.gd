class_name PlayerController3D
extends CharacterBody3D
## 2.5D side-scrolling character controller with a Hierarchical State Machine.
##
## Superstates / leaf states:
##   GROUNDED  -> Idle, CreepWalk, Run, HardLand, PushPullHeavy, WadingSwamp
##   AIRBORNE  -> JumpStart, AirborneRise, AirborneFall
##
## Superstates own shared behaviour (gravity, floor loss, jump buffering, air
## control, landing detection). Leaf states own their target speed, stride length
## and enter/exit side-effects. Every transition goes through _transition_to(),
## which runs leaf exit -> (super exit -> super enter) -> leaf enter and emits
## kinetic_state_changed.
##
## The controller is the single source of truth for kinetic events consumed by
## DynamicCameraRig3D (framing) and FoleyAudioDirector3D (footsteps / breathing).

signal kinetic_state_changed(new_state: StringName, prev_state: StringName)
signal stride_phase_triggered(foot_index: int, foot_global_pos: Vector3, impact_velocity: float, is_scuff: bool)
signal strain_factor_updated(strain_0_to_1: float)

enum State {
	IDLE,
	CREEP_WALK,
	RUN,
	JUMP_START,
	AIRBORNE_RISE,
	AIRBORNE_FALL,
	HARD_LAND,
	PUSH_PULL_HEAVY,
	WADING_SWAMP,
	CLIMB_LEDGE,
	DEAD,
}

enum SuperState {
	GROUNDED,
	AIRBORNE,
}

const STATE_IDLE: StringName = &"Idle"
const STATE_CREEP_WALK: StringName = &"CreepWalk"
const STATE_RUN: StringName = &"Run"
const STATE_JUMP_START: StringName = &"JumpStart"
const STATE_AIRBORNE_RISE: StringName = &"AirborneRise"
const STATE_AIRBORNE_FALL: StringName = &"AirborneFall"
const STATE_HARD_LAND: StringName = &"HardLand"
const STATE_PUSH_PULL_HEAVY: StringName = &"PushPullHeavy"
const STATE_WADING_SWAMP: StringName = &"WadingSwamp"
const STATE_CLIMB_LEDGE: StringName = &"ClimbLedge"
const STATE_DEAD: StringName = &"Dead"

const FLINCH_DURATION: float = 0.38
const DEATH_COLLAPSE_DURATION: float = 1.1

const GROUP_PUSHABLE_HEAVY: StringName = &"pushable_heavy"
const GROUP_SWAMP_HAZARD: StringName = &"swamp_hazard"

const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_JUMP: StringName = &"jump"
const ACTION_CREEP: StringName = &"creep"
const ACTION_GRAB: StringName = &"grab"

const INPUT_DEADZONE: float = 0.08
const FOOT_LEFT: int = 0
const FOOT_RIGHT: int = 1
const STRAIN_EMIT_EPSILON: float = 0.004
const PHASE_LEFT_PLANT: float = PI * 0.5
const PHASE_RIGHT_PLANT: float = PI * 1.5
const FIRST_STEP_PHASE_LEAD: float = 0.12
const WALK_ANIM_CYCLE_LEN: float = 1.0
const RUN_ANIM_CYCLE_LEN: float = 0.625

@export_group("Locomotion")
@export var creep_speed: float = 1.55
@export var run_speed: float = 4.6
@export var ground_acceleration: float = 30.0
@export var ground_deceleration: float = 38.0
## Analog stick deflection below this value walks instead of runs.
@export_range(0.1, 1.0) var creep_input_threshold: float = 0.55

@export_group("Airborne")
@export var gravity: float = 24.0
@export var fall_gravity_multiplier: float = 1.4
@export var max_fall_speed: float = 24.0
@export var jump_velocity: float = 8.4
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.45
@export var air_acceleration: float = 14.0
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.12
@export var jump_start_duration: float = 0.06

@export_group("Landing")
## Vertical impact speed (m/s) at or above which the landing becomes a HardLand.
@export var hard_land_impact_speed: float = 10.5
@export var hard_land_recovery_sec: float = 0.42
## Delay between lead and trailing foot contact on landings (flam, not a click).
@export var landing_second_foot_delay: float = 0.045

@export_group("Stride")
@export var creep_stride_length: float = 0.55
@export var run_stride_length: float = 0.95
@export var push_stride_length: float = 0.42
@export var wading_stride_length: float = 0.5
@export var scuff_min_speed: float = 2.4
@export var scuff_cooldown_sec: float = 0.3

@export_group("Swamp")
@export_range(0.05, 1.0) var swamp_speed_multiplier: float = 0.5
@export_range(0.05, 1.0) var swamp_jump_multiplier: float = 0.62
## Surface drag: extra stride-phase accumulation per metre (laboured, short steps).
@export_range(0.0, 2.0) var swamp_drag: float = 0.55

@export_group("Heavy Push")
@export var push_probe_length: float = 0.62
@export var push_base_speed: float = 2.2
## Mass (kg) considered "maximally heavy" for strain / speed scaling.
@export var reference_heavy_mass: float = 250.0
@export var push_acceleration: float = 7.0
@export var strain_smoothing: float = 6.0

@export_group("Nodes")
@export var foot_ray_left: RayCast3D
@export var foot_ray_right: RayCast3D
@export var push_probe: RayCast3D
@export var climb_ledge_probe: RayCast3D
@export var environment_sensor: Area3D
@export var visual_root: Node3D
@export var animator: PlayerAnimator

var _state: State = State.IDLE
var _state_time: float = 0.0
var _facing: float = 1.0
var _input_axis: float = 0.0
var _time_since_input: float = 0.0

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_cut_applied: bool = false
var _hard_land_timer: float = 0.0
var _pre_move_velocity_y: float = 0.0

var _climb_start_pos: Vector3 = Vector3.ZERO
var _climb_target_pos: Vector3 = Vector3.ZERO
var _climb_wall_x: float = 0.0
var _climb_ledge_top_y: float = 0.0
var _climb_brace_x: float = 0.0
var _climb_timer: float = 0.0
var _climb_duration: float = 0.78

var _stride_accum: float = 0.0
var _stride_phase: float = PHASE_LEFT_PLANT - FIRST_STEP_PHASE_LEAD
var _next_foot: int = FOOT_LEFT
var _scuff_cooldown_timer: float = 0.0
var _pending_foot_timer: float = -1.0
var _pending_foot_index: int = FOOT_RIGHT
var _pending_foot_impact: float = 0.0

var _skeleton: Skeleton3D = null
var _anim_player: AnimationPlayer = null
var _bone_hips: int = -1
var _bone_spine: int = -1
var _bone_spine1: int = -1
var _bone_spine2: int = -1
var _bone_neck: int = -1
var _bone_head: int = -1
var _bone_left_arm: int = -1
var _bone_left_forearm: int = -1
var _bone_right_arm: int = -1
var _bone_right_forearm: int = -1
var _bone_left_up_leg: int = -1
var _bone_left_leg: int = -1
var _bone_left_foot: int = -1
var _bone_right_up_leg: int = -1
var _bone_right_leg: int = -1
var _bone_right_foot: int = -1

var _flinch_timer: float = 0.0
var _flinch_cooldown: float = 0.0
var _flinch_dir_x: float = -1.0
var _flinch_vignette_pulse: float = 0.0
var _death_collapse_timer: float = 0.0
var _fx_audio_player: AudioStreamPlayer3D = null
var _fx_audio_mode: int = 0
var _fx_audio_elapsed: float = 0.0
var _fx_audio_duration: float = 0.0
var _fx_audio_phase: float = 0.0

var _swamp_overlaps: int = 0

var _push_body: RigidBody3D = null
var _push_direction: float = 0.0
var _push_command_vx: float = 0.0
var _push_contact_dir: float = 0.0
var _strain: float = 0.0
var _strain_target: float = 0.0
var _last_emitted_strain: float = -1.0
var external_strain_floor: float = 0.0

var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	_spawn_position = global_position
	_ensure_input_actions()
	if climb_ledge_probe != null:
		climb_ledge_probe.collision_mask = 5
	if push_probe != null:
		push_probe.collision_mask = 5
	if environment_sensor != null:
		environment_sensor.area_entered.connect(_on_environment_area_entered)
		environment_sensor.area_exited.connect(_on_environment_area_exited)
	if animator == null and visual_root != null:
		var anims: Array[Node] = visual_root.find_children("*", "PlayerAnimator")
		if not anims.is_empty():
			animator = anims[0] as PlayerAnimator
	if animator != null:
		animator.player = self
		animator.set_physics_process(false)
		_anim_player = animator.animation_player
		if not kinetic_state_changed.is_connected(animator._on_kinetic_state_changed):
			kinetic_state_changed.connect(animator._on_kinetic_state_changed)
	if visual_root != null:
		if _anim_player == null:
			var aps: Array[Node] = visual_root.find_children("*", "AnimationPlayer")
			if not aps.is_empty():
				_anim_player = aps[0] as AnimationPlayer
		var skels: Array[Node] = visual_root.find_children("*", "Skeleton3D")
		if not skels.is_empty():
			_skeleton = skels[0] as Skeleton3D
			if _skeleton != null:
				_bone_hips = _skeleton.find_bone("Hips")
				_bone_spine = _skeleton.find_bone("Spine")
				_bone_spine1 = _skeleton.find_bone("Spine1")
				_bone_spine2 = _skeleton.find_bone("Spine2")
				_bone_neck = _skeleton.find_bone("Neck")
				_bone_head = _skeleton.find_bone("Head")
				_bone_left_arm = _skeleton.find_bone("LeftArm")
				_bone_left_forearm = _skeleton.find_bone("LeftForeArm")
				_bone_right_arm = _skeleton.find_bone("RightArm")
				_bone_right_forearm = _skeleton.find_bone("RightForeArm")
				_bone_left_up_leg = _skeleton.find_bone("LeftUpLeg")
				_bone_left_leg = _skeleton.find_bone("LeftLeg")
				_bone_left_foot = _skeleton.find_bone("LeftFoot")
				_bone_right_up_leg = _skeleton.find_bone("RightUpLeg")
				_bone_right_leg = _skeleton.find_bone("RightLeg")
				_bone_right_foot = _skeleton.find_bone("RightFoot")
	_setup_fx_audio_player()
	_enter_super(SuperState.GROUNDED)
	_emit_strain(true)


func _physics_process(delta: float) -> void:
	_fill_fx_audio_buffer(delta)
	if _state == State.DEAD:
		_process_dead_state(delta)
		return

	if _state == State.CLIMB_LEDGE:
		_process_climb_state(delta)
		_post_move(delta)
		_update_strain(delta)
		_update_visual(delta)
		return

	_read_input(delta)
	_tick_timers(delta)
	_update_push_contact()

	if _check_ledge_climb():
		_post_move(delta)
		_update_strain(delta)
		_update_visual(delta)
		return

	match _get_super_state(_state):
		SuperState.GROUNDED:
			_process_grounded_super(delta)
		SuperState.AIRBORNE:
			_process_airborne_super(delta)

	velocity.z = 0.0
	_pre_move_velocity_y = velocity.y
	move_and_slide()
	if absf(global_position.z) > 0.0001:
		global_position.z = 0.0

	_post_move(delta)
	_update_strain(delta)
	_update_visual(delta)

	if global_position.y < -25.0:
		_respawn()


# --------------------------------------------------------------------------
# Public queries (used by camera / audio)
# --------------------------------------------------------------------------

func get_state_name() -> StringName:
	return state_to_name(_state)


func get_state_time() -> float:
	return _state_time


func get_time_since_input() -> float:
	return _time_since_input


func get_facing() -> float:
	return _facing


func get_strain() -> float:
	return _strain


func get_push_direction() -> float:
	return _push_direction if _push_direction != 0.0 else _push_contact_dir


func get_run_speed() -> float:
	return run_speed


func is_in_swamp() -> bool:
	return _swamp_overlaps > 0


func is_airborne_state() -> bool:
	return _get_super_state(_state) == SuperState.AIRBORNE


static func state_to_name(state: State) -> StringName:
	match state:
		State.IDLE:
			return STATE_IDLE
		State.CREEP_WALK:
			return STATE_CREEP_WALK
		State.RUN:
			return STATE_RUN
		State.JUMP_START:
			return STATE_JUMP_START
		State.AIRBORNE_RISE:
			return STATE_AIRBORNE_RISE
		State.AIRBORNE_FALL:
			return STATE_AIRBORNE_FALL
		State.HARD_LAND:
			return STATE_HARD_LAND
		State.PUSH_PULL_HEAVY:
			return STATE_PUSH_PULL_HEAVY
		State.WADING_SWAMP:
			return STATE_WADING_SWAMP
		State.CLIMB_LEDGE:
			return STATE_CLIMB_LEDGE
		State.DEAD:
			return STATE_DEAD
	return STATE_IDLE


# --------------------------------------------------------------------------
# Input & timers
# --------------------------------------------------------------------------

func _read_input(delta: float) -> void:
	_input_axis = Input.get_axis(ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT)
	if absf(_input_axis) < INPUT_DEADZONE:
		_input_axis = 0.0

	var any_input: bool = _input_axis != 0.0
	if Input.is_action_just_pressed(ACTION_JUMP):
		_jump_buffer_timer = jump_buffer_time
		any_input = true
	if Input.is_action_pressed(ACTION_GRAB) or Input.is_action_pressed(ACTION_JUMP):
		any_input = true

	if any_input:
		_time_since_input = 0.0
	else:
		_time_since_input += delta

	# While engaged with a crate the character keeps facing it (pull support).
	if _input_axis != 0.0 and _push_body == null:
		_facing = signf(_input_axis)


func _tick_timers(delta: float) -> void:
	_state_time += delta
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_hard_land_timer = maxf(_hard_land_timer - delta, 0.0)
	_scuff_cooldown_timer = maxf(_scuff_cooldown_timer - delta, 0.0)
	_flinch_timer = maxf(_flinch_timer - delta, 0.0)
	_flinch_cooldown = maxf(_flinch_cooldown - delta, 0.0)
	_flinch_vignette_pulse = move_toward(_flinch_vignette_pulse, 0.0, 0.95 * delta)

	if _pending_foot_timer >= 0.0:
		_pending_foot_timer -= delta
		if _pending_foot_timer < 0.0:
			_emit_stride(_pending_foot_index, _pending_foot_impact, false)


# --------------------------------------------------------------------------
# Ledge Mantling & Obstacle Climbing
# --------------------------------------------------------------------------

func _check_ledge_climb() -> bool:
	if _state == State.CLIMB_LEDGE or _state == State.DEAD:
		return false
	# Allow full-impulse JumpStart to initiate first on the ground when Jump is pressed
	if is_on_floor() and _jump_buffer_timer > 0.0 and _state != State.HARD_LAND:
		return false
	if _state == State.JUMP_START and _state_time < jump_start_duration * 0.5:
		return false
	if _state == State.PUSH_PULL_HEAVY and _jump_buffer_timer <= 0.0 and not Input.is_action_pressed(ACTION_JUMP):
		return false

	var pressing_forward: bool = (_input_axis != 0.0 and signf(_input_axis) == _facing)
	var jumping: bool = _jump_buffer_timer > 0.0 or Input.is_action_pressed(ACTION_JUMP) or is_airborne_state()
	var airborne_against_wall: bool = not is_on_floor() and (is_on_wall() or velocity.x * _facing > 0.1)

	if not (pressing_forward or jumping or airborne_against_wall):
		return false

	if climb_ledge_probe == null or push_probe == null:
		return false

	# 1. Tight horizontal wall raycast (max reach 0.42m from body center) to find exact wall_x
	var orig_push_pos: Vector3 = push_probe.position
	var orig_push_target: Vector3 = push_probe.target_position
	push_probe.collision_mask = 5
	push_probe.target_position = Vector3(_facing * 0.42, 0.0, 0.0)

	var wall_hit: bool = false
	var wall_x: float = 0.0
	var wall_collider: Object = null
	var probe_heights: Array[float] = [0.55, 1.05, 0.28]
	for h_y: float in probe_heights:
		push_probe.position = Vector3(0.0, h_y, 0.0)
		push_probe.force_raycast_update()
		if push_probe.is_colliding():
			var w_norm: Vector3 = push_probe.get_collision_normal()
			if absf(w_norm.x) >= 0.65:
				wall_hit = true
				wall_x = push_probe.get_collision_point().x
				wall_collider = push_probe.get_collider()
				break

	push_probe.position = orig_push_pos
	push_probe.target_position = orig_push_target

	if not wall_hit or absf(wall_x - global_position.x) > 0.425:
		return false

	# 2. Downward vertical raycast from above the obstacle to find exact top surface Y (ledge_top_y)
	var local_wall_dx: float = wall_x - global_position.x
	climb_ledge_probe.collision_mask = 5
	climb_ledge_probe.position = Vector3(local_wall_dx + _facing * 0.14, 2.25, 0.0)
	climb_ledge_probe.target_position = Vector3(0.0, -2.0, 0.0)
	climb_ledge_probe.force_raycast_update()

	if not climb_ledge_probe.is_colliding():
		return false

	var hit_normal: Vector3 = climb_ledge_probe.get_collision_normal()
	if hit_normal.y < 0.65:
		return false

	var hit_point: Vector3 = climb_ledge_probe.get_collision_point()
	var ledge_top_y: float = hit_point.y
	var height_diff: float = ledge_top_y - global_position.y
	if height_diff < 0.30 or height_diff > 2.05:
		return false

	var hit_collider: Object = climb_ledge_probe.get_collider()
	var hit_pushable: bool = ((hit_collider is Node) and (hit_collider as Node).is_in_group(GROUP_PUSHABLE_HEAVY)) \
			or ((wall_collider is Node) and (wall_collider as Node).is_in_group(GROUP_PUSHABLE_HEAVY))

	if hit_pushable:
		if hit_collider is RigidBody3D:
			var crate_body: RigidBody3D = hit_collider as RigidBody3D
			crate_body.linear_velocity = Vector3(0.0, crate_body.linear_velocity.y, 0.0)
		elif wall_collider is RigidBody3D:
			var w_crate: RigidBody3D = wall_collider as RigidBody3D
			w_crate.linear_velocity = Vector3(0.0, w_crate.linear_velocity.y, 0.0)

	_release_push()
	_start_climb(wall_x, ledge_top_y)
	return true


func _start_climb(wall_x: float, ledge_top_y: float) -> void:
	_climb_wall_x = wall_x
	_climb_ledge_top_y = ledge_top_y
	_climb_brace_x = wall_x - _facing * 0.26
	_climb_start_pos = global_position
	_climb_target_pos = Vector3(wall_x + _facing * 0.36, ledge_top_y, 0.0)
	_climb_timer = 0.0
	_climb_duration = 0.78
	velocity = Vector3.ZERO
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_transition_to(State.CLIMB_LEDGE)


func _process_climb_state(delta: float) -> void:
	_climb_timer += delta
	var grab_base_y: float = maxf(_climb_start_pos.y, _climb_ledge_top_y - 1.32)
	var pull_top_y: float = _climb_ledge_top_y - 0.38

	# Phase 1 (0.0..0.22s — Edge Grab & Wall Foot Brace): Snap X flush to wall (wall_x - facing * 0.26m)
	# Phase 2 (0.22..0.52s — Muscle-Up Pull): Pull torso upward while keeping hands world-locked to ledge_top_y
	# Phase 3 (0.52..0.78s — Knee Mantle & Step Up): Drive knee onto ledge_top_y and step X forward to wall_x + facing * 0.36m
	if _climb_timer <= 0.22:
		var u1: float = smoothstep(0.0, 1.0, clampf(_climb_timer / 0.22, 0.0, 1.0))
		global_position.x = lerpf(_climb_start_pos.x, _climb_brace_x, u1)
		global_position.y = lerpf(_climb_start_pos.y, grab_base_y, u1)
	elif _climb_timer <= 0.52:
		var u2: float = smoothstep(0.0, 1.0, clampf((_climb_timer - 0.22) / 0.30, 0.0, 1.0))
		global_position.x = lerpf(_climb_brace_x, _climb_wall_x - _facing * 0.12, u2)
		global_position.y = lerpf(grab_base_y, pull_top_y, u2)
	else:
		var u3: float = smoothstep(0.0, 1.0, clampf((_climb_timer - 0.52) / 0.26, 0.0, 1.0))
		global_position.x = lerpf(_climb_wall_x - _facing * 0.12, _climb_target_pos.x, u3)
		global_position.y = lerpf(pull_top_y, _climb_ledge_top_y, u3)

	global_position.z = 0.0
	velocity = Vector3.ZERO

	if _climb_timer >= _climb_duration:
		global_position = _climb_target_pos
		if _skeleton != null:
			_skeleton.reset_bone_poses()
		if visual_root != null:
			visual_root.position.y = 0.0
			visual_root.rotation.x = 0.0
			visual_root.rotation.z = 0.0
		_emit_stride(FOOT_RIGHT, 3.2, false)
		if _input_axis != 0.0:
			_transition_to(State.RUN)
		else:
			_transition_to(State.IDLE)


# --------------------------------------------------------------------------
# Superstate: GROUNDED
# --------------------------------------------------------------------------

func _process_grounded_super(delta: float) -> void:
	if not is_on_floor():
		_coyote_timer = coyote_time
		_transition_to(State.AIRBORNE_FALL)
		_process_airborne_super(delta)
		return

	if _jump_buffer_timer > 0.0 and _state != State.HARD_LAND:
		_start_jump()
		_process_airborne_super(delta)
		return

	var leaf: State = _select_grounded_state()
	if leaf != _state:
		_transition_to(leaf)

	match _state:
		State.PUSH_PULL_HEAVY:
			_process_push_pull(delta)
		State.HARD_LAND:
			velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * 1.5 * delta)
		_:
			var target_vx: float = _target_ground_speed() * _input_axis
			var rate: float = ground_acceleration if absf(target_vx) > absf(velocity.x) else ground_deceleration
			if _state == State.WADING_SWAMP:
				rate *= (1.0 - swamp_drag * 0.5)
			velocity.x = move_toward(velocity.x, target_vx, rate * delta)

	velocity.y -= gravity * delta


func _select_grounded_state() -> State:
	if _hard_land_timer > 0.0:
		return State.HARD_LAND
	if _push_body != null:
		return State.PUSH_PULL_HEAVY
	if _swamp_overlaps > 0:
		return State.WADING_SWAMP

	var magnitude: float = absf(_input_axis)
	if magnitude == 0.0:
		var speed: float = absf(velocity.x)
		if speed < 0.25:
			return State.IDLE
		return State.RUN if speed > creep_speed + 0.3 else State.CREEP_WALK
	if Input.is_action_pressed(ACTION_CREEP) or magnitude < creep_input_threshold:
		return State.CREEP_WALK
	return State.RUN


func _target_ground_speed() -> float:
	var magnitude: float = absf(_input_axis)
	match _state:
		State.CREEP_WALK:
			return creep_speed * clampf(magnitude / creep_input_threshold, 0.0, 1.0) / maxf(magnitude, 0.001)
		State.RUN:
			return run_speed
		State.WADING_SWAMP:
			var base: float = creep_speed if Input.is_action_pressed(ACTION_CREEP) else run_speed
			return base * swamp_speed_multiplier
		_:
			return 0.0


# --------------------------------------------------------------------------
# Leaf: PUSH_PULL_HEAVY
# --------------------------------------------------------------------------

func _process_push_pull(delta: float) -> void:
	if _push_body == null:
		return
	var mass_factor: float = clampf(_push_body.mass / maxf(reference_heavy_mass, 1.0), 0.1, 1.0)
	var max_push_speed: float = push_base_speed * (1.0 - 0.6 * mass_factor)
	var magnitude: float = absf(_input_axis)
	var desired_dir: float = signf(_input_axis)
	var target_vx: float = desired_dir * max_push_speed * magnitude

	var crate_velocity: Vector3 = _push_body.linear_velocity
	var measured_vx: float = crate_velocity.x
	# Ramp an internal commanded velocity (not the measured one): ground friction
	# removes more speed per step than one frame of acceleration adds, so ramping
	# from the measured value would never break static friction.
	var accel: float = push_acceleration * (1.0 - 0.5 * mass_factor)
	_push_command_vx = move_toward(_push_command_vx, target_vx, accel * delta)
	var new_vx: float = _push_command_vx

	_push_body.sleeping = false
	_push_body.linear_velocity = Vector3(new_vx, crate_velocity.y, 0.0)
	velocity.x = new_vx
	_push_direction = desired_dir

	# Resistance: how much the crate fails to follow the commanded motion
	# (blocked by a wall / obstacle -> measured speed stays near zero).
	var resistance: float = 0.0
	if absf(_push_command_vx) > 0.01:
		resistance = 1.0 - clampf(absf(measured_vx) / absf(_push_command_vx), 0.0, 1.0)
	var effort: float = clampf(0.25 + 0.45 * mass_factor + 0.3 * resistance, 0.0, 1.0)
	_strain_target = effort if magnitude > 0.0 else effort * 0.35


func _update_push_contact() -> void:
	var candidate: RigidBody3D = null
	var touching: bool = false

	if _get_super_state(_state) == SuperState.GROUNDED:
		var count: int = get_slide_collision_count()
		for i: int in count:
			var collision: KinematicCollision3D = get_slide_collision(i)
			var body: RigidBody3D = collision.get_collider() as RigidBody3D
			if body != null and body.is_in_group(GROUP_PUSHABLE_HEAVY) and absf(collision.get_normal().y) < 0.5:
				candidate = body
				touching = true
				break

		if push_probe != null:
			push_probe.target_position = Vector3(_facing * push_probe_length, 0.0, 0.0)
			push_probe.force_raycast_update()
			if candidate == null and push_probe.is_colliding():
				var probe_body: RigidBody3D = push_probe.get_collider() as RigidBody3D
				if probe_body != null and probe_body.is_in_group(GROUP_PUSHABLE_HEAVY):
					candidate = probe_body

	var engaged: RigidBody3D = null
	if candidate != null:
		var crate_dir: float = signf(candidate.global_position.x - global_position.x)
		var toward: float = _input_axis * crate_dir
		var grabbing: bool = Input.is_action_pressed(ACTION_GRAB)
		var pushing: bool = toward > 0.0 and (touching or push_probe != null)
		var pulling: bool = grabbing and toward < 0.0
		var holding: bool = grabbing and _input_axis == 0.0
		if pushing or pulling or holding:
			engaged = candidate
			_push_contact_dir = crate_dir

	if engaged != _push_body:
		_push_body = engaged
		_push_command_vx = 0.0
		if engaged == null:
			_push_direction = 0.0
			_strain_target = 0.0


func _release_push() -> void:
	_push_body = null
	_push_direction = 0.0
	_push_command_vx = 0.0
	_strain_target = 0.0


# --------------------------------------------------------------------------
# Superstate: AIRBORNE
# --------------------------------------------------------------------------

func _process_airborne_super(delta: float) -> void:
	if _state == State.AIRBORNE_FALL and _coyote_timer > 0.0 and _jump_buffer_timer > 0.0:
		_start_jump()

	var rising: bool = velocity.y > 0.0
	if rising and not _jump_cut_applied and not Input.is_action_pressed(ACTION_JUMP) \
			and (_state == State.JUMP_START or _state == State.AIRBORNE_RISE):
		velocity.y *= jump_cut_multiplier
		_jump_cut_applied = true

	var g: float = gravity if velocity.y > 0.0 else gravity * fall_gravity_multiplier
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	var air_target: float = _input_axis * run_speed
	velocity.x = move_toward(velocity.x, air_target, air_acceleration * delta)

	match _state:
		State.JUMP_START:
			if _state_time >= jump_start_duration:
				_transition_to(State.AIRBORNE_RISE if velocity.y > 0.0 else State.AIRBORNE_FALL)
		State.AIRBORNE_RISE:
			if velocity.y <= 0.0:
				_transition_to(State.AIRBORNE_FALL)
		_:
			pass


func _start_jump() -> void:
	# Full-impulse JumpStart in all grounded states including WadingSwamp and PushPullHeavy
	var takeoff_speed: float = jump_velocity
	velocity.y = takeoff_speed
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jump_cut_applied = false
	_release_push()
	_transition_to(State.JUMP_START)
	_emit_stride(_next_foot, 3.0 + absf(velocity.x) * 0.4, false)
	_toggle_foot()


func _land(impact_speed: float) -> void:
	_pending_foot_timer = -1.0
	if impact_speed >= hard_land_impact_speed:
		_hard_land_timer = hard_land_recovery_sec
		_transition_to(State.HARD_LAND)
	else:
		_transition_to(_select_grounded_state())

	var lead: int = _next_foot
	_stride_phase = PHASE_LEFT_PLANT if lead == FOOT_LEFT else PHASE_RIGHT_PLANT
	_sync_visual_gait_to_stride_phase(0.0)
	_emit_stride(lead, impact_speed, false)
	_pending_foot_index = 1 - lead
	_pending_foot_impact = impact_speed * 0.7
	_pending_foot_timer = landing_second_foot_delay
	_next_foot = lead
	_stride_phase = PHASE_RIGHT_PLANT if lead == FOOT_LEFT else PHASE_LEFT_PLANT
	_stride_accum = 0.0


# --------------------------------------------------------------------------
# Post-move: landing, strides, scuffs
# --------------------------------------------------------------------------

func _post_move(delta: float) -> void:
	var super_state: SuperState = _get_super_state(_state)
	if super_state == SuperState.AIRBORNE:
		var can_land: bool = _state != State.JUMP_START or velocity.y <= 0.0
		if can_land and is_on_floor():
			_land(maxf(-_pre_move_velocity_y, 0.0))
		return

	var real_vx: float = get_real_velocity().x
	var speed: float = absf(real_vx)

	# Direction-reversal scuff.
	if _scuff_cooldown_timer <= 0.0 and speed >= scuff_min_speed and _input_axis != 0.0 \
			and signf(_input_axis) != signf(real_vx) and _state != State.PUSH_PULL_HEAVY:
		_stride_phase = PHASE_LEFT_PLANT if _next_foot == FOOT_LEFT else PHASE_RIGHT_PLANT
		_sync_visual_gait_to_stride_phase(delta)
		_emit_stride(_next_foot, speed, true)
		_toggle_foot()
		_scuff_cooldown_timer = scuff_cooldown_sec
		_stride_accum = 0.0
		return

	var stride_length: float = _stride_length_for_state()
	if stride_length <= 0.0:
		_sync_visual_gait_to_stride_phase(delta)
		return
	var drag: float = swamp_drag if _state == State.WADING_SWAMP else 0.0
	var step_dist: float = speed * delta * (1.0 + drag)
	_stride_accum += step_dist
	var delta_phase: float = minf((step_dist / stride_length) * PI, PI * 0.95)
	var prev_phase: float = _stride_phase
	_stride_phase = fposmod(prev_phase + delta_phase, TAU)
	_sync_visual_gait_to_stride_phase(delta)

	var dist_to_left: float = fposmod(PHASE_LEFT_PLANT - prev_phase, TAU)
	var dist_to_right: float = fposmod(PHASE_RIGHT_PLANT - prev_phase, TAU)
	if dist_to_left > 0.0 and delta_phase >= dist_to_left:
		_stride_accum = 0.0
		_next_foot = FOOT_RIGHT
		_emit_stride(FOOT_LEFT, speed, false)
	elif dist_to_right > 0.0 and delta_phase >= dist_to_right:
		_stride_accum = 0.0
		_next_foot = FOOT_LEFT
		_emit_stride(FOOT_RIGHT, speed, false)


func _stride_length_for_state() -> float:
	match _state:
		State.CREEP_WALK:
			return creep_stride_length
		State.RUN:
			return run_stride_length
		State.PUSH_PULL_HEAVY:
			return push_stride_length
		State.WADING_SWAMP:
			return wading_stride_length
		_:
			return 0.0


func _emit_stride(foot_index: int, impact_velocity: float, is_scuff: bool) -> void:
	stride_phase_triggered.emit(foot_index, _get_foot_position(foot_index), impact_velocity, is_scuff)


func _toggle_foot() -> void:
	_next_foot = FOOT_RIGHT if _next_foot == FOOT_LEFT else FOOT_LEFT


func _get_foot_position(foot_index: int) -> Vector3:
	var ray: RayCast3D = foot_ray_left if foot_index == FOOT_LEFT else foot_ray_right
	if ray != null:
		ray.force_raycast_update()
		if ray.is_colliding():
			return ray.get_collision_point()
		return Vector3(ray.global_position.x, global_position.y, ray.global_position.z)
	var z_offset: float = 0.12 if foot_index == FOOT_LEFT else -0.12
	return global_position + Vector3(0.0, 0.0, z_offset)


# --------------------------------------------------------------------------
# HSM plumbing
# --------------------------------------------------------------------------

func _get_super_state(state: State) -> SuperState:
	match state:
		State.JUMP_START, State.AIRBORNE_RISE, State.AIRBORNE_FALL:
			return SuperState.AIRBORNE
		_:
			return SuperState.GROUNDED


func _transition_to(new_state: State) -> void:
	if new_state == _state:
		return
	var prev_state: State = _state
	var prev_super: SuperState = _get_super_state(prev_state)
	var new_super: SuperState = _get_super_state(new_state)

	_exit_leaf(prev_state)
	if prev_super != new_super:
		_exit_super(prev_super)
		_enter_super(new_super)
	_state = new_state
	_state_time = 0.0
	_enter_leaf(new_state, prev_state)

	kinetic_state_changed.emit(state_to_name(new_state), state_to_name(prev_state))


func _enter_super(super_state: SuperState) -> void:
	match super_state:
		SuperState.GROUNDED:
			_jump_cut_applied = false
		SuperState.AIRBORNE:
			_stride_accum = 0.0
			_pending_foot_timer = -1.0


func _exit_super(super_state: SuperState) -> void:
	match super_state:
		SuperState.GROUNDED:
			if _push_body != null:
				_release_push()
		SuperState.AIRBORNE:
			pass


func _enter_leaf(state: State, prev_state: State) -> void:
	match state:
		State.IDLE:
			_stride_accum = 0.0
		State.HARD_LAND:
			velocity.x *= 0.25
		State.CREEP_WALK, State.RUN, State.WADING_SWAMP, State.PUSH_PULL_HEAVY:
			if prev_state == State.IDLE or prev_state == State.HARD_LAND:
				var plant_phase: float = PHASE_LEFT_PLANT if _next_foot == FOOT_LEFT else PHASE_RIGHT_PLANT
				_stride_phase = fposmod(plant_phase - FIRST_STEP_PHASE_LEAD, TAU)
				_stride_accum = _stride_length_for_state() * ((PI - FIRST_STEP_PHASE_LEAD) / PI)
		_:
			pass


func _exit_leaf(state: State) -> void:
	match state:
		State.PUSH_PULL_HEAVY:
			_push_direction = 0.0
			_strain_target = 0.0
		_:
			pass


# --------------------------------------------------------------------------
# Strain, swamp sensing, visuals
# --------------------------------------------------------------------------

func _update_strain(delta: float) -> void:
	if _state != State.PUSH_PULL_HEAVY:
		_strain_target = 0.0
	_strain_target = clampf(maxf(_strain_target, external_strain_floor) + _flinch_vignette_pulse, 0.0, 1.0)
	var blend: float = 1.0 - exp(-strain_smoothing * delta)
	_strain = lerpf(_strain, _strain_target, blend)
	if _strain < 0.002 and _strain_target == 0.0:
		_strain = 0.0
	_emit_strain(false)


func set_checkpoint_spawn(pos: Vector3) -> void:
	_spawn_position = pos


func teleport_to_checkpoint(pos: Vector3) -> void:
	_spawn_position = pos
	global_position = pos
	velocity = Vector3.ZERO
	_hard_land_timer = 0.0
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_flinch_timer = 0.0
	_flinch_cooldown = 0.0
	_flinch_vignette_pulse = 0.0
	_death_collapse_timer = 0.0
	_fx_audio_mode = 0
	if _skeleton != null:
		_skeleton.reset_bone_poses()
	if _anim_player != null:
		_anim_player.speed_scale = 1.0
	if visual_root != null:
		var target_yaw: float = (PI * 0.5) if _facing > 0.0 else (-PI * 0.5)
		visual_root.position = Vector3.ZERO
		visual_root.rotation = Vector3(0.0, target_yaw, 0.0)
		visual_root.scale = Vector3.ONE
	_release_push()
	_transition_to(State.IDLE)


func trigger_damage_flinch(source_dir_x: float) -> void:
	if _state == State.DEAD or _flinch_cooldown > 0.0:
		return
	_flinch_cooldown = 0.55
	_flinch_timer = FLINCH_DURATION
	var recoil_dir: float = -signf(source_dir_x) if absf(source_dir_x) > 0.001 else -_facing
	_flinch_dir_x = recoil_dir
	if _state != State.CLIMB_LEDGE:
		velocity.x = recoil_dir * 3.15
	_flinch_vignette_pulse = 0.35
	_strain = clampf(_strain + 0.35, 0.0, 1.0)
	_emit_strain(true)
	_trigger_fx_audio(1, 0.32)


func trigger_death_collapse(source_dir_x: float = 0.0) -> void:
	if _state == State.DEAD:
		return
	_flinch_timer = 0.0
	_flinch_vignette_pulse = 0.45
	_death_collapse_timer = 0.0
	_pending_foot_timer = -1.0
	_release_push()
	var fall_dir: float = -signf(source_dir_x) if absf(source_dir_x) > 0.001 else _facing
	velocity.x = fall_dir * 1.35
	velocity.y = minf(velocity.y, 0.0)
	_transition_to(State.DEAD)
	_trigger_fx_audio(2, 1.15)


func _process_dead_state(delta: float) -> void:
	_state_time += delta
	_input_axis = 0.0
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_death_collapse_timer = minf(_death_collapse_timer + delta, DEATH_COLLAPSE_DURATION)

	if not is_on_floor():
		var g: float = gravity * fall_gravity_multiplier
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)
	else:
		velocity.y = 0.0
	velocity.x = move_toward(velocity.x, 0.0, 10.5 * delta)
	velocity.z = 0.0
	move_and_slide()
	if absf(global_position.z) > 0.0001:
		global_position.z = 0.0

	_flinch_vignette_pulse = move_toward(_flinch_vignette_pulse, 0.65, 1.2 * delta)
	_update_strain(delta)
	_update_visual(delta)


func _setup_fx_audio_player() -> void:
	_fx_audio_player = AudioStreamPlayer3D.new()
	_fx_audio_player.name = "ProceduralFlinchDeathAudio"
	var gen: AudioStreamGenerator = AudioStreamGenerator.new()
	gen.mix_rate = 11025.0
	gen.buffer_length = 0.14
	_fx_audio_player.stream = gen
	_fx_audio_player.volume_db = 0.0
	_fx_audio_player.unit_size = 8.0
	_fx_audio_player.max_distance = 32.0
	_fx_audio_player.bus = &"Foley" if AudioServer.get_bus_index(&"Foley") >= 0 else &"Master"
	add_child(_fx_audio_player)


func _trigger_fx_audio(mode: int, duration: float) -> void:
	_fx_audio_mode = mode
	_fx_audio_elapsed = 0.0
	_fx_audio_duration = duration
	_fx_audio_phase = 0.0
	if _fx_audio_player != null and _fx_audio_player.is_inside_tree():
		if not _fx_audio_player.playing:
			_fx_audio_player.play()
		_fill_fx_audio_buffer(0.0)


func _fill_fx_audio_buffer(_delta: float) -> void:
	if _fx_audio_mode == 0 or _fx_audio_player == null or not _fx_audio_player.is_inside_tree():
		return
	if not _fx_audio_player.playing:
		_fx_audio_player.play()
	var playback: AudioStreamGeneratorPlayback = _fx_audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return
	var dt: float = 1.0 / 11025.0
	for _i: int in frames:
		if _fx_audio_elapsed >= _fx_audio_duration:
			_fx_audio_mode = 0
			playback.push_frame(Vector2.ZERO)
			continue
		var t: float = _fx_audio_elapsed
		var sample: float = 0.0
		if _fx_audio_mode == 1:
			# Sharp intake gasp (formant-filtered noise burst) + chest impact thud
			var thud_env: float = exp(-t * 28.0)
			var thud: float = sin(t * TAU * lerpf(92.0, 44.0, clampf(t / 0.15, 0.0, 1.0))) * thud_env * 0.55
			var gasp_env: float = sin(clampf(t / 0.28, 0.0, 1.0) * PI) * exp(-t * 4.5)
			var breath_noise: float = sin(t * 14320.0 + sin(t * 3910.0) * 3.1) * 0.35
			var formant: float = (sin(t * TAU * 620.0) * 0.22 + sin(t * TAU * 1180.0) * 0.15) * (0.6 + 0.4 * breath_noise)
			sample = clampf(thud + (breath_noise + formant) * gasp_env, -0.95, 0.95)
		elif _fx_audio_mode == 2:
			# Heavy low-frequency sub-bass impact (52 Hz -> 26 Hz) + high-pitched tinnitus ringing decay (3120 Hz)
			var sub_env: float = exp(-t * 5.2)
			var sub_freq: float = lerpf(54.0, 25.0, clampf(t / 0.65, 0.0, 1.0))
			_fx_audio_phase += sub_freq * TAU * dt
			var sub_bass: float = (sin(_fx_audio_phase) * 0.68 + sin(_fx_audio_phase * 2.0) * 0.24) * sub_env
			var body_drop: float = 0.0
			if t >= 0.42:
				var dt_drop: float = t - 0.42
				body_drop = sin(dt_drop * TAU * 48.0) * exp(-dt_drop * 16.0) * 0.45
			var ring_env: float = smoothstep(0.0, 0.08, t) * exp(-t * 2.15)
			var ring: float = sin(t * TAU * 3120.0) * 0.18 * ring_env
			sample = clampf(sub_bass + body_drop + ring, -0.95, 0.95)
		playback.push_frame(Vector2(sample, sample))
		_fx_audio_elapsed += dt


func _apply_bone_euler_offset(bone_idx: int, euler_rad: Vector3) -> void:
	if _skeleton == null or bone_idx < 0:
		return
	var cur_rot: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
	var offset_rot: Quaternion = Quaternion.from_euler(euler_rad)
	_skeleton.set_bone_pose_rotation(bone_idx, cur_rot * offset_rot)


func _emit_strain(force: bool) -> void:
	var changed: bool = absf(_strain - _last_emitted_strain) > STRAIN_EMIT_EPSILON
	var settled_zero: bool = _strain == 0.0 and _last_emitted_strain != 0.0
	if force or changed or settled_zero:
		_last_emitted_strain = _strain
		strain_factor_updated.emit(_strain)


func _on_environment_area_entered(area: Area3D) -> void:
	if area.is_in_group(GROUP_SWAMP_HAZARD):
		_swamp_overlaps += 1


func _on_environment_area_exited(area: Area3D) -> void:
	if area.is_in_group(GROUP_SWAMP_HAZARD):
		_swamp_overlaps = maxi(_swamp_overlaps - 1, 0)


func _sync_visual_gait_to_stride_phase(delta: float) -> void:
	var is_locomotion: bool = _state == State.CREEP_WALK or _state == State.RUN \
			or _state == State.WADING_SWAMP or _state == State.PUSH_PULL_HEAVY
	if _anim_player != null:
		if _state == State.DEAD or _state == State.CLIMB_LEDGE:
			_anim_player.speed_scale = 0.0
		elif is_locomotion:
			var cycle_len: float = RUN_ANIM_CYCLE_LEN if _state == State.RUN else WALK_ANIM_CYCLE_LEN
			var norm_phase: float = fposmod(_stride_phase / TAU, 1.0)
			_anim_player.speed_scale = 0.0
			_anim_player.seek(norm_phase * cycle_len, true)
			_anim_player.advance(0.0)
		else:
			_anim_player.speed_scale = 1.0
			if _flinch_timer > 0.0:
				_anim_player.advance(0.0)

	if _state == State.DEAD:
		var collapse_t: float = clampf(_death_collapse_timer / DEATH_COLLAPSE_DURATION, 0.0, 1.0)
		var buckle_bell: float = sin(clampf(collapse_t / 0.55, 0.0, 1.0) * PI)
		var slump_u: float = smoothstep(0.08, 1.0, collapse_t)
		if _skeleton != null:
			_skeleton.reset_bone_poses()
			# Knees flex during initial buckle then extend flat along floor so zero geometry dips below local Y = 0.0
			_apply_bone_euler_offset(_bone_left_up_leg, Vector3(deg_to_rad(-28.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_up_leg, Vector3(deg_to_rad(-24.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_left_leg, Vector3(deg_to_rad(36.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_leg, Vector3(deg_to_rad(32.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_spine, Vector3(deg_to_rad(10.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_spine1, Vector3(deg_to_rad(8.0 * buckle_bell), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_neck, Vector3(deg_to_rad(8.0 * slump_u), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_head, Vector3(deg_to_rad(10.0 * slump_u), deg_to_rad(16.0 * slump_u), 0.0))
			_apply_bone_euler_offset(_bone_left_arm, Vector3(deg_to_rad(-18.0 * slump_u), 0.0, deg_to_rad(-14.0 * slump_u)))
			_apply_bone_euler_offset(_bone_right_arm, Vector3(deg_to_rad(-16.0 * slump_u), 0.0, deg_to_rad(14.0 * slump_u)))
			_apply_bone_euler_offset(_bone_left_forearm, Vector3(deg_to_rad(-14.0 * slump_u), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_forearm, Vector3(deg_to_rad(-12.0 * slump_u), 0.0, 0.0))
		if visual_root != null:
			# Rotate body flat onto the floor (~85 deg pitch/roll) and clamp visual_root.position.y >= +0.18m above floor contact point
			visual_root.position.y = maxf(lerpf(0.18, 0.22, slump_u), 0.18)
			visual_root.rotation.x = deg_to_rad(85.0 * slump_u)
			visual_root.rotation.z = deg_to_rad(6.0 * slump_u)
		return

	if _state == State.CLIMB_LEDGE:
		if _skeleton != null:
			_skeleton.reset_bone_poses()
			var arm_pitch_deg: float = 0.0
			var elbow_deg: float = 0.0
			var torso_lean_deg: float = 0.0
			var lead_hip_deg: float = 0.0
			var lead_knee_deg: float = 0.0
			var trail_hip_deg: float = 0.0
			var head_deg: float = 0.0

			if _climb_timer <= 0.22:
				# Phase 1 (0.0..0.22s — Edge Grab & Wall Foot Brace): Reach both arms overhead (-150 deg) and brace foot on wall
				var u1: float = smoothstep(0.0, 1.0, clampf(_climb_timer / 0.22, 0.0, 1.0))
				arm_pitch_deg = lerpf(-35.0, -150.0, u1)
				elbow_deg = lerpf(-12.0, -22.0, u1)
				torso_lean_deg = lerpf(0.0, 10.0, u1)
				lead_hip_deg = lerpf(0.0, -58.0, u1)
				lead_knee_deg = lerpf(0.0, 66.0, u1)
				head_deg = lerpf(0.0, -24.0, u1)
			elif _climb_timer <= 0.52:
				# Phase 2 (0.22..0.52s — Muscle-Up Pull): Rotate arms from -150 deg down to -25 deg and lean torso forward (+28 deg)
				var u2: float = smoothstep(0.0, 1.0, clampf((_climb_timer - 0.22) / 0.30, 0.0, 1.0))
				arm_pitch_deg = lerpf(-150.0, -25.0, u2)
				elbow_deg = -22.0 - 52.0 * sin(u2 * PI)
				torso_lean_deg = lerpf(10.0, 28.0, u2)
				lead_hip_deg = lerpf(-58.0, -42.0, u2)
				lead_knee_deg = lerpf(66.0, 54.0, u2)
				trail_hip_deg = lerpf(0.0, 18.0, sin(u2 * PI))
				head_deg = lerpf(-24.0, 10.0, u2)
			else:
				# Phase 3 (0.52..0.78s — Knee Mantle & Step Up): Drive lead knee up (+75 deg) onto ledge_top_y and return upright
				var u3: float = smoothstep(0.0, 1.0, clampf((_climb_timer - 0.52) / 0.26, 0.0, 1.0))
				var knee_drive: float = sin(u3 * PI)
				arm_pitch_deg = lerpf(-25.0, 0.0, u3)
				elbow_deg = lerpf(-24.0, 0.0, u3)
				torso_lean_deg = lerpf(28.0, 0.0, u3)
				lead_hip_deg = lerpf(-42.0, 0.0, u3) - 33.0 * knee_drive
				lead_knee_deg = lerpf(54.0, 0.0, u3) + 21.0 * knee_drive
				head_deg = lerpf(10.0, 0.0, u3)

			_apply_bone_euler_offset(_bone_spine, Vector3(deg_to_rad(torso_lean_deg * 0.38), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_spine1, Vector3(deg_to_rad(torso_lean_deg * 0.34), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_spine2, Vector3(deg_to_rad(torso_lean_deg * 0.28), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_head, Vector3(deg_to_rad(head_deg), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_left_arm, Vector3(deg_to_rad(arm_pitch_deg), 0.0, deg_to_rad(8.0)))
			_apply_bone_euler_offset(_bone_right_arm, Vector3(deg_to_rad(arm_pitch_deg), 0.0, deg_to_rad(-8.0)))
			_apply_bone_euler_offset(_bone_left_forearm, Vector3(deg_to_rad(elbow_deg), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_forearm, Vector3(deg_to_rad(elbow_deg), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_up_leg, Vector3(deg_to_rad(lead_hip_deg), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_right_leg, Vector3(deg_to_rad(lead_knee_deg), 0.0, 0.0))
			_apply_bone_euler_offset(_bone_left_up_leg, Vector3(deg_to_rad(trail_hip_deg), 0.0, 0.0))
		if visual_root != null:
			visual_root.position.y = 0.0
			visual_root.rotation.x = 0.0
			visual_root.rotation.z = 0.0
		return

	if visual_root != null:
		if is_locomotion:
			var speed_ratio: float = clampf(absf(get_real_velocity().x) / maxf(creep_speed, 0.1), 0.0, 1.2)
			var bob_amp: float = (0.022 if _state == State.RUN else 0.012) * speed_ratio
			# Lowest vertical contact point occurs at sin(_stride_phase) == +/-1.0 (visual_root.position.y == 0.0, never < 0.0)
			visual_root.position.y = maxf(bob_amp * (1.0 - absf(sin(_stride_phase))), 0.0)
		elif delta > 0.0:
			visual_root.position.y = maxf(move_toward(visual_root.position.y, 0.0, 0.25 * delta), 0.0)
		else:
			visual_root.position.y = 0.0

		if _flinch_timer > 0.0:
			var flinch_env: float = sin(clampf(_flinch_timer / FLINCH_DURATION, 0.0, 1.0) * PI)
			# Zero floor clipping: keep visual_root.position.y >= 0.0 and express stagger purely via upper-torso backward pitch (-24 deg), head recoil, and defensive arm raise
			visual_root.position.y = maxf(visual_root.position.y, 0.0)
			visual_root.rotation.x = 0.0
			visual_root.rotation.z = 0.0
			if _skeleton != null:
				_apply_bone_euler_offset(_bone_spine, Vector3(deg_to_rad(-9.0 * flinch_env), 0.0, 0.0))
				_apply_bone_euler_offset(_bone_spine1, Vector3(deg_to_rad(-8.0 * flinch_env), 0.0, 0.0))
				_apply_bone_euler_offset(_bone_spine2, Vector3(deg_to_rad(-7.0 * flinch_env), 0.0, 0.0))
				_apply_bone_euler_offset(_bone_neck, Vector3(deg_to_rad(-11.0 * flinch_env), 0.0, 0.0))
				_apply_bone_euler_offset(_bone_head, Vector3(deg_to_rad(-13.0 * flinch_env), deg_to_rad(10.0 * flinch_env), 0.0))
				_apply_bone_euler_offset(_bone_left_arm, Vector3(deg_to_rad(-75.0 * flinch_env), 0.0, deg_to_rad(18.0 * flinch_env)))
				_apply_bone_euler_offset(_bone_left_forearm, Vector3(deg_to_rad(-65.0 * flinch_env), 0.0, 0.0))
				_apply_bone_euler_offset(_bone_right_arm, Vector3(deg_to_rad(-60.0 * flinch_env), 0.0, deg_to_rad(-15.0 * flinch_env)))
				_apply_bone_euler_offset(_bone_right_forearm, Vector3(deg_to_rad(-54.0 * flinch_env), 0.0, 0.0))
		else:
			visual_root.position.y = maxf(visual_root.position.y, 0.0)
			visual_root.rotation.x = move_toward(visual_root.rotation.x, 0.0, 4.0 * delta)
			visual_root.rotation.z = move_toward(visual_root.rotation.z, 0.0, 4.0 * delta)

	if _skeleton != null and _bone_left_foot >= 0 and _bone_right_foot >= 0:
		var l_world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone_left_foot).origin
		var r_world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone_right_foot).origin
		if foot_ray_left != null:
			foot_ray_left.global_position = Vector3(l_world.x, global_position.y + 0.5, l_world.z)
		if foot_ray_right != null:
			foot_ray_right.global_position = Vector3(r_world.x, global_position.y + 0.5, r_world.z)
	else:
		var swing: float = sin(_stride_phase) * 0.22 * _facing
		if foot_ray_left != null:
			foot_ray_left.position = Vector3(swing, 0.5, 0.12)
		if foot_ray_right != null:
			foot_ray_right.position = Vector3(-swing, 0.5, -0.12)


func _update_visual(delta: float) -> void:
	if visual_root == null:
		return
	# Character model natively faces +Z, so +90 deg faces +X (right) and -90 deg faces -X (left)
	var target_yaw: float = (PI * 0.5) if _facing > 0.0 else (-PI * 0.5)
	visual_root.rotation.y = lerp_angle(visual_root.rotation.y, target_yaw, 1.0 - exp(-16.0 * delta))
	visual_root.scale = Vector3.ONE
	_sync_visual_gait_to_stride_phase(delta)


func _respawn() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_flinch_timer = 0.0
	_flinch_vignette_pulse = 0.0
	_death_collapse_timer = 0.0
	if _skeleton != null:
		_skeleton.reset_bone_poses()
	if visual_root != null:
		var target_yaw: float = (PI * 0.5) if _facing > 0.0 else (-PI * 0.5)
		visual_root.position = Vector3.ZERO
		visual_root.rotation = Vector3(0.0, target_yaw, 0.0)
	_release_push()
	_transition_to(State.AIRBORNE_FALL)


func _ensure_input_actions() -> void:
	_ensure_key_action(ACTION_MOVE_LEFT, [KEY_A, KEY_LEFT])
	_ensure_key_action(ACTION_MOVE_RIGHT, [KEY_D, KEY_RIGHT])
	_ensure_key_action(ACTION_JUMP, [KEY_SPACE, KEY_W, KEY_UP])
	_ensure_key_action(ACTION_CREEP, [KEY_SHIFT])
	_ensure_key_action(ACTION_GRAB, [KEY_E, KEY_CTRL])


func _ensure_key_action(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for key: Key in keys:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
