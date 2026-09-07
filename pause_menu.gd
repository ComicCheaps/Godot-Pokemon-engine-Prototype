extends CanvasLayer
class_name PauseMenu

var player: Node = null
var panel: PanelContainer
var content: VBoxContainer
var status_label: Label
var menu_buttons: Array[Button] = []
var selected_bag_category := "Capsules"
const RESONANCE_CAPSULE_TEXTURE = preload("res://assets/Capsules/Resonance Capsule.png")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	_build_menu()
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_accept") or event.is_echo():
		return
	var dialogue_manager := get_tree().get_first_node_in_group("dialogue_manager")
	var battle_manager := get_tree().get_first_node_in_group("battle_manager")
	var edit_mode := get_node_or_null("/root/EditMode")
	if dialogue_manager != null and dialogue_manager.has_method("is_dialogue_open") and dialogue_manager.is_dialogue_open():
		return
	if battle_manager != null and battle_manager.get("is_active"):
		return
	if edit_mode != null and bool(edit_mode.get("active")):
		return
	_toggle_menu()
	get_viewport().set_input_as_handled()

func _toggle_menu() -> void:
	panel.visible = not panel.visible
	get_tree().paused = panel.visible
	if panel.visible:
		_show_main()

func _build_menu() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(320, 70)
	panel.size = Vector2(640, 580)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation.add_theme_constant_override("separation", 8)
	root.add_child(navigation)
	_add_menu_button(navigation, "Party", _show_party)
	_add_menu_button(navigation, "Bag", _show_bag)
	_add_menu_button(navigation, "Save", _show_save)
	_add_menu_button(navigation, "Character", _show_character)
	_add_menu_button(navigation, "Options", _show_options)
	_add_menu_button(navigation, "Close", _close_menu)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

func _add_menu_button(parent: Container, label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(105, 42)
	button.pressed.connect(callback)
	parent.add_child(button)
	menu_buttons.append(button)

func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()

func _show_main() -> void:
	_clear_content()
	status_label.text = "Press Enter to close the menu."
	var hint := Label.new()
	hint.text = "Choose an option above."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)

func _show_party() -> void:
	_clear_content()
	status_label.text = ""
	var heading := Label.new()
	heading.text = "Party"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var party = _get_party()
	if party == null or party.members.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Your party is empty."
		content.add_child(empty_label)
		return
	for index in party.members.size():
		var monster: Monster = party.members[index]
		var button := Button.new()
		button.text = "%d. %s Lv. %d%s" % [index + 1, monster.get_species_name(), monster.level, "  (Active)" if index == party.active_index else ""]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_monster_summary.bind(index))
		content.add_child(button)
	var release := Button.new()
	release.text = "Release Active Pokemon"
	release.pressed.connect(_release_active_monster)
	content.add_child(release)

func _show_monster_summary(index: int) -> void:
	var party = _get_party()
	if party == null or index < 0 or index >= party.members.size():
		_show_party()
		return

	var monster: Monster = party.members[index]
	_clear_content()
	status_label.text = ""
	var heading := Label.new()
	heading.text = monster.get_species_name()
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)

	var types := monster.get_types()
	var details := Label.new()
	details.text = "Level %d    Type: %s\nHP: %d / %d    Status: %s\nNature: %s" % [
		monster.level,
		" / ".join(types) if not types.is_empty() else "Unknown",
		monster.current_hp if monster.current_hp >= 0 else monster.get_max_hp(),
		monster.get_max_hp(),
		monster.status_condition if not monster.status_condition.is_empty() else "Healthy",
		monster.nature
	]
	content.add_child(details)

	var stats := Label.new()
	stats.text = "Stats\nHP %d   ATK %d   DEF %d\nSP. ATK %d   SP. DEF %d   SPD %d" % [
		monster.get_calculated_stat("hp"),
		monster.get_calculated_stat("attack"),
		monster.get_calculated_stat("defense"),
		monster.get_calculated_stat("special_attack"),
		monster.get_calculated_stat("special_defense"),
		monster.get_calculated_stat("speed")
	]
	content.add_child(stats)

	var moves := Label.new()
	var move_names: PackedStringArray = []
	for move in monster.get_moves_for_level():
		if move != null:
			move_names.append("%s  %d/%d PP" % [move.move_name, monster.get_move_pp(move), move.maximum_pp])
	moves.text = "Moves\n%s" % ("\n".join(move_names) if not move_names.is_empty() else "No moves learned.")
	content.add_child(moves)

	var experience := Label.new()
	experience.text = "Experience: %d / %d" % [monster.experience, monster.get_experience_required()]
	content.add_child(experience)

	var active_button := Button.new()
	active_button.text = "Set as Active Pokemon"
	active_button.disabled = index == party.active_index
	active_button.pressed.connect(_set_active_monster.bind(index))
	content.add_child(active_button)
	var back_button := Button.new()
	back_button.text = "Back to Party"
	back_button.pressed.connect(_show_party)
	content.add_child(back_button)

