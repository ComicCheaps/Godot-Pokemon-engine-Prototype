extends Node

## Spawns a project's persisted world content (monster placements) whenever a scene loads.
const MonsterScene = preload("res://monster.tscn")
const NPCScene = preload("res://npc.tscn")
const WildAreaScene = preload("res://wild_encounter_block.tscn")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_load_world_content)
	_load_world_content()

func _load_world_content() -> void:
	_load_monster_placements()
	_load_npc_placements()
	_load_wild_areas()

func create_npc(profile: NPCProfile, world_position: Vector3) -> NPC:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty() or profile == null:
		return null
	var npc := NPCScene.instantiate() as NPC
	if npc == null:
		return null
	npc.profile = profile
	npc.global_position = world_position
	npc.add_to_group("editable_world_object")
	scene.add_child(npc)
	_save_npc_placements()
	return npc

func save_npcs() -> void:
	_save_npc_placements()

func _get_npc_placements_path() -> String:
	var pm := get_node_or_null("/root/ProjectManager")
	var scene := get_tree().current_scene
	if pm == null or scene == null or scene.scene_file_path.is_empty():
		return ""
	var directory: String = pm.get_active_content_dir("maps")
	return directory.path_join(scene.scene_file_path.md5_text() + "_npcs.json") if not directory.is_empty() else ""

func _save_npc_placements() -> void:
	var path := _get_npc_placements_path()
	if path.is_empty():
		return
	var entries: Array = []
	for node in get_tree().get_nodes_in_group("editable_world_object"):
		if node is NPC and node.profile != null and not node.profile.resource_path.is_empty():
			entries.append({
				"profile": node.profile.resource_path,
				"x": node.global_position.x, "y": node.global_position.y, "z": node.global_position.z,
				"rotation_y": node.rotation_degrees.y,
				"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z
			})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries))

func _load_npc_placements() -> void:
	var path := _get_npc_placements_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var entries = JSON.parse_string(file.get_as_text())
	if not entries is Array:
		return
	for entry: Dictionary in entries:
		var profile_path := str(entry.get("profile", ""))
		if profile_path.is_empty() or not ResourceLoader.exists(profile_path):
			continue
		var profile := load(profile_path) as NPCProfile
		var npc := create_npc(profile, Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0))))
		if npc == null:
			continue
		npc.rotation_degrees.y = float(entry.get("rotation_y", 0.0))
		npc.scale = Vector3(float(entry.get("scale_x", 1.0)), float(entry.get("scale_y", 1.0)), float(entry.get("scale_z", 1.0)))

func create_wild_area(world_position: Vector3, profile: MonsterProfile = null) -> WildEncounterBlock:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty():
		return null
	var area := WildAreaScene.instantiate() as WildEncounterBlock
	if area == null:
		return null
	scene.add_child(area)
	area.global_position = world_position
	area.collision_layer = 4
	area.add_to_group("editable_world_object")
	if profile != null:
		area.encounter_entries = [profile]
	_save_wild_areas()
	return area

func save_wild_areas() -> void:
	_save_wild_areas()

func _get_wild_areas_path() -> String:
	var pm := get_node_or_null("/root/ProjectManager")
	var scene := get_tree().current_scene
	if pm == null or scene == null or scene.scene_file_path.is_empty():
		return ""
	var directory: String = pm.get_active_content_dir("maps")
	return directory.path_join(scene.scene_file_path.md5_text() + "_wild_areas.json") if not directory.is_empty() else ""

func _save_wild_areas() -> void:
	var path := _get_wild_areas_path()
	if path.is_empty():
		return
	var entries: Array = []
	for node in get_tree().get_nodes_in_group("editable_world_object"):
		if node is WildEncounterBlock:
			var profiles: Array[String] = []
			for entry in node.encounter_entries:
				var profile := entry as MonsterProfile
				if profile != null and not profile.resource_path.is_empty():
					profiles.append(profile.resource_path)
			entries.append({
				"x": node.global_position.x, "y": node.global_position.y, "z": node.global_position.z,
				"scale_x": node.scale.x, "scale_y": node.scale.y, "scale_z": node.scale.z,
				"minimum_level": node.default_minimum_level,
				"maximum_level": node.default_maximum_level,
				"encounter_rate": node.encounter_rate_percent,
				"minimum_steps": node.minimum_steps_before_checks,
				"step_interval": node.step_check_interval,
				"trigger_once": node.trigger_once,
				"profiles": profiles
			})
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries))

func _load_wild_areas() -> void:
	var path := _get_wild_areas_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var entries = JSON.parse_string(file.get_as_text())
	if not entries is Array:
		return
	for entry: Dictionary in entries:
		var area := create_wild_area(Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0))))
		if area == null:
			continue
		area.scale = Vector3(float(entry.get("scale_x", 1.0)), float(entry.get("scale_y", 1.0)), float(entry.get("scale_z", 1.0)))
		area.default_minimum_level = int(entry.get("minimum_level", 2))
		area.default_maximum_level = int(entry.get("maximum_level", 5))
		area.encounter_rate_percent = float(entry.get("encounter_rate", 20.0))
		area.minimum_steps_before_checks = int(entry.get("minimum_steps", 0))
		area.step_check_interval = int(entry.get("step_interval", 1))
		area.trigger_once = bool(entry.get("trigger_once", false))
		var profiles: Array[Resource] = []
		for profile_path in entry.get("profiles", []):
			if ResourceLoader.exists(str(profile_path)):
				var profile := load(str(profile_path)) as MonsterProfile
				if profile != null:
					profiles.append(profile)
		area.encounter_entries = profiles

func _load_monster_placements() -> void:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm == null:
		return
	var dir: String = pm.get_active_content_dir("placements")
	var scene := get_tree().current_scene
	if dir.is_empty() or scene == null or scene.scene_file_path.is_empty():
		return
	var path := dir.path_join(scene.scene_file_path.md5_text() + ".json")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	for entry: Dictionary in parsed:
		var profile_path := str(entry.get("profile", ""))
		if profile_path.is_empty() or not ResourceLoader.exists(profile_path):
			continue
		var monster := MonsterScene.instantiate() as Monster
		monster.profile = load(profile_path) as MonsterProfile
		monster.level = int(entry.get("level", 5))
		scene.add_child(monster)
		monster.global_position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
