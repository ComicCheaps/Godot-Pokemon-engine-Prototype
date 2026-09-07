extends Node3D
class_name TerrainMap

const WorldObjectResourceScript = preload("res://world_object_resource.gd")
const BLOCK_CUBE: int = 0
const BLOCK_SLOPE: int = 1
const CURSOR_SELECT: int = 0
const CURSOR_PLACE: int = 1
const EDITABLE_WORLD_OBJECT_GROUP := &"editable_world_object"
const HISTORY_LIMIT := 100
const GIZMO_MOVE: int = 0
const GIZMO_ROTATE: int = 1
const GIZMO_SCALE: int = 2

@export var grid_size: float = 0.5
@export var block_height: float = 0.5
@export var edit_mode: bool = false
@export var selected_block: int = BLOCK_CUBE
@export var texture: Texture2D

var selected_rotation: int = 0
var cursor_mode: int = CURSOR_PLACE
var _blocks: Dictionary = {}
var _ghost: MeshInstance3D
var _gizmo: MeshInstance3D
var _material: StandardMaterial3D
var _selected_node: Node3D
var _editable_world_objects: Array[Node3D] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var gizmo_mode: int = GIZMO_MOVE
var _gizmo_drag_axis := Vector3.ZERO
var _gizmo_drag_start_mouse := Vector2.ZERO
var _gizmo_drag_start_position := Vector3.ZERO
var _gizmo_drag_start_rotation := Basis.IDENTITY
var _gizmo_drag_start_scale := Vector3.ONE
var _gizmo_drag_start_angle := 0.0
var _gizmo_dragging := false
var _gizmo_drag_changed := false
var _gizmo_hover_axis := Vector3.ZERO

func _ready() -> void:
	add_to_group("terrain_map")
	# Edit mode pauses the tree, so keep receiving input while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	if texture != null:
		_material.albedo_texture = texture
	_material.roughness = 0.85
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.billboard_keep_scale = false
	_create_ghost()
	_create_gizmo()
	_register_editable_world_objects()
	_update_ghost_visibility()
	_load_structures()

func set_edit_mode(value: bool) -> void:
	edit_mode = value
	_update_ghost_visibility()

func get_ground_point_from_mouse() -> Vector3:
	return _get_grid_point_from_mouse()

func get_player_placement_point_from_mouse(ground_height: float) -> Vector3:
	var point := _get_grid_point_from_mouse()
	if point == Vector3.INF:
		return Vector3.INF
	return Vector3(point.x, ground_height, point.z)

func _input(event: InputEvent) -> void:
	if not edit_mode:
		return

	if event is InputEventMouseMotion:
		if _gizmo_dragging:
			_update_gizmo_drag(event.position)
			get_viewport().set_input_as_handled()
			return
		_update_gizmo_hover(event.position)
		_update_ghost_position()
		return

	if event is InputEventMouseButton:
		# Don't let clicks that land on the edit-mode HUD also place/remove/rotate blocks.
		if get_viewport().gui_get_hovered_control() != null:
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _gizmo_dragging:
			_end_gizmo_drag()
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _begin_gizmo_drag(event.position):
				get_viewport().set_input_as_handled()
				return
			if cursor_mode == CURSOR_SELECT:
				_select_block_under_mouse()
			else:
				_place_selected_block_under_mouse()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_block_under_mouse()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rotate_selected(90)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rotate_selected(-90)

func _begin_gizmo_drag(mouse_position: Vector2) -> bool:
	if _selected_node == null or not is_instance_valid(_selected_node) or _gizmo == null or not _gizmo.visible:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var axis := _get_gizmo_axis_at_mouse(camera, mouse_position)
	if axis == Vector3.ZERO:
		return false
	_gizmo_drag_axis = axis
	_gizmo_drag_start_mouse = mouse_position
	_gizmo_drag_start_position = _selected_node.global_position
	_gizmo_drag_start_rotation = _selected_node.global_transform.basis
	_gizmo_drag_start_scale = _selected_node.scale
	_gizmo_drag_start_angle = (mouse_position - camera.unproject_position(_selected_node.global_position)).angle()
	_gizmo_dragging = true
	_gizmo_drag_changed = false
	return true

