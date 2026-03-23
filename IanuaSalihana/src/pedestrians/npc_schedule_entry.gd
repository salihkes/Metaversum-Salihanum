class_name NpcScheduleEntry
extends Resource

## A single entry in an NPC's daily schedule.
## The NPC will travel to the named waypoint at the given hour and
## perform the specified action until the next schedule entry takes over.

## Hour of day (0-24) when this entry becomes active.
@export_range(0, 24, 0.5) var hour: float = 9.0

## Name of a Marker3D node under the "Waypoints" container.
@export var waypoint_name: String = ""

## Action identifier (e.g. "teaching", "patrolling").
## Resolved to an NpcAction at runtime. Leave empty for idle.
@export var action_name: String = ""
