class_name SurfaceAudioProfile
extends Resource
## Three-layer footstep description for one surface material.
##
## Layer 1 - Strike : the heel/toe transient (soft creep, hard run, landing).
## Layer 2 - Body   : the material texture under the foot (grit, mud mass,
##                    grass crush) and the drag/scuff variant for reversals.
## Layer 3 - Tail   : the delayed release as the foot lifts (mud suction,
##                    grass blades springing back), fired from the director's
##                    fixed tail queue after `tail_release_delay_sec`.
##
## Randomizers are AudioStreamRandomizer resources so each layer gets its own
## pitch / volume randomisation and no-repeat pool. Empty pools are skipped
## safely by FoleyAudioDirector3D.

@export var surface_id: StringName = &"default"

@export_group("Layer 1 - Strike")
@export var strike_soft_randomizer: AudioStreamRandomizer
@export var strike_hard_randomizer: AudioStreamRandomizer
@export var strike_land_randomizer: AudioStreamRandomizer

@export_group("Layer 2 - Body")
@export var body_texture_randomizer: AudioStreamRandomizer
@export var scuff_drag_randomizer: AudioStreamRandomizer

@export_group("Layer 3 - Tail")
@export var tail_release_randomizer: AudioStreamRandomizer
@export_range(0.0, 1.0, 0.005) var tail_release_delay_sec: float = 0.12
@export_range(-40.0, 12.0, 0.1) var tail_volume_offset_db: float = -6.0

@export_group("Tone")
## Low-pass cutoff applied to the voice's sub-bus for this surface.
@export_range(200.0, 20000.0, 1.0) var base_lowpass_cutoff_hz: float = 12000.0
## 0 = hard reflective surface, 1 = fully absorbent (muffles soft steps,
## lowers strike level).
@export_range(0.0, 1.0, 0.01) var surface_dampening: float = 0.0
## Wetness transferred to the character's shoes when stepping on this surface
## (1.0 for swamp mud, 0.0 for dry surfaces).
@export_range(0.0, 1.0, 0.01) var adds_wetness: float = 0.0


static func randomizer_is_playable(randomizer: AudioStreamRandomizer) -> bool:
	return randomizer != null and randomizer.streams_count > 0
