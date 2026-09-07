@tool
extends Node3D
class_name ProceduralGrassPatch

const GRASS_SHADER = preload("res://shaders/reactive_grass_2d.gdshader")
const DEFAULT_GRASS = preload("res://assets/Grasses/grass.png")
const DEFAULT_TALL_GRASS = preload("res://assets/Grasses/tall grass.png")

@export_category("Patch")
@export_range(1, 4000) var blade_count: int = 1200:
	set(value):
		blade_count = value
		_regenerate_grass()
@export var patch_size: Vector2 = Vector2(12.0, 10.0):
	set(value):
		patch_size = value
		_regenerate_grass()
@export var grass_textures: Array[Texture2D] = [DEFAULT_GRASS, DEFAULT_TALL_GRASS]:
	set(value):
		grass_textures = value
		_regenerate_grass()
@export_range(0.1, 3.0, 0.05) var blade_width: float = 0.65:
	set(value):
		blade_width = value
		_regenerate_grass()
@export_range(0.1, 5.0, 0.05) var blade_height: float = 1.15:
	set(value):
		blade_height = value
		_regenerate_grass()
@export_range(0.1, 4.0, 0.05) var min_blade_scale: float = 0.8:
	set(value):
		min_blade_scale = value
		_regenerate_grass()
@export_range(0.1, 4.0, 0.05) var max_blade_scale: float = 1.25:
	set(value):
		max_blade_scale = value
		_regenerate_grass()
@export_range(0.0, 4.0, 0.01) var vertical_offset: float = 0.02:
	set(value):
		vertical_offset = value
		_regenerate_grass()
@export var cast_shadows: bool = false:
	set(value):
		cast_shadows = value
		_apply_shadow_mode()

@export_category("Wind")
@export var wind_direction: Vector2 = Vector2(1.0, 0.35)
@export_range(0.0, 2.0, 0.01) var wind_strength: float = 0.35
@export_range(0.1, 8.0, 0.01) var wind_speed: float = 2.2
@export_range(0.0, 2.0, 0.01) var turbulence_strength: float = 0.25

@export_category("Interactions")
@export var player_group_name: StringName = &"player"
@export_range(0.1, 8.0, 0.01) var interaction_radius: float = 1.8
@export_range(0.0, 2.0, 0.01) var interaction_strength: float = 0.45
@export_range(0.0, 3.0, 0.01) var gust_decay_per_second: float = 1.2

var _shader_material: ShaderMaterial
var _multimesh_instance: MultiMeshInstance3D
var _time_sec: float = 0.0
var _gust_world_pos: Vector3 = Vector3(0.0, -1000.0, 0.0)
var _gust_radius: float = 2.5
var _gust_strength: float = 0.0

func _ready() -> void:
	_ensure_multimesh()
	if Engine.is_editor_hint():
		_regenerate_grass()
	else:
		_regenerate_grass()
	_update_shader_uniforms(0.0)

func _process(delta: float) -> void:
	_time_sec += delta
	_gust_strength = maxf(0.0, _gust_strength - gust_decay_per_second * delta)
	_update_shader_uniforms(delta)

func trigger_gust(world_position: Vector3, strength: float = 1.0, radius: float = 2.5) -> void:
	_gust_world_pos = world_position
	_gust_strength = maxf(_gust_strength, strength)
	_gust_radius = maxf(0.1, radius)

func _regenerate_grass() -> void:
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	_ensure_multimesh()
	_ensure_material()
	var textures := _valid_textures()
	if textures.is_empty():
		_multimesh_instance.multimesh = null
		return
	_apply_texture_uniforms()

	var mesh := _build_cross_card_mesh(blade_width, blade_height)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = blade_count
	multimesh.mesh = mesh
	multimesh.visible_instance_count = blade_count
	multimesh.custom_aabb = AABB(
		Vector3(-patch_size.x * 0.5, vertical_offset - 0.2, -patch_size.y * 0.5),
		Vector3(patch_size.x, blade_height * maxf(1.0, max_blade_scale) + 0.6, patch_size.y)
	)
	_multimesh_instance.multimesh = multimesh
	_multimesh_instance.material_override = _shader_material
	_multimesh_instance.extra_cull_margin = 4.0
	_apply_shadow_mode()

	var min_scale := minf(min_blade_scale, max_blade_scale)
	var max_scale := maxf(min_blade_scale, max_blade_scale)
	for i in blade_count:
		var blade_position := Vector3(
			randf_range(-patch_size.x * 0.5, patch_size.x * 0.5),
			vertical_offset,
			randf_range(-patch_size.y * 0.5, patch_size.y * 0.5)
		)
		var random_scale := randf_range(min_scale, max_scale)
		var blade_basis := Basis(Vector3.UP, randf_range(0.0, TAU))
		var blade_transform := Transform3D(blade_basis.scaled(Vector3.ONE * random_scale), blade_position)
		multimesh.set_instance_transform(i, blade_transform)
		var texture_variant := float(randi_range(0, max(0, textures.size() - 1)))
		var phase := randf()
		multimesh.set_instance_custom_data(i, Color(texture_variant, phase, randf(), 1.0))

