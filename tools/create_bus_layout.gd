@tool
extends SceneTree

func _init() -> void:
	# Configure AudioServer
	# Bus 0 is Master
	AudioServer.set_bus_name(0, &"Master")

	# 1. Ambience -> Master
	var idx_amb: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(idx_amb, &"Ambience")
	AudioServer.set_bus_send(idx_amb, &"Master")

	# 2. Foley -> Master
	var idx_foley: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(idx_foley, &"Foley")
	AudioServer.set_bus_send(idx_foley, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.5
	reverb.damping = 0.5
	reverb.wet = 0.2
	reverb.dry = 1.0
	AudioServer.add_bus_effect(idx_foley, reverb)

	# 3. Foley_Voice_0..3 -> Foley
	for i: int in 4:
		var idx_v: int = AudioServer.bus_count
		AudioServer.add_bus()
		var v_name: StringName = StringName("Foley_Voice_" + str(i))
		AudioServer.set_bus_name(idx_v, v_name)
		AudioServer.set_bus_send(idx_v, &"Foley")
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 12000.0
		AudioServer.add_bus_effect(idx_v, lpf)

	# 4. Voice -> Foley
	var idx_voice: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(idx_voice, &"Voice")
	AudioServer.set_bus_send(idx_voice, &"Foley")

	var layout: AudioBusLayout = AudioServer.generate_bus_layout()
	var err: Error = ResourceSaver.save(layout, "res://default_bus_layout.tres")
	print("Saved default_bus_layout.tres: ", err)
	quit()

