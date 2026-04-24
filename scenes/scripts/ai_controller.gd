extends Node

var _spot_container: Node
var _swarm_launcher: Node
var _ai_races: Array = []
var _timers: Dictionary = {}
var _react_cd: Dictionary = {}  # cooldown de réaction par race (évite le spam)

# Paramètres dérivés du niveau (calculés une seule fois dans setup)
var _reaction_time: float    # secondes entre deux décisions périodiques
var _min_pop: int            # population minimale pour oser attaquer
var _defend_prob: float      # probabilité de tenter une défense active
var _skill: float            # 0.0 (niv 1, aléatoire) → 1.0 (niv 10, optimal)
var _difficulty: int = 1     # niveau brut conservé pour les seuils discrets
var _attack_threshold: float # ratio min (attaque / défense) pour oser un essaim
var _evac_threshold: int     # pop en dessous de laquelle on évacue au lieu de défendre
var _rally_prob: float       # probabilité de rassembler les troupes plutôt qu'attaquer

const REACT_CD := 4.0  # secondes minimum entre deux réactions événementielles


# Appelé par battle_scene._ready() avec les références de scène et le niveau.
func setup(spot_container: Node, swarm_launcher: Node, difficulty: int, races: Array) -> void:
	_spot_container = spot_container
	_swarm_launcher = swarm_launcher
	_ai_races = races.duplicate()

	_difficulty = clamp(difficulty, 1, 10)
	_skill = (_difficulty - 1) / 9.0
	_reaction_time = lerp(10.0, 1.5, _skill)
	_min_pop = int(round(lerp(20.0, 8.0, _skill)))
	_defend_prob = lerp(0.1, 0.85, _skill)
	# Niv 1 : attaque si ≥ 50 % de la pop adverse. Niv 10 : besoin de 120 % (ne perd jamais à dessein).
	_attack_threshold = lerp(0.5, 1.2, _skill)
	# Niv 1 : se bat jusqu'au bout. Niv 10 : évacue proactivement quand le spot est sur le point de tomber.
	_evac_threshold = int(round(lerp(0.0, 15.0, _skill)))
	# Niv 1 : jamais de rassemblement. Niv 10 : 25 % de chance par tick hors crise.
	_rally_prob = lerp(0.0, 0.25, _skill)

	# Décalage initial aléatoire pour éviter que toutes les factions agissent en même temps
	for race in _ai_races:
		_timers[race] = randf_range(2.0, _reaction_time)
		_react_cd[race] = 0.0


func _process(delta: float) -> void:
	for race in _ai_races:
		if _react_cd[race] > 0.0:
			_react_cd[race] = max(0.0, _react_cd[race] - delta)
		_timers[race] -= delta
		if _timers[race] <= 0.0:
			_timers[race] = randf_range(_reaction_time * 0.8, _reaction_time * 1.2)
			_decide(race)


func _decide(race: String) -> void:
	var owned: Array = _get_spots(race)
	if owned.is_empty():
		return

	# Menacé = combat en cours OU swarms ennemis déjà en transit vers ce spot
	var threatened: Array = owned.filter(func(s):
		return s.battle or _get_swarm_info(s, race).hostile > 0
	)

	# ── Priorité 1 : Évacuation ───────────────────────────────────────────────
	# Le spot est sur le point de tomber → sauver les troupes restantes vers un allié sûr.
	var critical: Array = threatened.filter(func(s): return s.pop <= _evac_threshold and s.pop >= 2)
	if not critical.is_empty():
		critical.sort_custom(func(a, b): return a.pop < b.pop)
		var spot = critical[0]
		var safe = _find_evacuation_target(owned, spot)
		if safe != null:
			_swarm_launcher.launch_swarm(spot, safe)
			return

	# ── Priorité 2 : Défense réaliste ────────────────────────────────────────
	# Spot encore viable → renforcer seulement si on a les moyens de changer le résultat.
	if randf() < _defend_prob:
		var defensible: Array = threatened.filter(func(s): return s.pop > _evac_threshold)
		if not defensible.is_empty():
			# Défendre en priorité le spot de plus grande taille (plus stratégique)
			defensible.sort_custom(func(a, b): return a.size > b.size)
			var spot = defensible[0]
			var reinforcer = _best_reinforcer(owned, spot)
			if reinforcer != null:
				_swarm_launcher.launch_swarm(reinforcer, spot)
				return

	# ── Priorité 3 : Rassemblement tactique (hors crise) ─────────────────────
	# Regrouper les surplus de pop vers l'enclos le plus stratégique avant d'attaquer.
	if threatened.is_empty() and randf() < _rally_prob:
		var rally_target = _find_rally_target(owned)
		if rally_target != null:
			var surplus = _find_rally_source(owned, rally_target)
			if surplus != null:
				_swarm_launcher.launch_swarm(surplus, rally_target)
				return

	# ── Priorité 4 : Attaque / expansion ─────────────────────────────────────
	# Un grand enclos doit conserver une réserve proportionnelle à sa valeur productive.
	var sources: Array = owned.filter(func(s): return s.pop >= _min_pop * _prod_weight(s) and not s.battle)
	if sources.is_empty():
		return
	var source = _pick_source(sources)
	var target = _pick_target(source, race)
	if target != null:
		_swarm_launcher.launch_swarm(source, target)