func _end_gizmo_drag() -> void:
	_gizmo_dragging = false
	_gizmo_drag_axis = Vector3.ZERO
	if _gizmo_drag_changed:
		_save_structures()
		_save_editable_world_object_changes()
	_update_gizmo()

func _get_gizmo_axis_at_mouse(camera: Camera3D, mouse_position: Vector2) -> Vector3:
	var origin := camera.unproject_position(_gizmo.global_position)
	var axes := [_gizmo.global_basis.x.normalized(), _gizmo.global_basis.y.normalized(), _gizmo.global_basis.z.normalized()]
	var best_axis := Vector3.ZERO
	var best_distance := 28.0
	for axis in axes:
		var endpoint := camera.unproject_position(_gizmo.global_position + axis * 0.8)
		if gizmo_mode == GIZMO_ROTATE:
			var ring_radius := origin.distance_to(endpoint)
			var distance := absf(mouse_position.distance_to(origin) - ring_radius)
			if distance < best_distance:
				best_distance = distance
				best_axis = axis
		else:
			var closest := Geometry2D.get_closest_point_to_segment(mouse_position, origin, endpoint)
			var distance := mouse_position.distance_to(closest)
			if distance < best_distance:
				best_distance = distance
				best_axis = axis
	return best_axis

func _update_gizmo_drag(mouse_position: Vector2) -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		_end_gizmo_drag()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.unproject_position(_gizmo_drag_start_position)
	var endpoint := camera.unproject_position(_gizmo_drag_start_position + _gizmo_drag_axis * 0.8)
	if gizmo_mode == GIZMO_ROTATE:
		var angle := (mouse_position - origin).angle() - _gizmo_drag_start_angle
		angle = snappedf(angle, deg_to_rad(15.0))
		if is_zero_approx(angle):
			return
		_record_gizmo_undo_state()
		var rotation_basis := Basis(_gizmo_drag_axis, angle) * _gizmo_drag_start_rotation
		var selected_transform := _selected_node.global_transform
		selected_transform.basis = rotation_basis
		_selected_node.global_transform = selected_transform
		_selected_node.set_meta("rotation", int(round(_selected_node.rotation_degrees.y)))
	elif gizmo_mode == GIZMO_SCALE:
		var scale_delta := _get_gizmo_drag_amount(mouse_position, origin, endpoint) * 0.75
		var axis_index := _get_axis_index(_gizmo_drag_axis)
		var new_scale := _gizmo_drag_start_scale
		new_scale[axis_index] = maxf(0.1, snappedf(new_scale[axis_index] + scale_delta, 0.1))
		if is_equal_approx(new_scale[axis_index], _selected_node.scale[axis_index]):
			return
		_record_gizmo_undo_state()
		_selected_node.scale = new_scale
	else:
		var step := block_height if absf(_gizmo_drag_axis.y) > 0.9 else grid_size
		var distance := snappedf(_get_gizmo_drag_amount(mouse_position, origin, endpoint), step)
		var target_position := _gizmo_drag_start_position + _gizmo_drag_axis * distance
		if target_position.is_equal_approx(_selected_node.global_position):
			return
		if not _can_move_selected_to_gizmo_position(target_position):
			return
		_record_gizmo_undo_state()
		_move_selected_to_gizmo_position(target_position)
	_gizmo_drag_changed = true
	_update_gizmo()

func _get_gizmo_drag_amount(mouse_position: Vector2, origin: Vector2, endpoint: Vector2) -> float:
	var screen_axis := endpoint - origin
	if screen_axis.length_squared() < 1.0:
		return 0.0
	return (mouse_position - _gizmo_drag_start_mouse).dot(screen_axis.normalized()) / screen_axis.length() * 0.8

func _get_axis_index(axis: Vector3) -> int:
	if absf(axis.x) > 0.9:
		return 0
	if absf(axis.y) > 0.9:
		return 1
	return 2

func _record_gizmo_undo_state() -> void:
	if not _gizmo_drag_changed:
		_record_undo_state()

