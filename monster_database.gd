extends CanvasLayer
class_name MonsterDatabase

const MONSTERS_FOLDER := "res://monsters"

@onready var panel: PanelContainer = $Panel
@onready var species_list: OptionButton = $Panel/Margin/VBox/SpeciesList
@onready var id_input: LineEdit = $Panel/Margin/VBox/Identity/Id
@onready var name_input: LineEdit = $Panel/Margin/VBox/Identity/Name
@onready var types_input: LineEdit = $Panel/Margin/VBox/Identity/Types
@onready var stats_input: LineEdit = $Panel/Margin/VBox/Stats
@onready var moves_input: TextEdit = $Panel/Margin/VBox/Moves
@onready var abilities_input: TextEdit = $Panel/Margin/VBox/Abilities
@onready var evolutions_input: TextEdit = $Panel/Margin/VBox/Evolutions
@onready var status_label: Label = $Panel/Margin/VBox/Status

var profiles: Array[MonsterProfile] = []
var profile_paths: Array[String] = []
var selected_profile: MonsterProfile = null
var selected_path: String = ""
var creating_new_profile: bool = false
var delete_confirmation_pending: bool = false

func _ready() -> void:
	add_to_group("monster_database")
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	_reload_profiles()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3 and not event.echo:
		panel.visible = not panel.visible
		if panel.visible:
			_reload_profiles()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("ui_cancel"):
		panel.visible = false
		get_viewport().set_input_as_handled()

func _reload_profiles() -> void:
	profiles.clear()
	profile_paths.clear()
	var directory := DirAccess.open(MONSTERS_FOLDER)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				var path := MONSTERS_FOLDER.path_join(file_name)
				var resource := load(path)
				if resource is MonsterProfile:
					profiles.append(resource)
					profile_paths.append(path)
			file_name = directory.get_next()
		directory.list_dir_end()

	species_list.clear()
	for profile in profiles:
		species_list.add_item("%s - %s" % [profile.species_id, profile.species_name])
	if not profiles.is_empty():
		species_list.select(0)
		_select_profile(0)
	else:
		_clear_form()
		_set_status("No profiles found. Create one with New Pokemon.")

func _on_species_selected(index: int) -> void:
	_select_profile(index)

func _select_profile(index: int) -> void:
	if index < 0 or index >= profiles.size():
		return
	selected_profile = profiles[index]
	selected_path = profile_paths[index]
	delete_confirmation_pending = false
	id_input.text = selected_profile.species_id
	name_input.text = selected_profile.species_name
	types_input.text = ", ".join(selected_profile.type_ids)
	stats_input.text = _stats_to_text(selected_profile.base_stats)
	moves_input.text = _moves_to_text(selected_profile.learnable_moves)
	abilities_input.text = _abilities_to_text(selected_profile.abilities)
	evolutions_input.text = _evolutions_to_text(selected_profile.evolutions)
	_set_status("Editing %s" % selected_path)

func _on_save_pressed() -> void:
	if selected_profile == null:
		_set_status("Create or select a Pokemon first.")
		return
	if not _apply_form_to_profile():
		return
	if creating_new_profile:
		selected_path = _get_unique_profile_path(selected_profile.species_id)
	var save_flags := ResourceSaver.FLAG_CHANGE_PATH if creating_new_profile else 0
	var error := ResourceSaver.save(selected_profile, selected_path, save_flags)
	if error != OK:
		_set_status("Save failed: %s" % error_string(error))
		return
	creating_new_profile = false
	_set_status("Saved %s" % selected_path)
	_reload_profiles()

func _on_delete_pressed() -> void:
	if selected_profile == null or selected_path.is_empty() or creating_new_profile:
		_set_status("Select a saved Pokemon before deleting.")
		return
	if not delete_confirmation_pending:
		delete_confirmation_pending = true
		_set_status("Press Delete Pokemon again to remove %s." % selected_profile.species_name)
		return

	var absolute_path := ProjectSettings.globalize_path(selected_path)
	var error := DirAccess.remove_absolute(absolute_path)
	if error != OK:
		_set_status("Delete failed: %s" % error_string(error))
		delete_confirmation_pending = false
		return

	delete_confirmation_pending = false
	selected_profile = null
	selected_path = ""
	creating_new_profile = false
	_set_status("Pokemon deleted.")
	_reload_profiles()

func _on_new_pressed() -> void:
	var profile := MonsterProfile.new()
	profile.species_id = "new_monster"
	profile.species_name = "New Pokemon"
	selected_profile = profile
	selected_path = ""
	creating_new_profile = true
	delete_confirmation_pending = false
	_clear_form()
	id_input.text = profile.species_id
	name_input.text = profile.species_name
	types_input.text = "normal"
	_set_status("Fill in the fields, then press Save Pokemon.")

func _on_close_pressed() -> void:
	panel.visible = false

