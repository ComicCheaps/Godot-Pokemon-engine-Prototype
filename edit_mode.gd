extends Node

## Global edit-mode toggle (F5): freecam, block/slope placement, monster placement, world pause.
const MonsterScene = preload("res://monster.tscn")
const NPCScene = preload("res://npc.tscn")
const CutsceneResourceScript = preload("res://cutscene_resource.gd")
const TrainerBattleProfileScript = preload("res://trainer_battle_profile.gd")
const MONSTERS_FOLDER := "res://monsters"
const CAMERA_SPEED := 6.0
const CAMERA_FAST_SPEED := 16.0
const CAMERA_LOOK_SENSITIVITY := 0.003

var active: bool = false

var _edit_camera: Camera3D
var _previous_camera: Camera3D
var _was_paused: bool = false
var _available_profiles: Array[MonsterProfile] = []

var _hud: CanvasLayer
var _hud_panel: Panel
var _species_options: OptionButton
var _world_npc_picker: OptionButton
var _cube_button: Button
var _slope_button: Button
var _grid_toggle: CheckButton
var _select_mode_button: Button
var _place_mode_button: Button
var _workspace_label: Label
var _selection_label: Label
var _undo_button: Button
var _redo_button: Button
var _asset_status_label: Label
var _asset_list_label: Label
var _selected_asset_picker: OptionButton
var _selected_tags_input: LineEdit
var _last_resource_object: Node3D
var _world_left_panel: PanelContainer
var _world_right_panel: PanelContainer
var _workspace_surface: Control
var _workspace_content: VBoxContainer
var _pokemon_picker: OptionButton
var _pokemon_details: Label
var _pokemon_id_input: LineEdit
var _pokemon_name_input: LineEdit
var _pokemon_types_input: LineEdit
var _pokemon_stats_input: LineEdit
var _pokemon_status_label: Label
var _pokemon_editing_profile: MonsterProfile
var _pokemon_editing_path := ""
var _npc_picker: OptionButton
var _npc_details: Label
var _npc_name_input: LineEdit
var _npc_dialogue_input: TextEdit
var _npc_dialogue_picker: OptionButton
var _npc_cutscene_picker: OptionButton
var _npc_trainer_battle_picker: OptionButton
var _npc_direction_picker: OptionButton
var _npc_behavior_picker: OptionButton
var _npc_status_label: Label
var _npc_editing_profile: NPCProfile
var _npc_editing_path := ""
var _available_npc_profiles: Array[NPCProfile] = []
var _dialogue_picker: OptionButton
var _dialogue_name_input: LineEdit
var _dialogue_speaker_input: LineEdit
var _dialogue_lines_input: TextEdit
var _dialogue_audio_group_picker: OptionButton
var _dialogue_status_label: Label
var _dialogue_editing_resource: DialogueResource
var _dialogue_editing_path := ""
var _available_dialogues: Array[DialogueResource] = []
var _cutscene_picker: OptionButton
var _cutscene_name_input: LineEdit
var _cutscene_action_picker: OptionButton
var _cutscene_dialogue_picker: OptionButton
var _cutscene_wait_input: SpinBox
var _cutscene_steps_label: Label
var _cutscene_status_label: Label
var _cutscene_editing_resource: Resource
var _cutscene_editing_path := ""
var _available_cutscenes: Array[Resource] = []
var _battle_theme_picker: OptionButton
var _battle_hybrid_toggle: CheckButton
var _battle_status_label: Label
var _trainer_battle_picker: OptionButton
var _trainer_battle_name_input: LineEdit
var _trainer_battle_opponent_picker: OptionButton
var _trainer_battle_level_input: SpinBox
var _trainer_battle_intro_picker: OptionButton
var _trainer_battle_status_label: Label
var _trainer_battle_editing_resource: Resource
var _trainer_battle_editing_path := ""
var _available_trainer_battles: Array[Resource] = []
var _item_template_picker: OptionButton
var _item_id_input: LineEdit
var _item_name_input: LineEdit
var _item_category_picker: OptionButton
var _item_tags_input: LineEdit
var _item_effect_input: LineEdit
var _item_audio_group_picker: OptionButton
var _item_status_label: Label
var _ui_panel_color_input: LineEdit
var _ui_accent_color_input: LineEdit
var _ui_text_color_input: LineEdit
var _ui_font_scale: SpinBox
var _ui_audio_group_picker: OptionButton
var _ui_preview_panel: PanelContainer
var _ui_status_label: Label
var _wild_minimum_level: SpinBox
var _wild_maximum_level: SpinBox
var _wild_rate: SpinBox
var _wild_step_interval: SpinBox
var _active_workspace := "World"

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_size: Vector2 = Vector2.ZERO
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _rotating_camera: bool = false

const HUD_MIN_SIZE := Vector2(260, 260)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_editor_shell()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		var engine_mode := get_node_or_null("/root/EngineMode")
		if engine_mode == null or not engine_mode.is_project_mode():
			return
		if not active and _is_pause_menu_open():
			return
		_set_active(not active)
		get_viewport().set_input_as_handled()
		return
	if not active or _edit_camera == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_rotating_camera = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _rotating_camera else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _rotating_camera:
		_edit_camera.rotate_y(-event.relative.x * CAMERA_LOOK_SENSITIVITY)
		_edit_camera.rotation.x = clampf(
			_edit_camera.rotation.x - event.relative.y * CAMERA_LOOK_SENSITIVITY,
			deg_to_rad(-85.0),
			deg_to_rad(85.0)
		)
		get_viewport().set_input_as_handled()

func _is_pause_menu_open() -> bool:
	var pause_menu := get_tree().get_first_node_in_group("pause_menu")
	return pause_menu != null and pause_menu.get("panel") != null and pause_menu.panel.visible

func _process(delta: float) -> void:
	if not active or _edit_camera == null:
		return
	_move_camera(delta)
	if Input.is_action_just_pressed("editor_place_player"):
		_place_player_under_mouse()
	if Input.is_action_just_pressed("editor_place_npc"):
		_place_npc_under_mouse()
	_sync_block_buttons()
	_sync_selection_inspector()
	_sync_history_buttons()

func _move_camera(delta: float) -> void:
	var direction := Vector3.ZERO
	var forward := -_edit_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := _edit_camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	if Input.is_action_pressed("ui_up"):
		direction += forward
	if Input.is_action_pressed("ui_down"):
		direction -= forward
	if Input.is_action_pressed("ui_left"):
		direction -= right
	if Input.is_action_pressed("ui_right"):
		direction += right
	if Input.is_key_pressed(KEY_Q):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_E):
		direction.y += 1.0
	if direction == Vector3.ZERO:
		return
	var speed := CAMERA_FAST_SPEED if Input.is_key_pressed(KEY_SHIFT) else CAMERA_SPEED
	_edit_camera.global_position += direction.normalized() * speed * delta

func _set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if active:
		_enter_edit_mode()
	else:
		_exit_edit_mode()

func _enter_edit_mode() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true

	_previous_camera = get_viewport().get_camera_3d()
	_edit_camera = Camera3D.new()
	if _previous_camera != null:
		_edit_camera.global_transform = _previous_camera.global_transform
		_edit_camera.fov = _previous_camera.fov
	get_tree().current_scene.add_child(_edit_camera)
	_edit_camera.make_current()

	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.set_edit_mode(true)
	var grid_debug := get_tree().get_first_node_in_group("grid_debug")
	if grid_debug != null:
		grid_debug.set_edit_mode(true)

	_load_profiles_from_folder()
	_refresh_species_options()
	_refresh_pokemon_workspace()
	_refresh_npc_workspace()
	_load_dialogues_from_folder()
	_load_cutscenes_from_folder()
	_load_trainer_battles_from_folder()
	_refresh_world_npc_options()
	_set_active_workspace(_active_workspace)
	_hud.visible = true

func _exit_edit_mode() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.set_edit_mode(false)
	var grid_debug := get_tree().get_first_node_in_group("grid_debug")
	if grid_debug != null:
		grid_debug.set_edit_mode(false)

	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	if _edit_camera != null and is_instance_valid(_edit_camera):
		_edit_camera.queue_free()
	_edit_camera = null
	_previous_camera = null

	_hud.visible = false
	_rotating_camera = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = _was_paused

func _place_monster_under_mouse() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map == null or _species_options.item_count == 0:
		return
	var target_position: Vector3 = terrain_map.get_ground_point_from_mouse()
	if target_position == Vector3.INF:
		return
	var profile: MonsterProfile = _species_options.get_item_metadata(_species_options.selected)
	if profile == null:
		return
	var monster := MonsterScene.instantiate() as Monster
	monster.profile = profile
	monster.level = 5
	get_tree().current_scene.add_child(monster)
	monster.global_position = target_position
	_save_monster_placement(profile, target_position)

func _place_player_under_mouse() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if terrain_map == null or player == null:
		return
	var ground_height := float(player.get("ground_height"))
	var target_position: Vector3 = terrain_map.get_player_placement_point_from_mouse(ground_height)
	if target_position == Vector3.INF:
		return
	player.global_position = target_position
	if player.get("is_moving") != null:
		player.set("is_moving", false)
	if player.get("reserved_position") != null:
		player.set("reserved_position", target_position)
	if player.get("start_position") != null:
		player.set("start_position", target_position)

func _place_npc_under_mouse() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	var world_content := get_node_or_null("/root/WorldContent")
	if terrain_map == null or world_content == null or _world_npc_picker == null or _world_npc_picker.item_count == 0:
		return
	var target_position := terrain_map.get_ground_point_from_mouse()
	if target_position == Vector3.INF:
		return
	var profile := _world_npc_picker.get_item_metadata(_world_npc_picker.selected) as NPCProfile
	if profile == null:
		return
	var npc = world_content.create_npc(profile, target_position)
	if npc != null:
		terrain_map.select_editor_object(npc)

func _save_monster_placement(profile: MonsterProfile, world_position: Vector3) -> void:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm == null or profile.resource_path.is_empty():
		return
	var dir: String = pm.get_active_content_dir("placements")
	var scene := get_tree().current_scene
	if dir.is_empty() or scene == null or scene.scene_file_path.is_empty():
		return
	var path := dir.path_join(scene.scene_file_path.md5_text() + ".json")
	var entries: Array = []
	if FileAccess.file_exists(path):
		var read_file := FileAccess.open(path, FileAccess.READ)
		if read_file != null:
			var parsed = JSON.parse_string(read_file.get_as_text())
			if parsed is Array:
				entries = parsed
	entries.append({
		"profile": profile.resource_path,
		"level": 5,
		"x": world_position.x, "y": world_position.y, "z": world_position.z
	})
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	if write_file != null:
		write_file.store_string(JSON.stringify(entries))

