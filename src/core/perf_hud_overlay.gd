class_name PerfHudOverlay
extends CanvasLayer
## 60 FPS Telemetry & Playdead Acoustic Debugger HUD (Toggleable via F3).
##
## Displays real-time frame-time metrics against the 16.67 ms Intel UHD budget,
## PlayerController3D HSM state & strain, DynamicCameraRig3D Second-Order
## Dynamics spring telemetry, and FoleyAudioDirector3D 3-layer sample selection,
## shoe wetness carry-over, LIMBO sustained-run decay, and breathing cadence.

const ACTION_TOGGLE_HUD: StringName = &"toggle_debug_hud"
const TARGET_FRAME_MS: float = 16.67
const HUD_UPDATE_INTERVAL_SEC: float = 0.12

@export var player: PlayerController3D
@export var camera_rig: DynamicCameraRig3D
@export var foley_director: FoleyAudioDirector3D
@export var post_process_material: ShaderMaterial
@export var start_visible: bool = true
@export var graphics_preset_label: String = "[RTX ULTRA: Volumetrics + SSR + SSAO ON]"
@export var narrative_status_label: String = "ACT I: THE SILENT BUNKER | Beat 1.1"

var _panel: PanelContainer = null
var _telemetry_label: RichTextLabel = null
var _smoothed_frame_ms: float = 16.67
var _hud_visible: bool = true
var _hud_refresh_accum: float = 0.12