func _move_selected_to_gizmo_position(target_position: Vector3) -> bool:
	var current_cell: Vector3i = _selected_node.get_meta("cell", Vector3i.MAX)
	if current_cell == Vector3i.MAX:
		_selected_node.global_position = target_position
		return true
	var destination_cell := _world_to_cell(target_position - Vector3(0.0, block_height * 0.5, 0.0))
	if destination_cell != current_cell and _blocks.has(destination_cell):
		return false
	if destination_cell != current_cell:
		_blocks.erase(current_cell)
		_blocks[destination_cell] = _selected_node
		_selected_node.set_meta("cell", destination_cell)
		var collider := _selected_node.get_node_or_null("StaticBody3D") as StaticBody3D
		if collider != null:
			collider.set_meta("terrain_cell", destination_cell)
	_selected_node.position = _cell_to_world(destination_cell) + Vector3(0.0, block_height * 0.5, 0.0)
	return true

func _can_move_selected_to_gizmo_position(target_position: Vector3) -> bool:
	var current_cell: Vector3i = _selected_node.get_meta("cell", Vector3i.MAX)
	if current_cell == Vector3i.MAX:
		return true
	var destination_cell := _world_to_cell(target_position - Vector3(0.0, block_height * 0.5, 0.0))
	return destination_cell == current_cell or not _blocks.has(destination_cell)

func _create_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _make_mesh_for_block(selected_block)
	_ghost.material_override = _make_material(Color(1.0, 1.0, 1.0, 0.45))
	_ghost.rotation_degrees.y = selected_rotation
	_ghost.visible = false
	add_child(_ghost)

func _create_gizmo() -> void:
	_gizmo = MeshInstance3D.new()
	_gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_gizmo.visible = false
	add_child(_gizmo)
	_rebuild_gizmo_mesh()

func set_gizmo_mode(value: int) -> void:
	if value < GIZMO_MOVE or value > GIZMO_SCALE:
		return
	gizmo_mode = value
	_rebuild_gizmo_mesh()
	_update_gizmo()

func _rebuild_gizmo_mesh() -> void:
	if _gizmo == null:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	match gizmo_mode:
		GIZMO_MOVE:
			_add_gizmo_axis(mesh, Vector3.RIGHT, Color(0.94, 0.25, 0.22, 1.0))
			_add_gizmo_axis(mesh, Vector3.UP, Color(0.32, 0.9, 0.35, 1.0))
			_add_gizmo_axis(mesh, Vector3.BACK, Color(0.24, 0.58, 1.0, 1.0))
		GIZMO_ROTATE:
			_add_gizmo_ring(mesh, Vector3.UP, Color(0.94, 0.25, 0.22, 1.0))
			_add_gizmo_ring(mesh, Vector3.RIGHT, Color(0.32, 0.9, 0.35, 1.0))
			_add_gizmo_ring(mesh, Vector3.BACK, Color(0.24, 0.58, 1.0, 1.0))
		GIZMO_SCALE:
			_add_gizmo_axis(mesh, Vector3.RIGHT, Color(0.94, 0.25, 0.22, 1.0), true)
			_add_gizmo_axis(mesh, Vector3.UP, Color(0.32, 0.9, 0.35, 1.0), true)
			_add_gizmo_axis(mesh, Vector3.BACK, Color(0.24, 0.58, 1.0, 1.0), true)
	mesh.surface_end()
	_gizmo.mesh = mesh
	_gizmo.custom_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.line_width = 5.0
	_gizmo.material_override = material

func _add_gizmo_axis(mesh: ImmediateMesh, axis: Vector3, color: Color, show_handle: bool = false) -> void:
	color = _get_gizmo_display_color(axis, color)
	var length := 0.8
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(axis * length)
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = axis.cross(Vector3.BACK)
	side = side.normalized() * 0.1
	var tip := axis * length
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(tip)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(tip - axis * 0.16 + side)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(tip)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(tip - axis * 0.16 - side)
	if show_handle:
		var half_size := 0.07
		for offset in [Vector3(-half_size, -half_size, 0), Vector3(half_size, -half_size, 0), Vector3(half_size, half_size, 0), Vector3(-half_size, half_size, 0)]:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(tip + offset)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(tip + Vector3(offset.y, -offset.x, 0))

