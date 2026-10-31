class_name PlayerAnimator
extends Node3D
## Drives character skeletal animations for PlayerController3D with smooth crossfades.
##
## Maps player HSM states to Inside-style boy animations:
##   Idle, Walk/Creep, Run, WadingSwamp, PushPullHeavy, JumpRise, JumpFall,
##   HardLand, and ClimbLedge.

@export var player: PlayerController3D
@export var animation_player: AnimationPlayer

var _current_anim: StringName = &""
var _anim_library: AnimationLibrary = null


func _ready() -> void:
	if animation_player == null:
		var parent_node: Node = get_parent()
		if parent_node != null:
			animation_player = parent_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation_player == null:
			animation_player = find_child("AnimationPlayer", true, false) as AnimationPlayer

	if animation_player != null:
		var lib: AnimationLibrary = load("res://resources/animations/inside_boy_animations.tres") as AnimationLibrary
		if lib != null:
			if animation_player.has_animation_library(&""):
				var default_lib: AnimationLibrary = animation_player.get_animation_library(&"")
				for anim_name: StringName in lib.get_animation_list():
					if not default_lib.has_animation(anim_name):
						default_lib.add_animation(anim_name, lib.get_animation(anim_name))
			else:
				animation_player.add_animation_library(&"", lib)

	if player == null:
		var curr: Node = get_parent()
		while curr != null:
			if curr is PlayerController3D:
				player = curr as PlayerController3D
				break
			curr = curr.get_parent()

	if player != null:
		player.kinetic_state_changed.connect(_on_kinetic_state_changed)
		_play_state_animation(player.get_state_name(), 0.0)


func _process(delta: float) -> void:
	if player == null or animation_player == null:
		return

	var state: StringName = player.get_state_name()
	if state == PlayerController3D.STATE_PUSH_PULL_HEAVY:
		var push_vx: float = absf(player.velocity.x)
		var base_speed: float = maxf(player.push_base_speed, 0.1)
		# Slow or pause pushing stride if pushing against resistance
		animation_player.speed_scale = clampf(push_vx / base_speed, 0.25, 1.3)
	elif state == PlayerController3D.STATE_RUN:
		var run_vx: float = absf(player.velocity.x)
		var target_speed: float = maxf(player.run_speed, 0.1)
		animation_player.speed_scale = clampf(run_vx / target_speed, 0.85, 1.25)
	elif state == PlayerController3D.STATE_CREEP_WALK:
		animation_player.speed_scale = 0.8
	elif state == PlayerController3D.STATE_WADING_SWAMP:
		var wade_vx: float = absf(player.velocity.x)
		animation_player.speed_scale = clampf(wade_vx / 2.0, 0.6, 1.1)
	else:
		animation_player.speed_scale = 1.0


func _on_kinetic_state_changed(new_state: StringName, _prev_state: StringName) -> void:
	_play_state_animation(new_state, 0.12)


func _play_state_animation(state: StringName, blend_time: float) -> void:
	if animation_player == null:
		return

	var target_anim: StringName = &"idle"
	var custom_blend: float = blend_time

	match state:
		PlayerController3D.STATE_IDLE:
			target_anim = &"idle"
			custom_blend = 0.2
		PlayerController3D.STATE_CREEP_WALK:
			target_anim = &"walk"
			custom_blend = 0.15
		PlayerController3D.STATE_RUN:
			target_anim = &"run"
			custom_blend = 0.15
		PlayerController3D.STATE_WADING_SWAMP:
			target_anim = &"wade"
			custom_blend = 0.2
		PlayerController3D.STATE_PUSH_PULL_HEAVY:
			target_anim = &"push"
			custom_blend = 0.15
		PlayerController3D.STATE_JUMP_START, PlayerController3D.STATE_AIRBORNE_RISE:
			target_anim = &"jump_rise"
			custom_blend = 0.08
		PlayerController3D.STATE_AIRBORNE_FALL:
			target_anim = &"jump_fall"
			custom_blend = 0.12
		PlayerController3D.STATE_HARD_LAND:
			target_anim = &"hard_land"
			custom_blend = 0.05
		PlayerController3D.STATE_CLIMB_LEDGE:
			target_anim = &"climb_ledge"
			custom_blend = 0.08
		_:
			target_anim = &"idle"

	if _current_anim != target_anim or not animation_player.is_playing():
		_current_anim = target_anim
		if animation_player.has_animation(target_anim):
			animation_player.play(target_anim, custom_blend)