func _load_profiles_from_folder() -> void:
	_available_profiles.clear()
	var folder := MONSTERS_FOLDER
	var pm := get_node_or_null("/root/ProjectManager")
	if pm != null:
		var project_dir: String = pm.get_active_content_dir("monsters")
		if not project_dir.is_empty():
			folder = project_dir
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource := load(folder.path_join(file_name))
			if resource is MonsterProfile:
				_available_profiles.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()

func _refresh_species_options() -> void:
	_species_options.clear()
	for profile in _available_profiles:
		_species_options.add_item(profile.species_name)
		_species_options.set_item_metadata(_species_options.item_count - 1, profile)
	if _species_options.item_count > 0:
		_species_options.select(0)

func _refresh_world_npc_options() -> void:
	if _world_npc_picker == null:
		return
	_load_npc_profiles_from_folder()
	_world_npc_picker.clear()
	for profile in _available_npc_profiles:
		_world_npc_picker.add_item(profile.npc_name)
		_world_npc_picker.set_item_metadata(_world_npc_picker.item_count - 1, profile)
	if _world_npc_picker.item_count > 0:
		_world_npc_picker.select(0)
	for profile in _available_npc_profiles:
		_world_npc_picker.add_item(profile.npc_name)
		_world_npc_picker.set_item_metadata(_world_npc_picker.item_count - 1, profile)

func _select_block_type(block_type: int) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.set_block_type(block_type)

func _set_cursor_mode(cursor_mode: int) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.set_cursor_mode(cursor_mode)

func _sync_block_buttons() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map == null or _cube_button == null:
		return
	var selected: int = terrain_map.selected_block
	_cube_button.set_pressed_no_signal(selected == TerrainMap.BLOCK_CUBE)
	_slope_button.set_pressed_no_signal(selected == TerrainMap.BLOCK_SLOPE)

func _set_show_3d_grid(value: bool) -> void:
	var grid_debug := get_tree().get_first_node_in_group("grid_debug")
	if grid_debug != null:
		grid_debug.set_show_3d_grid(value)

func _rotate_selected(delta_degrees: int) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.rotate_selected(delta_degrees)

func _move_selected_block(offset: Vector3i) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.move_selected_block(offset)

func _resize_selected_block(offset: Vector3i) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.resize_selected_block(offset)

func _set_gizmo_mode(gizmo_mode: int) -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.set_gizmo_mode(gizmo_mode)

func _undo_terrain() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.undo()

func _redo_terrain() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	if terrain_map != null:
		terrain_map.redo()

func _place_wild_area_under_mouse() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	var world_content := get_node_or_null("/root/WorldContent")
	if terrain_map == null or world_content == null:
		return
	var target_position := terrain_map.get_ground_point_from_mouse()
	if target_position == Vector3.INF:
		return
	var profile: MonsterProfile = _species_options.get_item_metadata(_species_options.selected) if _species_options.item_count > 0 else null
	var area = world_content.create_wild_area(target_position, profile)
	if area != null:
		var visual := area.get_node_or_null("EncounterVisual") as MeshInstance3D
		if visual != null:
			visual.visible = true
		terrain_map.select_editor_object(area)

func _apply_wild_area_settings() -> void:
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	var world_content := get_node_or_null("/root/WorldContent")
	if terrain_map == null or world_content == null:
		return
	var area = terrain_map.get_selected_object()
	if not area is WildEncounterBlock:
		return
	area.default_minimum_level = int(_wild_minimum_level.value)
	area.default_maximum_level = maxi(area.default_minimum_level, int(_wild_maximum_level.value))
	area.encounter_rate_percent = _wild_rate.value
	area.step_check_interval = int(_wild_step_interval.value)
	world_content.save_wild_areas()

func _sync_history_buttons() -> void:
	if _undo_button == null or _redo_button == null:
		return
	var terrain_map := get_tree().get_first_node_in_group("terrain_map")
	_undo_button.disabled = terrain_map == null or not terrain_map.can_undo()
	_redo_button.disabled = terrain_map == null or not terrain_map.can_redo()

func _open_asset_import_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = "Import Sprite, Model, or Audio"
	dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.svg ; Sprite Images")
	dialog.add_filter("*.glb, *.gltf, *.obj ; 3D Models")
	dialog.add_filter("*.wav, *.ogg, *.mp3 ; Audio")
	dialog.file_selected.connect(_import_asset.bind(dialog))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio()

func _import_asset(source_path: String, dialog: FileDialog) -> void:
	var project_manager := get_node_or_null("/root/ProjectManager")
	var asset: Dictionary = project_manager.import_asset(source_path) if project_manager != null else {}
	if _asset_status_label != null:
		_asset_status_label.text = "Imported %s" % str(asset.get("name", "")) if not asset.is_empty() else "Asset import failed"
	_refresh_imported_assets()
	dialog.queue_free()

func _refresh_imported_assets() -> void:
	if _asset_list_label == null:
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var assets: Array = project_manager.get_imported_assets() if project_manager != null else []
	if assets.is_empty():
		_asset_list_label.text = "No project assets imported"
		return
	var lines: PackedStringArray = []
	for index in range(maxi(0, assets.size() - 6), assets.size()):
		var asset: Dictionary = assets[index]
		lines.append("%s  %s" % [str(asset.get("type", "asset")).capitalize(), str(asset.get("name", ""))])
	_asset_list_label.text = "\n".join(lines)
	_refresh_selected_asset_picker(assets)

func _refresh_selected_asset_picker(assets: Array = []) -> void:
	if _selected_asset_picker == null:
		return
	if assets.is_empty():
		var project_manager := get_node_or_null("/root/ProjectManager")
		assets = project_manager.get_imported_assets() if project_manager != null else []
	_selected_asset_picker.clear()
	_selected_asset_picker.add_item("No asset assigned")
	_selected_asset_picker.set_item_metadata(0, {})
	for asset: Dictionary in assets:
		_selected_asset_picker.add_item("%s: %s" % [str(asset.get("type", "asset")).capitalize(), str(asset.get("name", ""))])
		_selected_asset_picker.set_item_metadata(_selected_asset_picker.item_count - 1, asset)

func _assign_selected_asset() -> void:
	if _selected_asset_picker == null or _selected_asset_picker.selected <= 0:
		return
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	if terrain_map != null:
		terrain_map.assign_selected_asset(_selected_asset_picker.get_item_metadata(_selected_asset_picker.selected))

func _save_selected_tags() -> void:
	if _selected_tags_input == null:
		return
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	if terrain_map != null:
		terrain_map.set_selected_tags(_selected_tags_input.text)

