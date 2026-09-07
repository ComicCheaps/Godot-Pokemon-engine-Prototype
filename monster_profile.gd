extends Resource
class_name MonsterProfile

@export_category("Identity")
@export_range(1, 9999) var national_dex_id: int = 1
@export var species_id: String = "monster_id"
@export var species_name: String = "New Monster"
@export var type_ids: Array[String] = ["normal"]

@export_category("Visuals")
@export var sprite_frames: SpriteFrames
@export var default_animation: String = "default"
@export_range(0.25, 5.0, 0.05) var battle_size: float = 1.0
@export_range(0.0, 999.9, 0.1) var weight_kg: float = 0.0

@export_category("Base Stats")
@export var base_stats: Dictionary = {
	"hp": 1,
	"attack": 1,
	"defense": 1,
	"special_attack": 1,
	"special_defense": 1,
	"speed": 1
}

@export_category("Growth")
@export_range(1, 100) var max_level: int = 100
@export_enum("Fast", "Medium Fast", "Medium Slow", "Slow") var experience_group: String = "Medium Fast"
@export var experience_requirements: PackedInt32Array = PackedInt32Array()
@export_range(0, 1000) var base_experience_yield: int = 50
@export_range(1, 255) var catch_rate: int = 45

@export_category("Moves")
@export var learnable_moves: Array[MonsterMove] = []

@export_category("Abilities")
@export var abilities: Array[MonsterAbility] = []

@export_category("Evolution")
@export var evolutions: Array[MonsterEvolution] = []

func get_experience_for_level(target_level: int) -> int:
	target_level = clampi(target_level, 1, max_level)
	if experience_requirements != null and experience_requirements.size() >= target_level:
		return experience_requirements[target_level - 1]

	var level_value := float(target_level)
	var experience_value: float
	match experience_group:
		"Fast":
			experience_value = 0.8 * pow(level_value, 3.0)
		"Medium Slow":
			experience_value = 1.2 * pow(level_value, 3.0) - 15.0 * pow(level_value, 2.0) + 100.0 * level_value - 140.0
		"Slow":
			experience_value = 1.25 * pow(level_value, 3.0)
		_:
			experience_value = pow(level_value, 3.0)

	return maxi(0, roundi(experience_value))