func _ensure_material() -> void:
	if _shader_material != null:
		return
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = GRASS_SHADER

func _build_cross_card_mesh(width: float, height: float) -> ArrayMesh:
	var half_w := width * 0.5
	var positions := PackedVector3Array([
		Vector3(-half_w, 0.0, 0.0), Vector3(half_w, 0.0, 0.0), Vector3(half_w, height, 0.0),
		Vector3(-half_w, 0.0, 0.0), Vector3(half_w, height, 0.0), Vector3(-half_w, height, 0.0),
		Vector3(0.0, 0.0, -half_w), Vector3(0.0, 0.0, half_w), Vector3(0.0, height, half_w),
		Vector3(0.0, 0.0, -half_w), Vector3(0.0, height, half_w), Vector3(0.0, height, -half_w)
	])
	var normals := PackedVector3Array([
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
		Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT,
		Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ensure_multimesh() -> void:
	if _multimesh_instance != null and is_instance_valid(_multimesh_instance):
		return
	var existing := get_node_or_null("GrassInstances") as MultiMeshInstance3D
	if existing != null:
		_multimesh_instance = existing
		return
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.name = "GrassInstances"
	add_child(_multimesh_instance)
	if Engine.is_editor_hint():
		_multimesh_instance.owner = get_tree().edited_scene_root

func _apply_shadow_mode() -> void:
	if _multimesh_instance == null:
		return
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _valid_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for texture in grass_textures:
		if texture != null:
			textures.append(texture)
	return textures

func _update_shader_uniforms(_delta: float) -> void:
	_ensure_material()
	_shader_material.set_shader_parameter("time_sec", _time_sec)
	_shader_material.set_shader_parameter("wind_direction", wind_direction)
	_shader_material.set_shader_parameter("wind_strength", wind_strength)
	_shader_material.set_shader_parameter("wind_speed", wind_speed)
	_shader_material.set_shader_parameter("turbulence_strength", turbulence_strength)
	_shader_material.set_shader_parameter("interaction_radius", interaction_radius)
	_shader_material.set_shader_parameter("interaction_strength", interaction_strength)
	_shader_material.set_shader_parameter("gust_world_pos", _gust_world_pos)
	_shader_material.set_shader_parameter("gust_radius", _gust_radius)
	_shader_material.set_shader_parameter("gust_strength", _gust_strength)

	var player := get_tree().get_first_node_in_group(player_group_name) as Node3D
	if player != null:
		_shader_material.set_shader_parameter("player_world_pos", player.global_position)
	else:
		_shader_material.set_shader_parameter("player_world_pos", Vector3(0.0, -1000.0, 0.0))

	var first_texture := _first_texture()
	if first_texture != null:
		_shader_material.set_shader_parameter("albedo_texture", first_texture)
	var secondary_texture := _second_texture(first_texture)
	if secondary_texture != null:
		_shader_material.set_shader_parameter("albedo_texture_2", secondary_texture)
		_shader_material.set_shader_parameter("use_secondary_texture", 1.0)
	else:
		_shader_material.set_shader_parameter("albedo_texture_2", first_texture)
		_shader_material.set_shader_parameter("use_secondary_texture", 0.0)

func _apply_texture_uniforms() -> void:
	var first_texture := _first_texture()
	if first_texture == null:
		return
	_shader_material.set_shader_parameter("albedo_texture", first_texture)
	var secondary_texture := _second_texture(first_texture)
	if secondary_texture != null:
		_shader_material.set_shader_parameter("albedo_texture_2", secondary_texture)
		_shader_material.set_shader_parameter("use_secondary_texture", 1.0)
	else:
		_shader_material.set_shader_parameter("albedo_texture_2", first_texture)
		_shader_material.set_shader_parameter("use_secondary_texture", 0.0)

func _first_texture() -> Texture2D:
	for texture in grass_textures:
		if texture != null:
			return texture
	return null

func _second_texture(first_texture: Texture2D) -> Texture2D:
	for texture in grass_textures:
		if texture != null and texture != first_texture:
			return texture
	return null
