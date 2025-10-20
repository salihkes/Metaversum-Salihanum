extends RefCounted
class_name AnimationBase

# Base class for animation modules
# This defines the interface that all animation types must implement

# References that will be set by the character controller
var character: CharacterBody3D
var character_model: Node3D
var sound_player: AudioStreamPlayer3D

# Animation parameters that can be overridden
var animation_speed := 10.0
var footstep_rate := 0.3

# Sound resources
var footstep_sound: AudioStream
var jump_sound: AudioStream

# Animation state
var footstep_timer := 0.0
var walk_cycle := 0.0

func _init():
	pass

# Virtual methods that must be implemented by subclasses
func setup(char: CharacterBody3D, model: Node3D, audio_player: AudioStreamPlayer3D) -> void:
	character = char
	character_model = model
	sound_player = audio_player
	
	# Load default sounds
	footstep_sound = preload("res://src/sound/bfsl-minifigfoots1.mp3")
	jump_sound = preload("res://src/sound/swoosh.wav")

func animate(delta: float, speed: float, movement_dir: Vector3, is_running: bool, is_on_floor: bool) -> void:
	# Override in subclasses to handle animations
	pass

func animate_remote(speed: float, direction: Vector3, is_on_floor: bool = true) -> void:
	# Override in subclasses to handle remote player animations
	pass

func cleanup() -> void:
	# Override in subclasses for cleanup when switching animation types
	pass

# Helper methods that can be used by subclasses
func play_footstep_sound(intensity: float = 1.0):
	if sound_player and footstep_sound:
		sound_player.stream = footstep_sound
		sound_player.pitch_scale = randf_range(0.8, 1.2) * intensity
		sound_player.volume_db = linear_to_db(0.3 * intensity)
		sound_player.play()

func play_jump_sound():
	if sound_player and jump_sound:
		sound_player.stream = jump_sound
		sound_player.pitch_scale = randf_range(0.9, 1.1)
		sound_player.volume_db = linear_to_db(0.5)
		sound_player.play()

# Helper to determine if character should be considered on floor
func _is_character_on_floor() -> bool:
	if character.has_method("_is_character_on_floor"):
		return character._is_character_on_floor()
	else:
		return character.is_on_floor() 