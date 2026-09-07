extends Node

const TRANSITION_LAYER := 100
const DEFAULT_FADE_DURATION := 0.35

var transitioning: bool = false
var pending_spawn_marker: String = ""
var fade_layer: CanvasLayer
var fade_rect: ColorRect
var persistent_player: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_fade_overlay()

func transition_to_scene(scene_path: String, spawn_marker: String = "PlayerSpawn", fade_duration: float = DEFAULT_FADE_DURATION) -> void:
	if transitioning or scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return

	transitioning = true
	pending_spawn_marker = spawn_marker
	persistent_player = get_tree().get_first_node_in_group("player") as Node3D
	var player := persistent_player
	if player != null and player.get("in_battle") != null:
		player.set("in_battle", true)
	if persistent_player != null:
		persistent_player.reparent(self, true)

	await _fade_to(1.0, fade_duration)
	var result := get_tree().change_scene_to_file(scene_path)
	if result != OK:
		_return_player_to_current_scene()
		pending_spawn_marker = ""
		persistent_player = null
		transitioning = false
		await _fade_to(0.0, fade_duration)
		return

	await get_tree().scene_changed
	_place_player_at_spawn()
	await _fade_to(0.0, fade_duration)
	transitioning = false
	return

func _create_fade_overlay() -> void:
	fade_layer = CanvasLayer.new()
	fade_layer.layer = TRANSITION_LAYER
	fade_layer.name = "WorldTransition"
	add_child(fade_layer)

	fade_rect = ColorRect.new()
	fade_rect.name = "FadeToBlack"
	fade_rect.color = Color.BLACK
	fade_rect.modulate.a = 0.0
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade_rect)

func _fade_to(target_alpha: float, fade_duration: float = DEFAULT_FADE_DURATION) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade_rect, "modulate:a", target_alpha, maxf(0.05, fade_duration))
	await tween.finished

func _place_player_at_spawn() -> void:
	var player := persistent_player
	for scene_player in get_tree().get_nodes_in_group("player"):
		if scene_player != player:
			scene_player.queue_free()
	if player == null:
		pending_spawn_marker = ""
		return

	var destination_root := get_tree().current_scene
	if destination_root == null:
		pending_spawn_marker = ""
		return
	player.reparent(destination_root, false)
	if player.get("is_moving") != null:
		player.set("is_moving", false)
	var player_camera := player.get_node_or_null("Camera3D") as Camera3D
	if player_camera != null:
		player_camera.make_current()
	var marker := destination_root.find_child(pending_spawn_marker, true, false) as Node3D
	if marker != null:
		player.global_position = marker.global_position
		if player.has_method("snap_to_grid"):
			player.snap_to_grid()
		if player.get("reserved_position") != null:
			player.set("reserved_position", player.global_position)
		if player.get("start_position") != null:
			player.set("start_position", player.global_position)
	pending_spawn_marker = ""
	if player.get("in_battle") != null:
		player.set("in_battle", false)
	persistent_player = null

func _return_player_to_current_scene() -> void:
	if persistent_player == null or get_tree().current_scene == null:
		return
	persistent_player.reparent(get_tree().current_scene, false)
	if persistent_player.get("in_battle") != null:
		persistent_player.set("in_battle", false)