func _add_transform_button(row: HBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	return label

func _make_editor_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.07, 0.94)
	style.border_color = Color(0.22, 0.38, 0.45, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_editor_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button

func _build_editor_shell() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 30
	_hud.visible = false
	add_child(_hud)

	var top_bar := _make_editor_panel()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.position = Vector2(16, 12)
	top_bar.size = Vector2(-32, 46)
	_hud.add_child(top_bar)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_bar.add_child(top_row)
	var title := Label.new()
	title.text = "PokeENGINE Studio"
	title.custom_minimum_size = Vector2(180, 0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	top_row.add_child(title)
	for workspace in ["World", "Pokemon", "NPCs", "Dialogues", "Cutscenes", "Items", "UI", "Battle"]:
		top_row.add_child(_make_editor_button(workspace, _set_active_workspace.bind(workspace)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	_undo_button = _make_editor_button("Undo", _undo_terrain)
	_undo_button.disabled = true
	top_row.add_child(_undo_button)
	_redo_button = _make_editor_button("Redo", _redo_terrain)
	_redo_button.disabled = true
	top_row.add_child(_redo_button)
	top_row.add_child(_make_editor_button("Exit", func() -> void: _set_active(false)))

	_world_left_panel = _make_editor_panel()
	_world_left_panel.position = Vector2(16, 72)
	_world_left_panel.size = Vector2(260, 570)
	_hud.add_child(_world_left_panel)
	var left_scroll := ScrollContainer.new()
	_world_left_panel.add_child(left_scroll)
	var tools := VBoxContainer.new()
	tools.custom_minimum_size = Vector2(236, 0)
	tools.add_theme_constant_override("separation", 8)
	left_scroll.add_child(tools)
	tools.add_child(_make_section_label("Viewport Tools"))
	var cursor_row := HBoxContainer.new()
	var cursor_group := ButtonGroup.new()
	_select_mode_button = Button.new()
	_select_mode_button.text = "Select"
	_select_mode_button.toggle_mode = true
	_select_mode_button.button_group = cursor_group
	_select_mode_button.pressed.connect(_set_cursor_mode.bind(TerrainMap.CURSOR_SELECT))
	cursor_row.add_child(_select_mode_button)
	_place_mode_button = Button.new()
	_place_mode_button.text = "Place"
	_place_mode_button.toggle_mode = true
	_place_mode_button.button_pressed = true
	_place_mode_button.button_group = cursor_group
	_place_mode_button.pressed.connect(_set_cursor_mode.bind(TerrainMap.CURSOR_PLACE))
	cursor_row.add_child(_place_mode_button)
	tools.add_child(cursor_row)
	tools.add_child(HSeparator.new())
	tools.add_child(_make_section_label("Terrain"))
	var block_row := HBoxContainer.new()
	var block_group := ButtonGroup.new()
	_cube_button = Button.new()
	_cube_button.text = "Cube"
	_cube_button.toggle_mode = true
	_cube_button.button_pressed = true
	_cube_button.button_group = block_group
	_cube_button.pressed.connect(_select_block_type.bind(TerrainMap.BLOCK_CUBE))
	block_row.add_child(_cube_button)
	_slope_button = Button.new()
	_slope_button.text = "Slope"
	_slope_button.toggle_mode = true
	_slope_button.button_group = block_group
	_slope_button.pressed.connect(_select_block_type.bind(TerrainMap.BLOCK_SLOPE))
	block_row.add_child(_slope_button)
	tools.add_child(block_row)
	_grid_toggle = CheckButton.new()
	_grid_toggle.text = "3D Grid"
	_grid_toggle.toggled.connect(_set_show_3d_grid)
	tools.add_child(_grid_toggle)
	tools.add_child(HSeparator.new())
	tools.add_child(_make_section_label("Transform"))
	var gizmo_row := HBoxContainer.new()
	var gizmo_group := ButtonGroup.new()
	for tool in [{"name": "Move", "mode": TerrainMap.GIZMO_MOVE}, {"name": "Rotate", "mode": TerrainMap.GIZMO_ROTATE}, {"name": "Scale", "mode": TerrainMap.GIZMO_SCALE}]:
		var tool_button := Button.new()
		tool_button.text = str(tool.name)
		tool_button.toggle_mode = true
		tool_button.button_group = gizmo_group
		tool_button.button_pressed = int(tool.mode) == TerrainMap.GIZMO_MOVE
		tool_button.pressed.connect(_set_gizmo_mode.bind(int(tool.mode)))
		gizmo_row.add_child(tool_button)
	tools.add_child(gizmo_row)
	var move_row := HBoxContainer.new()
	_add_transform_button(move_row, "X-", _move_selected_block.bind(Vector3i.LEFT))
	_add_transform_button(move_row, "X+", _move_selected_block.bind(Vector3i.RIGHT))
	_add_transform_button(move_row, "Y-", _move_selected_block.bind(Vector3i.DOWN))
	_add_transform_button(move_row, "Y+", _move_selected_block.bind(Vector3i.UP))
	tools.add_child(move_row)
	var rotate_row := HBoxContainer.new()
	rotate_row.add_child(_make_editor_button("Rotate -90", _rotate_selected.bind(-90)))
	rotate_row.add_child(_make_editor_button("Rotate +90", _rotate_selected.bind(90)))
	tools.add_child(rotate_row)
	var scale_row := HBoxContainer.new()
	_add_transform_button(scale_row, "Width-", _resize_selected_block.bind(Vector3i.LEFT))
	_add_transform_button(scale_row, "Width+", _resize_selected_block.bind(Vector3i.RIGHT))
	tools.add_child(scale_row)
	var height_row := HBoxContainer.new()
	_add_transform_button(height_row, "Height-", _resize_selected_block.bind(Vector3i.DOWN))
	_add_transform_button(height_row, "Height+", _resize_selected_block.bind(Vector3i.UP))
	tools.add_child(height_row)
	tools.add_child(HSeparator.new())
	tools.add_child(_make_section_label("Placement"))
	_species_options = OptionButton.new()
	tools.add_child(_species_options)
	tools.add_child(_make_editor_button("Place Pokemon", _place_monster_under_mouse))
	_world_npc_picker = OptionButton.new()
	_world_npc_picker.tooltip_text = "NPC profile to place"
	tools.add_child(_world_npc_picker)
	tools.add_child(_make_editor_button("Place NPC", _place_npc_under_mouse))
	tools.add_child(_make_editor_button("Place Player", _place_player_under_mouse))
	tools.add_child(HSeparator.new())
	tools.add_child(_make_section_label("Wild Area"))
	tools.add_child(_make_editor_button("Place Wild Area", _place_wild_area_under_mouse))
	var wild_level_row := HBoxContainer.new()
	_wild_minimum_level = SpinBox.new()
	_wild_minimum_level.min_value = 1
	_wild_minimum_level.max_value = 100
	_wild_minimum_level.value = 2
	wild_level_row.add_child(_wild_minimum_level)
	_wild_maximum_level = SpinBox.new()
	_wild_maximum_level.min_value = 1
	_wild_maximum_level.max_value = 100
	_wild_maximum_level.value = 5
	wild_level_row.add_child(_wild_maximum_level)
	tools.add_child(wild_level_row)
	_wild_rate = SpinBox.new()
	_wild_rate.min_value = 0
	_wild_rate.max_value = 100
	_wild_rate.step = 0.5
	_wild_rate.value = 20
	_wild_rate.tooltip_text = "Encounter rate percent"
	tools.add_child(_wild_rate)
	_wild_step_interval = SpinBox.new()
	_wild_step_interval.min_value = 1
	_wild_step_interval.max_value = 20
	_wild_step_interval.value = 1
	_wild_step_interval.tooltip_text = "Movement steps between encounter checks"
	tools.add_child(_wild_step_interval)
	tools.add_child(_make_editor_button("Apply Wild Settings", _apply_wild_area_settings))
	tools.add_child(HSeparator.new())
	tools.add_child(_make_section_label("Assets"))
	tools.add_child(_make_editor_button("Import Asset", _open_asset_import_dialog))

	_world_right_panel = _make_editor_panel()
	_world_right_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_world_right_panel.position = Vector2(-296, 72)
	_world_right_panel.size = Vector2(280, 360)
	_hud.add_child(_world_right_panel)
	var inspector := VBoxContainer.new()
	inspector.add_theme_constant_override("separation", 10)
	_world_right_panel.add_child(inspector)
	_workspace_label = _make_section_label("World Inspector")
	inspector.add_child(_workspace_label)
	inspector.add_child(HSeparator.new())
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_label.text = "No object selected"
	inspector.add_child(_selection_label)
	inspector.add_child(HSeparator.new())
	inspector.add_child(_make_section_label("Selected Resource"))
	_selected_asset_picker = OptionButton.new()
	inspector.add_child(_selected_asset_picker)
	inspector.add_child(_make_editor_button("Assign Asset", _assign_selected_asset))
	_selected_tags_input = LineEdit.new()
	_selected_tags_input.placeholder_text = "Tags, comma separated"
	_selected_tags_input.text_submitted.connect(func(_text: String) -> void: _save_selected_tags())
	inspector.add_child(_selected_tags_input)
	inspector.add_child(_make_editor_button("Save Tags", _save_selected_tags))
	inspector.add_child(HSeparator.new())
	inspector.add_child(_make_section_label("Project Assets"))
	_asset_status_label = Label.new()
	_asset_status_label.text = "Choose Import Asset to add files"
	_asset_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(_asset_status_label)
	_asset_list_label = Label.new()
	_asset_list_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(_asset_list_label)
	_refresh_imported_assets()
	_build_workspace_surface()

func _set_active_workspace(workspace: String) -> void:
	_active_workspace = workspace
	if _workspace_label != null:
		_workspace_label.text = "%s Inspector" % workspace
	var is_world := workspace == "World"
	if _world_left_panel != null:
		_world_left_panel.visible = is_world
	if _world_right_panel != null:
		_world_right_panel.visible = is_world
	if _workspace_surface != null:
		_workspace_surface.visible = not is_world
	if not is_world:
		_show_workspace_screen(workspace)

func _build_workspace_surface() -> void:
	_workspace_surface = Control.new()
	_workspace_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace_surface.offset_left = 16.0
	_workspace_surface.offset_top = 72.0
	_workspace_surface.offset_right = -16.0
	_workspace_surface.offset_bottom = -16.0
	_workspace_surface.visible = false
	_hud.add_child(_workspace_surface)
	var panel := _make_editor_panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace_surface.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	_workspace_content = VBoxContainer.new()
	_workspace_content.custom_minimum_size = Vector2(860, 620)
	_workspace_content.add_theme_constant_override("separation", 14)
	scroll.add_child(_workspace_content)

func _show_workspace_screen(workspace: String) -> void:
	if _workspace_content == null:
		return
	for child in _workspace_content.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = "%s Studio" % workspace
	heading.add_theme_font_size_override("font_size", 28)
	_workspace_content.add_child(heading)
	if workspace == "Pokemon":
		_build_pokemon_workspace()
	elif workspace == "NPCs":
		_build_npc_workspace()
	elif workspace == "Dialogues":
		_build_dialogue_workspace()
	elif workspace == "Cutscenes":
		_build_cutscene_workspace()
	elif workspace == "Items":
		_build_item_workspace()
	elif workspace == "UI":
		_build_ui_workspace()
	elif workspace == "Battle":
		_build_battle_workspace()

func _build_workspace_overview(title: String, description: String) -> void:
	var section := _make_section_label(title)
	section.add_theme_font_size_override("font_size", 20)
	_workspace_content.add_child(section)
	var details := Label.new()
	details.text = description
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace_content.add_child(details)
	_workspace_content.add_child(HSeparator.new())
	var status := Label.new()
	status.text = "This workspace is ready for its dedicated editor controls."
	_workspace_content.add_child(status)

func _build_battle_workspace() -> void:
	var battle_settings := get_node_or_null("/root/BattleSettings")
	var settings: Dictionary = battle_settings.get_settings() if battle_settings != null else {}
	_workspace_content.add_child(_make_section_label("Arena Presentation"))
	var settings_row := HBoxContainer.new()
	settings_row.add_child(_make_section_label("Arena Theme"))
	_battle_theme_picker = OptionButton.new()
	for theme in ["Default", "Gym", "Grass", "Cave"]:
		_battle_theme_picker.add_item(theme)
		if theme == str(settings.get("arena_theme", "Default")):
			_battle_theme_picker.select(_battle_theme_picker.item_count - 1)
	settings_row.add_child(_battle_theme_picker)
	_battle_hybrid_toggle = CheckButton.new()
	_battle_hybrid_toggle.text = "Cinematic Battle Presentation"
	_battle_hybrid_toggle.button_pressed = bool(settings.get("hybrid_presentation_enabled", true))
	settings_row.add_child(_battle_hybrid_toggle)
	_workspace_content.add_child(settings_row)
	var details := Label.new()
	details.text = "These defaults are stored with the active project and applied whenever its battle arena opens."
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace_content.add_child(details)
	_workspace_content.add_child(_make_editor_button("Save Battle Settings", _save_battle_settings))
	_battle_status_label = Label.new()
	_workspace_content.add_child(_battle_status_label)
	_workspace_content.add_child(HSeparator.new())
	_workspace_content.add_child(_make_section_label("Trainer Battle Profile"))
	var profile_row := HBoxContainer.new()
	_trainer_battle_picker = OptionButton.new()
	_trainer_battle_picker.item_selected.connect(_show_selected_trainer_battle)
	profile_row.add_child(_trainer_battle_picker)
	_trainer_battle_name_input = LineEdit.new()
	_trainer_battle_name_input.placeholder_text = "Trainer battle name"
	profile_row.add_child(_trainer_battle_name_input)
	_workspace_content.add_child(profile_row)
	var opponent_row := HBoxContainer.new()
	_trainer_battle_opponent_picker = OptionButton.new()
	opponent_row.add_child(_trainer_battle_opponent_picker)
	_trainer_battle_level_input = SpinBox.new()
	_trainer_battle_level_input.min_value = 1
	_trainer_battle_level_input.max_value = 100
	_trainer_battle_level_input.value = 5
	opponent_row.add_child(_trainer_battle_level_input)
	_trainer_battle_intro_picker = OptionButton.new()
	for flag in ["intro_trainer", "intro_standard", "intro_gym"]:
		_trainer_battle_intro_picker.add_item(flag.replace("intro_", "").capitalize())
		_trainer_battle_intro_picker.set_item_metadata(_trainer_battle_intro_picker.item_count - 1, flag)
	opponent_row.add_child(_trainer_battle_intro_picker)
	_workspace_content.add_child(opponent_row)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("New Trainer Battle", _new_trainer_battle_profile))
	actions.add_child(_make_editor_button("Save Trainer Battle", _save_trainer_battle_profile))
	_workspace_content.add_child(actions)
	_trainer_battle_status_label = Label.new()
	_workspace_content.add_child(_trainer_battle_status_label)
	_refresh_trainer_battle_workspace()

func _save_battle_settings() -> void:
	var battle_settings := get_node_or_null("/root/BattleSettings")
	if battle_settings == null:
		_battle_status_label.text = "Battle settings manager is unavailable."
		return
	battle_settings.save_settings({
		"arena_theme": _battle_theme_picker.get_item_text(_battle_theme_picker.selected),
		"hybrid_presentation_enabled": _battle_hybrid_toggle.button_pressed
	})
	_battle_status_label.text = "Battle presentation settings saved and applied."

func _load_trainer_battles_from_folder() -> void:
	_available_trainer_battles.clear()
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("battle") if project_manager != null else ""
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource := load(folder.path_join(file_name))
			if resource is Resource and resource.get_script() == TrainerBattleProfileScript:
				_available_trainer_battles.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()

func _refresh_npc_trainer_battle_picker() -> void:
	if _npc_trainer_battle_picker == null:
		return
	_npc_trainer_battle_picker.clear()
	_npc_trainer_battle_picker.add_item("No trainer battle")
	_npc_trainer_battle_picker.set_item_metadata(0, null)
	for resource in _available_trainer_battles:
		_npc_trainer_battle_picker.add_item(str(resource.get("display_name")))
		_npc_trainer_battle_picker.set_item_metadata(_npc_trainer_battle_picker.item_count - 1, resource)

func _refresh_trainer_battle_workspace() -> void:
	if _trainer_battle_picker == null:
		return
	_load_trainer_battles_from_folder()
	_trainer_battle_picker.clear()
	for resource in _available_trainer_battles:
		_trainer_battle_picker.add_item(str(resource.get("display_name")))
		_trainer_battle_picker.set_item_metadata(_trainer_battle_picker.item_count - 1, resource)
	_trainer_battle_opponent_picker.clear()
	for profile in _available_profiles:
		_trainer_battle_opponent_picker.add_item(profile.species_name)
		_trainer_battle_opponent_picker.set_item_metadata(_trainer_battle_opponent_picker.item_count - 1, profile)
	if _trainer_battle_picker.item_count > 0:
		_trainer_battle_picker.select(0)
		_show_selected_trainer_battle(0)
	else:
		_new_trainer_battle_profile()

func _show_selected_trainer_battle(index: int) -> void:
	var resource := _trainer_battle_picker.get_item_metadata(index) as Resource
	if resource == null:
		return
	_trainer_battle_editing_resource = resource
	_trainer_battle_editing_path = resource.resource_path
	_trainer_battle_name_input.text = str(resource.get("display_name"))
	_trainer_battle_level_input.value = int(resource.get("opponent_level"))
	var opponent := resource.get("opponent_profile") as MonsterProfile
	for opponent_index in _trainer_battle_opponent_picker.item_count:
		if _trainer_battle_opponent_picker.get_item_metadata(opponent_index) == opponent:
			_trainer_battle_opponent_picker.select(opponent_index)
			break
	var flags := resource.get("battle_flags") as PackedStringArray
	for intro_index in _trainer_battle_intro_picker.item_count:
		if flags.has(str(_trainer_battle_intro_picker.get_item_metadata(intro_index))):
			_trainer_battle_intro_picker.select(intro_index)
			break

func _new_trainer_battle_profile() -> void:
	_trainer_battle_editing_resource = TrainerBattleProfileScript.new() as Resource
	_trainer_battle_editing_path = ""
	_trainer_battle_name_input.text = "New Trainer Battle"
	_trainer_battle_level_input.value = 5
	_trainer_battle_intro_picker.select(0)

func _save_trainer_battle_profile() -> void:
	if _trainer_battle_editing_resource == null:
		_new_trainer_battle_profile()
	var display_name := _trainer_battle_name_input.text.strip_edges()
	var opponent: MonsterProfile = _trainer_battle_opponent_picker.get_item_metadata(_trainer_battle_opponent_picker.selected) as MonsterProfile if _trainer_battle_opponent_picker.item_count > 0 else null
	if display_name.is_empty() or opponent == null:
		_trainer_battle_status_label.text = "A battle name and opponent Pokemon are required."
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("battle") if project_manager != null else ""
	if folder.is_empty():
		_trainer_battle_status_label.text = "Open a project before saving trainer battles."
		return
	_trainer_battle_editing_resource.set("display_name", display_name)
	_trainer_battle_editing_resource.set("opponent_profile", opponent)
	_trainer_battle_editing_resource.set("opponent_level", int(_trainer_battle_level_input.value))
	_trainer_battle_editing_resource.set("roster", [{"profile": opponent, "level": int(_trainer_battle_level_input.value)}])
	_trainer_battle_editing_resource.set("battle_flags", PackedStringArray([str(_trainer_battle_intro_picker.get_item_metadata(_trainer_battle_intro_picker.selected))]))
	if _trainer_battle_editing_path.is_empty():
		_trainer_battle_editing_path = folder.path_join(_safe_trainer_battle_file_name(display_name) + ".tres")
	var error := ResourceSaver.save(_trainer_battle_editing_resource, _trainer_battle_editing_path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_trainer_battle_status_label.text = "Save failed: %s" % error_string(error)
		return
	_trainer_battle_status_label.text = "Saved %s" % display_name
	_load_trainer_battles_from_folder()
	_refresh_npc_trainer_battle_picker()
	_refresh_trainer_battle_workspace()

func _safe_trainer_battle_file_name(value: String) -> String:
	var safe_name := ""
	for character in value.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_name += character
	return safe_name if not safe_name.is_empty() else "new_trainer_battle"

func _build_pokemon_workspace() -> void:
	var selector_row := HBoxContainer.new()
	var selector_label := _make_section_label("Species")
	selector_row.add_child(selector_label)
	_pokemon_picker = OptionButton.new()
	_pokemon_picker.custom_minimum_size = Vector2(280, 0)
	_pokemon_picker.item_selected.connect(_show_selected_pokemon)
	selector_row.add_child(_pokemon_picker)
	_workspace_content.add_child(selector_row)
	_pokemon_details = Label.new()
	_pokemon_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pokemon_details.add_theme_font_size_override("font_size", 16)
	_workspace_content.add_child(_pokemon_details)
	_workspace_content.add_child(HSeparator.new())
	var identity_row := HBoxContainer.new()
	_pokemon_id_input = LineEdit.new()
	_pokemon_id_input.placeholder_text = "Species ID"
	identity_row.add_child(_pokemon_id_input)
	_pokemon_name_input = LineEdit.new()
	_pokemon_name_input.placeholder_text = "Species name"
	identity_row.add_child(_pokemon_name_input)
	_pokemon_types_input = LineEdit.new()
	_pokemon_types_input.placeholder_text = "Types: normal, fire"
	identity_row.add_child(_pokemon_types_input)
	_workspace_content.add_child(identity_row)
	var stats_label := _make_section_label("Base stats")
	_workspace_content.add_child(stats_label)
	_pokemon_stats_input = LineEdit.new()
	_pokemon_stats_input.placeholder_text = "hp: 1, attack: 1, defense: 1, special_attack: 1, special_defense: 1, speed: 1"
	_workspace_content.add_child(_pokemon_stats_input)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("New Pokemon", _new_pokemon_profile))
	actions.add_child(_make_editor_button("Save Pokemon", _save_pokemon_profile))
	_workspace_content.add_child(actions)
	_pokemon_status_label = Label.new()
	_workspace_content.add_child(_pokemon_status_label)
	_refresh_pokemon_workspace()

func _build_npc_workspace() -> void:
	var selector_row := HBoxContainer.new()
	selector_row.add_child(_make_section_label("NPC Profile"))
	_npc_picker = OptionButton.new()
	_npc_picker.custom_minimum_size = Vector2(280, 0)
	_npc_picker.item_selected.connect(_show_selected_npc)
	selector_row.add_child(_npc_picker)
	_workspace_content.add_child(selector_row)
	_npc_details = Label.new()
	_npc_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace_content.add_child(_npc_details)
	_workspace_content.add_child(HSeparator.new())
	_npc_name_input = LineEdit.new()
	_npc_name_input.placeholder_text = "NPC display name"
	_workspace_content.add_child(_npc_name_input)
	var settings_row := HBoxContainer.new()
	settings_row.add_child(_make_section_label("Facing"))
	_npc_direction_picker = OptionButton.new()
	for direction in ["Down", "Left", "Right", "Up"]:
		_npc_direction_picker.add_item(direction)
	settings_row.add_child(_npc_direction_picker)
	settings_row.add_child(_make_section_label("Behavior"))
	_npc_behavior_picker = OptionButton.new()
	for behavior in [{"name": "Standard NPC", "path": "res://npc_behavior.gd"}, {"name": "Trainer", "path": "res://trainer_behavior.gd"}, {"name": "Guard", "path": "res://guard_behavior.gd"}]:
		_npc_behavior_picker.add_item(str(behavior.name))
		_npc_behavior_picker.set_item_metadata(_npc_behavior_picker.item_count - 1, str(behavior.path))
	settings_row.add_child(_npc_behavior_picker)
	_workspace_content.add_child(settings_row)
	var dialogue_asset_row := HBoxContainer.new()
	dialogue_asset_row.add_child(_make_section_label("Dialogue Asset"))
	_npc_dialogue_picker = OptionButton.new()
	dialogue_asset_row.add_child(_npc_dialogue_picker)
	_workspace_content.add_child(dialogue_asset_row)
	_refresh_npc_dialogue_picker()
	var cutscene_row := HBoxContainer.new()
	cutscene_row.add_child(_make_section_label("Cutscene"))
	_npc_cutscene_picker = OptionButton.new()
	cutscene_row.add_child(_npc_cutscene_picker)
	_workspace_content.add_child(cutscene_row)
	_refresh_npc_cutscene_picker()
	var trainer_battle_row := HBoxContainer.new()
	trainer_battle_row.add_child(_make_section_label("Trainer Battle"))
	_npc_trainer_battle_picker = OptionButton.new()
	trainer_battle_row.add_child(_npc_trainer_battle_picker)
	_workspace_content.add_child(trainer_battle_row)
	_refresh_npc_trainer_battle_picker()
	_workspace_content.add_child(_make_section_label("Dialogue"))
	_npc_dialogue_input = TextEdit.new()
	_npc_dialogue_input.custom_minimum_size = Vector2(0, 180)
	_npc_dialogue_input.placeholder_text = "One dialogue line per row"
	_workspace_content.add_child(_npc_dialogue_input)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("New NPC", _new_npc_profile))
	actions.add_child(_make_editor_button("Save NPC", _save_npc_profile))
	_workspace_content.add_child(actions)
	_npc_status_label = Label.new()
	_workspace_content.add_child(_npc_status_label)
	_refresh_npc_workspace()

func _build_dialogue_workspace() -> void:
	var selector_row := HBoxContainer.new()
	selector_row.add_child(_make_section_label("Dialogue Asset"))
	_dialogue_picker = OptionButton.new()
	_dialogue_picker.custom_minimum_size = Vector2(300, 0)
	_dialogue_picker.item_selected.connect(_show_selected_dialogue)
	selector_row.add_child(_dialogue_picker)
	_workspace_content.add_child(selector_row)
	var identity_row := HBoxContainer.new()
	_dialogue_name_input = LineEdit.new()
	_dialogue_name_input.placeholder_text = "Dialogue asset name"
	identity_row.add_child(_dialogue_name_input)
	_dialogue_speaker_input = LineEdit.new()
	_dialogue_speaker_input.placeholder_text = "Speaker name (optional)"
	identity_row.add_child(_dialogue_speaker_input)
	_dialogue_audio_group_picker = OptionButton.new()
	for group in ["UI", "NPC", "Pokemon", "Battle", "Stage", "Ambient"]:
		_dialogue_audio_group_picker.add_item(group)
	identity_row.add_child(_dialogue_audio_group_picker)
	_workspace_content.add_child(identity_row)
	_workspace_content.add_child(_make_section_label("Lines"))
	_dialogue_lines_input = TextEdit.new()
	_dialogue_lines_input.custom_minimum_size = Vector2(0, 260)
	_dialogue_lines_input.placeholder_text = "One dialogue line per row"
	_workspace_content.add_child(_dialogue_lines_input)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("New Dialogue", _new_dialogue_resource))
	actions.add_child(_make_editor_button("Save Dialogue", _save_dialogue_resource))
	_workspace_content.add_child(actions)
	_dialogue_status_label = Label.new()
	_workspace_content.add_child(_dialogue_status_label)
	_refresh_dialogue_workspace()

func _build_cutscene_workspace() -> void:
	var selector_row := HBoxContainer.new()
	selector_row.add_child(_make_section_label("Cutscene"))
	_cutscene_picker = OptionButton.new()
	_cutscene_picker.custom_minimum_size = Vector2(300, 0)
	_cutscene_picker.item_selected.connect(_show_selected_cutscene)
	selector_row.add_child(_cutscene_picker)
	_workspace_content.add_child(selector_row)
	_cutscene_name_input = LineEdit.new()
	_cutscene_name_input.placeholder_text = "Cutscene name"
	_workspace_content.add_child(_cutscene_name_input)
	var action_row := HBoxContainer.new()
	_cutscene_action_picker = OptionButton.new()
	for action in ["Dialogue", "Wait", "Face Player", "Interaction / Battle"]:
		_cutscene_action_picker.add_item(action)
	action_row.add_child(_cutscene_action_picker)
	_cutscene_dialogue_picker = OptionButton.new()
	action_row.add_child(_cutscene_dialogue_picker)
	_cutscene_wait_input = SpinBox.new()
	_cutscene_wait_input.min_value = 0.0
	_cutscene_wait_input.max_value = 30.0
	_cutscene_wait_input.step = 0.1
	_cutscene_wait_input.value = 1.0
	action_row.add_child(_cutscene_wait_input)
	action_row.add_child(_make_editor_button("Add Action", _add_cutscene_step))
	_workspace_content.add_child(action_row)
	_cutscene_steps_label = Label.new()
	_cutscene_steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_workspace_content.add_child(_cutscene_steps_label)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("Remove Last Action", _remove_cutscene_step))
	actions.add_child(_make_editor_button("New Cutscene", _new_cutscene_resource))
	actions.add_child(_make_editor_button("Save Cutscene", _save_cutscene_resource))
	_workspace_content.add_child(actions)
	_cutscene_status_label = Label.new()
	_workspace_content.add_child(_cutscene_status_label)
	_refresh_cutscene_workspace()
	_refresh_world_npc_options()

