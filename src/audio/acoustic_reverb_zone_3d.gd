class_name AcousticReverbZone3D
extends Area3D
## Acoustic space volume. When the player enters, the zone becomes the active
## acoustic space and crossfades the reverb on the `Foley` bus toward its own
## room_size / damping / wet (plus predelay, spread and dry for character).
##
## Zones form a static stack shared by all instances: the active zone is the
## highest priority overlapping zone (ties -> most recently entered). Only the
## active zone drives the reverb, so overlapping boundaries never fight.
## The crossfade is a frame-rate independent exponential approach evaluated in
## _physics_process (no Tweens, no allocations).
##
## FoleyAudioDirector3D queries get_active_zone() to decide whether the space is
## "quiet" enough for inverse ambience ducking.

signal zone_activated(zone_id: StringName)

enum AcousticPreset {
	CUSTOM,
	CONCRETE_BUNKER,
	SWAMP_MARSH,
	OPEN_FIELD,
}

static var _active_stack: Array[AcousticReverbZone3D] = []

@export var zone_id: StringName = &"zone"
## Selecting a preset overwrites the reverb targets below.
@export var preset: AcousticPreset = AcousticPreset.CUSTOM:
	set(value):
		preset = value
		_apply_preset(value)
# Note: `priority` is inherited from Area3D and already exported.

@export var target_bus: StringName = &"Foley"
@export var crossfade_time_sec: float = 1.2
## Quiet zones enable the "naked world" inverse ambience ducking on footsteps.
@export var is_quiet_zone: bool = true

@export_group("Reverb Targets")
@export_range(0.0, 1.0, 0.01) var room_size: float = 0.5
@export_range(0.0, 1.0, 0.01) var damping: float = 0.5
@export_range(0.0, 1.0, 0.01) var wet: float = 0.2
@export_range(0.0, 1.0, 0.01) var dry: float = 1.0
@export_range(20.0, 500.0, 1.0) var predelay_msec: float = 20.0
@export_range(0.0, 0.98, 0.01) var predelay_feedback: float = 0.2
@export_range(0.0, 1.0, 0.01) var spread: float = 0.8
@export_range(0.0, 1.0, 0.01) var hipass: float = 0.0

var _reverb: AudioEffectReverb = null


static func get_active_zone() -> AcousticReverbZone3D:
	var best: AcousticReverbZone3D = null
	for zone: AcousticReverbZone3D in _active_stack:
		if not is_instance_valid(zone):
			continue
		if best == null or zone.priority >= best.priority:
			best = zone
	return best


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_reverb = _find_reverb()


func _exit_tree() -> void:
	_active_stack.erase(self)


func _physics_process(delta: float) -> void:
	if _reverb == null or get_active_zone() != self:
		return
	var k: float = 1.0 - exp(-delta * 4.0 / maxf(crossfade_time_sec, 0.01))
	_reverb.room_size = lerpf(_reverb.room_size, room_size, k)
	_reverb.damping = lerpf(_reverb.damping, damping, k)
	_reverb.wet = lerpf(_reverb.wet, wet, k)
	_reverb.dry = lerpf(_reverb.dry, dry, k)
	_reverb.predelay_msec = lerpf(_reverb.predelay_msec, predelay_msec, k)
	_reverb.predelay_feedback = lerpf(_reverb.predelay_feedback, predelay_feedback, k)
	_reverb.spread = lerpf(_reverb.spread, spread, k)
	_reverb.hipass = lerpf(_reverb.hipass, hipass, k)


func _on_body_entered(body: Node3D) -> void:
	if not (body is PlayerController3D):
		return
	_active_stack.erase(self)
	_active_stack.append(self)
	if get_active_zone() == self:
		zone_activated.emit(zone_id)


func _on_body_exited(body: Node3D) -> void:
	if not (body is PlayerController3D):
		return
	_active_stack.erase(self)
	var next_zone: AcousticReverbZone3D = get_active_zone()
	if next_zone != null:
		next_zone.zone_activated.emit(next_zone.zone_id)


func _find_reverb() -> AudioEffectReverb:
	var bus_index: int = AudioServer.get_bus_index(target_bus)
	if bus_index < 0:
		push_warning("AcousticReverbZone3D '%s': bus '%s' not found." % [name, target_bus])
		return null
	for i: int in AudioServer.get_bus_effect_count(bus_index):
		var reverb: AudioEffectReverb = AudioServer.get_bus_effect(bus_index, i) as AudioEffectReverb
		if reverb != null:
			return reverb
	push_warning("AcousticReverbZone3D '%s': no AudioEffectReverb on bus '%s'." % [name, target_bus])
	return null


func _apply_preset(value: AcousticPreset) -> void:
	match value:
		AcousticPreset.CONCRETE_BUNKER:
			# Cold, metallic slapback: small hard room, bright, early repeats.
			room_size = 0.42
			damping = 0.12
			wet = 0.38
			dry = 1.0
			predelay_msec = 38.0
			predelay_feedback = 0.35
			spread = 0.6
			hipass = 0.08
			is_quiet_zone = true
		AcousticPreset.SWAMP_MARSH:
			# Humid, damped decay: soft absorbent air, short dull tail.
			room_size = 0.62
			damping = 0.88
			wet = 0.2
			dry = 1.0
			predelay_msec = 12.0
			predelay_feedback = 0.1
			spread = 0.85
			hipass = 0.0
			is_quiet_zone = true
		AcousticPreset.OPEN_FIELD:
			# Wide air diffusion: barely-there wash, late and broad.
			room_size = 0.85
			damping = 0.55
			wet = 0.07
			dry = 1.0
			predelay_msec = 60.0
			predelay_feedback = 0.05
			spread = 1.0
			hipass = 0.15
			is_quiet_zone = false
		AcousticPreset.CUSTOM:
			pass