func _apply_form_to_profile() -> bool:
	var species_id := id_input.text.strip_edges().to_lower()
	var species_name := name_input.text.strip_edges()
	if species_id.is_empty() or species_name.is_empty():
		_set_status("Species ID and name are required.")
		return false
	selected_profile.species_id = species_id
	selected_profile.species_name = species_name
	selected_profile.type_ids = _parse_types(types_input.text)
	selected_profile.base_stats = _parse_stats(stats_input.text)
	selected_profile.learnable_moves = _parse_moves(moves_input.text)
	selected_profile.abilities = _parse_abilities(abilities_input.text)
	selected_profile.evolutions = _parse_evolutions(evolutions_input.text)
	return true

func _safe_file_name(value: String) -> String:
	var safe_name := value.to_lower().strip_edges()
	var sanitized := ""
	for character in safe_name:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			sanitized += character
	return sanitized if not sanitized.is_empty() else "new_monster"

func _get_unique_profile_path(species_id: String) -> String:
	var base_name := _safe_file_name(species_id)
	var path := MONSTERS_FOLDER.path_join(base_name + ".tres")
	var suffix := 2
	while ResourceLoader.exists(path):
		path = MONSTERS_FOLDER.path_join("%s_%d.tres" % [base_name, suffix])
		suffix += 1
	return path

func _parse_types(value: String) -> Array[String]:
	var result: Array[String] = []
	for entry in value.split(","):
		var type_id := entry.strip_edges().to_lower()
		if not type_id.is_empty() and result.size() < 2:
			result.append(type_id)
	return result if not result.is_empty() else ["normal"]

func _parse_stats(value: String) -> Dictionary:
	var stats := {"hp": 1, "attack": 1, "defense": 1, "special_attack": 1, "special_defense": 1, "speed": 1}
	for entry in value.split(","):
		var parts := entry.split(":")
		if parts.size() == 2 and stats.has(parts[0].strip_edges()):
			stats[parts[0].strip_edges()] = maxi(0, parts[1].strip_edges().to_int())
	return stats

func _parse_moves(value: String) -> Array[MonsterMove]:
	var result: Array[MonsterMove] = []
	for line in value.split("\n"):
		var parts := line.strip_edges().split("|")
		if parts.size() >= 3 and not parts[0].is_empty():
			var move := MonsterMove.new()
			move.move_id = parts[0].strip_edges()
			move.move_name = parts[1].strip_edges()
			move.learn_level = clampi(parts[2].strip_edges().to_int(), 1, 100)
			result.append(move)
	return result

func _parse_abilities(value: String) -> Array[MonsterAbility]:
	var result: Array[MonsterAbility] = []
	for line in value.split("\n"):
		var parts := line.strip_edges().split("|")
		if parts.size() >= 2 and not parts[0].is_empty():
			var ability := MonsterAbility.new()
			ability.ability_id = parts[0].strip_edges()
			ability.ability_name = parts[1].strip_edges()
			ability.is_hidden = parts.size() >= 3 and parts[2].strip_edges().to_lower() == "true"
			ability.description = parts[3].strip_edges() if parts.size() >= 4 else ""
			result.append(ability)
	return result

func _parse_evolutions(value: String) -> Array[MonsterEvolution]:
	var result: Array[MonsterEvolution] = []
	for line in value.split("\n"):
		var parts := line.strip_edges().split("|")
		if parts.size() >= 3 and not parts[0].is_empty():
			var evolution := MonsterEvolution.new()
			evolution.target_species_id = parts[0].strip_edges()
			evolution.target_species_name = parts[1].strip_edges()
			evolution.method = parts[2].strip_edges()
			evolution.minimum_level = parts[3].strip_edges().to_int() if parts.size() >= 4 else 1
			result.append(evolution)
	return result

func _stats_to_text(stats: Dictionary) -> String:
	var values: PackedStringArray = []
	for stat_name in ["hp", "attack", "defense", "special_attack", "special_defense", "speed"]:
		values.append("%s: %d" % [stat_name, int(stats.get(stat_name, 0))])
	return ", ".join(values)

func _moves_to_text(moves: Array[MonsterMove]) -> String:
	var values: PackedStringArray = []
	for move in moves:
		if move != null:
			values.append("%s | %s | %d" % [move.move_id, move.move_name, move.learn_level])
	return "\n".join(values)

func _abilities_to_text(abilities: Array[MonsterAbility]) -> String:
	var values: PackedStringArray = []
	for ability in abilities:
		if ability != null:
			values.append("%s | %s | %s | %s" % [ability.ability_id, ability.ability_name, str(ability.is_hidden), ability.description])
	return "\n".join(values)

func _evolutions_to_text(evolutions: Array[MonsterEvolution]) -> String:
	var values: PackedStringArray = []
	for evolution in evolutions:
		if evolution != null:
			values.append("%s | %s | %s | %d" % [evolution.target_species_id, evolution.target_species_name, evolution.method, evolution.minimum_level])
	return "\n".join(values)

func _clear_form() -> void:
	id_input.clear()
	name_input.clear()
	types_input.text = "normal"
	stats_input.text = "hp: 1, attack: 1, defense: 1, special_attack: 1, special_defense: 1, speed: 1"
	moves_input.clear()
	abilities_input.clear()
	evolutions_input.clear()

func _set_status(message: String) -> void:
	status_label.text = message
