extends CanvasLayer
class_name CheatMenu

const MonsterScene = preload("res://monster.tscn")
const ItemBagScript = preload("res://item_bag.gd")
const MONSTERS_FOLDER := "res://monsters"

@onready var panel: PanelContainer = $Panel
@onready var species_id_input: LineEdit = $Panel/Margin/VBox/SpeciesId
@onready var species_options: OptionButton = $Panel/Margin/VBox/SpeciesOptions
@onready var level_input: SpinBox = $Panel/Margin/VBox/Level
@onready var item_options: OptionButton = $Panel/Margin/VBox/ItemOptions
@onready var item_quantity_input: SpinBox = $Panel/Margin/VBox/ItemQuantity
@onready var new_item_id_input: LineEdit = $Panel/Margin/VBox/NewItemId
@onready var new_item_name_input: LineEdit = $Panel/Margin/VBox/NewItemName
@onready var new_item_category_options: OptionButton = $Panel/Margin/VBox/NewItemCategory
@onready var status_label: Label = $Panel/Margin/VBox/Status

@export var available_profiles: Array[MonsterProfile] = []

var player: Node = null

func _ready() -> void:
	add_to_group("cheat_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	for category in ["Capsules", "Medicine", "Battle Items", "Key Items", "Other"]:
		new_item_category_options.add_item(category)
	_load_profiles_from_folder()
	_refresh_profile_options()
	_refresh_item_options()
	player = get_tree().get_first_node_in_group("player")
	level_input.value = 5
	item_quantity_input.value = 1
	status_label.text = "Press F2 to open cheats."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2 and not event.echo:
		panel.visible = not panel.visible
		if panel.visible:
			_load_profiles_from_folder()
			_refresh_profile_options()
			_refresh_item_options()
			species_id_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif panel.visible and event.is_action_pressed("ui_cancel"):
		panel.visible = false
		get_viewport().set_input_as_handled()

func _on_add_pressed() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		_set_status("No player found.")
		return

	var party = player.get_node_or_null("Party")
	if party == null:
		_set_status("The player has no party.")
		return
	if party.is_full():
		_set_status("Party is full: maximum 6 Pokemon.")
		return

	var species_id := species_id_input.text.strip_edges()
	if species_id.is_empty() and species_options.selected >= 0:
		species_id = species_options.get_item_metadata(species_options.selected)
	if species_id.is_empty():
		_set_status("Choose a Pokemon from the list or enter its ID.")
		return

	var profile := _find_profile(species_id)
	if profile == null:
		_set_status("Unknown Pokemon. Add a profile to res://monsters/.")
		return

	var monster := MonsterScene.instantiate() as Monster
	if monster == null:
		_set_status("Could not load the monster scene.")
		return
	monster.profile = profile
	monster.level = clampi(int(level_input.value), 1, profile.max_level)
	monster.experience = profile.get_experience_for_level(monster.level)

	if party.add_monster(monster):
		_set_status("Summoned %s Lv. %d to the party." % [profile.species_name, monster.level])
		species_id_input.clear()
	else:
		monster.queue_free()
		_set_status("Could not summon Pokemon to the party.")

func _on_summon_item_pressed() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		_set_status("No player found.")
		return

	var bag = player.get_node_or_null("Bag")
	if bag == null:
		_set_status("The player has no bag.")
		return
	if item_options.selected < 0:
		_set_status("Choose an item to summon.")
		return

	var item_id: String = item_options.get_item_metadata(item_options.selected)
	var quantity := clampi(int(item_quantity_input.value), 1, 999)
	if bag.add_item(item_id, quantity):
		_set_status("Added %d %s%s to the bag." % [quantity, bag.get_item_name(item_id), "" if quantity == 1 else "s"])
	else:
		_set_status("Could not add that item.")

func _find_profile(species_id: String) -> MonsterProfile:
	for profile in available_profiles:
		if profile != null and (profile.species_id.to_lower() == species_id.to_lower() or profile.species_name.to_lower() == species_id.to_lower()):
			return profile
	return null

func _refresh_profile_options() -> void:
	species_options.clear()
	for profile in available_profiles:
		if profile != null:
			species_options.add_item("%s (%s)" % [profile.species_name, profile.species_id])
			species_options.set_item_metadata(species_options.item_count - 1, profile.species_id)
	if not available_profiles.is_empty():
		species_options.select(0)
		on_species_option_selected(0)

func on_species_option_selected(index: int) -> void:
	if index >= 0 and index < species_options.item_count:
		species_id_input.text = species_options.get_item_metadata(index)

func _refresh_item_options() -> void:
	item_options.clear()
	var definitions := _get_item_definitions()
	for item_id in definitions:
		item_options.add_item(str(definitions[item_id].get("name", item_id)))
		item_options.set_item_metadata(item_options.item_count - 1, item_id)
	if item_options.item_count > 0:
		item_options.select(0)

func _get_item_definitions() -> Dictionary:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	var bag = player.get_node_or_null("Bag") if player != null else null
	if bag != null:
		return bag.get_all_item_definitions()
	return ItemBagScript.DEFAULT_ITEM_DEFINITIONS

func _on_create_item_pressed() -> void:
	var bag = _get_bag()
	if bag == null:
		_set_status("No player found.")
		return
	var item_id := new_item_id_input.text.strip_edges().to_lower().replace(" ", "_")
	var display_name := new_item_name_input.text.strip_edges()
	if item_id.is_empty() or display_name.is_empty():
		_set_status("Enter both an item ID and display name.")
		return
	var category := new_item_category_options.get_item_text(new_item_category_options.selected)
	bag.define_item(item_id, display_name, category)
	new_item_id_input.clear()
	new_item_name_input.clear()
	_refresh_item_options()
	_set_status("Created item '%s'." % display_name)

func _get_bag():
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	return player.get_node_or_null("Bag") if player != null else null

func _load_profiles_from_folder() -> void:
	var folder := MONSTERS_FOLDER
	var pm := get_node_or_null("/root/ProjectManager")
	if pm != null:
		var project_dir: String = pm.get_active_content_dir("monsters")
		if not project_dir.is_empty():
			folder = project_dir
	var directory := DirAccess.open(folder)
	if directory == null:
		push_warning("Monster folder not found: %s" % folder)
		return

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource := load(folder.path_join(file_name))
			if resource is MonsterProfile and not available_profiles.has(resource):
				available_profiles.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()

func _set_status(message: String) -> void:
	status_label.text = message
