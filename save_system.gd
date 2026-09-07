extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var loading: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var pm := get_node_or_null("/root/ProjectManager")
	if pm != null and str(pm.get("active_project_id")).is_empty():
		return
	await load_game()

func get_save_path() -> String:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm != null and pm.has_method("get_active_save_path"):
		var path: String = pm.get_active_save_path()
		if not path.is_empty():
			return path
	return SAVE_PATH

func save_game() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var party = player.get_node_or_null("Party")
	var bag = player.get_node_or_null("Bag")
	if party == null:
		return false

	var save_data := {
		"version": SAVE_VERSION,
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "",
		"player": {
			"position": _vector_to_array(player.global_position),
			"grid_size": player.get("grid_size"),
			"move_duration": player.get("move_duration"),
			"sprint_duration": player.get("sprint_duration")
		},
		"items": bag.items.duplicate(true) if bag != null else {},
		"party": {
			"maximum_size": party.maximum_size,
			"active_index": party.active_index,
			"members": _serialize_party(party.members)
		}
	}

	var file := FileAccess.open(get_save_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(save_data))
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(get_save_path())

func delete_save() -> bool:
	if not has_save_file():
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(get_save_path())) == OK

func load_game() -> bool:
	if loading or not FileAccess.file_exists(get_save_path()):
		return false
	var file := FileAccess.open(get_save_path(), FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false

	loading = true
	var save_data: Dictionary = parsed
	_migrate_legacy_save(save_data)
	var saved_scene := str(save_data.get("scene", ""))
	if not saved_scene.is_empty() and ResourceLoader.exists(saved_scene) and _current_scene_path() != saved_scene:
		var result := get_tree().change_scene_to_file(saved_scene)
		if result != OK:
			loading = false
			return false
		await get_tree().scene_changed
		await get_tree().process_frame

	var restored := _restore_state(save_data)
	loading = false
	return restored

func _migrate_legacy_save(save_data: Dictionary) -> void:
	if save_data.has("player") or not save_data.has("position"):
		return
	save_data["player"] = {"position": save_data.get("position", [])}
	save_data["party"] = {
		"active_index": save_data.get("active_index", 0),
		"members": save_data.get("party", [])
	}

func _serialize_party(members: Array) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for monster: Monster in members:
		if monster == null:
			continue
		serialized.append({
			"profile": monster.profile.resource_path if monster.profile != null else "",
			"level": monster.level,
			"experience": monster.experience,
			"current_hp": monster.current_hp,
			"status": monster.status_condition,
			"status_turns": monster.status_turns,
			"individual_values": monster.individual_values.duplicate(true),
			"effort_values": monster.effort_values.duplicate(true),
			"nature": monster.nature,
			"move_pp": monster.move_pp.duplicate(true)
		})
	return serialized

func _restore_state(save_data: Dictionary) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var player_data: Dictionary = save_data.get("player", {})
	var position_data: Array = player_data.get("position", [])
	if position_data.size() >= 3:
		player.global_position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		if player.has_method("snap_to_grid"):
			player.snap_to_grid()
	_set_player_property(player, "grid_size", player_data)
	_set_player_property(player, "move_duration", player_data)
	_set_player_property(player, "sprint_duration", player_data)

	var bag = player.get_node_or_null("Bag")
	if bag != null:
		var saved_items: Dictionary = save_data.get("items", {})
		bag.items = saved_items.duplicate(true)
		if bag.has_signal("inventory_changed"):
			bag.inventory_changed.emit(bag.items)

	var party = player.get_node_or_null("Party")
	var party_data: Dictionary = save_data.get("party", {})
	if party == null:
		return false
	_restore_party(party, party_data)
	return true

func _restore_party(party: Node, party_data: Dictionary) -> void:
	for member in party.members:
		if is_instance_valid(member):
			member.queue_free()
	party.members.clear()
	party.maximum_size = clampi(int(party_data.get("maximum_size", party.maximum_size)), 1, 6)
	var saved_members: Array = party_data.get("members", [])
	for member_data: Dictionary in saved_members:
		var monster := Monster.new()
		var profile_path := str(member_data.get("profile", ""))
		if not profile_path.is_empty():
			monster.profile = load(profile_path) as MonsterProfile
		monster.level = clampi(int(member_data.get("level", 1)), 1, 100)
		monster.experience = maxi(0, int(member_data.get("experience", 0)))
		monster.current_hp = int(member_data.get("current_hp", -1))
		monster.status_condition = str(member_data.get("status", ""))
		monster.status_turns = maxi(0, int(member_data.get("status_turns", 0)))
		monster.individual_values = member_data.get("individual_values", monster.individual_values).duplicate(true)
		monster.effort_values = member_data.get("effort_values", monster.effort_values).duplicate(true)
		monster.nature = str(member_data.get("nature", monster.nature))
		monster.move_pp = member_data.get("move_pp", {}).duplicate(true)
		party.add_monster(monster)
	party.active_index = clampi(int(party_data.get("active_index", 0)), 0, maxi(party.members.size() - 1, 0))

func _set_player_property(player: Node, property_name: String, source: Dictionary) -> void:
	if source.has(property_name) and player.get(property_name) != null:
		player.set(property_name, float(source[property_name]))

func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _current_scene_path() -> String:
	return get_tree().current_scene.scene_file_path if get_tree().current_scene != null else ""