func _build_item_workspace() -> void:
	var template_row := HBoxContainer.new()
	template_row.add_child(_make_section_label("Template"))
	_item_template_picker = OptionButton.new()
	_item_template_picker.add_item("Create from scratch")
	_item_template_picker.set_item_metadata(0, "")
	for template_id in ["resonance_capsule", "potion", "super_potion"]:
		_item_template_picker.add_item(template_id.capitalize().replace("_", " "))
		_item_template_picker.set_item_metadata(_item_template_picker.item_count - 1, template_id)
	template_row.add_child(_item_template_picker)
	_workspace_content.add_child(template_row)
	var identity_row := HBoxContainer.new()
	_item_id_input = LineEdit.new()
	_item_id_input.placeholder_text = "Item ID"
	identity_row.add_child(_item_id_input)
	_item_name_input = LineEdit.new()
	_item_name_input.placeholder_text = "Display name"
	identity_row.add_child(_item_name_input)
	_item_category_picker = OptionButton.new()
	for category in ["Capsules", "Medicine", "Battle Items", "Key Items", "Other"]:
		_item_category_picker.add_item(category)
	identity_row.add_child(_item_category_picker)
	_workspace_content.add_child(identity_row)
	_item_tags_input = LineEdit.new()
	_item_tags_input.placeholder_text = "Tags: capture, consumable, healing"
	_workspace_content.add_child(_item_tags_input)
	_item_effect_input = LineEdit.new()
	_item_effect_input.placeholder_text = "Effect data: capture_multiplier: 1.5"
	_workspace_content.add_child(_item_effect_input)
	var audio_row := HBoxContainer.new()
	audio_row.add_child(_make_section_label("Audio Group"))
	_item_audio_group_picker = OptionButton.new()
	for group in ["Item", "UI", "Pokemon", "Battle", "Stage", "Ambient"]:
		_item_audio_group_picker.add_item(group)
	audio_row.add_child(_item_audio_group_picker)
	_workspace_content.add_child(audio_row)
	_workspace_content.add_child(_make_editor_button("Save Item", _save_item_definition))
	_item_status_label = Label.new()
	_workspace_content.add_child(_item_status_label)

