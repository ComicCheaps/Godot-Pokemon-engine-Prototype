extends Node

const DEFAULT_SETTINGS := {
	"arena_theme": "Default",
	"hybrid_presentation_enabled": true
}

var active_settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)

func get_settings() -> Dictionary:
	_load_settings()
	return active_settings.duplicate(true)

func save_settings(settings: Dictionary) -> void:
	active_settings = DEFAULT_SETTINGS.duplicate(true)
	for key in settings:
		if active_settings.has(key):
			active_settings[key] = settings[key]
	var path := _get_settings_path()
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(active_settings))
	apply_to_active_arena()

func apply_to_active_arena() -> void:
	var arena: Node = get_tree().get_first_node_in_group("battle_arena")
	if arena != null:
		apply_to_arena(arena)

func apply_to_arena(arena: Node) -> void:
	_load_settings()
	arena.configure_for_area(str(active_settings.get("arena_theme", "Default")))
	arena.configure_hybrid_presentation(bool(active_settings.get("hybrid_presentation_enabled", true)))

func _load_settings() -> void:
	active_settings = DEFAULT_SETTINGS.duplicate(true)
	var path := _get_settings_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key in active_settings:
			if parsed.has(key):
				active_settings[key] = parsed[key]

func _get_settings_path() -> String:
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("battle") if project_manager != null else ""
	return folder.path_join("settings.json") if not folder.is_empty() else ""