func _add_gizmo_ring(mesh: ImmediateMesh, normal: Vector3, color: Color) -> void:
	color = _get_gizmo_display_color(normal, color)
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = normal.cross(Vector3.BACK)
	tangent = tangent.normalized()
	var bitangent := normal.cross(tangent).normalized()
	var segments := 32
	for index in range(segments):
		var angle_a := TAU * float(index) / segments
		var angle_b := TAU * float(index + 1) / segments
		mesh.surface_set_color(color)
		mesh.surface_add_vertex((tangent * cos(angle_a) + bitangent * sin(angle_a)) * 0.72)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex((tangent * cos(angle_b) + bitangent * sin(angle_b)) * 0.72)

func _get_gizmo_display_color(axis: Vector3, color: Color) -> Color:
	if axis.dot(_gizmo_hover_axis) > 0.99:
		return color.lerp(Color.WHITE, 0.55)
	return color

func _update_gizmo_hover(mouse_position: Vector2) -> void:
	if _gizmo_dragging or _gizmo == null or not _gizmo.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var hovered_axis := _get_gizmo_axis_at_mouse(camera, mouse_position)
	if hovered_axis.is_equal_approx(_gizmo_hover_axis):
		return
	_gizmo_hover_axis = hovered_axis
	_rebuild_gizmo_mesh()

func _update_gizmo() -> void:
	if _gizmo == null:
		return
	if not edit_mode or _selected_node == null or not is_instance_valid(_selected_node):
		_gizmo.visible = false
		return
	_gizmo.global_position = _selected_node.global_position
	_gizmo.global_rotation = _selected_node.global_rotation
	_gizmo.scale = Vector3.ONE
	_gizmo.visible = true

