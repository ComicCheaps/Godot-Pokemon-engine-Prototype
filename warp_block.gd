@tool
extends Area3D
class_name WarpBlock

@export_category("Warp Destination")
@export_file("*.tscn") var destination_scene: String = "res://maps/zone_meadow.tscn"
@export var destination_spawn_marker: String = "PlayerSpawn"
@export_range(0.1, 1.5, 0.05, "suffix:s") var fade_duration: float = 0.35

@onready var warp_visual: MeshInstance3D = $WarpVisual

var player_overlapping: bool = false
var triggered: bool = false

func _ready() -> void:
	if warp_visual != null:
		warp_visual.visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if destination_scene.is_empty():
		warnings.append("Choose a destination scene.")
	elif not ResourceLoader.exists(destination_scene):
		warnings.append("Destination scene does not exist: %s" % destination_scene)
	return warnings

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or triggered:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var is_overlapping := player != null and _contains_player(player)
	if is_overlapping and not player_overlapping:
		player_overlapping = true
		_start_warp(player)
	elif not is_overlapping:
		player_overlapping = false

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_overlapping = true
		_start_warp(body)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_overlapping = false

func _contains_player(player: Node3D) -> bool:
	var local_position := to_local(player.global_position)
	return abs(local_position.x) <= 0.5 and abs(local_position.z) <= 0.5

func _start_warp(_player: Node3D) -> void:
	if triggered:
		return
	var transition := get_node_or_null("/root/WorldTransition")
	if transition == null or not transition.has_method("transition_to_scene"):
		push_warning("WarpBlock: WorldTransition autoload was not found.")
		return
	if destination_scene.is_empty() or not ResourceLoader.exists(destination_scene):
		push_warning("WarpBlock: destination scene does not exist: %s" % destination_scene)
		return
	if transition.transitioning:
		return
	triggered = true
	transition.transition_to_scene(destination_scene, destination_spawn_marker, fade_duration)
