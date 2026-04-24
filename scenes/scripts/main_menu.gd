extends Control

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
	vbox.add_theme_constant_override("separation", 24)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Battle Sheep"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	var solo_btn := Button.new()
	solo_btn.text = "Solo"
	solo_btn.custom_minimum_size = Vector2(240, 55)
	solo_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/solo_setup.tscn"))
	vbox.add_child(solo_btn)

	var multi_btn := Button.new()
	multi_btn.text = "Multijoueur"
	multi_btn.custom_minimum_size = Vector2(240, 55)
	multi_btn.pressed.connect(_on_multi)
	vbox.add_child(multi_btn)


func _on_multi() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Multijoueur\nÀ venir..."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 32)
	vbox.add_child(lbl)

	var close_btn := Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(130, 44)
	close_btn.pressed.connect(func(): canvas.queue_free())
	vbox.add_child(close_btn)
