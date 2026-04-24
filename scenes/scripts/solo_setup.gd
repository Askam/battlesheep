extends Control

var _selected_race: String = "sheep"
var _num_enemies: int = 1
var _difficulty: int = 5


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := TextureRect.new()
	bg.texture = load("res://assets/img/bg.jpg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Mode Solo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	# ── Choix de l'animal ────────────────────────────────────────────────────
	var race_lbl := Label.new()
	race_lbl.text = "Votre animal :"
	race_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(race_lbl)

	var race_hbox := HBoxContainer.new()
	race_hbox.add_theme_constant_override("separation", 12)
	race_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(race_hbox)

	var race_names := {"sheep": "Mouton", "pig": "Cochon", "penguin": "Pingouin"}
	var race_group := ButtonGroup.new()
	var first_btn: Button = null

	for r in ["sheep", "pig", "penguin"]:
		var btn := Button.new()
		btn.text = race_names[r]
		btn.custom_minimum_size = Vector2(110, 44)
		btn.toggle_mode = true
		btn.button_group = race_group
		btn.toggled.connect(_on_race_toggled.bind(r))
		race_hbox.add_child(btn)
		if r == _selected_race:
			first_btn = btn

	if first_btn:
		first_btn.set_pressed_no_signal(true)

	# ── Nombre d'ennemis ─────────────────────────────────────────────────────
	var enemy_lbl := Label.new()
	enemy_lbl.text = "Nombre d'ennemis :"
	enemy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(enemy_lbl)

	var enemy_hbox := HBoxContainer.new()
	enemy_hbox.add_theme_constant_override("separation", 12)
	enemy_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(enemy_hbox)

	var enemy_group := ButtonGroup.new()
	var first_enemy_btn: Button = null

	for n in [1, 2]:
		var btn := Button.new()
		btn.text = "%d ennemi%s" % [n, "s" if n > 1 else ""]
		btn.custom_minimum_size = Vector2(130, 44)
		btn.toggle_mode = true
		btn.button_group = enemy_group
		btn.toggled.connect(_on_enemy_count_toggled.bind(n))
		enemy_hbox.add_child(btn)
		if n == _num_enemies:
			first_enemy_btn = btn

	if first_enemy_btn:
		first_enemy_btn.set_pressed_no_signal(true)

	# ── Difficulté ───────────────────────────────────────────────────────────
	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 12)
	diff_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(diff_hbox)

	var diff_lbl := Label.new()
	diff_lbl.text = "Difficulté :"
	diff_hbox.add_child(diff_lbl)

	var diff_slider := HSlider.new()
	diff_slider.min_value = 1
	diff_slider.max_value = 10
	diff_slider.step = 1
	diff_slider.value = _difficulty
	diff_slider.custom_minimum_size = Vector2(220, 30)
	diff_hbox.add_child(diff_slider)

	var diff_val := Label.new()
	diff_val.text = str(_difficulty)
	diff_val.custom_minimum_size = Vector2(24, 0)
	diff_hbox.add_child(diff_val)

	diff_slider.value_changed.connect(func(val: float):
		_difficulty = int(val)
		diff_val.text = str(_difficulty)
	)

	# ── Boutons ──────────────────────────────────────────────────────────────
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 20)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	var back_btn := Button.new()
	back_btn.text = "Retour"
	back_btn.custom_minimum_size = Vector2(130, 48)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	btn_hbox.add_child(back_btn)

	var play_btn := Button.new()
	play_btn.text = "Jouer !"
	play_btn.custom_minimum_size = Vector2(130, 48)
	play_btn.pressed.connect(_on_play)
	btn_hbox.add_child(play_btn)


func _on_race_toggled(pressed: bool, race: String) -> void:
	if pressed:
		_selected_race = race


func _on_enemy_count_toggled(pressed: bool, count: int) -> void:
	if pressed:
		_num_enemies = count


func _on_play() -> void:
	GameConfig.num_players = 1
	GameConfig.num_enemies = _num_enemies
	GameConfig.player_race = _selected_race
	GameConfig.difficulty = _difficulty
	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")
