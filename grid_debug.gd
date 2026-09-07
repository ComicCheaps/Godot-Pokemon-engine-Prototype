extends Node3D

@export var grid_size: float = 0.5
@export var grid_width: int = 40
@export var grid_depth: int = 40
@export var grid_height: int = 12
@export var line_color: Color = Color(0.45, 0.7, 1.0, 0.25)
@export var edit_mode: bool = false
@export var show_3d_grid: bool = false

var _grid_mesh: MeshInstance3D

func _ready() -> void:
    add_to_group("grid_debug")
    _grid_mesh = MeshInstance3D.new()
    _grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_grid_mesh)
    _rebuild_grid()
    _apply_edit_mode()

func toggle_edit_mode() -> void:
    edit_mode = not edit_mode
    _apply_edit_mode()

func set_edit_mode(value: bool) -> void:
    edit_mode = value
    _apply_edit_mode()

func set_show_3d_grid(value: bool) -> void:
    if show_3d_grid == value:
        return
    show_3d_grid = value
    _rebuild_grid()

func _rebuild_grid() -> void:
    if _grid_mesh == null or grid_size <= 0.0:
        return
    var half_width := int(ceil(float(grid_width) / 2.0))
    var half_depth := int(ceil(float(grid_depth) / 2.0))
    var mesh := ImmediateMesh.new()
    mesh.surface_begin(Mesh.PRIMITIVE_LINES)
    for x in range(-half_width, half_width + 1):
        mesh.surface_add_vertex(Vector3(x * grid_size, 0.0, -half_depth * grid_size))
        mesh.surface_add_vertex(Vector3(x * grid_size, 0.0, half_depth * grid_size))
    for z in range(-half_depth, half_depth + 1):
        mesh.surface_add_vertex(Vector3(-half_width * grid_size, 0.0, z * grid_size))
        mesh.surface_add_vertex(Vector3(half_width * grid_size, 0.0, z * grid_size))
    if show_3d_grid:
        var min_corner := Vector3(-half_width * grid_size, 0.0, -half_depth * grid_size)
        var max_corner := Vector3(half_width * grid_size, grid_height * grid_size, half_depth * grid_size)
        for x in [min_corner.x, max_corner.x]:
            for z in [min_corner.z, max_corner.z]:
                mesh.surface_add_vertex(Vector3(x, min_corner.y, z))
                mesh.surface_add_vertex(Vector3(x, max_corner.y, z))
        for y in [min_corner.y, max_corner.y]:
            mesh.surface_add_vertex(Vector3(min_corner.x, y, min_corner.z))
            mesh.surface_add_vertex(Vector3(max_corner.x, y, min_corner.z))
            mesh.surface_add_vertex(Vector3(min_corner.x, y, max_corner.z))
            mesh.surface_add_vertex(Vector3(max_corner.x, y, max_corner.z))
            mesh.surface_add_vertex(Vector3(min_corner.x, y, min_corner.z))
            mesh.surface_add_vertex(Vector3(min_corner.x, y, max_corner.z))
            mesh.surface_add_vertex(Vector3(max_corner.x, y, min_corner.z))
            mesh.surface_add_vertex(Vector3(max_corner.x, y, max_corner.z))
    mesh.surface_end()
    _grid_mesh.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = line_color
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.vertex_color_use_as_albedo = true
    material.disable_ambient_light = true
    _grid_mesh.material_override = material

func _apply_edit_mode() -> void:
    visible = edit_mode
