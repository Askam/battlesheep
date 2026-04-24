extends Node2D

const SMALL_BUILDINGS := ["canon", "rage", "totem"]
const LARGE_BUILDINGS := ["bunker", "igloo", "love", "totem", "tower", "water"]
const BUILDING_NAMES := {
	"canon": "Canon", "rage": "Rage", "totem": "Totem",
	"bunker": "Bunker", "igloo": "Igloo", "love": "Love Shack",
	"tower": "Tour de guet", "warp": "Portail", "water": "Marécage",
}
const BUILDING_DESCS := {
	"canon": "Élimine 1 ennemi en déplacement par seconde dans un rayon autour de l'enclos.",
	"rage": "Les attaquants ont 20 % de chance de tuer 2 ennemis d'un coup.",
	"totem": "Multiplie les points gagnés (à venir).",
	"bunker": "Renvoie les attaquants à leur source dans 40 % des cas.",
	"igloo": "Les swarms partant de cet enclos se déplacent 2× plus vite.",
	"love": "La population de cet enclos croît 25 % plus vite.",
	"tower": "Révèle les effectifs ennemis sur la carte.",
	"warp": "Effet à venir.",
	"water": "Ralentit de moitié les swarms ennemis qui traversent la zone.",
}

var selected_spot: StaticBody2D = null
var is_dragging := false
var current_hover: StaticBody2D = null
var drag_line: Line2D = null

var _game_over := false
var _game_check_timer := 0.0
var _game_start_timer := 2.0  # grace period before checking end condition

func _ready():
	var ai_races: Array = []
	for race in $SpotContainer.active_races:
		if race != GameConfig.player_race:
			ai_races.append(race)

	var ai_controller = null
	if not ai_races.is_empty():
		ai_controller = preload("res://scenes/scripts/ai_controller.gd").new()
		add_child(ai_controller)
		ai_controller.setup($SpotContainer, $SwarmLauncher, $SpotContainer.difficulty, ai_races)
		$SwarmLauncher.swarm_launched.connect(ai_controller.on_swarm_launched)

	for spot in $SpotContainer.spots:
		if ai_controller != null:
			spot.owner_changed.connect(ai_controller.on_spot_owner_changed)
		spot.box_opened.connect(on_box_opened)

func _process(delta: float):
	if is_dragging and selected_spot != null:
		var mouse_pos = get_viewport().get_mouse_position()
		drag_line.set_point_position(1, mouse_pos)

	if not _game_over and GameConfig.num_players == 1:
		if _game_start_timer > 0.0:
			_game_start_timer -= delta
		else:
			_game_check_timer += delta
			if _game_check_timer >= 0.5:
				_game_check_timer = 0.0
				_check_game_over()


func _check_game_over() -> void:
	var player := GameConfig.player_race
	var player_spots := 0
	var enemy_spots := 0
	var player_units := 0
	var enemy_units := 0

	for spot in $SpotContainer.spots:
		if not is_instance_valid(spot):
			continue
		if spot.spotOwner == player:
			player_spots += 1
		elif spot.spotOwner != "none":
			enemy_spots += 1

	for unit in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(unit) or unit._dying:
			continue
		if unit.race == player:
			player_units += 1
		else:
			enemy_units += 1

	if enemy_spots == 0 and enemy_units == 0:
		_show_end_screen(true)
	elif player_spots == 0 and player_units == 0:
		_show_end_screen(false)


func _show_end_screen(victory: bool) -> void:
	_game_over = true

	# Nettoyer le drag en cours si besoin
	if is_dragging:
		if selected_spot:
			selected_spot.set_selected(false)
		if drag_line and is_instance_valid(drag_line):
			drag_line.queue_free()
			drag_line = null
		for s in $SpotContainer.spots:
			s.set_target(false)
		is_dragging = false
		selected_spot = null

	var canvas := CanvasLayer.new()
	canvas.layer = 25
	add_child(canvas)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	panel.add_child(vbox)

	var result_lbl := Label.new()
	result_lbl.text = "VICTOIRE !" if victory else "DÉFAITE..."
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 52)
	if victory:
		result_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	else:
		result_lbl.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	vbox.add_child(result_lbl)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var replay_btn := Button.new()
	replay_btn.text = "Rejouer"
	replay_btn.custom_minimum_size = Vector2(150, 52)
	replay_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")
	)
	hbox.add_child(replay_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.custom_minimum_size = Vector2(150, 52)
	menu_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/solo_setup.tscn")
	)
	hbox.add_child(menu_btn)


func create_drag_line():
	drag_line = Line2D.new()
	drag_line.default_color = Color.WHITE
	drag_line.width = 2
	drag_line.add_point(selected_spot.global_position)
	drag_line.add_point(selected_spot.global_position)
	add_child(drag_line)

func update_hover_target(mouse_pos: Vector2):
	current_hover = null
	for spot in $SpotContainer.spots:
		if spot.get_global_rect().has_point(mouse_pos) and spot != selected_spot:
			current_hover = spot
			spot.set_target(true)
		else:
			spot.set_target(false)


func on_spot_click_start(spot) -> void:
	if _game_over:
		return
	if spot.spotOwner == GameConfig.player_race:
		selected_spot = spot
		selected_spot.set_selected(true)
		is_dragging = true
		create_drag_line()

func on_spot_click_end(spot) -> void:
	if _game_over:
		return
	if is_dragging and selected_spot != null and spot != selected_spot:
		$SwarmLauncher.launch_swarm(selected_spot, spot)
		print("Swarm from %s to %s" % [selected_spot.name, spot.name])

	if selected_spot:
		selected_spot.set_selected(false)

	if drag_line and is_instance_valid(drag_line):
		drag_line.queue_free()
		drag_line = null

	for s in $SpotContainer.spots:
		s.set_target(false)

	is_dragging = false
	selected_spot = null


func on_box_opened(spot, owner: String) -> void:
	var pool: Array = SMALL_BUILDINGS if spot.size <= 1 else LARGE_BUILDINGS
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	var choices := shuffled.slice(0, 2)
	if owner == GameConfig.player_race:
		_show_box_choice(spot, choices)
	else:
		spot.replace_building(choices[randi() % 2])


func _show_box_choice(spot, choices: Array) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 20
	add_child(canvas)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Choisissez un bâtiment"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	for b in choices:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(180, 0)
		hbox.add_child(card)

		var name_lbl := Label.new()
		name_lbl.text = BUILDING_NAMES.get(b, b)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = BUILDING_DESCS.get(b, "")
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(180, 60)
		card.add_child(desc_lbl)

		var btn := Button.new()
		btn.text = "Choisir"
		var chosen: String = b
		btn.pressed.connect(func():
			spot.replace_building(chosen)
			canvas.queue_free()
		)
		card.add_child(btn)
