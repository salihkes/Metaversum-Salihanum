extends Node

var udp := PacketPeerUDP.new()
const PORT = 9000

func _ready():
	var err = udp.bind(PORT)
	if err != OK:
		print("Error binding to port " + str(PORT))
	else:
		print("Pixel Streaming Input Receiver listening on port " + str(PORT))

func _process(delta):
	if udp.get_available_packet_count() > 0:
		var packet = udp.get_packet()
		var packet_string = packet.get_string_from_utf8()
		if packet_string:
			_handle_input_packet(packet_string)

func _handle_input_packet(json_str):
	var json = JSON.new()
	var error = json.parse(json_str)
	if error != OK:
		print("JSON Parse Error: ", json.get_error_message())
		return
	
	var data = json.data
	if not data is Dictionary:
		return

	var type = data.get("type", "")
	
	if type == "key":
		var ev = InputEventKey.new()
		ev.pressed = data.get("pressed", false)
		
		var code_str = data.get("code", "")
		if code_str != "":
			var k = _map_js_key_to_godot(code_str)
			ev.physical_keycode = k
			ev.keycode = k
		else:
			ev.keycode = int(data.get("keycode", 0))
			ev.physical_keycode = int(data.get("physical_keycode", 0))
			
		ev.unicode = int(data.get("unicode", 0))
		ev.echo = false
		Input.parse_input_event(ev)
		
	elif type == "mouse_motion":
		var ev = InputEventMouseMotion.new()
		ev.position = Vector2(data.get("x", 0), data.get("y", 0))
		ev.relative = Vector2(data.get("dx", 0), data.get("dy", 0))
		Input.parse_input_event(ev)
		
	elif type == "mouse_button":
		var ev = InputEventMouseButton.new()
		ev.position = Vector2(data.get("x", 0), data.get("y", 0))
		ev.button_index = int(data.get("button_index", 1))
		ev.pressed = data.get("pressed", false)
		Input.parse_input_event(ev)

	elif type == "wheel":
		# Handle scroll wheel as mouse buttons 4 and 5 usually
		var ev = InputEventMouseButton.new()
		ev.position = Vector2(data.get("x", 0), data.get("y", 0))
		var delta_y = data.get("delta_y", 0)
		if delta_y > 0:
			ev.button_index = MOUSE_BUTTON_WHEEL_UP
		else:
			ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		Input.parse_input_event(ev)
		# Release immediately usually for wheel events? 
		# Godot handles wheel as press events.
		ev.pressed = false
		Input.parse_input_event(ev)
		
	elif type == "mouse_mode":
		var captured = data.get("captured", false)
		if captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _map_js_key_to_godot(js_code: String) -> int:
	# Strip "Key" prefix
	var key_str = js_code
	if key_str.begins_with("Key"):
		key_str = key_str.substr(3)
	elif key_str.begins_with("Digit"):
		key_str = key_str.substr(5)
	
	# Manual mapping for mismatches
	match key_str:
		"ArrowUp": key_str = "Up"
		"ArrowDown": key_str = "Down"
		"ArrowLeft": key_str = "Left"
		"ArrowRight": key_str = "Right"
		"ControlLeft": key_str = "Ctrl"
		"ControlRight": key_str = "Ctrl"
		"ShiftLeft": key_str = "Shift"
		"ShiftRight": key_str = "Shift"
		"AltLeft": key_str = "Alt"
		"AltRight": key_str = "Alt"
		"Escape": key_str = "Escape"
		"Enter": key_str = "Enter"
		"Space": key_str = "Space"
		"Backspace": key_str = "Backspace"
		"Tab": key_str = "Tab"
		
	return OS.find_keycode_from_string(key_str)
