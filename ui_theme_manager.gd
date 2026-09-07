extends Node

const DEFAULT_THEME := {
	"panel_color": "15202b",
	"accent_color": "67d7ad",
	"text_color": "f4f7f5",
	"font_scale": 1.0,
	"ui_audio_group": "UI"
}

var active_theme: Dictionary = DEFAULT_THEME.duplicate(true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("refresh_active_theme")

func refresh_active_theme() -> void:
	active_theme = _load_theme()
	apply_theme_to_scene()

func save_theme(theme_data: Dictionary) -> void:
	active_theme = DEFAULT_THEME.duplicate(true)
	active_theme.merge(theme_data, true)
	var path := _get_theme_path()
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(active_theme))
	apply_theme_to_scene()

func apply_theme_to_scene() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_apply_theme_recursive(scene)

func _on_scene_changed() -> void:
	call_deferred("refresh_active_theme")

func _load_theme() -> Dictionary:
	var theme_data := DEFAULT_THEME.duplicate(true)
	var path := _get_theme_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return theme_data
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return theme_data
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		theme_data.merge(parsed, true)
	return theme_data

func _get_theme_path() -> String:
	var project_manager := get_node_or_null("/root/ProjectManager")
	if project_manager == null:
		return ""
	var directory: String = project_manager.get_active_content_dir("ui")
	return directory.path_join("theme.json") if not directory.is_empty() else ""

func _apply_theme_recursive(node: Node) -> void:
	if node is PanelContainer:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(str(active_theme.get("panel_color", "15202b")))
		panel_style.border_color = Color(str(active_theme.get("accent_color", "67d7ad")))
		panel_style.set_border_width_all(1)
		panel_style.set_corner_radius_all(4)
		node.add_theme_stylebox_override("panel", panel_style)
	if node is Label or node is Button:
		node.add_theme_color_override("font_color", Color(str(active_theme.get("text_color", "f4f7f5"))))
		var base_size: int = node.get_theme_font_size("font_size")
		if base_size > 0:
			node.add_theme_font_size_override("font_size", roundi(base_size * float(active_theme.get("font_scale", 1.0))))
	if node is ProgressBar:
		node.add_theme_color_override("font_color", Color(str(active_theme.get("text_color", "f4f7f5"))))
	for child in node.get_children():
		_apply_theme_recursive(child)