func _show_bag() -> void:
	_clear_content()
	status_label.text = ""
	var heading := Label.new()
	heading.text = "Bag"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var bag = _get_bag()
	var categories := ["Capsules", "Medicine", "Battle Items", "Key Items", "Other"]
	var category_tabs := HBoxContainer.new()
	category_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	category_tabs.add_theme_constant_override("separation", 6)
	content.add_child(category_tabs)
	for category in categories:
		var category_button := Button.new()
		category_button.text = category
		category_button.toggle_mode = true
		category_button.button_pressed = category == selected_bag_category
		category_button.pressed.connect(_select_bag_category.bind(category))
		category_tabs.add_child(category_button)
	var item_ids: Array[String] = bag.get_item_ids_in_category(selected_bag_category) if bag != null else []
	if item_ids.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No items in this section."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty_label)
		return
	for item_id in item_ids:
		var item_button := Button.new()
		item_button.text = "%s  x%d" % [bag.get_item_name(item_id), bag.get_quantity(item_id)]
		if item_id == "resonance_capsule":
			item_button.icon = RESONANCE_CAPSULE_TEXTURE
			item_button.expand_icon = true
			item_button.add_theme_constant_override("icon_max_width", 32)
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_button.pressed.connect(_use_bag_item.bind(item_id))
		content.add_child(item_button)

func _select_bag_category(category: String) -> void:
	selected_bag_category = category
	_show_bag()

func _use_bag_item(item_id: String) -> void:
	var bag = _get_bag()
	if bag == null:
		return
	if item_id == "potion":
		var party = _get_party()
		var monster: Monster = party.get_active_monster() if party != null else null
		if monster == null:
			status_label.text = "You have no active Pokemon."
			return
		monster.ensure_full_health_if_uninitialized()
		var healed := mini(20, monster.get_max_hp() - monster.current_hp)
		if healed <= 0:
			status_label.text = "%s is already at full health." % monster.get_species_name()
			return
		if bag.remove_item(item_id):
			monster.current_hp += healed
			status_label.text = "%s recovered %d HP." % [monster.get_species_name(), healed]
			_show_bag()
	else:
		status_label.text = "%s can only be used in battle." % bag.get_item_name(item_id)

func _set_active_monster(index: int) -> void:
	var party = _get_party()
	if party != null:
		party.set_active_index(index)
		_show_party()

func _release_active_monster() -> void:
	var party = _get_party()
	if party != null and party.members.size() > 1:
		party.release_monster(party.active_index)
		_show_party()
	else:
		status_label.text = "Keep at least one Pokemon in your party."

func _show_character() -> void:
	_clear_content()
	var heading := Label.new()
	heading.text = "Character"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var details := Label.new()
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		details.text = "Character data unavailable."
	else:
		details.text = "Position: %s\nGrid size: %.2f\nMove duration: %.2f s\nSprint duration: %.2f s" % [player.global_position, player.grid_size, player.move_duration, player.sprint_duration]
	content.add_child(details)

