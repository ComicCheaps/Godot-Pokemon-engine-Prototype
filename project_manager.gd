extends Node

## Manages independently-savable "projects" (playthroughs/games built with the engine).
## Authored content (monsters, items, npcs, maps, structures, placements) lives per-project,
## not baked into the shared Godot game resources, so it can be exported once a project is done.
const PROJECTS_DIR := "user://projects/"
const INDEX_PATH := "user://projects/index.json"
const DEFAULT_SCENE := "res://maps/blank_map.tscn"
const CONTENT_CATEGORIES := ["monsters", "items", "npcs", "dialogues", "cutscenes", "battle", "maps", "structures", "placements", "assets", "ui"]
const BUILTIN_MONSTERS_DIR := "res://monsters"
const IMPORTABLE_ASSET_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "glb", "gltf", "obj", "wav", "ogg", "mp3"]

var active_project_id: String = ""
var _index: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_projects_dir()
	_load_index()

func list_projects() -> Array[Dictionary]:
	var projects: Array[Dictionary] = []
	for id in _index.keys():
		projects.append(_index[id])
	projects.sort_custom(func(a, b): return str(a.get("last_played", "")) > str(b.get("last_played", "")))
	return projects

func get_project(id: String) -> Dictionary:
	return _index.get(id, {})

func create_project(project_name: String, scene_path: String = DEFAULT_SCENE) -> Dictionary:
	var id := _generate_id()
	var timestamp := Time.get_datetime_string_from_system()
	var project := {
		"id": id,
		"name": project_name,
		"scene": scene_path,
		"created_at": timestamp,
		"last_played": timestamp
	}
	_index[id] = project
	_save_index()
	var dir := DirAccess.open(PROJECTS_DIR)
	if dir != null:
		dir.make_dir(id)
	for category in CONTENT_CATEGORIES:
		get_content_dir(id, category)
	_seed_starter_monsters(id)
	_seed_starter_items(id)
	return project

func delete_project(id: String) -> bool:
	if not _index.has(id):
		return false
	_index.erase(id)
	_save_index()
	if active_project_id == id:
		active_project_id = ""
	var project_dir := PROJECTS_DIR.path_join(id)
	if DirAccess.dir_exists_absolute(project_dir):
		_remove_dir_recursive(project_dir)
	return true

func set_active_project(id: String) -> void:
	if not _index.has(id):
		return
	active_project_id = id
	_index[id]["last_played"] = Time.get_datetime_string_from_system()
	_save_index()

func get_active_save_path() -> String:
	if active_project_id.is_empty() or not _index.has(active_project_id):
		return ""
	return PROJECTS_DIR.path_join(active_project_id).path_join("save.json")

func get_project_dir(id: String) -> String:
	return PROJECTS_DIR.path_join(id)

## Returns (and ensures the existence of) a project's content folder for the given category,
## e.g. "monsters", "items", "npcs", "maps", "structures", "placements".
func get_content_dir(id: String, category: String) -> String:
	var dir := get_project_dir(id).path_join("content").path_join(category)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir

func get_active_content_dir(category: String) -> String:
	if active_project_id.is_empty() or not _index.has(active_project_id):
		return ""
	return get_content_dir(active_project_id, category)

func import_asset(source_path: String) -> Dictionary:
	if active_project_id.is_empty() or source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {}
	var extension := source_path.get_extension().to_lower()
	if not IMPORTABLE_ASSET_EXTENSIONS.has(extension):
		return {}
	var assets_dir := get_active_content_dir("assets")
	if assets_dir.is_empty():
		return {}
	var base_name := source_path.get_file().get_basename().validate_filename()
	var destination_name := "%s.%s" % [base_name, extension]
	var index := 2
	while FileAccess.file_exists(assets_dir.path_join(destination_name)):
		destination_name = "%s_%d.%s" % [base_name, index, extension]
		index += 1
	var destination_path := assets_dir.path_join(destination_name)
	if not _copy_file(source_path, destination_path):
		return {}
	var entry := {
		"id": destination_path.md5_text(),
		"name": destination_name,
		"path": destination_path,
		"type": _get_asset_type(extension),
		"extension": extension,
		"imported_at": Time.get_datetime_string_from_system()
	}
	var manifest := _load_asset_manifest()
	manifest.append(entry)
	_save_asset_manifest(manifest)
	return entry

func get_imported_assets() -> Array:
	return _load_asset_manifest()

func _get_asset_type(extension: String) -> String:
	if extension in ["png", "jpg", "jpeg", "webp", "svg"]:
		return "sprite"
	if extension in ["glb", "gltf", "obj"]:
		return "model"
	return "audio"

func _load_asset_manifest() -> Array:
	var assets_dir := get_active_content_dir("assets")
	if assets_dir.is_empty():
		return []
	var path := assets_dir.path_join("assets.json")
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []

func _save_asset_manifest(entries: Array) -> void:
	var assets_dir := get_active_content_dir("assets")
	if assets_dir.is_empty():
		return
	var file := FileAccess.open(assets_dir.path_join("assets.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries))

## Copies the full project folder (save + authored content) to a destination directory
## a developer picks once their project is ready to ship.
func export_project(id: String, destination_path: String) -> bool:
	if not _index.has(id) or destination_path.is_empty():
		return false
	var source := ProjectSettings.globalize_path(get_project_dir(id))
	var destination := destination_path.path_join(str(_index[id].get("name", id)))
	return _copy_dir_recursive(source, destination)

func _seed_starter_items(id: String) -> void:
	var destination := get_content_dir(id, "items").path_join("items.json")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({}))

func _seed_starter_monsters(id: String) -> void:
	var destination := get_content_dir(id, "monsters")
	var source_dir := DirAccess.open(BUILTIN_MONSTERS_DIR)
	if source_dir == null:
		return
	source_dir.list_dir_begin()
	var file_name := source_dir.get_next()
	while file_name != "":
		if not source_dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			_copy_file(BUILTIN_MONSTERS_DIR.path_join(file_name), destination.path_join(file_name))
		file_name = source_dir.get_next()
	source_dir.list_dir_end()

func _copy_file(source_path: String, destination_path: String) -> bool:
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return false
	var destination_file := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		return false
	destination_file.store_buffer(source_file.get_buffer(source_file.get_length()))
	return true

func _copy_dir_recursive(source: String, destination: String) -> bool:
	var dir := DirAccess.open(source)
	if dir == null:
		return false
	DirAccess.make_dir_recursive_absolute(destination)
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			var source_path := source.path_join(file_name)
			var dest_path := destination.path_join(file_name)
			if dir.current_is_dir():
				if not _copy_dir_recursive(source_path, dest_path):
					return false
			elif not _copy_file(source_path, dest_path):
				return false
		file_name = dir.get_next()
	dir.list_dir_end()
	return true

func _generate_id() -> String:
	var id := str(Time.get_unix_time_from_system()).replace(".", "")
	while _index.has(id):
		id += "x"
	return id

func _ensure_projects_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROJECTS_DIR))

func _load_index() -> void:
	if not FileAccess.file_exists(INDEX_PATH):
		_index = {}
		return
	var file := FileAccess.open(INDEX_PATH, FileAccess.READ)
	if file == null:
		_index = {}
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_index = parsed if parsed is Dictionary else {}

func _save_index() -> void:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_index))

func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path := path.path_join(file_name)
				if dir.current_is_dir():
					_remove_dir_recursive(full_path)
				else:
					dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
