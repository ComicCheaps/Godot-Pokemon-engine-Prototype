extends Node3D
class_name Monster

const MonsterProfileResource = preload("res://monster_profile.gd")

signal level_changed(new_level: int)

@export_category("Monster State")
@export var profile: MonsterProfileResource
@export_range(1, 100) var level: int = 1
@export var experience: int = 0
@export var current_hp: int = -1
@export var individual_values: Dictionary = {
	"hp": 0, "attack": 0, "defense": 0, "special_attack": 0, "special_defense": 0, "speed": 0
}
@export var effort_values: Dictionary = {
	"hp": 0, "attack": 0, "defense": 0, "special_attack": 0, "special_defense": 0, "speed": 0
}
@export var nature: String = "Hardy"

var move_pp: Dictionary = {}
var status_condition: String = ""
var status_turns: int = 0

@onready var animated_sprite: AnimatedSprite3D = get_node_or_null("AnimatedSprite3D")
@onready var shadow_sprite: AnimatedSprite3D = get_node_or_null("ShadowSprite3D")

func _ready() -> void:
	_apply_profile_visuals()

func _apply_profile_visuals() -> void:
	if animated_sprite == null or shadow_sprite == null or profile == null:
		return
	if profile.sprite_frames == null:
		animated_sprite.visible = false
		shadow_sprite.visible = false
		return

	animated_sprite.sprite_frames = profile.sprite_frames
	shadow_sprite.sprite_frames = profile.sprite_frames
	animated_sprite.visible = true
	shadow_sprite.visible = true
	shadow_sprite.modulate = Color(0.0, 0.0, 0.0, 0.4)
	var animation_name: String = profile.default_animation
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		var animation_names := animated_sprite.sprite_frames.get_animation_names()
		if animation_names.is_empty():
			animated_sprite.visible = false
			shadow_sprite.visible = false
			return
		animation_name = animation_names[0]
	animated_sprite.animation = animation_name
	shadow_sprite.animation = animation_name
	animated_sprite.play()
	shadow_sprite.play()

func _process(_delta: float) -> void:
	if animated_sprite == null or shadow_sprite == null:
		return
	shadow_sprite.animation = animated_sprite.animation
	shadow_sprite.frame = animated_sprite.frame
	shadow_sprite.frame_progress = animated_sprite.frame_progress

func get_species_id() -> String:
	return profile.species_id if profile != null else ""

func get_species_name() -> String:
	return profile.species_name if profile != null else ""

func get_types() -> Array[String]:
	if profile == null:
		return []
	var types: Array[String] = []
	for type_id in profile.type_ids:
		if types.size() >= 2:
			break
		types.append(type_id)
	return types

func get_base_stat(stat_name: String) -> int:
	if profile == null:
		return 0
	return int(profile.base_stats.get(stat_name, 0))

func get_calculated_stat(stat_name: String) -> int:
	var base_stat := get_base_stat(stat_name)
	var individual_value := clampi(int(individual_values.get(stat_name, 0)), 0, 31)
	var effort_value := clampi(int(effort_values.get(stat_name, 0)), 0, 252)
	var stat_value := floori(((2.0 * base_stat + individual_value + floori(effort_value / 4.0)) * level) / 100.0)
	if stat_name == "hp":
		return maxi(1, stat_value + level + 10)
	return maxi(1, roundi((stat_value + 5) * _nature_modifier(stat_name)))

func get_max_hp() -> int:
	return get_calculated_stat("hp")

func ensure_full_health_if_uninitialized() -> void:
	if current_hp < 0:
		current_hp = get_max_hp()

func _nature_modifier(stat_name: String) -> float:
	const NATURES := {
		"Lonely": ["attack", "defense"], "Adamant": ["attack", "special_attack"], "Naughty": ["attack", "special_defense"],
		"Bold": ["defense", "attack"], "Impish": ["defense", "special_attack"], "Lax": ["defense", "special_defense"],
		"Modest": ["special_attack", "attack"], "Mild": ["special_attack", "defense"], "Quiet": ["special_attack", "speed"],
		"Calm": ["special_defense", "attack"], "Gentle": ["special_defense", "defense"], "Sassy": ["special_defense", "speed"],
		"Timid": ["speed", "attack"], "Hasty": ["speed", "defense"], "Jolly": ["speed", "special_attack"],
		"Naive": ["speed", "special_defense"]
	}
	var nature_data: Array = NATURES.get(nature, [])
	if nature_data.size() == 2 and stat_name == nature_data[0]:
		return 1.1
	if nature_data.size() == 2 and stat_name == nature_data[1]:
		return 0.9
	return 1.0

func get_experience_required(target_level: int = -1) -> int:
	if profile == null:
		return 0
	if target_level < 1:
		target_level = level + 1
	return profile.get_experience_for_level(target_level)

func add_experience(amount: int) -> int:
	if profile == null or amount <= 0:
		return 0

	experience += amount
	var levels_gained := 0
	while level < profile.max_level and experience >= profile.get_experience_for_level(level + 1):
		level += 1
		levels_gained += 1
		level_changed.emit(level)
	return levels_gained

func get_learnable_moves() -> Array[MonsterMove]:
	if profile == null:
		return []
	return profile.learnable_moves

func get_moves_for_level(target_level: int = -1) -> Array[MonsterMove]:
	if profile == null:
		return []
	if target_level < 1:
		target_level = level

	var available_moves: Array[MonsterMove] = []
	for move in profile.learnable_moves:
		if move != null and move.learn_level <= target_level:
			available_moves.append(move)
	return available_moves

func get_move_pp(move: MonsterMove) -> int:
	if move == null:
		return 0
	var move_key := move.move_id if not move.move_id.is_empty() else move.resource_path
	if not move_pp.has(move_key):
		move_pp[move_key] = move.maximum_pp
	return int(move_pp[move_key])

func consume_move_pp(move: MonsterMove) -> bool:
	var current_pp := get_move_pp(move)
	if current_pp <= 0:
		return false
	var move_key := move.move_id if not move.move_id.is_empty() else move.resource_path
	move_pp[move_key] = current_pp - 1
	return true

func can_act_this_turn() -> bool:
	match status_condition:
		"Sleep":
			if status_turns > 0:
				status_turns -= 1
				return false
			status_condition = ""
			return true
		"Freeze":
			if randf() < 0.2:
				status_condition = ""
				return true
			return false
		"Paralysis":
			return randf() >= 0.25
	return true

func apply_status(new_status: String) -> bool:
	if status_condition != "" or new_status.is_empty() or new_status == "None":
		return false
	status_condition = new_status
	status_turns = randi_range(1, 3) if new_status == "Sleep" else 0
	return true

func end_turn_status_damage() -> int:
	if status_condition == "Burn" or status_condition == "Poison":
		return maxi(1, roundi(get_base_stat("hp") * 0.0625))
	return 0

func get_abilities() -> Array[MonsterAbility]:
	if profile == null:
		return []
	return profile.abilities

func get_evolutions() -> Array[MonsterEvolution]:
	if profile == null:
		return []
	return profile.evolutions

func can_evolve(evolution: MonsterEvolution, item_id: String = "") -> bool:
	if evolution == null:
		return false
	if evolution.method == "Level" and level < evolution.minimum_level:
		return false
	if evolution.method == "Item" and evolution.required_item != item_id:
		return false
	return true
