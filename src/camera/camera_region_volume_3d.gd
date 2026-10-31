class_name CameraRegionVolume3D
extends Area3D
## Macro framing volume. While the player overlaps this Area3D, its framing and
## spring settings are offered to the DynamicCameraRig3D. When several volumes
## overlap, the rig uses the highest priority (ties -> most recently entered).
##
## The rig is resolved from `camera_rig` if assigned, otherwise from the first
## node in the "dynamic_camera_rig" group.

const RIG_GROUP: StringName = &"dynamic_camera_rig"

@export var camera_rig: DynamicCameraRig3D

@export_group("Framing")
# Note: `priority` is inherited from Area3D and already exported.

## Offset from the player's feet to the framed focus point (world space).
@export var framing_offset: Vector3 = Vector3(0.0, 1.2, 0.0)
## Distance from the focus point to the camera along the camera's back axis.
@export var target_distance_z: float = 8.0
@export_range(-60.0, 60.0) var pitch_degrees: float = -6.0
@export_range(-45.0, 45.0) var yaw_degrees: float = 0.0
@export_range(20.0, 100.0) var base_fov: float = 50.0

@export_group("Spring")
@export var spring_frequency: float = 1.2
@export var spring_damping_zeta: float = 1.0
@export var spring_response_r: float = 0.0


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	var rig: DynamicCameraRig3D = _resolve_rig()
	if rig != null:
		rig.unregister_region(self)


func _on_body_entered(body: Node3D) -> void:
	if not (body is PlayerController3D):
		return
	var rig: DynamicCameraRig3D = _resolve_rig()
	if rig != null:
		rig.register_region(self)


func _on_body_exited(body: Node3D) -> void:
	if not (body is PlayerController3D):
		return
	var rig: DynamicCameraRig3D = _resolve_rig()
	if rig != null:
		rig.unregister_region(self)


func _resolve_rig() -> DynamicCameraRig3D:
	if camera_rig != null:
		return camera_rig
	if not is_inside_tree():
		return null
	camera_rig = get_tree().get_first_node_in_group(RIG_GROUP) as DynamicCameraRig3D
	return camera_rig