# ── Helpers défense ───────────────────────────────────────────────────────────

func _get_spots(race: String) -> Array:
	return _spot_container.spots.filter(func(s): return s.spotOwner == race)


func _find_evacuation_target(owned: Array, threatened):
	# Enclos allié le plus proche qui n'est pas lui-même sous attaque.
	var safe: Array = owned.filter(func(s): return s != threatened and not s.battle)
	if safe.is_empty():
		return null
	var best = safe[0]
	for s in safe:
		if s.global_position.distance_to(threatened.global_position) < best.global_position.distance_to(threatened.global_position):
			best = s
	return best


func _best_reinforcer(owned: Array, target):
	# Défense "réaliste" : le renfort envoie au moins 50 % de la pop actuelle du spot défendu.
	var min_send: float = max(target.pop * 0.5, float(_evac_threshold))
	var candidates: Array = owned.filter(func(s):
		return s != target and not s.battle and s.pop / 2.0 >= min_send
	)
	if candidates.is_empty():
		return null
	var best = candidates[0]
	for s in candidates:
		if s.global_position.distance_to(target.global_position) < best.global_position.distance_to(target.global_position):
			best = s
	return best


# ── Helpers rassemblement ─────────────────────────────────────────────────────

func _find_rally_target(owned: Array):
	# Spot le plus stratégique : taille max, puis pop max en cas d'égalité.
	if owned.size() <= 1:
		return null
	var best = owned[0]
	for s in owned:
		if s.size > best.size or (s.size == best.size and s.pop > best.pop):
			best = s
	return best


func _find_rally_source(owned: Array, rally_target):
	# Spot périphérique avec surplus de pop (> 1.5 × _min_pop), pas en combat.
	var candidates: Array = owned.filter(func(s):
		return s != rally_target and s.pop >= int(_min_pop * 1.5) and not s.battle
	)
	if candidates.is_empty():
		return null
	var best = candidates[0]
	for s in candidates:
		if s.pop > best.pop:
			best = s
	return best


# ── Perception ennemie (information partielle selon difficulté) ───────────────

func _observed_pop(spot) -> int:
	# Spots alliés ou neutres : toujours la vraie valeur.
	if spot.spotOwner in _ai_races or spot.spotOwner == "none":
		return spot.pop
	# Difficulté 10 : l'IA triche, elle voit tout.
	if _difficulty == 10:
		return spot.pop
	# Difficulté < 5 : information complète pour tout le monde.
	if _difficulty < 5:
		return spot.pop
	# Difficulté 5-9 : estimation bruitée. Plus le niveau est bas, plus le bruit est grand.
	# noise_ratio : ~33 % à niv 5, ~7 % à niv 9.
	var noise_ratio := (1.0 - _skill) * 0.6
	var noise := int(float(spot.pop) * randf_range(-noise_ratio, noise_ratio))
	return max(0, int(spot.pop) + noise)


# ── Helpers offensifs ─────────────────────────────────────────────────────────

func _pick_source(sources: Array):
	# Niveau élevé : enclos le plus peuplé. Niveau faible : aléatoire.
	if randf() < _skill:
		var best = sources[0]
		for s in sources:
			if s.pop > best.pop:
				best = s
		return best
	return sources[randi() % sources.size()]


func _pick_target(source, race: String):
	var attack_power: float = source.pop / 2.0
	var candidates: Array = _spot_container.spots.filter(func(s):
		if s.spotOwner == race or s == source:
			return false
		# Ne pas cibler un spot vers lequel on envoie déjà un swarm
		var info := _get_swarm_info(s, race)
		if info.friendly > 0:
			return false
		# La défense effective tient compte des swarms ennemis déjà en route
		# (s'ils affaiblissent déjà le spot, c'est plus facile à prendre)
		var effective_defense: int = max(0, _observed_pop(s) - int(info.hostile))
		if effective_defense > 0 and attack_power < effective_defense * _attack_threshold:
			return false
		return true
	)
	if candidates.is_empty():
		return null

	# Niveau faible : cible aléatoire. Niveau élevé : score par pop faible + proximité.
	if randf() > _skill:
		return candidates[randi() % candidates.size()]

	candidates.sort_custom(func(a, b): return _target_score(a, source) < _target_score(b, source))
	# Top 1-3 pour garder un peu d'imprévisibilité même au niveau max
	var pool: int = max(1, min(3, candidates.size()))
	return candidates[randi() % pool]


