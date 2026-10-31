@tool
extends SceneTree

func _init() -> void:
	_add_action(&"move_left", KEY_A)
	_add_action(&"move_right", KEY_D)
	_add_action(&"jump", KEY_SPACE)
	_add_action(&"creep", KEY_SHIFT)
	_add_action(&"grab", KEY_E)

	var err: Error = ProjectSettings.save()
	print("ProjectSettings.save(): ", err)
	quit(0 if err == OK else 1)


static func _add_action(name: StringName, keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	var action_dict: Dictionary = {
		"deadzone": 0.2,
		"events": [event]
	}
	ProjectSettings.set_setting("input/" + name, action_dict)

