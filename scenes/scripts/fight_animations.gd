extends Node2D

@onready var template: AnimatedSprite2D = $Template

const STANDARD_ANIMS := ["1", "2", "3"]
const RACE_ANIM := {"sheep": "sheep", "pig": "pig", "penguin": "pingouin"}
const ANIM_DURATION := 2.0
const OVERLAP := 0.3

var _running := false
var _defender_race: String
var _attacker_race: String
var _spot_size: int
var _slot_count: int
var _slot_timers: Array[float] = []

func start_fight(defender_race: String, attacker_race: String, spot_size: int) -> void:
	visible = true
	modulate.a = 1.0
	_defender_race = defender_race
	_attacker_race = attacker_race
	_spot_size = spot_size
	_running = true
	_slot_count = 3 + spot_size
	_slot_timers.resize(_slot_count)

	for i in _slot_count:
		if i < 2:
			# Spawn les animations de race immédiatement
			_spawn_anim(i)
			_slot_timers[i] = ANIM_DURATION - OVERLAP
		else:
			# Décalage aléatoire pour les animations standard
			_slot_timers[i] = randf_range(0.0, ANIM_DURATION)

func _process(delta: float) -> void:
	if not _running:
		return
	for i in _slot_count:
		_slot_timers[i] -= delta
		if _slot_timers[i] <= 0.0:
			_spawn_anim(i)
			_slot_timers[i] = ANIM_DURATION - OVERLAP

func _pick_animation(slot: int) -> String:
	# Slot 0 : race du défenseur (si l'enclos n'est pas neutre)
	if slot == 0 and _defender_race in RACE_ANIM:
		return RACE_ANIM[_defender_race]
	# Slot 1 : race de l'attaquant
	if slot == 1:
		return RACE_ANIM.get(_attacker_race, STANDARD_ANIMS[randi() % STANDARD_ANIMS.size()])
	return STANDARD_ANIMS[randi() % STANDARD_ANIMS.size()]

func _spawn_anim(slot: int) -> void:
	var spread := 10.0 + _spot_size * 7.0
	var anim: AnimatedSprite2D = template.duplicate()
	anim.visible = true
	anim.position = Vector2(randf_range(-spread, spread), randf_range(-spread, spread))
	anim.animation = _pick_animation(slot)
	anim.frame = randi() % anim.sprite_frames.get_frame_count(anim.animation)
	anim.modulate.a = 0.0
	anim.play()
	add_child(anim)

	# Fade in
	create_tween().tween_property(anim, "modulate:a", 1.0, 0.3)

	# Fade out après ANIM_DURATION puis libère le nœud
	var t := create_tween()
	t.tween_interval(ANIM_DURATION)
	t.tween_property(anim, "modulate:a", 0.0, OVERLAP)
	t.tween_callback(anim.queue_free)

func stop_fight() -> void:
	_running = false
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)
