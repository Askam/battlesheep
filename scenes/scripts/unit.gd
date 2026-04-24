extends CharacterBody2D

var target: StaticBody2D       # Enclos visé par cette unité
var source_spot = null         # Enclos d'origine (pour renvoi bunker)
var has_rage: bool = false     # Buff rage : 20 % de chance de tuer 2 ennemis
var speed: float = 60.0
var race: String
var active_sprite: AnimatedSprite2D

# Tangente de la normale de collision du dernier frame (Vector2.ZERO = pas de contact mur)
# Calculé APRÈS move_and_slide(), appliqué au frame SUIVANT.
var slide_force := Vector2.ZERO

# Normale moyenne du mur touché, stockée pour le mode évasion.
var _last_wall_normal := Vector2.ZERO

# Détection de blocage : si l'unité ne progresse pas assez vers la cible en mode wall-following.
var _stuck_timer: float = 0.0
var _stuck_check_dist: float = 0.0
const STUCK_CHECK_INTERVAL := 2  # secondes entre deux vérifications de progrès
const STUCK_MIN_PROGRESS := 15.0   # pixels de rapprochement minimum pour ne pas être "bloquée"

# Mode évasion : applique la normale du mur au lieu de la tangente pour se décoincer.
var _escape_timer: float = 0.0
const ESCAPE_DURATION := 0.6       # secondes de poussée d'évasion

# Rayon et force max de l'évitement préventif des enclos (mode normal)
var avoid_radius: float = 70.0
var max_avoid_strength: float = 12.0

# Répulsion inter-unités activée uniquement en mode wall-following
const SEPARATION_RADIUS := 14.0
const SEPARATION_STRENGTH := 8.0

# Combat inter-factions en plein champ
const COMBAT_RADIUS := 10.0
var _dying: bool = false
var _combat_immune_timer: float = 0.0


func _ready() -> void:
	add_to_group("unit")
	if has_rage:
		var tween := create_tween().set_loops()
		tween.tween_property(self, "modulate:a", 0.2, 0.12)
		tween.tween_property(self, "modulate:a", 1.0, 0.12)