func _show_options() -> void:
	_clear_content()
	var heading := Label.new()
	heading.text = "Options"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var engine_mode := get_node_or_null("/root/EngineMode")
	if engine_mode != null:
		var project_mode_button := Button.new()
		project_mode_button.text = "Exit Project Mode" if engine_mode.is_project_mode() else "Enter Project Mode"
		project_mode_button.pressed.connect(_toggle_project_mode)
		content.add_child(project_mode_button)
	var arena = get_tree().get_first_node_in_group("battle_arena")
	if arena != null and arena.has_method("configure_hybrid_presentation"):
		var hybrid_toggle := CheckButton.new()
		hybrid_toggle.text = "Hybrid Battle Presentation"
		hybrid_toggle.button_pressed = bool(arena.get("hybrid_presentation_enabled"))
		hybrid_toggle.toggled.connect(func(enabled: bool) -> void:
			arena.configure_hybrid_presentation(enabled)
		)
		content.add_child(hybrid_toggle)
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_add_slider("Move duration", player.move_duration, 0.05, 0.5, func(value: float) -> void: player.move_duration = value)
	_add_slider("Sprint duration", player.sprint_duration, 0.03, 0.3, func(value: float) -> void: player.sprint_duration = value)

func _show_save() -> void:
	_clear_content()
	status_label.text = ""
	var heading := Label.new()
	heading.text = "Save Data"
	heading.add_theme_font_size_override("font_size", 20)
	content.add_child(heading)
	var save_system := get_node_or_null("/root/SaveSystem")
	var save_exists: bool = save_system != null and save_system.has_save_file()
	var details := Label.new()
	details.text = "Save file found." if save_exists else "No save file found."
	content.add_child(details)
	var save_button := Button.new()
	save_button.text = "Save Game"
	save_button.pressed.connect(_save_game)
	content.add_child(save_button)
	var delete_button := Button.new()
	delete_button.text = "Delete Save File"
	delete_button.disabled = not save_exists
	delete_button.pressed.connect(_confirm_delete_save)
	content.add_child(delete_button)

func _confirm_delete_save() -> void:
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Delete Save File"
	confirmation.dialog_text = "Delete the current save file? This cannot be undone."
	confirmation.ok_button_text = "Delete"
	confirmation.confirmed.connect(_delete_save)
	add_child(confirmation)
	confirmation.popup_centered()

func _delete_save() -> void:
	var save_system := get_node_or_null("/root/SaveSystem")
	var deleted: bool = save_system != null and save_system.delete_save()
	_show_save()
	status_label.text = "Save deleted." if deleted else "No save file to delete."

func _add_slider(label_text: String, initial_value: float, minimum: float, maximum: float, changed: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.2f s" % [label_text, initial_value]
	content.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial_value
	slider.value_changed.connect(func(value: float) -> void:
		label.text = "%s: %.2f s" % [label_text, value]
		changed.call(value)
	)
	content.add_child(slider)

func _save_game() -> void:
	var save_system := get_node_or_null("/root/SaveSystem")
	status_label.text = "Game saved." if save_system != null and save_system.save_game() else "Save failed."

func _toggle_project_mode() -> void:
	var engine_mode := get_node_or_null("/root/EngineMode")
	if engine_mode == null:
		return
	var entering_project_mode: bool = not engine_mode.is_project_mode()
	engine_mode.set_project_mode(entering_project_mode)
	_close_menu()
	if entering_project_mode:
		var edit_mode := get_node_or_null("/root/EditMode")
		if edit_mode != null:
			edit_mode._set_active(true)

func _get_party():
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("Party")

func _get_bag():
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	return player.get_node_or_null("Bag") if player != null else null

func _close_menu() -> void:
	panel.visible = false
	_get_tree().paused = false

func _get_tree() -> SceneTree:
	return get_tree()