func _prod_weight(spot) -> float:
	# Ratio de production par rapport à la taille 0 (inverse des cooldowns : 4s/3s/2s/1s).
	match spot.size:
		0: return 1.0
		1: return 4.0 / 3.0
		2: return 2.0
		3: return 4.0
		_: return 1.0


func _target_score(spot, source) -> float:
	# Score bas = cible attractive. Préfère : pop faible, proche, neutre, grande taille.
	var dist_penalty: float = spot.global_position.distance_to(source.global_position) * 0.05
	var pop_penalty: float = float(_observed_pop(spot)) * 2.0
	var enemy_malus: float = 0.0 if spot.spotOwner == "none" else 10.0
	var size_bonus: float = _prod_weight(spot) * 8.0
	return pop_penalty + dist_penalty + enemy_malus - size_bonus


# ── Conscience des swarms en vol ──────────────────────────────────────────────

func _get_swarm_info(target_spot, race: String) -> Dictionary:
	# Compte les unités en transit vers target_spot, du point de vue de 'race'.
	var friendly := 0  # unités de 'race' en route
	var hostile  := 0  # unités d'autres factions en route
	for unit in _swarm_launcher.units:
		if not is_instance_valid(unit) or unit.target != target_spot:
			continue
		if unit.race == race:
			friendly += 1
		else:
			hostile += 1
	return {"friendly": friendly, "hostile": hostile}


# ── Réactivité événementielle ─────────────────────────────────────────────────

func on_swarm_launched(source_spot, target_spot, race: String) -> void:
	# Ignoré si c'est un de nos propres swarms.
	if race in _ai_races:
		return
	# Un swarm ennemi vient d'être lancé : réagir si on possède la cible.
	for ai_race in _ai_races:
		if _react_cd[ai_race] > 0.0:
			continue
		if target_spot.spotOwner == ai_race:
			_react_to_attack(source_spot, target_spot, ai_race)
			break


func on_spot_owner_changed(spot, new_owner: String, old_owner: String) -> void:
	# Un de nos spots vient d'être capturé → tenter de le reprendre immédiatement.
	if old_owner not in _ai_races:
		return
	var race: String = old_owner
	if _react_cd[race] > 0.0:
		return
	if randf() > _defend_prob:
		return
	var owned := _get_spots(race)
	if owned.is_empty():
		return
	# Trouver le spot allié le plus proche et le plus apte à contre-attaquer.
	owned = owned.filter(func(s): return s.pop >= _min_pop and not s.battle)
	if owned.is_empty():
		return
	owned.sort_custom(func(a, b):
		return a.global_position.distance_to(spot.global_position) < b.global_position.distance_to(spot.global_position)
	)
	_swarm_launcher.launch_swarm(owned[0], spot)
	_react_cd[race] = REACT_CD


func _react_to_attack(source_spot, target_spot, race: String) -> void:
	if randf() > _defend_prob:
		return
	var owned := _get_spots(race)
	var info := _get_swarm_info(target_spot, race)
	var our_total: float = float(target_spot.pop) + float(info.friendly)
	var their_total: float = float(info.hostile)

	# Option 1 : renforcer si on peut renverser la balance.
	if our_total < their_total:
		var reinforcer = _best_reinforcer(owned, target_spot)
		if reinforcer != null:
			_swarm_launcher.launch_swarm(reinforcer, target_spot)
			_react_cd[race] = REACT_CD
			return

	# Option 2 : contre-attaquer le spot source (l'ennemi vient de s'affaiblir).
	if source_spot.spotOwner == race:
		return  # la source nous appartient déjà, pas de sens
	var attackers := owned.filter(func(s):
		return s != target_spot and s.pop >= _min_pop and not s.battle
	)
	if attackers.is_empty():
		return
	attackers.sort_custom(func(a, b):
		return a.global_position.distance_to(source_spot.global_position) < b.global_position.distance_to(source_spot.global_position)
	)
	var attacker = attackers[0]
	# La source vient d'envoyer un swarm → sa défense effective est réduite
	var src_pop: int = _observed_pop(source_spot)
	var source_defense: float = src_pop * 0.5
	if float(attacker.pop) / 2.0 >= source_defense * _attack_threshold or randf() > _skill:
		_swarm_launcher.launch_swarm(attacker, source_spot)
		_react_cd[race] = REACT_CD