func _physics_process(delta: float) -> void:
	if _dying:
		velocity = Vector2.ZERO
		return
	if _combat_immune_timer > 0.0:
		_combat_immune_timer -= delta

	if target == null:
		velocity = Vector2.ZERO
		slide_force = Vector2.ZERO
		update_animation(Vector2.ZERO)
		return

	var dir_to_target: Vector2 = (target.global_position - global_position).normalized()
	var combined: Vector2

	if slide_force.length() > 0.01:
		# ── Mode wall-following ──────────────────────────────────────────────
		_stuck_timer += delta
		if _stuck_timer >= STUCK_CHECK_INTERVAL:
			var dist_now := global_position.distance_to(target.global_position)
			if _stuck_check_dist - dist_now < STUCK_MIN_PROGRESS:
				# Pas assez de progrès → déclencher l'évasion
				_escape_timer = ESCAPE_DURATION
			_stuck_timer = 0.0
			_stuck_check_dist = global_position.distance_to(target.global_position)

		if _escape_timer > 0.0:
			# Mode évasion : pousser perpendiculairement au mur (normale) + direction cible.
			# Évite le glissement qui maintenait l'unité coincée dans le coin.
			_escape_timer -= delta
			combined = _last_wall_normal * 3.0 + dir_to_target
		else:
			# Wall-following normal : slide_force dominant + légère attraction vers la cible.
			combined = slide_force * 3.0 + dir_to_target

			# Répulsion inter-unités pour éviter l'empilement contre le mur.
			for unit in get_tree().get_nodes_in_group("unit"):
				if unit == self:
					continue
				var to_other: Vector2 = unit.global_position - global_position
				var dist := to_other.length()
				if dist < SEPARATION_RADIUS and dist > 0.01:
					var strength := (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
					combined -= to_other.normalized() * strength * SEPARATION_STRENGTH

		# Guard : si les forces s'annulent (cas coin), on replie sur la normale d'évasion
		if combined.length() < 0.001:
			combined = _last_wall_normal if _last_wall_normal.length() > 0.01 else dir_to_target

	else:
		# ── Mode normal : steering ───────────────────────────────────────────
		_stuck_timer = 0.0
		_stuck_check_dist = global_position.distance_to(target.global_position)

		# Évitement préventif des enclos non ciblés dans le rayon d'influence.
		var avoidance := Vector2.ZERO
		for spot in get_tree().get_nodes_in_group("spots"):
			if spot == target:
				continue
			var to_spot: Vector2 = spot.global_position - global_position
			var dist := to_spot.length()
			if dist <= 0.01 or dist >= avoid_radius:
				continue
			var to_spot_norm: Vector2 = to_spot / dist
			var strength: float = clamp((avoid_radius - dist) / avoid_radius * max_avoid_strength, 0.0, max_avoid_strength)
			var tangent1: Vector2 = Vector2(-to_spot_norm.y, to_spot_norm.x)
			var tangent2: Vector2 = -tangent1
			avoidance += (tangent1 if tangent1.dot(dir_to_target) >= tangent2.dot(dir_to_target) else tangent2) * strength

		combined = dir_to_target + avoidance
		if combined.length() < 0.001:
			combined = dir_to_target

	velocity = combined.normalized() * speed
	for spot in get_tree().get_nodes_in_group("spots"):
		if spot.building == "water" and spot.spotOwner != "none" and spot.spotOwner != race:
			if global_position.distance_to(spot.global_position) <= 160.0:
				velocity *= 0.5
				break
	update_animation(combined)
	move_and_slide()

	# ── Mise à jour du slide_force et de la normale ──────────────────────────
	# Après move_and_slide(), on lit les collisions réelles pour savoir si l'unité
	# touche un enclos non ciblé. On stocke la tangente (wall-following) ET la normale
	# (évasion) pour le frame suivant.
	slide_force = Vector2.ZERO
	_last_wall_normal = Vector2.ZERO
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var collider := col.get_collider()
		if collider != target and collider is StaticBody2D and collider.is_in_group("spots"):
			var normal := col.get_normal()
			_last_wall_normal += normal
			var t1 := Vector2(-normal.y, normal.x)
			var t2 := -t1
			slide_force += t1 if t1.dot(dir_to_target) > t2.dot(dir_to_target) else t2

	# Normalisation si plusieurs collisions simultanées s'accumulent
	if slide_force.length() > 1.0:
		slide_force = slide_force.normalized()
	if _last_wall_normal.length() > 1.0:
		_last_wall_normal = _last_wall_normal.normalized()

	# Combat en plein champ.
	if _combat_immune_timer > 0.0:
		return
	for unit in get_tree().get_nodes_in_group("unit"):
		if unit == self or unit._dying or unit.target == null or unit._combat_immune_timer > 0.0:
			continue
		if unit.race == race:
			continue
		if global_position.distance_to(unit.global_position) <= COMBAT_RADIUS:
			var self_dies: bool = not (has_rage and randf() < 0.2)
			var other_dies: bool = not (bool(unit.has_rage) and randf() < 0.2)
			if self_dies:
				_dying = true
				kill()
			else:
				_combat_immune_timer = 0.5
			if other_dies:
				unit._dying = true
				unit.kill()
			else:
				unit._combat_immune_timer = 0.5
			return


func set_race(newRace: String) -> void:
	$Sheep.visible = false
	$Pig.visible = false
	$Penguin.visible = false
	race = newRace
	match race:
		"sheep":  active_sprite = $Sheep
		"pig":    active_sprite = $Pig
		"penguin": active_sprite = $Penguin
	active_sprite.visible = true
	active_sprite.animation = "still"
	active_sprite.play()


func update_animation(direction: Vector2) -> void:
	if not active_sprite:
		return
	if direction == Vector2.ZERO:
		active_sprite.animation = "still"
		active_sprite.flip_h = false
	else:
		if abs(direction.x) > abs(direction.y):
			active_sprite.animation = "right"
			active_sprite.flip_h = direction.x < 0
		elif direction.y > 0:
			active_sprite.animation = "down"
			active_sprite.flip_h = false
		else:
			active_sprite.animation = "up"
			active_sprite.flip_h = false
	active_sprite.play()


func kill() -> void:
	if not active_sprite:
		queue_free()
		return
	active_sprite.animation = "splash"
	active_sprite.play()
	await get_tree().create_timer(1).timeout
	queue_free()