func _save_item_definition() -> void:
	var item_id := _item_id_input.text.strip_edges().to_lower()
	var display_name := _item_name_input.text.strip_edges()
	if item_id.is_empty() or display_name.is_empty():
		_item_status_label.text = "Item ID and display name are required."
		return
	var player := get_tree().get_first_node_in_group("player")
	var bag := player.get_node_or_null("Bag") as ItemBag if player != null else null
	if bag == null:
		_item_status_label.text = "Open a project world before editing items."
		return
	var metadata := {
		"tags": _parse_editor_tags(_item_tags_input.text),
		"effect": _item_effect_input.text.strip_edges(),
		"audio_group": _item_audio_group_picker.get_item_text(_item_audio_group_picker.selected)
	}
	var template_id := str(_item_template_picker.get_item_metadata(_item_template_picker.selected))
	bag.define_item(item_id, display_name, _item_category_picker.get_item_text(_item_category_picker.selected), template_id, metadata)
	_item_status_label.text = "Saved %s" % display_name

func _parse_editor_tags(value: String) -> PackedStringArray:
	var tags := PackedStringArray()
	for entry in value.split(","):
		var tag := entry.strip_edges().to_lower()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	return tags

func _build_ui_workspace() -> void:
	var theme_manager := get_node_or_null("/root/UIThemeManager")
	var theme_data: Dictionary = theme_manager.active_theme if theme_manager != null else {}
	var color_row := HBoxContainer.new()
	_ui_panel_color_input = LineEdit.new()
	_ui_panel_color_input.placeholder_text = "Panel hex"
	_ui_panel_color_input.text = str(theme_data.get("panel_color", "15202b"))
	color_row.add_child(_ui_panel_color_input)
	_ui_accent_color_input = LineEdit.new()
	_ui_accent_color_input.placeholder_text = "Accent hex"
	_ui_accent_color_input.text = str(theme_data.get("accent_color", "67d7ad"))
	color_row.add_child(_ui_accent_color_input)
	_ui_text_color_input = LineEdit.new()
	_ui_text_color_input.placeholder_text = "Text hex"
	_ui_text_color_input.text = str(theme_data.get("text_color", "f4f7f5"))
	color_row.add_child(_ui_text_color_input)
	_workspace_content.add_child(color_row)
	var options_row := HBoxContainer.new()
	options_row.add_child(_make_section_label("Font Scale"))
	_ui_font_scale = SpinBox.new()
	_ui_font_scale.min_value = 0.7
	_ui_font_scale.max_value = 1.6
	_ui_font_scale.step = 0.05
	_ui_font_scale.value = float(theme_data.get("font_scale", 1.0))
	options_row.add_child(_ui_font_scale)
	options_row.add_child(_make_section_label("UI Audio"))
	_ui_audio_group_picker = OptionButton.new()
	for group in ["UI", "Item", "Pokemon", "Battle", "Stage", "Ambient"]:
		_ui_audio_group_picker.add_item(group)
		if group == str(theme_data.get("ui_audio_group", "UI")):
			_ui_audio_group_picker.select(_ui_audio_group_picker.item_count - 1)
	options_row.add_child(_ui_audio_group_picker)
	_workspace_content.add_child(options_row)
	var actions := HBoxContainer.new()
	actions.add_child(_make_editor_button("Preview Theme", _preview_ui_theme))
	actions.add_child(_make_editor_button("Save and Apply", _save_ui_theme))
	_workspace_content.add_child(actions)
	_ui_status_label = Label.new()
	_workspace_content.add_child(_ui_status_label)
	_workspace_content.add_child(HSeparator.new())
	_workspace_content.add_child(_make_section_label("Interface Preview"))
	_ui_preview_panel = PanelContainer.new()
	_ui_preview_panel.custom_minimum_size = Vector2(680, 280)
	_workspace_content.add_child(_ui_preview_panel)
	var preview_layout := VBoxContainer.new()
	preview_layout.add_theme_constant_override("separation", 12)
	_ui_preview_panel.add_child(preview_layout)
	var preview_title := Label.new()
	preview_title.text = "Trainer"
	preview_title.add_theme_font_size_override("font_size", 22)
	preview_layout.add_child(preview_title)
	var hp := ProgressBar.new()
	hp.value = 72
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(0, 20)
	preview_layout.add_child(hp)
	var dialogue := Label.new()
	dialogue.text = "A dialogue panel, health display, bag, move choices, and battle controls share this project theme."
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_layout.add_child(dialogue)
	var buttons := HBoxContainer.new()
	for label in ["Fight", "Bag", "Pokemon", "Run"]:
		var button := Button.new()
		button.text = label
		buttons.add_child(button)
	preview_layout.add_child(buttons)
	_preview_ui_theme()