func _make_material(color: Color = Color(1.0, 1.0, 1.0, 1.0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if texture != null:
		mat.albedo_texture = texture
	mat.roughness = 0.85
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return mat

func _update_ghost_visibility() -> void:
	if _ghost == null:
		return
	_ghost.visible = edit_mode
	if edit_mode:
		_update_ghost_position()
	_update_gizmo()

func _update_ghost_position() -> void:
	if _ghost == null:
		return
	if cursor_mode == CURSOR_SELECT:
		var hovered_object := _get_editable_object_from_mouse()
		var hovered_mesh := _get_object_mesh(hovered_object)
		if hovered_mesh == null:
			_ghost.visible = false
			return
		_ghost.mesh = hovered_mesh.mesh
		_ghost.material_override = _make_material(Color(1.0, 0.78, 0.2, 0.45))
		_ghost.global_transform = hovered_mesh.global_transform
		_ghost.scale *= 1.02
		_ghost.visible = edit_mode
		return
	var target_cell := _get_placement_cell_from_mouse()
	if target_cell == Vector3i.MAX:
		_ghost.visible = false
		return
	_ghost.mesh = _make_mesh_for_block(selected_block)
	_ghost.material_override = _make_material(Color(1.0, 1.0, 1.0, 0.45))
	_ghost.position = _cell_to_world(target_cell) + Vector3(0.0, block_height * 0.5, 0.0)
	_ghost.rotation_degrees.y = selected_rotation
	_ghost.scale = Vector3.ONE
	_ghost.visible = edit_mode and cursor_mode == CURSOR_PLACE

func _get_grid_point_from_mouse() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var origin_y := 0.0
	var t: float = (origin_y - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	var world_point := from + dir * t
	var snapped_x: float = round(world_point.x / grid_size) * grid_size
	var snapped_z: float = round(world_point.z / grid_size) * grid_size
	var snapped_y: float = 0.0
	return Vector3(snapped_x, snapped_y, snapped_z)

func _place_selected_block_under_mouse() -> void:
	var cell := _get_placement_cell_from_mouse()
	if cell == Vector3i.MAX:
		return
	if _blocks.has(cell):
		return
	_record_undo_state()
	var block: Node3D = _spawn_block(selected_block, cell, selected_rotation)
	_blocks[cell] = block
	_save_structures()

func _remove_block_under_mouse() -> void:
	var cell := _get_block_cell_from_mouse()
	if cell == Vector3i.MAX:
		return
	if not _blocks.has(cell):
		return
	_record_undo_state()
	var block: Node3D = _blocks[cell]
	if block != null and is_instance_valid(block):
		block.queue_free()
	_blocks.erase(cell)
	if _selected_node == block:
		_selected_node = null
	_save_structures()

func set_cursor_mode(value: int) -> void:
	if value != CURSOR_SELECT and value != CURSOR_PLACE:
		return
	cursor_mode = value
	_update_ghost_visibility()

func get_selected_object() -> Node3D:
	return _selected_node

func select_editor_object(node: Node3D) -> void:
	_set_selected_node(node)

func _save_editable_world_object_changes() -> void:
	var world_content := get_node_or_null("/root/WorldContent")
	if world_content == null:
		return
	if _selected_node is WildEncounterBlock:
		world_content.save_wild_areas()
	elif _selected_node is NPC:
		world_content.save_npcs()

func get_selected_world_resource():
	if _selected_node == null or not is_instance_valid(_selected_node):
		return null
	var resource = _selected_node.get_meta("world_resource") if _selected_node.has_meta("world_resource") else null
	if resource == null:
		resource = WorldObjectResourceScript.new()
		resource.display_name = _selected_node.name
		resource.object_type = "terrain" if _selected_node.has_meta("cell") else "world"
		_selected_node.set_meta("world_resource", resource)
	return resource

func assign_selected_asset(asset: Dictionary) -> void:
	var resource = get_selected_world_resource()
	if resource == null or asset.is_empty():
		return
	_record_undo_state()
	resource.asset_id = str(asset.get("id", ""))
	resource.asset_path = str(asset.get("path", ""))
	resource.object_type = str(asset.get("type", "prop"))
	_save_structures()

func set_selected_tags(tag_text: String) -> void:
	var resource = get_selected_world_resource()
	if resource == null:
		return
	var parsed_tags := PackedStringArray()
	for tag in tag_text.split(",", false):
		var trimmed := tag.strip_edges()
		if not trimmed.is_empty() and not parsed_tags.has(trimmed):
			parsed_tags.append(trimmed)
	if resource.tags == parsed_tags:
		return
	_record_undo_state()
	resource.tags = parsed_tags
	_save_structures()

func move_selected_block(cell_offset: Vector3i) -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		return
	var current_cell: Vector3i = _selected_node.get_meta("cell", Vector3i.MAX)
	if current_cell == Vector3i.MAX:
		_record_undo_state()
		_selected_node.position += Vector3(cell_offset.x * grid_size, cell_offset.y * block_height, cell_offset.z * grid_size)
		_save_structures()
		_save_editable_world_object_changes()
		return
	var destination_cell := current_cell + cell_offset
	if _blocks.has(destination_cell):
		return
	_record_undo_state()
	_blocks.erase(current_cell)
	_blocks[destination_cell] = _selected_node
	_selected_node.set_meta("cell", destination_cell)
	var collider := _selected_node.get_node_or_null("StaticBody3D") as StaticBody3D
	if collider != null:
		collider.set_meta("terrain_cell", destination_cell)
	_selected_node.position = _cell_to_world(destination_cell) + Vector3(0.0, block_height * 0.5, 0.0)
	_save_structures()
	_save_editable_world_object_changes()

func resize_selected_block(size_offset: Vector3i) -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		return
	var units: Vector3i = _selected_node.get_meta("size_units", Vector3i.ONE)
	units += size_offset
	units.x = maxi(1, units.x)
	units.y = maxi(1, units.y)
	units.z = maxi(1, units.z)
	if units == _selected_node.get_meta("size_units", Vector3i.ONE):
		return
	_record_undo_state()
	_selected_node.set_meta("size_units", units)
	_selected_node.scale = Vector3(units.x, units.y, units.z)
	_save_structures()
	_save_editable_world_object_changes()

func _select_block_under_mouse() -> void:
	_set_selected_node(_get_editable_object_from_mouse())

func _set_selected_node(node: Node3D) -> void:
	if _selected_node != null and is_instance_valid(_selected_node):
		var old_mesh := _get_object_mesh(_selected_node)
		if old_mesh != null:
			old_mesh.material_override = _make_material()
	_selected_node = node
	if _selected_node != null and is_instance_valid(_selected_node) and _selected_node.has_meta("cell"):
		var selected_mesh := _get_object_mesh(_selected_node)
		if selected_mesh != null:
			selected_mesh.material_override = _make_material(Color(1.0, 0.78, 0.2, 1.0))
	_update_gizmo()

func _get_object_mesh(node: Node3D) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node
	return node.get_node_or_null("Mesh") as MeshInstance3D

func _register_editable_world_objects() -> void:
	_editable_world_objects.clear()
	for node in get_tree().get_nodes_in_group(EDITABLE_WORLD_OBJECT_GROUP):
		if node is Node3D:
			_editable_world_objects.append(node)

func _get_editable_object_from_mouse() -> Node3D:
	var hit := _get_block_hit_from_mouse(7)
	var collider := hit.get("collider") as Node
	if collider == null:
		return null
	var cell = collider.get_meta("terrain_cell", Vector3i.MAX)
	if cell is Vector3i and _blocks.has(cell):
		return _blocks[cell]
	var node: Node = collider
	while node != null:
		if node.is_in_group(EDITABLE_WORLD_OBJECT_GROUP):
			return node as Node3D
		node = node.get_parent()
	return null

func _world_to_cell(world_position: Vector3) -> Vector3i:
	return Vector3i(
		int(round(world_position.x / grid_size)),
		int(floor(world_position.y / block_height)),
		int(round(world_position.z / grid_size))
	)

func _cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * grid_size, cell.y * block_height, cell.z * grid_size)

func _spawn_block(block_type: int, cell: Vector3i, rotation_y: int = 0) -> Node3D:
	var node := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := _make_mesh_for_block(block_type)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(mesh_instance)
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 2
	static_body.set_meta("terrain_cell", cell)
	var collision := CollisionShape3D.new()
	if block_type == BLOCK_SLOPE:
		collision.shape = mesh.create_convex_shape()
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(grid_size, block_height, grid_size)
		collision.shape = shape
	static_body.add_child(collision)
	node.add_child(static_body)
	add_child(node)
	node.set_meta("block_type", block_type)
	node.set_meta("rotation", rotation_y)
	node.set_meta("cell", cell)
	node.set_meta("size_units", Vector3i.ONE)
	var resource = WorldObjectResourceScript.new()
	resource.display_name = "Terrain Block"
	resource.object_type = "terrain"
	node.set_meta("world_resource", resource)

	node.position = _cell_to_world(cell) + Vector3(0.0, block_height * 0.5, 0.0)
	node.rotation_degrees.y = rotation_y
	return node

func _get_placement_cell_from_mouse() -> Vector3i:
	var hit := _get_block_hit_from_mouse()
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		var block_cell = collider.get_meta("terrain_cell", Vector3i.MAX) if collider != null else Vector3i.MAX
		if block_cell is Vector3i:
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			var face_offset := Vector3i(
				int(round(normal.x)), int(round(normal.y)), int(round(normal.z))
			)
			return block_cell + face_offset
	var ground_point := _get_grid_point_from_mouse()
	return Vector3i.MAX if ground_point == Vector3.INF else _world_to_cell(ground_point)

func _get_block_cell_from_mouse() -> Vector3i:
	var hit := _get_block_hit_from_mouse()
	if hit.is_empty():
		return Vector3i.MAX
	var collider := hit.get("collider") as Node
	var cell = collider.get_meta("terrain_cell", Vector3i.MAX) if collider != null else Vector3i.MAX
	return cell if cell is Vector3i else Vector3i.MAX

func _get_block_hit_from_mouse(collision_mask: int = 2) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var query := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * 500.0,
		collision_mask
	)
	return get_world_3d().direct_space_state.intersect_ray(query)

func get_walkable_height(_current_position: Vector3, _next_position: Vector3, ground_height: float = 0.0) -> float:
	return ground_height

func _get_top_block_in_column(column: Vector2i) -> Vector3i:
	var top_cell := Vector3i.MAX
	for cell: Vector3i in _blocks:
		if cell.x == column.x and cell.z == column.y and (top_cell == Vector3i.MAX or cell.y > top_cell.y):
			top_cell = cell
	return top_cell

func _slope_low_direction(rotation_y: int) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(rotation_y)).normalized()