func _ready() -> void:
	layer = 64
	_ensure_toggle_input()
	_build_hud_controls()
	_hud_visible = start_visible
	if _panel != null:
		_panel.visible = _hud_visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE_HUD):
		_hud_visible = not _hud_visible
		if _panel != null:
			_panel.visible = _hud_visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var inst_ms: float = delta * 1000.0
	_smoothed_frame_ms = lerpf(_smoothed_frame_ms, inst_ms, 0.12)

	# Drive post-process vignette boost from player strain & swamp exertion
	if post_process_material != null and player != null:
		var strain_val: float = player.get_strain()
		if foley_director != null:
			strain_val = maxf(strain_val, foley_director.get_exertion() * 0.65)
		post_process_material.set_shader_parameter(&"strain_vignette_boost", clampf(strain_val, 0.0, 1.0))

	if not _hud_visible or _telemetry_label == null:
		return

	_hud_refresh_accum += delta
	if _hud_refresh_accum < HUD_UPDATE_INTERVAL_SEC:
		return
	_hud_refresh_accum = 0.0

	var fps: float = Engine.get_frames_per_second()
	var budget_ok: bool = _smoothed_frame_ms <= TARGET_FRAME_MS + 0.5
	var perf_color: String = "#7ce38b" if budget_ok else "#ff7b72"

	# Player HSM & Strain
	var state_str: String = "N/A"
	var strain_pct: float = 0.0
	var vel_str: String = "(0.00, 0.00)"
	if player != null:
		state_str = String(player.get_state_name())
		strain_pct = player.get_strain() * 100.0
		vel_str = "(%.2f, %.2f) m/s" % [player.velocity.x, player.velocity.y]

	# Camera Rig Telemetry
	var cam_region_str: String = "Default Framing"
	var cam_vel_str: String = "(0.00, 0.00, 0.00)"
	var cam_fov_val: float = 52.0
	if camera_rig != null:
		var active_reg: CameraRegionVolume3D = camera_rig.get_active_region()
		if active_reg != null:
			cam_region_str = "%s (prio %d)" % [active_reg.name, active_reg.priority]
		var sv: Vector3 = camera_rig.get_spring_velocity()
		cam_vel_str = "(%.2f, %.2f, %.2f) m/s" % [sv.x, sv.y, sv.z]
		if camera_rig.camera != null:
			cam_fov_val = camera_rig.camera.fov

	# Acoustic & Foley Telemetry
	var surf_str: String = "concrete_dry"
	var wetness_pct: float = 0.0
	var decay_db: float = 0.0
	var step_count: int = 0
	var breath_phase_str: String = "Idle"
	var exertion_pct: float = 0.0
	var duck_db: float = 0.0
	var l1_wav: String = "-"
	var l2_wav: String = "-"
	var l3_wav: String = "-"
	if foley_director != null:
		var sid: StringName = foley_director.get_last_surface_id()
		surf_str = String(sid) if sid != &"" else "concrete_dry (init)"
		wetness_pct = foley_director.get_shoe_wetness() * 100.0
		step_count = foley_director.get_consecutive_steps()
		decay_db = foley_director.get_sustained_decay_db(step_count)
		breath_phase_str = foley_director.get_breath_phase()
		exertion_pct = foley_director.get_exertion() * 100.0
		duck_db = foley_director.get_ambience_duck_db()
		l1_wav = foley_director.get_last_layer1_wav()
		l2_wav = foley_director.get_last_layer2_wav()
		l3_wav = foley_director.get_last_layer3_wav()

	var zone_str: String = "None (Dry)"
	var active_reverb: AcousticReverbZone3D = AcousticReverbZone3D.get_active_zone()
	if active_reverb != null:
		zone_str = "%s (wet %.0f%%, room %.0f%%)" % [
			active_reverb.name,
			active_reverb.wet * 100.0,
			active_reverb.room_size * 100.0
		]

	var lines: PackedStringArray = PackedStringArray([
		"[b][color=#c9d1d9]SILENT WEIGHT (2.5D) — TELEMETRY & PLAYDEAD ACOUSTIC DEBUGGER[/color][/b] [color=#8b949e][F3 HUD | F4 Graphics][/color]",
		"[color=#58a6ff]■ PERFORMANCE & GRAPHICS SCALER[/color]",
		"  FPS: [b][color=%s]%.0f[/color][/b]  |  Frame Time: [b][color=%s]%.2f ms[/color][/b] (Target <= 16.6 ms)",
		"  Graphics Preset (F4): [b][color=#ffa657]%s[/color][/b]",
		"  Narrative State: [b][color=#d2a8ff]%s[/color][/b]",
		"[color=#58a6ff]■ PLAYER HSM & BIOMECHANICS[/color]",
		"  State: [b]%s[/b]  |  Velocity: %s",
		"  Strain Factor: [b]%.0f%%[/b]  |  Exertion: [b]%.0f%%[/b]  |  Breathing: [b]%s[/b]",
		"[color=#58a6ff]■ DYNAMIC CAMERA RIG (Second-Order Dynamics)[/color]",
		"  Active Region: [b]%s[/b]  |  FOV: [b]%.1f°[/b]",
		"  Spring Velocity: %s",
		"[color=#58a6ff]■ PLAYDEAD FOLEY ENGINE (Martin Stig Andersen Pipeline)[/color]",
		"  Surface ID: [b]%s[/b]  |  Reverb Zone: [b]%s[/b]",
		"  Shoe Wetness Carry-Over: [b]%.0f%%[/b]  |  LIMBO Run Decay: [b]%+.2f dB[/b] (step #%d)  |  Amb Duck: [b]%+.2f dB[/b]",
		"  L1 (Strike):   [color=#a5d6ff]%s[/color]",
		"  L2 (Body/Scuff): [color=#a5d6ff]%s[/color]",
		"  L3 (Suction/Tail): [color=#a5d6ff]%s[/color]"
	])
	var template: String = "\n".join(lines)
	_telemetry_label.text = template % [
		perf_color, fps, perf_color, _smoothed_frame_ms,
		graphics_preset_label,
		narrative_status_label,
		state_str, vel_str,
		strain_pct, exertion_pct, breath_phase_str,
		cam_region_str, cam_fov_val,
		cam_vel_str,
		surf_str, zone_str,
		wetness_pct, decay_db, step_count, duck_db,
		l1_wav,
		l2_wav,
		l3_wav
	]


func _ensure_toggle_input() -> void:
	if not InputMap.has_action(ACTION_TOGGLE_HUD):
		InputMap.add_action(ACTION_TOGGLE_HUD)
	if InputMap.action_get_events(ACTION_TOGGLE_HUD).is_empty():
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = KEY_F3
		InputMap.action_add_event(ACTION_TOGGLE_HUD, ev)


func _build_hud_controls() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TelemetryPanel"
	_panel.position = Vector2(14.0, 14.0)
	_panel.custom_minimum_size = Vector2(540.0, 290.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.82)
	style.border_color = Color(0.22, 0.28, 0.34, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override(&"panel", style)

	_telemetry_label = RichTextLabel.new()
	_telemetry_label.name = "TelemetryRichText"
	_telemetry_label.bbcode_enabled = true
	_telemetry_label.fit_content = true
	_telemetry_label.scroll_active = false
	_telemetry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_telemetry_label.custom_minimum_size = Vector2(516.0, 268.0)
	_telemetry_label.add_theme_font_size_override(&"normal_font_size", 12)
	_telemetry_label.add_theme_font_size_override(&"bold_font_size", 12)

	_panel.add_child(_telemetry_label)
	add_child(_panel)