func _get_ui_editor_theme_data() -> Dictionary:
	return {
		"panel_color": _ui_panel_color_input.text.strip_edges().trim_prefix("#"),
		"accent_color": _ui_accent_color_input.text.strip_edges().trim_prefix("#"),
		"text_color": _ui_text_color_input.text.strip_edges().trim_prefix("#"),
		"font_scale": _ui_font_scale.value,
		"ui_audio_group": _ui_audio_group_picker.get_item_text(_ui_audio_group_picker.selected)
	}

func _preview_ui_theme() -> void:
	if _ui_preview_panel == null:
		return
	var theme_data := _get_ui_editor_theme_data()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#" + str(theme_data.panel_color))
	style.border_color = Color("#" + str(theme_data.accent_color))
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	_ui_preview_panel.add_theme_stylebox_override("panel", style)
	_apply_preview_theme(_ui_preview_panel, Color("#" + str(theme_data.text_color)), float(theme_data.font_scale))
	_ui_status_label.text = "Preview updated."

func _apply_preview_theme(node: Node, text_color: Color, font_scale: float) -> void:
	if node is Label or node is Button:
		node.add_theme_color_override("font_color", text_color)
		var base_size: int = node.get_theme_font_size("font_size")
		if base_size > 0:
			node.add_theme_font_size_override("font_size", roundi(base_size * font_scale))
	for child in node.get_children():
		_apply_preview_theme(child, text_color, font_scale)

func _save_ui_theme() -> void:
	var theme_manager := get_node_or_null("/root/UIThemeManager")
	if theme_manager == null:
		_ui_status_label.text = "UI theme manager is unavailable."
		return
	var theme_data := _get_ui_editor_theme_data()
	for color_key in ["panel_color", "accent_color", "text_color"]:
		if not Color.html_is_valid("#" + str(theme_data[color_key])):
			_ui_status_label.text = "Enter valid six-digit hex colors."
			return
	theme_manager.save_theme(theme_data)
	_ui_status_label.text = "Theme saved and applied to the current game UI."

func _refresh_pokemon_workspace() -> void:
	if _pokemon_picker == null:
		return
	_pokemon_picker.clear()
	for profile in _available_profiles:
		_pokemon_picker.add_item(profile.species_name)
		_pokemon_picker.set_item_metadata(_pokemon_picker.item_count - 1, profile)
	if _pokemon_picker.item_count > 0:
		_pokemon_picker.select(0)
		_show_selected_pokemon(0)
	elif _pokemon_details != null:
		_pokemon_details.text = "No Pokemon profiles are available in this project."

func _refresh_npc_workspace() -> void:
	if _npc_picker == null:
		return
	_load_npc_profiles_from_folder()
	_npc_picker.clear()
	for profile in _available_npc_profiles:
		_npc_picker.add_item(profile.npc_name)
		_npc_picker.set_item_metadata(_npc_picker.item_count - 1, profile)
	if _npc_picker.item_count > 0:
		_npc_picker.select(0)
		_show_selected_npc(0)
	elif _npc_details != null:
		_npc_details.text = "No NPC profiles are available in this project. Create one to begin."

func _load_npc_profiles_from_folder() -> void:
	_available_npc_profiles.clear()
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("npcs") if project_manager != null else ""
	if folder.is_empty():
		return
	var directory := DirAccess.open(folder)
	if directory != null:
		directory.list_dir_begin()
		var file_name := directory.get_next()
		while not file_name.is_empty():
			if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
				var resource := load(folder.path_join(file_name))
				if resource is NPCProfile:
					_available_npc_profiles.append(resource)
			file_name = directory.get_next()
		directory.list_dir_end()

func _load_dialogues_from_folder() -> void:
	_available_dialogues.clear()
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("dialogues") if project_manager != null else ""
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource := load(folder.path_join(file_name))
			if resource is DialogueResource:
				_available_dialogues.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()

func _refresh_npc_dialogue_picker() -> void:
	if _npc_dialogue_picker == null:
		return
	_npc_dialogue_picker.clear()
	_npc_dialogue_picker.add_item("Use embedded dialogue")
	_npc_dialogue_picker.set_item_metadata(0, null)
	for resource in _available_dialogues:
		_npc_dialogue_picker.add_item(resource.display_name)
		_npc_dialogue_picker.set_item_metadata(_npc_dialogue_picker.item_count - 1, resource)

func _refresh_dialogue_workspace() -> void:
	if _dialogue_picker == null:
		return
	_load_dialogues_from_folder()
	_dialogue_picker.clear()
	for resource in _available_dialogues:
		_dialogue_picker.add_item(resource.display_name)
		_dialogue_picker.set_item_metadata(_dialogue_picker.item_count - 1, resource)
	if _dialogue_picker.item_count > 0:
		_dialogue_picker.select(0)
		_show_selected_dialogue(0)

func _show_selected_dialogue(index: int) -> void:
	if _dialogue_picker == null:
		return
	var resource := _dialogue_picker.get_item_metadata(index) as DialogueResource
	if resource == null:
		return
	_dialogue_editing_resource = resource
	_dialogue_editing_path = resource.resource_path
	_dialogue_name_input.text = resource.display_name
	_dialogue_speaker_input.text = resource.speaker_name
	_dialogue_lines_input.text = "\n".join(resource.lines)
	for group_index in _dialogue_audio_group_picker.item_count:
		if _dialogue_audio_group_picker.get_item_text(group_index) == resource.audio_group:
			_dialogue_audio_group_picker.select(group_index)
			break

func _new_dialogue_resource() -> void:
	_dialogue_editing_resource = DialogueResource.new()
	_dialogue_editing_path = ""
	_dialogue_name_input.text = "New Dialogue"
	_dialogue_speaker_input.text = ""
	_dialogue_lines_input.text = "Hello there!"
	_dialogue_audio_group_picker.select(0)
	_dialogue_status_label.text = "New dialogue asset ready to save."