func _make_mesh_for_block(block_type: int) -> Mesh:
	if block_type == BLOCK_SLOPE:
		var prism := PrismMesh.new()
		prism.size = Vector3(grid_size, block_height, grid_size)
		return prism
	var box := BoxMesh.new()
	box.size = Vector3(grid_size, block_height, grid_size)
	return box

func set_block_type(block_type: int) -> void:
	if block_type != BLOCK_CUBE and block_type != BLOCK_SLOPE:
		return
	selected_block = block_type
	if _ghost != null:
		_ghost.mesh = _make_mesh_for_block(selected_block)
		_ghost.material_override = _make_material(Color(1.0, 1.0, 1.0, 0.45))

func _rotate_selected(delta_degrees: int) -> void:
	selected_rotation = int(fposmod(selected_rotation + delta_degrees, 360))
	if _ghost != null:
		_ghost.rotation_degrees.y = selected_rotation

func rotate_selected(delta_degrees: int) -> void:
	if _selected_node == null or not is_instance_valid(_selected_node):
		_rotate_selected(delta_degrees)
		return
	_record_undo_state()
	var rotation_y := int(fposmod(int(_selected_node.get_meta("rotation", 0)) + delta_degrees, 360))
	_selected_node.set_meta("rotation", rotation_y)
	_selected_node.rotation_degrees.y = rotation_y
	_save_structures()
	_save_editable_world_object_changes()

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_capture_structure_state())
	_apply_structure_state(_undo_stack.pop_back())

func redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_capture_structure_state())
	_apply_structure_state(_redo_stack.pop_back())

func _record_undo_state() -> void:
	_undo_stack.append(_capture_structure_state())
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()

func _capture_structure_state() -> Dictionary:
	return {"entries": _get_structure_entries()}

func _apply_structure_state(state: Dictionary) -> void:
	for block: Node3D in _blocks.values():
		if block != null and is_instance_valid(block):
			block.queue_free()
	_blocks.clear()
	_selected_node = null
	var entries: Array = state.get("entries", [])
	for entry: Dictionary in entries:
		var object_path := str(entry.get("object_path", ""))
		if not object_path.is_empty():
			var object := get_node_or_null(NodePath(object_path)) as Node3D
			if object != null:
				object.position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
				object.rotation_degrees = Vector3(float(entry.get("rotation_x", 0.0)), float(entry.get("rotation_y", 0.0)), float(entry.get("rotation_z", 0.0)))
				object.scale = Vector3(float(entry.get("scale_x", 1.0)), float(entry.get("scale_y", 1.0)), float(entry.get("scale_z", 1.0)))
				_restore_world_resource(object, entry)
			continue
		var cell := Vector3i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("z", 0)))
		var block := _spawn_block(int(entry.get("type", BLOCK_CUBE)), cell, int(entry.get("rotation", 0)))
		block.rotation_degrees = Vector3(float(entry.get("rotation_x", 0.0)), float(entry.get("rotation_y", entry.get("rotation", 0))), float(entry.get("rotation_z", 0.0)))
		var size_units := Vector3i(int(entry.get("size_x", 1)), int(entry.get("size_y", 1)), int(entry.get("size_z", 1)))
		block.set_meta("size_units", size_units)
		block.scale = Vector3(size_units.x, size_units.y, size_units.z)
		_restore_world_resource(block, entry)
		_blocks[cell] = block
	_update_ghost_visibility()
	_save_structures()

