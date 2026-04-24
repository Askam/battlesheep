extends Node2D


@export var spot_scene: PackedScene
@export var num_spots: int = 12
@export var area_size := Vector2(1024, 640)
@export var area_offset := Vector2(0, 80)
@export var num_players: int = 2
@export_range(1, 10) var difficulty: int = 5

var rng := RandomNumberGenerator.new()
var races := ["penguin", "sheep", "pig"]
var active_races := []
var spots = []

# Max half-diagonal (px from node origin) per spot size, derived from CollisionShape2D in spot.gd:
#   size 0: 35×40 at (2,-17.5)  → corner (19.5,-37.5) → 42.3 px
#   size 1: 50×56 at (2,-16)    → corner (27,-44)     → 51.6 px
#   size 2: 58×64 at (0,-12)    → corner (29,-44)     → 52.7 px
#   size 3: 74×81 at (2,-3.5)   → corner (39,-44)     → 58.8 px
const SPOT_HALF_DIAG: Array[float] = [43.0, 52.0, 53.0, 59.0]
const UNIT_PASSAGE := 28.0  # gap for 2 animals (2 × SEPARATION_RADIUS)

func _ready() -> void:
	num_players = GameConfig.num_players
	difficulty = GameConfig.difficulty
	rng.randomize()
	spawn_spots()

func _process(_delta: float) -> void:
	pass

func _min_center_dist(sa: int, sb: int) -> float:
	return SPOT_HALF_DIAG[sa] + SPOT_HALF_DIAG[sb] + UNIT_PASSAGE

func _valid_candidate(pos: Vector2, sz: int, positions: Array[Vector2], sizes: Array[int]) -> bool:
	for i in positions.size():
		if pos.distance_to(positions[i]) < _min_center_dist(sz, sizes[i]):
			return false
	return true

func spawn_spots():
	var tries := 0
	var target_size: int = rng.randi_range(0, 3)
	spots.clear()
	active_races.clear()

	var ai_spots := 0
	if num_players == 1:
		active_races.append(GameConfig.player_race)
		var added := 0
		for r in ["penguin", "sheep", "pig"]:
			if r != GameConfig.player_race:
				active_races.append(r)
				added += 1
				if added >= GameConfig.num_enemies:
					break
		# Avec 2 ennemis chacun a son enclos de départ : pas d'extra nécessaire
		ai_spots = 1 + (difficulty - 1) / 3
	else:
		for i in range(num_players):
			active_races.append(races[i])

	var total_players := active_races.size()

	# Étape 1 : générer des candidats {position, taille} en respectant l'espace réel entre enclos
	var cand_pos: Array[Vector2] = []
	var cand_sz: Array[int] = []
	while cand_pos.size() < num_spots * 4 and tries < 1000:
		var pos := Vector2(
			rng.randf_range(80, area_size.x - 80),
			rng.randf_range(80, area_size.y - 80)
		) + area_offset
		var sz: int = rng.randi_range(0, 3)
		if _valid_candidate(pos, sz, cand_pos, cand_sz):
			cand_pos.append(pos)
			cand_sz.append(sz)
		tries += 1

	# Étape 2 : choisir les positions les plus éloignées pour les joueurs
	var player_pos: Array[Vector2] = []
	var player_sz: Array[int] = []
	if cand_pos.size() >= total_players:
		player_pos.append(cand_pos[0])
		player_sz.append(cand_sz[0])
		cand_pos.remove_at(0)
		cand_sz.remove_at(0)
		while player_pos.size() < total_players:
			var best_idx := -1
			var best_dist := -1.0
			for i in cand_pos.size():
				var total_dist := 0.0
				for pp in player_pos:
					total_dist += cand_pos[i].distance_to(pp)
				if total_dist > best_dist:
					best_dist = total_dist
					best_idx = i
			if best_idx < 0:
				break
			player_pos.append(cand_pos[best_idx])
			player_sz.append(cand_sz[best_idx])
			cand_pos.remove_at(best_idx)
			cand_sz.remove_at(best_idx)

	# Étape 3 : instancier les spots joueurs (taille commune target_size)
	for i in range(player_pos.size()):
		var spot = spot_scene.instantiate()
		spot.position = player_pos[i]
		spot.set_data(active_races[i], target_size, 30, difficulty)
		add_child(spot)
		spots.append(spot)

	# Étape 4 : spots IA supplémentaires (uniquement avec 1 ennemi)
	var num_extra := (ai_spots - 1) if GameConfig.num_enemies == 1 else 0
	var extra_ai_race: String = active_races[1] if active_races.size() > 1 else "penguin"
	for _i in range(num_extra):
		if cand_pos.is_empty():
			break
		var spot = spot_scene.instantiate()
		spot.position = cand_pos[0]
		spot.set_data(extra_ai_race, cand_sz[0], 30, difficulty)
		add_child(spot)
		spots.append(spot)
		cand_pos.remove_at(0)
		cand_sz.remove_at(0)

	# Étape 5 : spots neutres
	while spots.size() < num_spots and not cand_pos.is_empty():
		var spot_size: int = cand_sz[0]
		var spot = spot_scene.instantiate()
		spot.position = cand_pos[0]
		spot.set_data("none", spot_size, rng.randi_range(0, 10 + spot_size * 10), difficulty)
		add_child(spot)
		spots.append(spot)
		cand_pos.remove_at(0)
		cand_sz.remove_at(0)

	# Étape 6 : garantir que les portails viennent toujours par paires.
	# On boucle pour gérer 1, 3, 5… portails impairs.
	var warp_spots: Array = spots.filter(func(s): return s.building == "warp")
	while warp_spots.size() % 2 != 0:
		var new_pos := Vector2.ZERO
		var new_sz: int = rng.randi_range(2, 3)
		for _try in 100:
			var pos := Vector2(
				rng.randf_range(80, area_size.x - 80),
				rng.randf_range(80, area_size.y - 80)
			) + area_offset
			if is_far_enough(pos, new_sz):
				new_pos = pos
				break
		if new_pos != Vector2.ZERO:
			# Place un second portail
			var spot = spot_scene.instantiate()
			spot.position = new_pos
			spot.set_data("none", new_sz, rng.randi_range(0, 20), difficulty)
			add_child(spot)
			spots.append(spot)
			spot.replace_building("warp")
			warp_spots.append(spot)
		else:
			# Plus de place → recycler un enclos vide (size >= 2) pour y poser le portail
			var empty_spot: Node = null
			for s in spots:
				if s.building == "none" and s.size >= 2:
					empty_spot = s
					break
			if empty_spot != null:
				empty_spot.replace_building("warp")
				warp_spots.append(empty_spot)
			else:
				# Aucun enclos disponible → supprimer le portail solitaire
				var lone: Node = warp_spots.pop_back()
				var fallback := ["bunker", "igloo", "love", "totem", "tower", "water", "box"]
				lone.replace_building(fallback[rng.randi() % fallback.size()])


func is_far_enough(pos: Vector2, sz: int = 3) -> bool:
	for s in spots:
		if s.position.distance_to(pos) < _min_center_dist(sz, s.size):
			return false
	return true

func randi_range(min_val: int, max_val: int) -> int:
	return rng.randi_range(min_val, max_val)