func _save_dialogue_resource() -> void:
	if _dialogue_editing_resource == null:
		_new_dialogue_resource()
	var display_name := _dialogue_name_input.text.strip_edges()
	var lines := _parse_npc_dialogue(_dialogue_lines_input.text)
	if display_name.is_empty() or lines.is_empty():
		_dialogue_status_label.text = "A dialogue name and at least one line are required."
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("dialogues") if project_manager != null else ""
	if folder.is_empty():
		_dialogue_status_label.text = "Open a project before saving dialogue."
		return
	_dialogue_editing_resource.display_name = display_name
	_dialogue_editing_resource.speaker_name = _dialogue_speaker_input.text.strip_edges()
	_dialogue_editing_resource.lines = lines
	_dialogue_editing_resource.audio_group = _dialogue_audio_group_picker.get_item_text(_dialogue_audio_group_picker.selected)
	if _dialogue_editing_path.is_empty():
		_dialogue_editing_path = folder.path_join(_safe_dialogue_file_name(display_name) + ".tres")
	var error := ResourceSaver.save(_dialogue_editing_resource, _dialogue_editing_path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_dialogue_status_label.text = "Save failed: %s" % error_string(error)
		return
	_dialogue_status_label.text = "Saved %s" % display_name
	_load_dialogues_from_folder()
	_refresh_npc_dialogue_picker()
	_refresh_dialogue_workspace()

func _safe_dialogue_file_name(value: String) -> String:
	var safe_name := ""
	for character in value.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_name += character
	return safe_name if not safe_name.is_empty() else "new_dialogue"

func _load_cutscenes_from_folder() -> void:
	_available_cutscenes.clear()
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("cutscenes") if project_manager != null else ""
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource := load(folder.path_join(file_name))
			if resource is Resource and resource.get_script() == CutsceneResourceScript:
				_available_cutscenes.append(resource)
		file_name = directory.get_next()
	directory.list_dir_end()

func _refresh_npc_cutscene_picker() -> void:
	if _npc_cutscene_picker == null:
		return
	_npc_cutscene_picker.clear()
	_npc_cutscene_picker.add_item("No cutscene")
	_npc_cutscene_picker.set_item_metadata(0, null)
	for resource in _available_cutscenes:
		_npc_cutscene_picker.add_item(str(resource.get("display_name")))
		_npc_cutscene_picker.set_item_metadata(_npc_cutscene_picker.item_count - 1, resource)

func _refresh_cutscene_workspace() -> void:
	if _cutscene_picker == null:
		return
	_load_cutscenes_from_folder()
	_cutscene_picker.clear()
	for resource in _available_cutscenes:
		_cutscene_picker.add_item(str(resource.get("display_name")))
		_cutscene_picker.set_item_metadata(_cutscene_picker.item_count - 1, resource)
	_cutscene_dialogue_picker.clear()
	for resource in _available_dialogues:
		_cutscene_dialogue_picker.add_item(resource.display_name)
		_cutscene_dialogue_picker.set_item_metadata(_cutscene_dialogue_picker.item_count - 1, resource)
	if _cutscene_picker.item_count > 0:
		_cutscene_picker.select(0)
		_show_selected_cutscene(0)
	else:
		_new_cutscene_resource()

func _show_selected_cutscene(index: int) -> void:
	if _cutscene_picker == null:
		return
	var resource := _cutscene_picker.get_item_metadata(index) as Resource
	if resource == null:
		return
	_cutscene_editing_resource = resource
	_cutscene_editing_path = resource.resource_path
	_cutscene_name_input.text = str(resource.get("display_name"))
	_refresh_cutscene_steps()

func _new_cutscene_resource() -> void:
	_cutscene_editing_resource = CutsceneResourceScript.new() as Resource
	_cutscene_editing_path = ""
	if _cutscene_name_input != null:
		_cutscene_name_input.text = "New Cutscene"
	_refresh_cutscene_steps()
	if _cutscene_status_label != null:
		_cutscene_status_label.text = "New cutscene ready to edit."

func _add_cutscene_step() -> void:
	if _cutscene_editing_resource == null:
		_new_cutscene_resource()
	var action_index := _cutscene_action_picker.selected
	var step: Dictionary = {}
	match action_index:
		0:
			if _cutscene_dialogue_picker.item_count == 0:
				_cutscene_status_label.text = "Create a dialogue asset before adding dialogue."
				return
			var dialogue := _cutscene_dialogue_picker.get_item_metadata(_cutscene_dialogue_picker.selected) as DialogueResource
			if dialogue == null or dialogue.resource_path.is_empty():
				_cutscene_status_label.text = "Save the dialogue asset before using it in a cutscene."
				return
			step = {"type": "dialogue", "dialogue_path": dialogue.resource_path}
		1:
			step = {"type": "wait", "seconds": _cutscene_wait_input.value}
		2:
			step = {"type": "face_player"}
		3:
			step = {"type": "interaction"}
	var steps: Array = _cutscene_editing_resource.get("steps")
	steps.append(step)
	_cutscene_editing_resource.set("steps", steps)
	_refresh_cutscene_steps()

func _remove_cutscene_step() -> void:
	if _cutscene_editing_resource == null or (_cutscene_editing_resource.get("steps") as Array).is_empty():
		return
	var steps: Array = _cutscene_editing_resource.get("steps")
	steps.pop_back()
	_cutscene_editing_resource.set("steps", steps)
	_refresh_cutscene_steps()

func _refresh_cutscene_steps() -> void:
	if _cutscene_steps_label == null:
		return
	var steps: Array = _cutscene_editing_resource.get("steps") if _cutscene_editing_resource != null else []
	if steps.is_empty():
		_cutscene_steps_label.text = "No actions yet. Add dialogue, a wait, a facing action, or an interaction/battle trigger."
		return
	var labels: PackedStringArray = []
	for step_index in steps.size():
		var step: Dictionary = steps[step_index]
		var description := str(step.get("type", "action")).capitalize()
		if step.get("type") == "dialogue":
			description = "Dialogue: %s" % str(step.get("dialogue_path", "")).get_file().get_basename()
		elif step.get("type") == "wait":
			description = "Wait: %.1f seconds" % float(step.get("seconds", 0.0))
		elif step.get("type") == "interaction":
			description = "Interaction / Battle"
		labels.append("%d. %s" % [step_index + 1, description])
	_cutscene_steps_label.text = "\n".join(labels)

func _save_cutscene_resource() -> void:
	if _cutscene_editing_resource == null:
		_new_cutscene_resource()
	var display_name := _cutscene_name_input.text.strip_edges()
	var steps: Array = _cutscene_editing_resource.get("steps")
	if display_name.is_empty() or steps.is_empty():
		_cutscene_status_label.text = "A cutscene name and at least one action are required."
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("cutscenes") if project_manager != null else ""
	if folder.is_empty():
		_cutscene_status_label.text = "Open a project before saving a cutscene."
		return
	_cutscene_editing_resource.display_name = display_name
	if _cutscene_editing_path.is_empty():
		_cutscene_editing_path = folder.path_join(_safe_cutscene_file_name(display_name) + ".tres")
	var error := ResourceSaver.save(_cutscene_editing_resource, _cutscene_editing_path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_cutscene_status_label.text = "Save failed: %s" % error_string(error)
		return
	_cutscene_status_label.text = "Saved %s" % display_name
	_load_cutscenes_from_folder()
	_refresh_npc_cutscene_picker()
	_refresh_cutscene_workspace()

func _safe_cutscene_file_name(value: String) -> String:
	var safe_name := ""
	for character in value.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_name += character
	return safe_name if not safe_name.is_empty() else "new_cutscene"

func _show_selected_npc(index: int) -> void:
	if _npc_picker == null or _npc_details == null:
		return
	var profile := _npc_picker.get_item_metadata(index) as NPCProfile
	if profile == null:
		return
	_npc_editing_profile = profile
	_npc_editing_path = profile.resource_path
	_npc_name_input.text = profile.npc_name
	_npc_dialogue_input.text = "\n".join(profile.dialogue)
	_refresh_npc_dialogue_picker()
	for dialogue_index in _npc_dialogue_picker.item_count:
		if _npc_dialogue_picker.get_item_metadata(dialogue_index) == profile.dialogue_sequence:
			_npc_dialogue_picker.select(dialogue_index)
			break
	_refresh_npc_cutscene_picker()
	for cutscene_index in _npc_cutscene_picker.item_count:
		if _npc_cutscene_picker.get_item_metadata(cutscene_index) == profile.cutscene_sequence:
			_npc_cutscene_picker.select(cutscene_index)
			break
	_refresh_npc_trainer_battle_picker()
	for battle_index in _npc_trainer_battle_picker.item_count:
		if _npc_trainer_battle_picker.get_item_metadata(battle_index) == profile.trainer_battle:
			_npc_trainer_battle_picker.select(battle_index)
			break
	_npc_direction_picker.select(_direction_to_index(profile.default_direction))
	var behavior_path := profile.character_script.resource_path if profile.character_script != null else "res://npc_behavior.gd"
	for behavior_index in _npc_behavior_picker.item_count:
		if str(_npc_behavior_picker.get_item_metadata(behavior_index)) == behavior_path:
			_npc_behavior_picker.select(behavior_index)
			break
	_npc_details.text = "%s\n\nBehavior: %s\nFacing: %s\nDialogue lines: %d" % [
		profile.npc_name,
		_npc_behavior_picker.get_item_text(_npc_behavior_picker.selected),
		_npc_direction_picker.get_item_text(_npc_direction_picker.selected),
		profile.dialogue.size()
	]

func _new_npc_profile() -> void:
	_npc_editing_profile = NPCProfile.new()
	_npc_editing_profile.npc_name = "New NPC"
	_npc_editing_profile.dialogue = ["Hello there!"]
	_npc_editing_profile.default_direction = Vector2.DOWN
	_npc_editing_profile.character_script = load("res://npc_behavior.gd")
	_npc_editing_path = ""
	_npc_name_input.text = _npc_editing_profile.npc_name
	_npc_dialogue_input.text = "Hello there!"
	_refresh_npc_dialogue_picker()
	_refresh_npc_cutscene_picker()
	_refresh_npc_trainer_battle_picker()
	_npc_direction_picker.select(0)
	_npc_behavior_picker.select(0)
	_npc_status_label.text = "New NPC ready to save."

func _save_npc_profile() -> void:
	if _npc_editing_profile == null:
		return
	var npc_name := _npc_name_input.text.strip_edges()
	if npc_name.is_empty():
		_npc_status_label.text = "NPC display name is required."
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("npcs") if project_manager != null else ""
	if folder.is_empty():
		_npc_status_label.text = "Open a project before saving NPC profiles."
		return
	_npc_editing_profile.npc_name = npc_name
	_npc_editing_profile.dialogue = _parse_npc_dialogue(_npc_dialogue_input.text)
	_npc_editing_profile.dialogue_sequence = _npc_dialogue_picker.get_item_metadata(_npc_dialogue_picker.selected) as DialogueResource
	_npc_editing_profile.cutscene_sequence = _npc_cutscene_picker.get_item_metadata(_npc_cutscene_picker.selected) as Resource
	_npc_editing_profile.trainer_battle = _npc_trainer_battle_picker.get_item_metadata(_npc_trainer_battle_picker.selected) as Resource
	_npc_editing_profile.default_direction = _index_to_direction(_npc_direction_picker.selected)
	_npc_editing_profile.character_script = load(str(_npc_behavior_picker.get_item_metadata(_npc_behavior_picker.selected)))
	if _npc_editing_path.is_empty():
		_npc_editing_path = folder.path_join(_safe_npc_file_name(npc_name) + ".tres")
	var error := ResourceSaver.save(_npc_editing_profile, _npc_editing_path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_npc_status_label.text = "Save failed: %s" % error_string(error)
		return
	_npc_status_label.text = "Saved %s" % npc_name
	_refresh_npc_workspace()

func _parse_npc_dialogue(value: String) -> Array[String]:
	var lines: Array[String] = []
	for entry in value.split("\n"):
		var line := entry.strip_edges()
		if not line.is_empty():
			lines.append(line)
	return lines

func _direction_to_index(direction: Vector2) -> int:
	if direction == Vector2.LEFT:
		return 1
	if direction == Vector2.RIGHT:
		return 2
	if direction == Vector2.UP:
		return 3
	return 0

func _index_to_direction(index: int) -> Vector2:
	return [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP][clampi(index, 0, 3)]

func _safe_npc_file_name(value: String) -> String:
	var safe_name := ""
	for character in value.to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_name += character
	return safe_name if not safe_name.is_empty() else "new_npc"

func _show_selected_pokemon(index: int) -> void:
	if _pokemon_picker == null or _pokemon_details == null:
		return
	var profile := _pokemon_picker.get_item_metadata(index) as MonsterProfile
	if profile == null:
		_pokemon_details.text = "No Pokemon profile selected."
		return
	_pokemon_editing_profile = profile
	_pokemon_editing_path = profile.resource_path
	if _pokemon_id_input != null:
		_pokemon_id_input.text = profile.species_id
		_pokemon_name_input.text = profile.species_name
		_pokemon_types_input.text = ", ".join(profile.type_ids)
		_pokemon_stats_input.text = _pokemon_stats_to_text(profile.base_stats)
	var stats := profile.base_stats
	var move_names: PackedStringArray = []
	for move in profile.learnable_moves:
		move_names.append("%s Lv.%d" % [move.move_name, move.learn_level])
	_pokemon_details.text = "%s  #%d\n\nTypes: %s\nMax level: %d   Catch rate: %d   Base EXP: %d\n\nBase Stats\nHP %d   Attack %d   Defense %d\nSp. Attack %d   Sp. Defense %d   Speed %d\n\nMoves\n%s\n\nAbilities\n%d configured   Evolutions %d configured" % [
		profile.species_name, profile.national_dex_id,
		", ".join(profile.type_ids), profile.max_level, profile.catch_rate, profile.base_experience_yield,
		int(stats.get("hp", 0)), int(stats.get("attack", 0)), int(stats.get("defense", 0)),
		int(stats.get("special_attack", 0)), int(stats.get("special_defense", 0)), int(stats.get("speed", 0)),
		", ".join(move_names) if not move_names.is_empty() else "No moves configured",
		profile.abilities.size(), profile.evolutions.size()
	]

func _new_pokemon_profile() -> void:
	_pokemon_editing_profile = MonsterProfile.new()
	_pokemon_editing_profile.species_id = "new_pokemon"
	_pokemon_editing_profile.species_name = "New Pokemon"
	_pokemon_editing_path = ""
	_pokemon_id_input.text = _pokemon_editing_profile.species_id
	_pokemon_name_input.text = _pokemon_editing_profile.species_name
	_pokemon_types_input.text = "normal"
	_pokemon_stats_input.text = _pokemon_stats_to_text(_pokemon_editing_profile.base_stats)
	_pokemon_status_label.text = "New Pokemon ready to save."

func _save_pokemon_profile() -> void:
	if _pokemon_editing_profile == null:
		return
	var species_id := _pokemon_id_input.text.strip_edges().to_lower()
	var species_name := _pokemon_name_input.text.strip_edges()
	if species_id.is_empty() or species_name.is_empty():
		_pokemon_status_label.text = "Species ID and name are required."
		return
	var project_manager := get_node_or_null("/root/ProjectManager")
	var folder: String = project_manager.get_active_content_dir("monsters") if project_manager != null else ""
	if folder.is_empty():
		_pokemon_status_label.text = "Open a project before saving Pokemon."
		return
	_pokemon_editing_profile.species_id = species_id
	_pokemon_editing_profile.species_name = species_name
	_pokemon_editing_profile.type_ids = _parse_pokemon_types(_pokemon_types_input.text)
	_pokemon_editing_profile.base_stats = _parse_pokemon_stats(_pokemon_stats_input.text)
	if _pokemon_editing_path.is_empty():
		_pokemon_editing_path = folder.path_join(_safe_pokemon_file_name(species_id) + ".tres")
	var error := ResourceSaver.save(_pokemon_editing_profile, _pokemon_editing_path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		_pokemon_status_label.text = "Save failed: %s" % error_string(error)
		return
	_pokemon_status_label.text = "Saved %s" % _pokemon_editing_profile.species_name
	_load_profiles_from_folder()
	_refresh_pokemon_workspace()

func _parse_pokemon_types(value: String) -> Array[String]:
	var result: Array[String] = []
	for entry in value.split(","):
		var type_id := entry.strip_edges().to_lower()
		if not type_id.is_empty() and result.size() < 2:
			result.append(type_id)
	return result if not result.is_empty() else ["normal"]

func _parse_pokemon_stats(value: String) -> Dictionary:
	var stats := {"hp": 1, "attack": 1, "defense": 1, "special_attack": 1, "special_defense": 1, "speed": 1}
	for entry in value.split(","):
		var parts := entry.split(":")
		if parts.size() == 2:
			var stat_name := parts[0].strip_edges()
			if stats.has(stat_name):
				stats[stat_name] = maxi(0, parts[1].strip_edges().to_int())
	return stats

func _pokemon_stats_to_text(stats: Dictionary) -> String:
	return "hp: %d, attack: %d, defense: %d, special_attack: %d, special_defense: %d, speed: %d" % [
		int(stats.get("hp", 1)), int(stats.get("attack", 1)), int(stats.get("defense", 1)),
		int(stats.get("special_attack", 1)), int(stats.get("special_defense", 1)), int(stats.get("speed", 1))
	]

func _safe_pokemon_file_name(value: String) -> String:
	var safe_name := ""
	for character in value:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			safe_name += character
	return safe_name if not safe_name.is_empty() else "new_pokemon"

func _sync_selection_inspector() -> void:
	if _selection_label == null:
		return
	var terrain_map := get_tree().get_first_node_in_group("terrain_map") as TerrainMap
	var selected := terrain_map.get_selected_object() if terrain_map != null else null
	if selected == null or not is_instance_valid(selected):
		_selection_label.text = "No object selected"
		_last_resource_object = null
		return
	var resource = terrain_map.get_selected_world_resource()
	if selected != _last_resource_object:
		_last_resource_object = selected
		_refresh_selected_asset_picker()
		if _selected_tags_input != null:
			_selected_tags_input.text = ", ".join(resource.tags) if resource != null else ""
	_selection_label.text = "%s\n\nPosition  X %.2f  Y %.2f  Z %.2f\nRotation  X %.1f  Y %.1f  Z %.1f\nScale  X %.2f  Y %.2f  Z %.2f" % [
		selected.name,
		selected.position.x, selected.position.y, selected.position.z,
		selected.rotation_degrees.x, selected.rotation_degrees.y, selected.rotation_degrees.z,
		selected.scale.x, selected.scale.y, selected.scale.z
	]

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 30
	_hud.visible = false
	add_child(_hud)

	_hud_panel = Panel.new()
	_hud_panel.position = Vector2(24, 24)
	_hud_panel.size = Vector2(320, 340)
	_hud_panel.custom_minimum_size = HUD_MIN_SIZE
	_hud.add_child(_hud_panel)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_panel.add_child(layout)

	var title_bar := PanelContainer.new()
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_bar_input)
	layout.add_child(title_bar)
	var title := Label.new()
	title.text = "Edit Mode"
	title.add_theme_font_size_override("font_size", 18)
	title_bar.add_child(title)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_make_section_label("Camera"))
	var camera_hint := Label.new()
	camera_hint.text = "Arrow keys move   Q/E rise and descend   Middle drag turns   Shift boosts"
	camera_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(camera_hint)

	root.add_child(HSeparator.new())
	root.add_child(_make_section_label("Blocks"))
	var cursor_mode_row := HBoxContainer.new()
	cursor_mode_row.add_theme_constant_override("separation", 6)
	root.add_child(cursor_mode_row)
	var cursor_mode_group := ButtonGroup.new()
	_select_mode_button = Button.new()
	_select_mode_button.text = "Select"
	_select_mode_button.toggle_mode = true
	_select_mode_button.button_group = cursor_mode_group
	_select_mode_button.pressed.connect(_set_cursor_mode.bind(TerrainMap.CURSOR_SELECT))
	cursor_mode_row.add_child(_select_mode_button)
	_place_mode_button = Button.new()
	_place_mode_button.text = "Place"
	_place_mode_button.toggle_mode = true
	_place_mode_button.button_pressed = true
	_place_mode_button.button_group = cursor_mode_group
	_place_mode_button.pressed.connect(_set_cursor_mode.bind(TerrainMap.CURSOR_PLACE))
	cursor_mode_row.add_child(_place_mode_button)
	var block_row := HBoxContainer.new()
	block_row.add_theme_constant_override("separation", 6)
	root.add_child(block_row)
	var block_type_group := ButtonGroup.new()
	_cube_button = Button.new()
	_cube_button.text = "Cube"
	_cube_button.toggle_mode = true
	_cube_button.button_pressed = true
	_cube_button.button_group = block_type_group
	_cube_button.pressed.connect(_select_block_type.bind(TerrainMap.BLOCK_CUBE))
	block_row.add_child(_cube_button)
	_slope_button = Button.new()
	_slope_button.text = "Slope"
	_slope_button.toggle_mode = true
	_slope_button.button_group = block_type_group
	_slope_button.pressed.connect(_select_block_type.bind(TerrainMap.BLOCK_SLOPE))
	block_row.add_child(_slope_button)
	var block_hint := Label.new()
	block_hint.text = "Left click: place   Right click: remove   Scroll wheel: rotate"
	block_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(block_hint)
	_grid_toggle = CheckButton.new()
	_grid_toggle.text = "Show 3D Grid"
	_grid_toggle.toggled.connect(_set_show_3d_grid)
	root.add_child(_grid_toggle)

	var rotate_row := HBoxContainer.new()
	rotate_row.add_theme_constant_override("separation", 6)
	root.add_child(rotate_row)
	var rotate_left_button := Button.new()
	rotate_left_button.text = "Rotate Left"
	rotate_left_button.pressed.connect(_rotate_selected.bind(-90))
	rotate_row.add_child(rotate_left_button)
	var rotate_right_button := Button.new()
	rotate_right_button.text = "Rotate Right"
	rotate_right_button.pressed.connect(_rotate_selected.bind(90))
	rotate_row.add_child(rotate_right_button)

	root.add_child(_make_section_label("Selected Block"))
	var move_x_row := HBoxContainer.new()
	root.add_child(move_x_row)
	_add_transform_button(move_x_row, "Move X-", _move_selected_block.bind(Vector3i.LEFT))
	_add_transform_button(move_x_row, "Move X+", _move_selected_block.bind(Vector3i.RIGHT))
	var move_y_row := HBoxContainer.new()
	root.add_child(move_y_row)
	_add_transform_button(move_y_row, "Move Down", _move_selected_block.bind(Vector3i.DOWN))
	_add_transform_button(move_y_row, "Move Up", _move_selected_block.bind(Vector3i.UP))
	var move_z_row := HBoxContainer.new()
	root.add_child(move_z_row)
	_add_transform_button(move_z_row, "Move Z-", _move_selected_block.bind(Vector3i.FORWARD))
	_add_transform_button(move_z_row, "Move Z+", _move_selected_block.bind(Vector3i.BACK))
	var resize_x_row := HBoxContainer.new()
	root.add_child(resize_x_row)
	_add_transform_button(resize_x_row, "Resize X-", _resize_selected_block.bind(Vector3i.LEFT))
	_add_transform_button(resize_x_row, "Resize X+", _resize_selected_block.bind(Vector3i.RIGHT))
	var resize_y_row := HBoxContainer.new()
	root.add_child(resize_y_row)
	_add_transform_button(resize_y_row, "Resize Y-", _resize_selected_block.bind(Vector3i.DOWN))
	_add_transform_button(resize_y_row, "Resize Y+", _resize_selected_block.bind(Vector3i.UP))
	var resize_z_row := HBoxContainer.new()
	root.add_child(resize_z_row)
	_add_transform_button(resize_z_row, "Resize Z-", _resize_selected_block.bind(Vector3i.FORWARD))
	_add_transform_button(resize_z_row, "Resize Z+", _resize_selected_block.bind(Vector3i.BACK))

	root.add_child(HSeparator.new())
	root.add_child(_make_section_label("Monsters"))
	_species_options = OptionButton.new()
	root.add_child(_species_options)
	var place_monster_button := Button.new()
	place_monster_button.text = "Place Pokemon Here (Enter)"
	place_monster_button.pressed.connect(_place_monster_under_mouse)
	root.add_child(place_monster_button)
	var place_player_button := Button.new()
	place_player_button.text = "Place Player Here (P)"
	place_player_button.pressed.connect(_place_player_under_mouse)
	root.add_child(place_player_button)

	root.add_child(HSeparator.new())
	var exit_button := Button.new()
	exit_button.text = "Exit Edit Mode (F5)"
	exit_button.pressed.connect(func() -> void: _set_active(false))
	root.add_child(exit_button)

	var resize_handle := ColorRect.new()
	resize_handle.color = Color(1.0, 1.0, 1.0, 0.35)
	resize_handle.custom_minimum_size = Vector2(14, 14)
	resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	resize_handle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	resize_handle.gui_input.connect(_on_resize_handle_input)
	_hud_panel.add_child(resize_handle)

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button_event.pressed
			if button_event.pressed:
				_drag_offset = _hud_panel.position - button_event.global_position
	elif event is InputEventMouseMotion and _dragging:
		var motion_event := event as InputEventMouseMotion
		_hud_panel.position = motion_event.global_position + _drag_offset

func _on_resize_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			_resizing = button_event.pressed
			if button_event.pressed:
				_resize_start_size = _hud_panel.size
				_resize_start_mouse = button_event.global_position
	elif event is InputEventMouseMotion and _resizing:
		var motion_event := event as InputEventMouseMotion
		var delta := motion_event.global_position - _resize_start_mouse
		_hud_panel.size = Vector2(
			maxf(HUD_MIN_SIZE.x, _resize_start_size.x + delta.x),
			maxf(HUD_MIN_SIZE.y, _resize_start_size.y + delta.y)
		)

func toggle() -> void:
	_set_active(not active)