func _get_structures_path() -> String:
	var pm := get_node_or_null("/root/ProjectManager")
	if pm == null:
		return ""
	var dir: String = pm.get_active_content_dir("structures")
	if dir.is_empty():
		return ""
	var scene := get_tree().current_scene
	var scene_path := scene.scene_file_path if scene != null else ""
	if scene_path.is_empty():
		return ""
	return dir.path_join(scene_path.md5_text() + ".json")

func _save_structures() -> void:
	var path := _get_structures_path()
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_get_structure_entries()))

func _get_structure_entries() -> Array:
	var entries: Array = []
	for cell: Vector3i in _blocks:
		var block: Node3D = _blocks[cell]
		if block == null or not is_instance_valid(block):
			continue
		entries.append({
			"x": cell.x, "y": cell.y, "z": cell.z,
			"type": int(block.get_meta("block_type", BLOCK_CUBE)),
			"rotation": int(block.get_meta("rotation", 0)),
			"rotation_x": block.rotation_degrees.x,
			"rotation_y": block.rotation_degrees.y,
			"rotation_z": block.rotation_degrees.z,
			"world_resource": _get_world_resource_data(block),
			"size_x": int((block.get_meta("size_units", Vector3i.ONE) as Vector3i).x),
			"size_y": int((block.get_meta("size_units", Vector3i.ONE) as Vector3i).y),
			"size_z": int((block.get_meta("size_units", Vector3i.ONE) as Vector3i).z)
		})
	for object in _editable_world_objects:
		if object == null or not is_instance_valid(object):
			continue
		entries.append({
			"object_path": str(get_path_to(object)),
			"x": object.position.x, "y": object.position.y, "z": object.position.z,
			"rotation_x": object.rotation_degrees.x,
			"rotation_y": object.rotation_degrees.y,
			"rotation_z": object.rotation_degrees.z,
			"scale_x": object.scale.x, "scale_y": object.scale.y, "scale_z": object.scale.z,
			"world_resource": _get_world_resource_data(object)
		})
	return entries

func _get_world_resource_data(node: Node3D) -> Dictionary:
	if node == null or not node.has_meta("world_resource"):
		return {}
	var resource = node.get_meta("world_resource", null)
	return resource.to_dictionary() if resource != null else {}

func _restore_world_resource(node: Node3D, data: Dictionary) -> void:
	var saved_resource = data.get("world_resource", {})
	if saved_resource is Dictionary and not saved_resource.is_empty():
		node.set_meta("world_resource", WorldObjectResourceScript.from_dictionary(saved_resource))

func _load_structures() -> void:
	var path := _get_structures_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	for entry: Dictionary in parsed:
		var object_path := str(entry.get("object_path", ""))
		if not object_path.is_empty():
			var object := get_node_or_null(NodePath(object_path)) as Node3D
			if object != null:
				object.position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)), float(entry.get("z", 0.0)))
				object.rotation_degrees = Vector3(float(entry.get("rotation_x", 0.0)), float(entry.get("rotation_y", 0.0)), float(entry.get("rotation_z", 0.0)))
				object.scale = Vector3(float(entry.get("scale_x", 1.0)), float(entry.get("scale_y", 1.0)), float(entry.get("scale_z", 1.0)))
				_restore_world_resource(object, entry)
			continue
		var cell := Vector3i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("z", 0)))
		if _blocks.has(cell):
			continue
		var block := _spawn_block(int(entry.get("type", BLOCK_CUBE)), cell, int(entry.get("rotation", 0)))
		block.rotation_degrees = Vector3(float(entry.get("rotation_x", 0.0)), float(entry.get("rotation_y", entry.get("rotation", 0))), float(entry.get("rotation_z", 0.0)))
		var size_units := Vector3i(int(entry.get("size_x", 1)), int(entry.get("size_y", 1)), int(entry.get("size_z", 1)))
		block.set_meta("size_units", size_units)
		block.scale = Vector3(size_units.x, size_units.y, size_units.z)
		_restore_world_resource(block, entry)
		_blocks[cell] = block
