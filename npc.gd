extends CharacterBody3D
class_name NPC

signal interacted(npc_name: String, line: String)

@export var npc_name: String = "NPC"
@export var dialogue: Array[String] = ["Hello there!"]
@export var sprite_frames: SpriteFrames
@export var default_direction: Vector2 = Vector2.DOWN
@export var interaction_range: float = 2.0
@export var interact_key: String = "ui_accept"
@export var grid_size: float = 0.5
@export var player_path: NodePath
@export var behavior_script: Script
@export var profile: NPCProfile
@export var battle_profile: MonsterProfile
@export var battle_flags: PackedStringArray = []
@export var dialogue_box_path: NodePath

@onready var animated_sprite: AnimatedSprite3D = $AnimatedSprite3D
@onready var prompt_label: Label3D = $PromptLabel

var debug_box: MeshInstance3D

var player: Node3D
var behavior: NPCBehavior
var current_line_index: int = 0
var is_player_nearby: bool = false
var dialogue_manager: CanvasLayer

func _ready() -> void:
	snap_to_grid()
	create_debug_box()

	if profile != null:
		apply_profile(profile)

	if player_path != NodePath():
		player = get_node(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	if player == null:
		call_deferred("_resolve_player")

	if dialogue_box_path != NodePath():
		dialogue_manager = get_node_or_null(dialogue_box_path)
	if dialogue_manager == null:
		dialogue_manager = get_tree().get_first_node_in_group("dialogue_manager")

	if behavior_script != null:
		var instance = behavior_script.new()
		if instance is NPCBehavior:
			behavior = instance
			behavior.setup(self)
		else:
			push_warning("Behavior script must extend NPCBehavior.")

	if sprite_frames != null:
		animated_sprite.sprite_frames = sprite_frames
	elif animated_sprite != null and animated_sprite.sprite_frames == null:
		push_warning("NPC: AnimatedSprite3D has no SpriteFrames assigned.")

	set_direction(default_direction)

	if prompt_label != null:
		prompt_label.visible = false

func _resolve_player() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if player == null and player_path != NodePath():
		player = get_node_or_null(player_path)
	if player == null:
		player = get_tree().get_first_node_in_group("player")

	is_player_nearby = player != null and global_position.distance_to(player.global_position) <= interaction_range

	if prompt_label != null:
		prompt_label.visible = is_player_nearby
		if is_player_nearby:
			prompt_label.text = "[E] Talk"

	if behavior != null and behavior.has_method("update_behavior"):
		behavior.update_behavior(self, _delta)

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_nearby:
		return

	var pressed_interact := event.is_action_pressed(interact_key)
	if not pressed_interact:
		pressed_interact = event.is_action_pressed("ui_accept")
	if not pressed_interact:
		pressed_interact = event.is_action_pressed("interact")

	if pressed_interact and is_player_facing_me():
		talk()

func talk() -> void:
	if profile != null and profile.cutscene_sequence != null:
		var cutscene_manager := get_node_or_null("/root/CutsceneManager")
		if cutscene_manager != null:
			cutscene_manager.play(profile.cutscene_sequence, self)
			return
	var lines: Array[String] = dialogue.duplicate()
	if behavior != null and behavior.has_method("get_lines"):
		var behavior_lines: Array[String] = behavior.get_lines(self)
		if not behavior_lines.is_empty():
			lines = behavior_lines

	if lines.is_empty():
		if behavior != null and behavior.has_method("on_interact"):
			behavior.on_interact(self, "")
		if player != null:
			face_player()
		return

	var line: String = lines[current_line_index % lines.size()]
	current_line_index = (current_line_index + 1) % lines.size()

	var custom_result: Variant = run_interaction_behavior(line)
	if custom_result is String and custom_result.length() > 0:
		line = custom_result

	# Face player last so it always ends up facing the player
	if player != null:
		face_player()

	var speaker_name := npc_name
	if profile != null and profile.dialogue_sequence != null and not profile.dialogue_sequence.speaker_name.is_empty():
		speaker_name = profile.dialogue_sequence.speaker_name
	emit_signal("interacted", speaker_name, line)
	print("%s: %s" % [speaker_name, line])

	if dialogue_manager != null and dialogue_manager.has_method("show_dialogue"):
		dialogue_manager.show_dialogue(speaker_name, lines)
	elif prompt_label != null:
		prompt_label.text = line

func run_interaction_behavior(line: String) -> Variant:
	if behavior != null and behavior.has_method("on_interact"):
		return behavior.on_interact(self, line)
	return line

func get_battle_flags() -> Dictionary:
	var flags: Dictionary = {}
	var resolved_flags: PackedStringArray = battle_flags
	if profile != null and profile.trainer_battle != null:
		resolved_flags = profile.trainer_battle.get("battle_flags") as PackedStringArray
	for flag in resolved_flags:
		if flag.is_empty():
			continue
		flags[flag] = true
	if resolved_flags.has("intro_standard"):
		flags["intro_mode"] = "standard"
	elif resolved_flags.has("intro_trainer") or resolved_flags.has("intro_gym"):
		flags["intro_mode"] = "trainer"
	return flags

func apply_profile(profile_data: NPCProfile) -> void:
	if profile_data == null:
		return

	npc_name = profile_data.npc_name
	dialogue = profile_data.dialogue.duplicate()
	if profile_data.dialogue_sequence != null:
		dialogue = profile_data.dialogue_sequence.lines.duplicate()
	sprite_frames = profile_data.sprite_frames
	default_direction = profile_data.default_direction
	behavior_script = profile_data.character_script
	if profile_data.trainer_battle != null:
		battle_profile = profile_data.trainer_battle.get("opponent_profile") as MonsterProfile
		battle_flags = profile_data.trainer_battle.get("battle_flags") as PackedStringArray

	if sprite_frames != null:
		animated_sprite.sprite_frames = sprite_frames

	set_direction(default_direction)

func create_debug_box() -> void:
	debug_box = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(grid_size * 0.4, 0.3, grid_size * 0.4)
	debug_box.mesh = box_mesh
	debug_box.material_override = StandardMaterial3D.new()
	debug_box.material_override.albedo_color = Color(1.0, 0.6, 0.2, 0.35)
	debug_box.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debug_box)
	debug_box.position = Vector3(0, 0.1, 0)

