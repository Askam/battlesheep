extends Node2D

signal swarm_launched(source_spot, target_spot, race)

@export var unit_scene: PackedScene
var units: Array = []
var race: String
var target: StaticBody2D = null
var finished: bool = false
var isReady = false

func launch_swarm(source_spot, target_spot):
	if source_spot.building == "warp" and target_spot.building == "warp":
		_resolve_warp(source_spot, target_spot)
		return

	race = source_spot.spotOwner
	target = target_spot
	target_spot.isTarget = true

	var unit_count = source_spot.pop / 2
	var is_rage: bool = source_spot.building == "rage"
	var is_igloo: bool = source_spot.building == "igloo"
	for i in range(unit_count):
		source_spot.remove_unit(false)
		add_unit(source_spot.global_position, source_spot, is_rage, is_igloo)

	swarm_launched.emit(source_spot, target_spot, race)

func _resolve_warp(source_spot, target_spot) -> void:
	var swarm_race: String = source_spot.spotOwner
	var unit_count: int = source_spot.pop / 2
	for i in range(unit_count):
		source_spot.remove_unit(false)
	swarm_launched.emit(source_spot, target_spot, swarm_race)
	for i in range(unit_count):
		target_spot.receive_unit(swarm_race)


func add_unit(source_pos: Vector2, src_spot = null, rage: bool = false, igloo: bool = false) -> void:
	var unit = unit_scene.instantiate()
	unit.set_race(race)
	unit.source_spot = src_spot
	unit.has_rage = rage
	if igloo:
		unit.speed = 120.0
	
	# Compute direction from source to target
	var dir := (target.global_position - source_pos).normalized()

	# Perpendicular vector to spread units left/right
	var perp := Vector2(-dir.y, dir.x)

	# Distance in front of the source spot
	var forward_distance := 60.0 + randf_range(-5.0, 5.0)

	# Lateral offset to avoid stacking (tune this)
	var side_offset := randf_range(-20.0, 20.0)

	var start_pos := source_pos \
		+ dir * forward_distance \
		+ perp.normalized() * side_offset
	
	unit.target = target
	units.append(unit)
	unit.tree_exiting.connect(func(): units.erase(unit))
	add_child(unit)
	unit.global_position = start_pos
	
