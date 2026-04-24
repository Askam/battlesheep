extends StaticBody2D

var spotOwner := "none"
var size := 0
var pop := 0
var isSelected = false
var isTarget = false
var battle = false

var wait_pop := 0
var cur_swarmed := false
var time_accumulator := 0.0
var maxVisiblePop
var units = []

var building = "none"
var _building_excl := Rect2()  # zone locale où les unités ne spawnnent pas
var difficulty: int = 1

var fight_anim_instance = null
var battle_timer := 0.0
const BATTLE_TIMEOUT := 2.0

const CANNON_RANGE := 200.0
var cannon_timer := 0.0
var _cannon_circle: Polygon2D = null

const WATER_RANGE := 160.0
var _water_circle: Polygon2D = null

signal owner_changed(spot, new_owner, old_owner)
signal box_opened(spot, owner)

var _building_instance: Node = null
var _box_opening: bool = false

@export var unit_scene: PackedScene
@export var fight_animation: PackedScene
@export var building_scene: PackedScene
@export var small_building_scene: PackedScene

#Défini le cooldown d'apparition d'un nouveau mouton
func get_pop_cooldown_secs() -> float:
	var c
	match size:
		0: c = 4.0
		1: c = 3.0
		2: c = 2.0
		3: c = 1.0
		_: c = 10.0
		
	if building == "love" :
		c = c * 0.75
	return c

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	wait_pop = get_pop_cooldown_secs()
	add_to_group("spots")


func _should_hide_pop() -> bool:
	if spotOwner == GameConfig.player_race or spotOwner == "none":
		return false
	if difficulty < 5:
		return false
	for s in get_tree().get_nodes_in_group("spots"):
		if s.spotOwner == GameConfig.player_race and s.building == "tower":
			return false
	return true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$PopAmount.text = "?" if _should_hide_pop() else str(pop)
	
	if battle:
		battle_timer -= delta
		if battle_timer <= 0.0:
			end_battle()

	if !cur_swarmed and spotOwner != "none" and building != "plague" and building != "canon":
		time_accumulator += delta
		if time_accumulator >= get_pop_cooldown_secs():
			if pop < 50 + size*50:
				pop += 1
				#On affiche pas le nouveau mouton si y a plus la place
				if pop <= maxVisiblePop:
					add_unit()
			time_accumulator = 0.0

	if building == "canon" and spotOwner != "none":
		cannon_timer += delta
		if cannon_timer >= 1.0:
			cannon_timer = 0.0
			_fire_cannon()