func is_player_facing_me() -> bool:
	if player == null:
		return false

	# Get player's facing direction (access directly since it's public)
	var player_facing: Vector2 = player.last_direction
	
	# Calculate direction from player to NPC
	var delta := global_position - player.global_position
	var npc_direction: Vector2 = Vector2.ZERO
	
	if abs(delta.x) > abs(delta.z):
		npc_direction = Vector2(sign(delta.x), 0.0)
	else:
		npc_direction = Vector2(0.0, sign(delta.z))
	
	# Check if player is facing towards NPC
	return player_facing == npc_direction

func snap_to_grid() -> void:
	var snapped_pos := Vector3(
		round(global_position.x / grid_size) * grid_size,
		global_position.y,
		round(global_position.z / grid_size) * grid_size
	)
	global_position = snapped_pos

func face_player() -> void:
	if player == null:
		return

	var delta := player.global_position - global_position
	var facing := Vector2.ZERO

	if abs(delta.x) > abs(delta.z):
		facing = Vector2(sign(delta.x), 0.0)
	else:
		facing = Vector2(0.0, sign(delta.z))

	set_direction(facing)

func set_direction(direction: Vector2) -> void:
	if animated_sprite == null:
		return

	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null:
		return

	var animation_name: String = "IdleFront"
	if abs(direction.y) > abs(direction.x):
		animation_name = "IdleUp" if direction.y < 0 else "IdleFront"
	else:
		animation_name = "IdleSides"
		# Mirror logic: left needs flip_h=false, right needs flip_h=true
		animated_sprite.flip_h = direction.x > 0

	if not frames.has_animation(animation_name):
		animation_name = _find_animation_fallback(frames)

	animated_sprite.animation = animation_name
	if frames.has_animation(animation_name):
		animated_sprite.play(animation_name)

func _find_animation_fallback(frames: SpriteFrames) -> String:
	var preferred_names: Array[String] = [
		"IdleFront",
		"IdleSides",
		"IdleUp",
		"WalkFront",
		"WalkSides",
        "WalkUp"
	]

	for animation_name in preferred_names:
		if frames.has_animation(animation_name):
			return animation_name

	var available_names: PackedStringArray = frames.get_animation_names()
	if available_names.size() > 0:
		return available_names[0]

	return ""
