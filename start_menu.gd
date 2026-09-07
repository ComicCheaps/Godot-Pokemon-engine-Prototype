extends Control
class_name StartMenu

const MAIN_SCENE := "res://node_3d.tscn"
const MonsterScene = preload("res://monster.tscn")

var panel: PanelContainer
var content: VBoxContainer
var status_label: Label
var name_edit: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_menu()
	_show_project_list()

func _build_menu() -> void:
	var background := ColorRect.new()
	background.color = Color(0.0431373, 0.0745098, 0.109804, 1)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	panel = PanelContainer.new()
	panel.position = Vector2(320, 90)
	panel.size = Vector2(640, 540)
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
	title.text = "The-TRUE-PokeENGINE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Select a Project"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	root.add_child(subtitle)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

func _show_project_list() -> void:
	_clear_content()
	status_label.text = ""
	var pm := _project_manager()
	var projects: Array[Dictionary] = pm.list_projects() if pm != null else []
	if projects.is_empty():
		var empty := Label.new()
		empty.text = "No projects yet. Create one to begin."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty)
	for project: Dictionary in projects:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		var info := Label.new()
		info.text = "%s   (Last played: %s)" % [project.get("name", ""), project.get("last_played", "Never")]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var continue_button := Button.new()
		continue_button.text = "Continue"
		continue_button.pressed.connect(_continue_project.bind(str(project.get("id", ""))))
		row.add_child(continue_button)
		var edit_button := Button.new()
		edit_button.text = "Edit"
		edit_button.pressed.connect(_edit_project.bind(str(project.get("id", ""))))
		row.add_child(edit_button)
		var export_button := Button.new()
		export_button.text = "Export"
		export_button.pressed.connect(_export_project.bind(str(project.get("id", "")), str(project.get("name", ""))))
		row.add_child(export_button)
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.pressed.connect(_confirm_delete_project.bind(str(project.get("id", "")), str(project.get("name", ""))))
		row.add_child(delete_button)

	var new_section := HBoxContainer.new()
	new_section.add_theme_constant_override("separation", 8)
	content.add_child(new_section)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "New project name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_section.add_child(name_edit)
	var create_button := Button.new()
	create_button.text = "New Project"
	create_button.pressed.connect(_create_project)
	new_section.add_child(create_button)

func _create_project() -> void:
	var pm := _project_manager()
	if pm == null:
		return
	var project_name := name_edit.text.strip_edges()
	if project_name.is_empty():
		status_label.text = "Enter a project name."
		return
	var project: Dictionary = pm.create_project(project_name)
	_launch_project(str(project.get("id", "")), false, true)

func _continue_project(id: String) -> void:
	_launch_project(id, true, false)

func _edit_project(id: String) -> void:
	_launch_project(id, true, true)

func _launch_project(id: String, load_existing: bool, use_project_mode: bool) -> void:
	var pm := _project_manager()
	if pm == null or id.is_empty():
		return
	var engine_mode := get_node_or_null("/root/EngineMode")
	if engine_mode != null:
		engine_mode.set_project_mode(use_project_mode)
	pm.set_active_project(id)
	var project: Dictionary = pm.get_project(id)
	var scene_path := str(project.get("scene", MAIN_SCENE))
	if not ResourceLoader.exists(scene_path):
		scene_path = MAIN_SCENE
	status_label.text = "Loading..."
	var tree := get_tree()
	var result := tree.change_scene_to_file(scene_path)
	if result != OK:
		status_label.text = "Failed to load project."
		return
	await tree.scene_changed
	await tree.process_frame
	if load_existing:
		var save_system := tree.root.get_node_or_null("SaveSystem")
		if save_system != null:
			await save_system.load_game()
	_ensure_starter_party()

func _ensure_starter_party() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var party := player.get_node_or_null("Party") if player != null else null
	if party == null or not party.members.is_empty():
		return
	var project_manager := _project_manager()
	var folder: String = project_manager.get_active_content_dir("monsters") if project_manager != null else ""
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var profile := load(folder.path_join(file_name)) as MonsterProfile
			if profile != null:
				var starter := MonsterScene.instantiate() as Monster
				starter.profile = profile
				starter.level = 5
				if party.add_monster(starter):
					var save_system := get_tree().root.get_node_or_null("SaveSystem")
					if save_system != null:
						save_system.save_game()
				directory.list_dir_end()
				return
		file_name = directory.get_next()
	directory.list_dir_end()

func _export_project(id: String, project_name: String) -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Choose export destination for '%s'" % project_name
	dialog.dir_selected.connect(func(destination: String) -> void:
		var pm := _project_manager()
		var success: bool = pm != null and pm.export_project(id, destination)
		status_label.text = "Exported '%s' to %s" % [project_name, destination] if success else "Export failed."
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio()

func _confirm_delete_project(id: String, project_name: String) -> void:
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Delete Project"
	confirmation.dialog_text = "Delete project '%s'? This cannot be undone." % project_name
	confirmation.ok_button_text = "Delete"
	confirmation.confirmed.connect(_delete_project.bind(id))
	add_child(confirmation)
	confirmation.popup_centered()

func _delete_project(id: String) -> void:
	var pm := _project_manager()
	if pm != null:
		pm.delete_project(id)
	_show_project_list()

func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()

func _project_manager() -> Node:
	return get_node_or_null("/root/ProjectManager")