#Ajoute 1 unitée
func add_unit() -> void:
	var unit = unit_scene.instantiate()
	unit.set_race(spotOwner)
	unit.position += _spawn_position()
	$UnitContainer.add_child(unit)
	units.append(unit)
	
	# Apparition animée
	unit.modulate.a = 0.0
	unit.scale = Vector2(0.1, 0.1)
	var tween := create_tween()
	tween.tween_property(unit, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(unit, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
func remove_unit(isKill: bool) -> void:
	pop = max(pop - 1, 0)
	if pop < maxVisiblePop and not units.is_empty():
		var unit = units.pop_back()
		if isKill and unit.has_method("kill"):
			unit.kill()
		else:
			unit.queue_free()
	
#Permet d'initialiser le spot
func set_data(newOwner: String, newSize: int, newPop: int, diff: int = 1) -> void:
	difficulty = diff
	size = clamp(newSize, 0, 3)
	change_owner(newOwner)
	pop = newPop
	maxVisiblePop = 5+size*15
	update_collision_shape()

	#On limite le nombre d'unité a afficher dans l'enclos
	if newOwner != "none":
		var maxPop = min(pop,maxVisiblePop)
		for n in maxPop:
			add_unit()

	var region = Rect2(0,100*size,100,100)
	$Shadow.texture = make_atlas($Shadow.texture.atlas, region)
	$Fence.texture = make_atlas($Fence.texture.atlas, region)
	$Selected.texture = make_atlas($Selected.texture.atlas, region)
	$Target.texture = make_atlas($Target.texture.atlas, region)

	if newOwner == "none":
		spawn_building(difficulty)


func spawn_building(diff: int) -> void:
	if randf() >= diff * 0.02:
		return
	var type: String
	if size <= 1:
		var roll := randf()
		if roll < 0.4: type = "canon"
		elif roll < 0.8: type = "rage"
		elif roll < 0.9: type = "totem"
		else: type = "box"
	else:
		if randf() < 0.6:
			type = "box"
		else:
			var large_types := ["bunker", "igloo", "love", "totem", "tower", "warp", "water"]
			type = large_types[randi() % large_types.size()]
	_apply_building(type)


func _apply_building(type: String) -> void:
	var instance: Node
	var build_pos: Vector2
	var excl_half: Vector2
	if size <= 1:
		instance = small_building_scene.instantiate()
		build_pos = Vector2(-4, -14) if size == 0 else Vector2(-11, -20)
		excl_half = Vector2(13, 22)
		instance.position = build_pos
		instance.z_index = 3
		add_child(instance)
		if type == "box":
			instance.get_node("box").visible = true
			instance.get_node("Building").visible = false
		else:
			instance.get_node("Building").animation = type
			instance.get_node("Building").visible = true
			instance.get_node("Building").play()
			instance.get_node("box").visible = false
	else:
		instance = building_scene.instantiate()
		build_pos = Vector2(-9, -16) if size == 2 else Vector2(-15, -16)
		excl_half = Vector2(20, 26)
		instance.position = build_pos
		instance.z_index = 3
		add_child(instance)
		instance.get_node("Building").animation = type
		if type != "box":
			instance.get_node("Building").play()
	building = type
	_building_excl = Rect2(build_pos - excl_half, excl_half * 2.0)
	_building_instance = instance
	if type == "canon":
		_add_cannon_circle()
	if type == "water":
		_add_water_circle()


func replace_building(new_type: String) -> void:
	if is_instance_valid(_building_instance):
		_building_instance.queue_free()
		_building_instance = null
	building = "none"
	_building_excl = Rect2()
	_apply_building(new_type)


func _open_box() -> void:
	if is_instance_valid(_building_instance):
		if size <= 1:
			_building_instance.get_node("box").play()
		else:
			_building_instance.get_node("Building").play()
	await get_tree().create_timer(0.8).timeout
	box_opened.emit(self, spotOwner)

func make_atlas(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = region
	return tex

func update_collision_shape():
	var shape := RectangleShape2D.new()
	var collisionPos
	match size:
		0:
			shape.size = Vector2(35, 40)
			collisionPos = Vector2(2, -17.5)
		1: 
			shape.size = Vector2(50, 56)
			collisionPos = Vector2(2, -16)
		2: 
			shape.size = Vector2(58, 64)
			collisionPos = Vector2(0, -12)
		3: 
			shape.size = Vector2(74, 81)
			collisionPos = Vector2(2, -3.5)
	$CollisionShape2D.position = collisionPos
	$CollisionShape2D.shape = shape
	$MouseDetectionArea.get_node("CollisionShape2D").shape = RectangleShape2D.new()
	$MouseDetectionArea.get_node("CollisionShape2D").position = collisionPos
	$MouseDetectionArea.get_node("CollisionShape2D").shape.size = shape.size + Vector2(5,5)

func set_selected(val: bool):
	$Selected.visible = val
	$Selected.modulate.a = 1
	isSelected = val

func set_target(val: bool):
	$Target.visible = val
	$Target.modulate.a = 1.0
	isTarget = val


#Détecter les clics
func _on_mouse_detection_area_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				get_parent().get_parent().call_deferred("on_spot_click_start", self)
			else:
				get_parent().get_parent().call_deferred("on_spot_click_end", self)
	pass # Replace with function body.

#Pour afficher la préselection
func _on_mouse_detection_area_mouse_entered() -> void:
	if get_parent().get_parent().selected_spot == null:
		#Pas encore de selection,
		$Selected.visible = true
		$Selected.modulate.a = 0.5
	else:
		$Target.visible = true
		$Target.modulate.a = 0.5

#Pour cacher la préselection
func _on_mouse_detection_area_mouse_exited() -> void:
	if !isSelected:
		$Selected.visible = false
		$Selected.modulate.a = 1
	if !isTarget:
		$Target.visible = false
		$Target.modulate.a = 1

#On utilise l'area de la souris pour détecter les moutons
func _on_mouse_detection_area_body_entered(body: Node2D) -> void:
	call_deferred("_handle_body_entered", body)

func _handle_body_entered(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	if body is CharacterBody2D and body.is_in_group("unit"):
		if body.target == self:
			var unit_race = body.race
			if unit_race == spotOwner:
				body.queue_free()
				pop += 1
				if pop <= maxVisiblePop:
					add_unit()
			else:
				if building == "bunker" and spotOwner != "none" and randf() < 0.4:
					# Renvoi : l'attaquant repart vers son spot d'origine, sans dégâts.
					if is_instance_valid(body.source_spot):
						body.target = body.source_spot
					else:
						body.queue_free()
					return
				start_battle(unit_race)
				var kills := 2 if body.has_rage and randf() < 0.2 else 1
				for i in kills:
					remove_unit(true)
				body.queue_free()
				if pop <= 0:
					end_battle()
					change_owner(body.race)
					
func receive_unit(arriving_race: String) -> void:
	if arriving_race == spotOwner:
		pop += 1
		if pop <= maxVisiblePop:
			add_unit()
	else:
		start_battle(arriving_race)
		remove_unit(true)
		if pop <= 0:
			end_battle()
			change_owner(arriving_race)


func start_battle(attacker_race: String) -> void:
	if not battle:
		battle = true
		fight_anim_instance = fight_animation.instantiate()
		fight_anim_instance.z_index = 10
		add_child(fight_anim_instance)
		fight_anim_instance.start_fight(spotOwner, attacker_race, size)
	battle_timer = BATTLE_TIMEOUT

func end_battle() -> void:
	battle = false
	if fight_anim_instance and is_instance_valid(fight_anim_instance):
		fight_anim_instance.stop_fight()
	fight_anim_instance = null

func change_owner(new_owner):
	var old_owner := spotOwner
	spotOwner = new_owner

	for unit in $UnitContainer.get_children():
		unit.queue_free()
	units.clear()

	# Masquer tous les grounds d'abord
	$GroundSheep.visible = false
	$GroundPinguin.visible = false
	$GroundPig.visible = false
	$GroundNeutral.visible = false

	# Afficher le bon sol
	var region = Rect2(0,100*size,100,100)
	match spotOwner:
		"sheep":
			$GroundSheep.visible = true
			$GroundSheep.texture = make_atlas($GroundSheep.texture.atlas, region)
		"pig":
			$GroundPig.visible = true
			$GroundPig.texture = make_atlas($GroundPig.texture.atlas, region)
		"penguin":
			$GroundPinguin.visible = true
			$GroundPinguin.texture = make_atlas($GroundPinguin.texture.atlas, region)
		_:
			$GroundNeutral.visible = true
			$GroundNeutral.texture = make_atlas($GroundNeutral.texture.atlas, region)

	_update_cannon_color()
	if building == "box" and new_owner != "none" and not _box_opening:
		_box_opening = true
		_open_box()
	owner_changed.emit(self, new_owner, old_owner)


# ── Spawn position avec zone d'exclusion ──────────────────────────────────────

func _spawn_position() -> Vector2:
	var r := 10.0 + 5.0 * size
	if building == "none":
		return Vector2(randf_range(-r, r), randf_range(-r, r) - 12.0)
	for _i in 10:
		var p := Vector2(randf_range(-r, r), randf_range(-r, r) - 12.0)
		if not _building_excl.has_point(p):
			return p
	# Repli vers le coin bas-droit si le building occupe trop de place
	return Vector2(r * 0.4, -12.0 + r * 0.3)


# ── Canon ─────────────────────────────────────────────────────────────────────

func _add_cannon_circle() -> void:
	var circle := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 64:
		var a := i * TAU / 64.0
		pts.append(Vector2(cos(a), sin(a)) * CANNON_RANGE)
	circle.polygon = pts
	circle.z_index = 1
	circle.z_as_relative = false  # z absolu : toujours visible au-dessus du sol de la carte
	_cannon_circle = circle
	_update_cannon_color()
	add_child(circle)


func _update_cannon_color() -> void:
	if _cannon_circle == null:
		return
	if spotOwner == GameConfig.player_race:
		_cannon_circle.color = Color(0.2, 0.5, 1.0, 0.25)
	else:
		_cannon_circle.color = Color(1.0, 0.2, 0.2, 0.25)


func _fire_cannon() -> void:
	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit):
			continue
		if unit.race == spotOwner:
			continue
		if unit._dying or unit.target == null:
			continue
		if global_position.distance_to(unit.global_position) > CANNON_RANGE:
			continue
		unit._dying = true
		unit.kill()
		return  # 1 kill par seconde


func _add_water_circle() -> void:
	var circle := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 64:
		var a := i * TAU / 64.0
		pts.append(Vector2(cos(a), sin(a)) * WATER_RANGE)
	circle.polygon = pts
	circle.color = Color(0.2, 0.7, 1.0, 0.18)
	circle.z_index = 1
	circle.z_as_relative = false
	_water_circle = circle
	add_child(circle)
