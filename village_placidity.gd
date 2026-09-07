extends Node3D

const TITLE_CARD_DURATION := 3.0

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(28, 28)
	panel.custom_minimum_size = Vector2(280, 54)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.1, 0.1, 0.88)
	panel_style.border_color = Color(0.65, 0.86, 0.78, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)

	var label := Label.new()
	label.text = "The Village of Placidity"
	label.add_theme_color_override("font_color", Color(0.9, 0.97, 0.91, 1.0))
	label.add_theme_font_size_override("font_size", 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)

	var fade := create_tween()
	fade.tween_interval(TITLE_CARD_DURATION)
	fade.tween_property(panel, "modulate:a", 0.0, 0.5)
	await fade.finished
	layer.queue_free()
