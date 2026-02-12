@tool
extends Node3D
## Sun orbits the planet center using real UTC time, so every client
## sees the same sun position without any network sync.

## Orbit speed in radians per real-world second.
## Default 0.02 → full day/night cycle ≈ 5 minutes.
## 0.005 → ~21 min cycle.   0.001 → ~105 min cycle.
@export var orbit_speed: float = 0.02

## Distance from the planet center (visual only; directional lights
## ignore position, only direction matters).
@export var orbit_radius: float = 1200.0

## Axial tilt in degrees — tilts the orbit plane for varied lighting.
@export var orbit_tilt: float = 23.5


func _physics_process(_delta: float) -> void:
	# Use real UTC epoch so all clients compute the same angle.
	var now := Time.get_unix_time_from_system()
	var angle := fmod(now * orbit_speed, TAU)

	var tilt_rad := deg_to_rad(orbit_tilt)
	var x := cos(angle) * orbit_radius
	var z := sin(angle) * cos(tilt_rad) * orbit_radius
	var y := sin(angle) * sin(tilt_rad) * orbit_radius

	global_position = Vector3(x, y, z)

	# Face the planet center — the DirectionalLight3D child inherits
	# this rotation, so light always shines toward the planet.
	var up := Vector3.UP
	if abs(y / orbit_radius) > 0.99:
		up = Vector3.RIGHT  # avoid gimbal lock near poles
	look_at(Vector3.ZERO, up)
