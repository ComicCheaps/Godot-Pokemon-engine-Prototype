extends Resource
class_name MonsterMove

@export var move_id: String = "move_id"
@export var move_name: String = "New Move"
@export var type_id: String = "normal"
@export_enum("Physical", "Special", "Status") var category: String = "Physical"
@export_range(1, 100) var learn_level: int = 1
@export_range(1, 999) var power: int = 0
@export_range(0, 100) var accuracy: int = 100
@export_range(1, 40) var maximum_pp: int = 10
@export_range(-7, 5) var priority: int = 0
@export_enum("None", "Burn", "Poison", "Paralysis", "Sleep", "Freeze") var status_effect: String = "None"
@export_range(0, 100) var status_chance: int = 0
@export var action_flags: PackedStringArray = []

func has_action_flag(flag_name: String) -> bool:
	return action_flags.has(flag_name)
